#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Shared vector source for the Dock/Finder and menu-bar mascots. Keep the app
// icon canvas transparent so its rounded tile has no opaque outer frame.
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appendingPathComponent("tracken/Resources/Assets.xcassets/AppIcon.appiconset")
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ rgb: UInt32) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [
        CGFloat((rgb >> 16) & 255) / 255,
        CGFloat((rgb >> 8) & 255) / 255,
        CGFloat(rgb & 255) / 255,
        1
    ])!
}

func context(size: Int) -> CGContext {
    CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func gradient(in context: CGContext, colors: [UInt32], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(
        colorsSpace: colorSpace, colors: colors.map(color) as CFArray,
        locations: nil
    )!
    context.drawLinearGradient(
        gradient, start: from, end: to,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

let canvas = context(size: 1024)
canvas.translateBy(x: 0, y: 1024)
canvas.scaleBy(x: 1, y: -1)

// Leave breathing room around the tile so it sits at the same visual scale as
// other macOS apps. The background has no light stroke or opaque outer frame.
canvas.saveGState()
canvas.addPath(CGPath(
    roundedRect: CGRect(x: 96, y: 96, width: 832, height: 832),
    cornerWidth: 208, cornerHeight: 208, transform: nil
))
canvas.clip()
gradient(in: canvas, colors: [0x203442, 0x0A141C],
         from: CGPoint(x: 180, y: 96), to: CGPoint(x: 844, y: 928))
canvas.restoreGState()

// A wider head and five short, rounded tentacles keep the familiar mascot
// readable at Dock sizes. Soft valleys replace the old square notches.
let mascot = CGMutablePath()
mascot.move(to: CGPoint(x: 252, y: 548))
mascot.addCurve(to: CGPoint(x: 512, y: 264),
                control1: CGPoint(x: 252, y: 388), control2: CGPoint(x: 362, y: 264))
mascot.addCurve(to: CGPoint(x: 772, y: 548),
                control1: CGPoint(x: 662, y: 264), control2: CGPoint(x: 772, y: 388))
mascot.addLine(to: CGPoint(x: 772, y: 632))
mascot.addCurve(to: CGPoint(x: 728, y: 682),
                control1: CGPoint(x: 772, y: 660), control2: CGPoint(x: 753, y: 682))
mascot.addCurve(to: CGPoint(x: 682, y: 640),
                control1: CGPoint(x: 704, y: 682), control2: CGPoint(x: 682, y: 664))
mascot.addLine(to: CGPoint(x: 682, y: 622))
mascot.addCurve(to: CGPoint(x: 662, y: 622),
                control1: CGPoint(x: 682, y: 609), control2: CGPoint(x: 662, y: 609))
mascot.addLine(to: CGPoint(x: 662, y: 708))
mascot.addCurve(to: CGPoint(x: 618, y: 760),
                control1: CGPoint(x: 662, y: 739), control2: CGPoint(x: 643, y: 760))
mascot.addCurve(to: CGPoint(x: 574, y: 714),
                control1: CGPoint(x: 593, y: 760), control2: CGPoint(x: 574, y: 739))
mascot.addLine(to: CGPoint(x: 574, y: 648))
mascot.addCurve(to: CGPoint(x: 554, y: 648),
                control1: CGPoint(x: 574, y: 635), control2: CGPoint(x: 554, y: 635))
mascot.addLine(to: CGPoint(x: 554, y: 677))
mascot.addCurve(to: CGPoint(x: 512, y: 720),
                control1: CGPoint(x: 554, y: 702), control2: CGPoint(x: 537, y: 720))
mascot.addCurve(to: CGPoint(x: 470, y: 677),
                control1: CGPoint(x: 487, y: 720), control2: CGPoint(x: 470, y: 702))
mascot.addLine(to: CGPoint(x: 470, y: 639))
mascot.addCurve(to: CGPoint(x: 450, y: 639),
                control1: CGPoint(x: 470, y: 626), control2: CGPoint(x: 450, y: 626))
mascot.addLine(to: CGPoint(x: 450, y: 696))
mascot.addCurve(to: CGPoint(x: 406, y: 744),
                control1: CGPoint(x: 450, y: 723), control2: CGPoint(x: 431, y: 744))
mascot.addCurve(to: CGPoint(x: 362, y: 696),
                control1: CGPoint(x: 381, y: 744), control2: CGPoint(x: 362, y: 723))
mascot.addLine(to: CGPoint(x: 362, y: 622))
mascot.addCurve(to: CGPoint(x: 342, y: 622),
                control1: CGPoint(x: 362, y: 609), control2: CGPoint(x: 342, y: 609))
mascot.addLine(to: CGPoint(x: 342, y: 637))
mascot.addCurve(to: CGPoint(x: 298, y: 682),
                control1: CGPoint(x: 342, y: 662), control2: CGPoint(x: 323, y: 682))
mascot.addCurve(to: CGPoint(x: 252, y: 637),
                control1: CGPoint(x: 273, y: 682), control2: CGPoint(x: 252, y: 662))
mascot.closeSubpath()

canvas.saveGState()
canvas.addPath(mascot)
canvas.clip()
gradient(in: canvas, colors: [0xFFD08C, 0xEFA568],
         from: CGPoint(x: 330, y: 264), to: CGPoint(x: 660, y: 760))
canvas.restoreGState()

let eyes = [CGRect(x: 388, y: 424, width: 92, height: 92),
            CGRect(x: 544, y: 424, width: 92, height: 92)]
canvas.setFillColor(color(0x0B1821))
for eye in eyes { canvas.fillEllipse(in: eye) }
canvas.setFillColor(color(0xFFF4DD))
for eye in eyes {
    canvas.fillEllipse(in: CGRect(x: eye.minX + 19, y: eye.minY + 17, width: 20, height: 20))
}
canvas.setStrokeColor(color(0x0B1821))
canvas.setLineWidth(8)
canvas.setLineCap(.round)
canvas.move(to: CGPoint(x: 489, y: 535))
canvas.addCurve(to: CGPoint(x: 535, y: 535),
                control1: CGPoint(x: 499, y: 551), control2: CGPoint(x: 525, y: 551))
canvas.strokePath()

let master = canvas.makeImage()!

struct IconSet: Decodable {
    struct Entry: Decodable {
        let filename: String
        let size: String
        let scale: String
    }
    let images: [Entry]
}

let manifest = try JSONDecoder().decode(
    IconSet.self, from: Data(contentsOf: iconSet.appendingPathComponent("Contents.json"))
)
for entry in manifest.images {
    let size = Int(entry.size.split(separator: "x")[0])!
        * Int(entry.scale.dropLast())!
    let bitmap = context(size: size)
    bitmap.interpolationQuality = .high
    bitmap.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    let destination = CGImageDestinationCreateWithURL(
        iconSet.appendingPathComponent(entry.filename) as CFURL,
        UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not write \(entry.filename)")
    }
    print("Generated \(entry.filename) (\(size) × \(size), RGBA)")
}

// The template asset uses the same silhouette and eye positions, with facial
// details omitted to stay crisp at 18 points and in selected/dark menu bars.
let template = CGMutablePath()
template.addPath(mascot)
for eye in eyes { template.addEllipse(in: eye) }
var segments: [String] = []
template.applyWithBlock { pointer in
    let element = pointer.pointee
    func point(_ index: Int) -> String {
        let point = element.points[index]
        return String(format: "%g %g", locale: Locale(identifier: "en_US_POSIX"),
                      Double(point.x), Double(point.y))
    }
    switch element.type {
    case .moveToPoint: segments.append("M\(point(0))")
    case .addLineToPoint: segments.append("L\(point(0))")
    case .addQuadCurveToPoint: segments.append("Q\(point(0)) \(point(1))")
    case .addCurveToPoint: segments.append("C\(point(0)) \(point(1)) \(point(2))")
    case .closeSubpath: segments.append("Z")
    @unknown default: fatalError("Unsupported vector path element")
    }
}
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="180 192 664 664">
  <path fill="#000" fill-rule="evenodd" d="\(segments.joined(separator: " "))"/>
</svg>

"""
let templateURL = root.appendingPathComponent("tracken/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.svg")
try svg.write(to: templateURL, atomically: true, encoding: .utf8)
print("Generated MenuBarIcon.svg (18 × 18, template)")
