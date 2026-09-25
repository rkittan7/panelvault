// Lift a product out of its photo with Vision's subject mask.
//
// cutout.swift separates a part from its backdrop by brightness, which fails
// when the part is as light as the paper it sits on: a white Hager relay or a
// light-grey miniature breaker on a white studio sweep gets flooded straight
// through at any threshold. Vision's foreground instance mask (the one Photos
// uses to lift a subject) separates by shape instead, so a white body, a
// translucent label cover and a grey backdrop behind a grey breaker all come
// out right.
//
// The output is cropped to the subject but not scaled or cleaned, so follow
// it with `cutout --trim`, which drops stray islands and fits the catalog's
// long side:
//
//     swiftc -O tools/lift.swift -o /tmp/lift
//     swiftc -O tools/cutout.swift -o /tmp/cutout
//     /tmp/lift in.webp /tmp/lifted.png && /tmp/cutout /tmp/lifted.png out.png --trim
//
// Needs macOS 14 or later. Reads anything Core Image reads, including WebP.
// Check the result by eye: on small or busy photos the mask can smear an
// edge, and there cutout.swift may still be the better cut.

import CoreImage
import Foundation
import Vision

let args = CommandLine.arguments
guard args.count == 3, let input = CIImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("usage: lift <in> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: input)
try handler.perform([request])
guard let result = request.results?.first else {
    FileHandle.standardError.write("no subject found in \(args[1])\n".data(using: .utf8)!)
    exit(1)
}
let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                            croppedToInstancesExtent: true)
let lifted = CIImage(cvPixelBuffer: buffer)
try CIContext().writePNGRepresentation(of: lifted, to: URL(fileURLWithPath: args[2]),
                                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
print("\(args[1]) -> \(args[2]) \(Int(lifted.extent.width))x\(Int(lifted.extent.height))")
