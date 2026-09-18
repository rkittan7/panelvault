// Turn a product photo shot on white into the transparent PNG the catalog wants.
//
// Catalog rows draw a part as a cut-out: the apps cast a glow from the
// silhouette and the website tints a row behind it, both of which need real
// transparency rather than a white plate.
//
// The white is removed by flooding inward from the border rather than by
// deleting every white pixel, so printing, labels and the white of a toggle
// inside the product survive — only white that the outside can reach is
// background. Pixels at the boundary keep a partial alpha so the edge does not
// come out jagged, and the result is cropped to what is left and scaled to fit
// the catalog's long side.
//
// Build and run (macOS, Command Line Tools are enough):
//
//     swiftc -O tools/cutout.swift -o /tmp/cutout
//     /tmp/cutout in.jpg out.png [--max 1400]
//
// Reads anything ImageIO reads, including HEIC and WebP.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Luminance at or above this, reachable from the border, is background.
/// A light grey product photographed on white paper needs both of these pushed
/// up (`--hard 250 --soft 238`) or its own body reads as backdrop.
var hardWhite: Double = 238
/// Between this and `hardWhite` the pixel is on the boundary and keeps part of
/// its alpha, which is what stops the cut-out edge from stair-stepping.
var softWhite: Double = 212
/// How grey a background pixel may be. A coloured pixel that happens to be
/// bright — a yellow warning label caught by the light — is not background.
let maxChroma: Double = 26
/// The shadow pass will not go darker than this, will not accept a step larger
/// than this between neighbouring pixels, and will not follow anything with
/// colour in it. Together these keep it inside the shadow: a product edge is a
/// cliff, and a grey product body is reached only across one.
let shadowFloor: Double = 158
let maxShadowStep: Double = 13
let maxShadowChroma: Double = 30
/// Alpha below this, on a pixel the flood reached, is haze rather than edge.
let hazeFloor: Double = 90
/// How sharp a step the flood may cross. Paper is flat, so its own noise sits
/// under this; the outline of a product is a step above it even when the
/// product is white and the paper is white. Without this the flood walks
/// straight into a white breaker body and deletes it, which brightness alone
/// can never prevent.
let edgeLimit: Double = 7

struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]  // RGBA, 4 bytes per pixel

    subscript(x: Int, y: Int) -> Int { (y * width + x) * 4 }

    func luminance(at index: Int) -> Double {
        0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
    }

    /// The bitmap is premultiplied: a pixel's colour has to be scaled by its own
    /// alpha, or Core Graphics reads a transparent white pixel back as an opaque
    /// white one and the cut-out is written out with its background intact.
    mutating func setAlpha(_ alpha: Double, at index: Int) {
        let scale = max(0, min(1, alpha / 255))
        for channel in 0..<3 {
            pixels[index + channel] = UInt8((Double(pixels[index + channel]) * scale).rounded())
        }
        pixels[index + 3] = UInt8(max(0, min(255, alpha)))
    }

    func chroma(at index: Int) -> Double {
        let r = Double(pixels[index]), g = Double(pixels[index + 1]), b = Double(pixels[index + 2])
        return max(r, max(g, b)) - min(r, min(g, b))
    }
}

func load(_ path: String) -> Bitmap? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // Anything already transparent composites over white first, so a source
    // that is half cut out already is treated the same as a flat photo.
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return Bitmap(width: width, height: height, pixels: pixels)
}

/// Flood from every border pixel, following anything white enough to be the
/// backdrop, and write the alpha each reached pixel keeps.
func cutOut(_ bitmap: inout Bitmap) {
    let width = bitmap.width, height = bitmap.height
    var reached = [Bool](repeating: false, count: width * height)
    var queue: [Int] = []
    queue.reserveCapacity(width * height / 4)

    // Luminance smoothed over 3x3 before the steps are measured, so a JPEG's
    // speckle does not read as an edge and stop the flood in open paper.
    var smooth = [Double](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            var total = 0.0
            var count = 0.0
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    total += bitmap.luminance(at: (ny * width + nx) * 4)
                    count += 1
                }
            }
            smooth[y * width + x] = total / count
        }
    }

    /// The sharpest step between this pixel and its neighbours.
    func edge(_ x: Int, _ y: Int) -> Double {
        let here = smooth[y * width + x]
        var sharpest = 0.0
        if x > 0 { sharpest = max(sharpest, abs(here - smooth[y * width + x - 1])) }
        if x < width - 1 { sharpest = max(sharpest, abs(here - smooth[y * width + x + 1])) }
        if y > 0 { sharpest = max(sharpest, abs(here - smooth[(y - 1) * width + x])) }
        if y < height - 1 { sharpest = max(sharpest, abs(here - smooth[(y + 1) * width + x])) }
        return sharpest
    }

    func isBackdrop(_ index: Int) -> Bool {
        bitmap.luminance(at: index) >= softWhite && bitmap.chroma(at: index) <= maxChroma
    }

    func seed(_ x: Int, _ y: Int) {
        let cell = y * width + x
        guard !reached[cell], isBackdrop(cell * 4), edge(x, y) <= edgeLimit else { return }
        reached[cell] = true
        queue.append(cell)
    }

    for x in 0..<width { seed(x, 0); seed(x, height - 1) }
    for y in 0..<height { seed(0, y); seed(width - 1, y) }

    var head = 0
    while head < queue.count {
        let cell = queue[head]; head += 1
        let x = cell % width, y = cell / width
        if x > 0 { seed(x - 1, y) }
        if x < width - 1 { seed(x + 1, y) }
        if y > 0 { seed(x, y - 1) }
        if y < height - 1 { seed(x, y + 1) }
    }

    // Second pass: the drop shadow a product is photographed with is grey, so
    // the flood above stops at its outer edge and leaves a smudge behind the
    // cut-out. A shadow darkens smoothly away from the paper while the product
    // itself starts at a hard edge, so the fill continues only where the step
    // from one pixel to the next is gentle and never brightens — which walks
    // down a shadow and stops dead at a rim.
    var shadow = [Bool](repeating: false, count: width * height)
    var shadowQueue = queue
    shadowQueue.removeAll(keepingCapacity: true)
    for cell in 0..<(width * height) where reached[cell] { shadowQueue.append(cell) }

    func follow(_ x: Int, _ y: Int, from lum: Double) {
        let cell = y * width + x
        guard !reached[cell], !shadow[cell] else { return }
        let index = cell * 4
        let next = bitmap.luminance(at: index)
        guard next >= shadowFloor, bitmap.chroma(at: index) <= maxShadowChroma,
              next <= lum + 2, lum - next <= maxShadowStep else { return }
        shadow[cell] = true
        shadowQueue.append(cell)
    }

    head = 0
    while head < shadowQueue.count {
        let cell = shadowQueue[head]; head += 1
        let x = cell % width, y = cell / width
        let lum = bitmap.luminance(at: cell * 4)
        if x > 0 { follow(x - 1, y, from: lum) }
        if x < width - 1 { follow(x + 1, y, from: lum) }
        if y > 0 { follow(x, y - 1, from: lum) }
        if y < height - 1 { follow(x, y + 1, from: lum) }
    }
    for cell in 0..<(width * height) where shadow[cell] { bitmap.setAlpha(0, at: cell * 4) }

    for cell in 0..<(width * height) where reached[cell] {
        let index = cell * 4
        let lum = bitmap.luminance(at: index)
        if lum >= hardWhite {
            bitmap.setAlpha(0, at: index)
        } else {
            // Boundary pixel: the whiter it is, the more of it was backdrop.
            let keep = (hardWhite - lum) / (hardWhite - softWhite)
            let alpha = max(0, min(255, keep * 255))
            // A backdrop that is not quite uniform leaves a faint wash over the
            // whole frame at this point, which reads as a pale rectangle on a
            // dark row and holds the crop open. Real edge feathering lands well
            // above this, so anything fainter is backdrop.
            bitmap.setAlpha(alpha < hazeFloor ? 0 : alpha, at: index)
        }
    }
}

/// Drop everything that is not part of the product: after the background is
/// gone, a photograph's mirror reflection and any corner the flood nibbled off
/// are left floating as small islands. The product is the biggest thing in the
/// picture, so anything under `share` of it goes.
func dropIslands(_ bitmap: inout Bitmap, share: Double) -> Int {
    let width = bitmap.width, height = bitmap.height
    var label = [Int](repeating: -1, count: width * height)
    var sizes: [Int] = []
    var queue: [Int] = []

    for start in 0..<(width * height) where label[start] == -1 && bitmap.pixels[start * 4 + 3] > 24 {
        let id = sizes.count
        var size = 0
        label[start] = id
        queue.removeAll(keepingCapacity: true)
        queue.append(start)
        var head = 0
        while head < queue.count {
            let cell = queue[head]; head += 1
            size += 1
            let x = cell % width, y = cell / width
            func visit(_ nx: Int, _ ny: Int) {
                let next = ny * width + nx
                guard label[next] == -1, bitmap.pixels[next * 4 + 3] > 24 else { return }
                label[next] = id
                queue.append(next)
            }
            if x > 0 { visit(x - 1, y) }
            if x < width - 1 { visit(x + 1, y) }
            if y > 0 { visit(x, y - 1) }
            if y < height - 1 { visit(x, y + 1) }
        }
        sizes.append(size)
    }

    guard let biggest = sizes.max(), biggest > 0 else { return 0 }
    let floor = Int(Double(biggest) * share)
    var dropped = 0
    for cell in 0..<(width * height) {
        let id = label[cell]
        guard id >= 0, sizes[id] < floor else { continue }
        bitmap.setAlpha(0, at: cell * 4)
        dropped += 1
    }
    return sizes.filter { $0 < floor }.count
}

/// How solid the cut-out is: the share of what is left that belongs to its
/// biggest connected piece. A device whose body was flooded away leaves only
/// its printing, which reads as many small pieces and a low share.
func solidity(_ bitmap: Bitmap) -> Double {
    let width = bitmap.width, height = bitmap.height
    var label = [Int](repeating: -1, count: width * height)
    var sizes: [Int] = []
    var queue: [Int] = []
    var ink = 0
    for start in 0..<(width * height) where bitmap.pixels[start * 4 + 3] > 128 {
        ink += 1
        guard label[start] == -1 else { continue }
        let id = sizes.count
        var size = 0
        label[start] = id
        queue.removeAll(keepingCapacity: true)
        queue.append(start)
        var head = 0
        while head < queue.count {
            let cell = queue[head]; head += 1
            size += 1
            let x = cell % width, y = cell / width
            func visit(_ nx: Int, _ ny: Int) {
                let next = ny * width + nx
                guard label[next] == -1, bitmap.pixels[next * 4 + 3] > 128 else { return }
                label[next] = id
                queue.append(next)
            }
            if x > 0 { visit(x - 1, y) }
            if x < width - 1 { visit(x + 1, y) }
            if y > 0 { visit(x, y - 1) }
            if y < height - 1 { visit(x, y + 1) }
        }
        sizes.append(size)
    }
    guard ink > 0, let biggest = sizes.max() else { return 0 }
    return Double(biggest) / Double(ink)
}

/// Put back the body of a part the flood ate.
///
/// A white breaker photographed on white paper has a body at the same level as
/// the backdrop, so no threshold can tell them apart and the flood walks in
/// through the anti-aliased rim and hollows it out, leaving the printing
/// floating in mid-air. These devices are rectangles, so what belongs to the
/// part is what has printing to its left and right and above and below: every
/// such pixel is restored from the original photograph.
func restoreBody(_ bitmap: inout Bitmap, original: [UInt8]) {
    let width = bitmap.width, height = bitmap.height
    var betweenRows = [Bool](repeating: false, count: width * height)
    var betweenColumns = [Bool](repeating: false, count: width * height)

    for y in 0..<height {
        var first = -1, last = -1
        for x in 0..<width where bitmap.pixels[bitmap[x, y] + 3] > 128 {
            if first < 0 { first = x }
            last = x
        }
        if first >= 0 { for x in first...last { betweenRows[y * width + x] = true } }
    }
    for x in 0..<width {
        var first = -1, last = -1
        for y in 0..<height where bitmap.pixels[bitmap[x, y] + 3] > 128 {
            if first < 0 { first = y }
            last = y
        }
        if first >= 0 { for y in first...last { betweenColumns[y * width + x] = true } }
    }

    for cell in 0..<(width * height) where betweenRows[cell] && betweenColumns[cell] {
        let index = cell * 4
        guard bitmap.pixels[index + 3] <= 128 else { continue }
        for channel in 0..<4 { bitmap.pixels[index + channel] = original[index + channel] }
        bitmap.pixels[index + 3] = 255
    }
}

/// The box around everything still visible, with a small margin so a part does
/// not sit hard against the edge of its own picture.
func contentBox(_ bitmap: Bitmap) -> CGRect {
    var minX = bitmap.width, minY = bitmap.height, maxX = -1, maxY = -1
    for y in 0..<bitmap.height {
        // Well above zero: a faint ghost the flood left behind must not hold the
        // frame open around a part that is otherwise cut out cleanly.
        for x in 0..<bitmap.width where Double(bitmap.pixels[bitmap[x, y] + 3]) >= hazeFloor {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else {
        return CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
    }
    let margin = Int((Double(max(maxX - minX, maxY - minY)) * 0.02).rounded())
    minX = max(0, minX - margin); minY = max(0, minY - margin)
    maxX = min(bitmap.width - 1, maxX + margin); maxY = min(bitmap.height - 1, maxY + margin)
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func write(_ bitmap: Bitmap, crop: CGRect, maxSide: Int, to path: String) -> Bool {
    var pixels = bitmap.pixels
    guard let context = CGContext(
        data: &pixels, width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
        bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let full = context.makeImage(),
          let cropped = full.cropping(to: crop) else { return false }

    let longest = max(cropped.width, cropped.height)
    let scale = longest > maxSide ? Double(maxSide) / Double(longest) : 1
    let outWidth = Int((Double(cropped.width) * scale).rounded())
    let outHeight = Int((Double(cropped.height) * scale).rounded())

    guard let out = CGContext(
        data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    out.interpolationQuality = .high
    out.draw(cropped, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))
    guard let scaled = out.makeImage() else { return false }

    guard let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, scaled, nil)
    return CGImageDestinationFinalize(destination)
}

// MARK: - main

var arguments = Array(CommandLine.arguments.dropFirst())
var maxSide = 1400
var islandShare = 0.03

func number(_ flag: String) -> Double? {
    guard let at = arguments.firstIndex(of: flag), at + 1 < arguments.count else { return nil }
    let value = Double(arguments[at + 1])
    arguments.removeSubrange(at...(at + 1))
    return value
}
if let value = number("--max") { maxSide = Int(value) }
var thresholdsGiven = false
if let value = number("--hard") { hardWhite = value; thresholdsGiven = true }
if let value = number("--soft") { softWhite = value; thresholdsGiven = true }
if let value = number("--islands") { islandShare = value }
var wantsProbe = false
if let at = arguments.firstIndex(of: "--probe") { wantsProbe = true; arguments.remove(at: at) }
var wantsPlain = false
if let at = arguments.firstIndex(of: "--plain") { wantsPlain = true; arguments.remove(at: at) }
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: cutout <in> <out.png> [--max 1400]\n".data(using: .utf8)!)
    exit(2)
}
guard var probeBitmap = load(arguments[0]) else {
    FileHandle.standardError.write("cannot read \(arguments[0])\n".data(using: .utf8)!)
    exit(1)
}
if wantsProbe {
    // What the backdrop actually is, which is the only way to pick thresholds
    // for a photograph that was not shot on paper white.
    var border: [Double] = []
    for x in 0..<probeBitmap.width {
        border.append(probeBitmap.luminance(at: probeBitmap[x, 0]))
        border.append(probeBitmap.luminance(at: probeBitmap[x, probeBitmap.height - 1]))
    }
    for y in 0..<probeBitmap.height {
        border.append(probeBitmap.luminance(at: probeBitmap[0, y]))
        border.append(probeBitmap.luminance(at: probeBitmap[probeBitmap.width - 1, y]))
    }
    border.sort()
    let median = border[border.count / 2]
    print(String(format: "%@ border luminance min %.0f median %.0f max %.0f",
                 arguments[0], border.first ?? 0, median, border.last ?? 0))
    exit(0)
}
var bitmap = probeBitmap
if !thresholdsGiven {
    // Calibrate to this photograph's own backdrop. A studio shot on paper white
    // sits at 255 and wants a tight band just under it, so a near-white product
    // body survives; a JPEG whose backdrop has been compressed down to the low
    // 240s wants a lower one, or its background never lifts. The fifth
    // percentile of the border is the backdrop with its darkest fringe ignored.
    var border: [Double] = []
    for x in 0..<bitmap.width {
        border.append(bitmap.luminance(at: bitmap[x, 0]))
        border.append(bitmap.luminance(at: bitmap[x, bitmap.height - 1]))
    }
    for y in 0..<bitmap.height {
        border.append(bitmap.luminance(at: bitmap[0, y]))
        border.append(bitmap.luminance(at: bitmap[bitmap.width - 1, y]))
    }
    border.sort()
    let backdrop = border[max(0, border.count / 20)]
    hardWhite = min(253, max(236, backdrop - 2))
    // A narrow fade band, not a wide one. The band is where a pixel is treated
    // as part backdrop, and a white breaker body photographed on white paper
    // sits only a few levels under the paper: a wide band swallows the body at
    // a third of its alpha, which is how a part came out as floating printing
    // with nothing behind it. Five levels is enough to feather the rim.
    softWhite = hardWhite - 5
    print(String(format: "  backdrop %.0f -> hard %.0f soft %.0f", backdrop, hardWhite, softWhite))
}
if false {
    FileHandle.standardError.write("cannot read \(arguments[0])\n".data(using: .utf8)!)
    exit(1)
}
let original = bitmap.pixels
cutOut(&bitmap)
var note = ""
// A cut that shreds the part is worse than no cut at all. First it is put back
// together; if that still leaves the part in pieces, the photograph goes out as
// it was taken. A white plate behind a whole breaker beats a clean cut-out of
// half of one.
if wantsPlain {
    // Asked for as-photographed: some products are the same white as the paper
    // they were shot on, and a whole breaker on a white plate beats a clean
    // cut-out of half of one.
    bitmap.pixels = original
    note = " left uncut as asked"
} else if solidity(bitmap) < 0.85 {
    restoreBody(&bitmap, original: original)
    note = String(format: " body restored, solidity %.0f%%", solidity(bitmap) * 100)
}
let islands = islandShare > 0 ? dropIslands(&bitmap, share: islandShare) : 0
let box = contentBox(bitmap)
guard write(bitmap, crop: box, maxSide: maxSide, to: arguments[1]) else {
    FileHandle.standardError.write("cannot write \(arguments[1])\n".data(using: .utf8)!)
    exit(1)
}
let cut = Int(box.width) < bitmap.width || Int(box.height) < bitmap.height
print("\(arguments[0]) -> \(arguments[1]) \(Int(box.width))x\(Int(box.height))"
      + (cut ? " cropped" : "") + (islands > 0 ? " \(islands) island(s) dropped" : "") + note)
