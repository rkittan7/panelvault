#!/usr/bin/env swift
//
// Cut the PanelVault app icons from the mark in assets/brand.
//
// There is no SVG rasteriser on a machine with only the Command Line Tools, so
// the mark is redrawn here in CoreGraphics rather than converted. The geometry
// below is the same numbers as assets/brand/panelvault-mark.svg — if you move a
// rail, move it in both.
//
// Run from the repo root:
//   swift tools/make_app_icons.swift manager ios/Runner/Assets.xcassets/AppIcon.appiconset
//   swift tools/make_app_icons.swift worker  worker/Assets.xcassets/AppIcon.appiconset
//
// App Store icons may not carry an alpha channel, so the canvas is opaque and
// the mark is composited from a scratch layer — the carve is a real hole in the
// rails, punched with .clear, not a stripe painted in the background colour.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - The mark, on a 100 x 100 grid

/// Four breaker rails. `y` values leave a 3.47 gap between 10.6-tall rails.
let railX: CGFloat = 20
let railWidth: CGFloat = 60
let railHeight: CGFloat = 10.6
let railRadius: CGFloat = 2.6
let railTops: [CGFloat] = [24.0, 38.0667, 52.1333, 66.2]
let railOpacity: CGFloat = 0.74

/// The bolt, tip at the bottom, crossing every rail.
let boltPoints: [CGPoint] = [
  CGPoint(x: 58, y: 20),
  CGPoint(x: 33, y: 55),
  CGPoint(x: 46, y: 55),
  CGPoint(x: 42, y: 80),
  CGPoint(x: 67, y: 45),
  CGPoint(x: 54, y: 45),
]

/// Softens the bolt's points, and the width the same path is stroked with to
/// clear the gap around it.
let boltSoften: CGFloat = 2
let carveWidth: CGFloat = 10

// MARK: - Colourways

struct Colourway {
  let name: String
  let groundTop: (CGFloat, CGFloat, CGFloat)
  let groundBottom: (CGFloat, CGFloat, CGFloat)
  let mark: (CGFloat, CGFloat, CGFloat)
}

let colourways: [String: Colourway] = [
  // The manager app. Control-room blue, white mark.
  "manager": Colourway(
    name: "manager",
    groundTop: hex(0x3B6BFF),
    groundBottom: hex(0x0A2296),
    mark: hex(0xFFFFFF)
  ),
  // The worker app. Hi-vis amber with a near-black mark, which is how the
  // warning labels already on a cabinet are printed.
  "worker": Colourway(
    name: "worker",
    groundTop: hex(0xFFC61F),
    groundBottom: hex(0xF58400),
    mark: hex(0x14181B)
  ),
]

func hex(_ value: Int) -> (CGFloat, CGFloat, CGFloat) {
  (
    CGFloat((value >> 16) & 0xFF) / 255,
    CGFloat((value >> 8) & 0xFF) / 255,
    CGFloat(value & 0xFF) / 255
  )
}

// MARK: - Slots

/// Every file ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json names.
/// The worker app gets the same set so the two catalogues stay interchangeable.
let slots: [(name: String, pixels: Int)] = [
  ("Icon-App-20x20@1x", 20),
  ("Icon-App-20x20@2x", 40),
  ("Icon-App-20x20@3x", 60),
  ("Icon-App-29x29@1x", 29),
  ("Icon-App-29x29@2x", 58),
  ("Icon-App-29x29@3x", 87),
  ("Icon-App-40x40@1x", 40),
  ("Icon-App-40x40@2x", 80),
  ("Icon-App-40x40@3x", 120),
  ("Icon-App-60x60@2x", 120),
  ("Icon-App-60x60@3x", 180),
  ("Icon-App-76x76@1x", 76),
  ("Icon-App-76x76@2x", 152),
  ("Icon-App-83.5x83.5@2x", 167),
  ("Icon-App-1024x1024@1x", 1024),
]

// MARK: - Drawing

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func boltPath(scale: CGFloat) -> CGPath {
  let path = CGMutablePath()
  path.move(to: boltPoints[0].scaled(scale))
  for point in boltPoints.dropFirst() {
    path.addLine(to: point.scaled(scale))
  }
  path.closeSubpath()
  return path
}

extension CGPoint {
  func scaled(_ factor: CGFloat) -> CGPoint {
    CGPoint(x: x * factor, y: y * factor)
  }
}

/// The mark on its own transparent canvas, so the carve can be punched out of
/// the rails instead of painted over them.
func drawMark(size: Int, colour: (CGFloat, CGFloat, CGFloat)) -> CGImage {
  let side = CGFloat(size)
  let scale = side / 100
  guard
    let context = CGContext(
      data: nil,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: srgb,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else { fatalError("could not open a \(size)px scratch layer") }

  // CoreGraphics counts y upwards; the mark is drawn in the SVG's downward grid.
  context.translateBy(x: 0, y: side)
  context.scaleBy(x: 1, y: -1)
  context.setAllowsAntialiasing(true)
  context.setLineJoin(.round)

  let bolt = boltPath(scale: scale)

  // Rails.
  context.setFillColor(red: colour.0, green: colour.1, blue: colour.2, alpha: railOpacity)
  for top in railTops {
    let rect = CGRect(
      x: railX * scale,
      y: top * scale,
      width: railWidth * scale,
      height: railHeight * scale
    )
    context.addPath(
      CGPath(
        roundedRect: rect,
        cornerWidth: railRadius * scale,
        cornerHeight: railRadius * scale,
        transform: nil
      )
    )
  }
  context.fillPath()

  // The gap: clear the bolt itself and a band around it.
  context.setBlendMode(.clear)
  context.addPath(bolt)
  context.fillPath()
  context.addPath(bolt)
  context.setLineWidth(carveWidth * scale)
  // Mitred, not rounded: the gap then follows the bolt's own angles. A round
  // join bites a semicircle out of every rail the bolt turns on, which reads as
  // damage rather than as a cut.
  context.setLineJoin(.miter)
  context.setMiterLimit(3)
  context.strokePath()
  context.setLineJoin(.round)

  // The bolt, sitting in the hole it just made.
  context.setBlendMode(.normal)
  context.setFillColor(red: colour.0, green: colour.1, blue: colour.2, alpha: 1)
  context.setStrokeColor(red: colour.0, green: colour.1, blue: colour.2, alpha: 1)
  context.setLineWidth(boltSoften * scale)
  context.addPath(bolt)
  context.drawPath(using: .fillStroke)

  guard let image = context.makeImage() else { fatalError("could not read back the mark") }
  return image
}

/// One finished icon: opaque ground, mark on top, no alpha channel.
func drawIcon(size: Int, colourway: Colourway) -> CGImage {
  let side = CGFloat(size)
  guard
    let context = CGContext(
      data: nil,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: srgb,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
  else { fatalError("could not open a \(size)px canvas") }

  let components: [CGFloat] = [
    colourway.groundTop.0, colourway.groundTop.1, colourway.groundTop.2, 1,
    colourway.groundBottom.0, colourway.groundBottom.1, colourway.groundBottom.2, 1,
  ]
  guard
    let gradient = CGGradient(
      colorSpace: srgb,
      colorComponents: components,
      locations: [0, 1],
      count: 2
    )
  else { fatalError("could not mix the ground") }

  // Top-left to bottom-right, reading top-left as the light side.
  context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: side),
    end: CGPoint(x: side, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )

  context.draw(
    drawMark(size: size, colour: colourway.mark),
    in: CGRect(x: 0, y: 0, width: side, height: side)
  )

  guard let image = context.makeImage() else { fatalError("could not read back the icon") }
  return image
}

func writePNG(_ image: CGImage, to url: URL) {
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else { fatalError("could not open \(url.path) for writing") }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    fatalError("could not finish writing \(url.path)")
  }
}

// MARK: - Contents.json

/// Matches the catalogue Flutter left in ios/Runner, so the manager app's
/// Contents.json does not have to change and the worker app gets the same one.
let catalogueEntries: [(size: String, idiom: String, filename: String, scale: String)] = [
  ("20x20", "iphone", "Icon-App-20x20@2x.png", "2x"),
  ("20x20", "iphone", "Icon-App-20x20@3x.png", "3x"),
  ("29x29", "iphone", "Icon-App-29x29@1x.png", "1x"),
  ("29x29", "iphone", "Icon-App-29x29@2x.png", "2x"),
  ("29x29", "iphone", "Icon-App-29x29@3x.png", "3x"),
  ("40x40", "iphone", "Icon-App-40x40@2x.png", "2x"),
  ("40x40", "iphone", "Icon-App-40x40@3x.png", "3x"),
  ("60x60", "iphone", "Icon-App-60x60@2x.png", "2x"),
  ("60x60", "iphone", "Icon-App-60x60@3x.png", "3x"),
  ("20x20", "ipad", "Icon-App-20x20@1x.png", "1x"),
  ("20x20", "ipad", "Icon-App-20x20@2x.png", "2x"),
  ("29x29", "ipad", "Icon-App-29x29@1x.png", "1x"),
  ("29x29", "ipad", "Icon-App-29x29@2x.png", "2x"),
  ("40x40", "ipad", "Icon-App-40x40@1x.png", "1x"),
  ("40x40", "ipad", "Icon-App-40x40@2x.png", "2x"),
  ("76x76", "ipad", "Icon-App-76x76@1x.png", "1x"),
  ("76x76", "ipad", "Icon-App-76x76@2x.png", "2x"),
  ("83.5x83.5", "ipad", "Icon-App-83.5x83.5@2x.png", "2x"),
  ("1024x1024", "ios-marketing", "Icon-App-1024x1024@1x.png", "1x"),
]

func contentsJSON() -> String {
  var lines: [String] = ["{", "  \"images\" : ["]
  for (index, entry) in catalogueEntries.enumerated() {
    let comma = index == catalogueEntries.count - 1 ? "" : ","
    lines.append("    {")
    lines.append("      \"size\" : \"\(entry.size)\",")
    lines.append("      \"idiom\" : \"\(entry.idiom)\",")
    lines.append("      \"filename\" : \"\(entry.filename)\",")
    lines.append("      \"scale\" : \"\(entry.scale)\"")
    lines.append("    }" + comma)
  }
  lines.append("  ],")
  lines.append("  \"info\" : {")
  lines.append("    \"version\" : 1,")
  lines.append("    \"author\" : \"xcode\"")
  lines.append("  }")
  lines.append("}")
  return lines.joined(separator: "\n") + "\n"
}

// MARK: - Run

let arguments = CommandLine.arguments
guard arguments.count == 3, let colourway = colourways[arguments[1]] else {
  FileHandle.standardError.write(
    Data("usage: swift tools/make_app_icons.swift <manager|worker> <appiconset-dir>\n".utf8)
  )
  exit(2)
}

let outputDirectory = URL(fileURLWithPath: arguments[2])
try? FileManager.default.createDirectory(
  at: outputDirectory,
  withIntermediateDirectories: true
)

for slot in slots {
  let url = outputDirectory.appendingPathComponent("\(slot.name).png")
  writePNG(drawIcon(size: slot.pixels, colourway: colourway), to: url)
  print("  \(slot.name).png  \(slot.pixels)x\(slot.pixels)")
}

try contentsJSON().write(
  to: outputDirectory.appendingPathComponent("Contents.json"),
  atomically: true,
  encoding: .utf8
)

print("\(colourway.name): \(slots.count) icons + Contents.json in \(outputDirectory.path)")
