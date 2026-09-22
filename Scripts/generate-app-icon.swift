#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Vector source for the Dock/Finder icon. Keep the canvas transparent; a white
// matte around rounded corners remains visible when macOS scales the icon.
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
    cornerWidth: 184, cornerHeight: 184, transform: nil
))
canvas.clip()
gradient(in: canvas, colors: [0x203442, 0x0A141C],
         from: CGPoint(x: 180, y: 96), to: CGPoint(x: 844, y: 928))
canvas.restoreGState()

// Preserve tracken's orange mascot, with its optical center aligned to the
// tile. Coordinates use a top-left origin, matching the menu-bar artwork.
canvas.saveGState()
canvas.translateBy(x: 512, y: 512)
canvas.scaleBy(x: 0.9, y: 0.9)
canvas.translateBy(x: -512, y: -558)

let mascot = CGMutablePath()
mascot.move(to: CGPoint(x: 296, y: 608))
mascot.addCurve(to: CGPoint(x: 512, y: 244),
                control1: CGPoint(x: 296, y: 406), control2: CGPoint(x: 371, y: 244))
mascot.addCurve(to: CGPoint(x: 728, y: 608),
                control1: CGPoint(x: 653, y: 244), control2: CGPoint(x: 728, y: 406))
mascot.addLine(to: CGPoint(x: 728, y: 750))
mascot.addCurve(to: CGPoint(x: 660, y: 750),
                control1: CGPoint(x: 728, y: 795), control2: CGPoint(x: 660, y: 795))
mascot.addLine(to: CGPoint(x: 660, y: 640))
mascot.addLine(to: CGPoint(x: 637, y: 640))
mascot.addLine(to: CGPoint(x: 637, y: 838))
mascot.addCurve(to: CGPoint(x: 569, y: 838),
                control1: CGPoint(x: 637, y: 883), control2: CGPoint(x: 569, y: 883))
mascot.addLine(to: CGPoint(x: 569, y: 640))
mascot.addLine(to: CGPoint(x: 546, y: 640))
mascot.addLine(to: CGPoint(x: 546, y: 666))
mascot.addCurve(to: CGPoint(x: 478, y: 666),
                control1: CGPoint(x: 546, y: 711), control2: CGPoint(x: 478, y: 711))
mascot.addLine(to: CGPoint(x: 478, y: 640))
mascot.addLine(to: CGPoint(x: 455, y: 640))
mascot.addLine(to: CGPoint(x: 455, y: 794))
mascot.addCurve(to: CGPoint(x: 387, y: 794),
                control1: CGPoint(x: 455, y: 839), control2: CGPoint(x: 387, y: 839))
mascot.addLine(to: CGPoint(x: 387, y: 640))
mascot.addLine(to: CGPoint(x: 364, y: 640))
mascot.addLine(to: CGPoint(x: 364, y: 710))
mascot.addCurve(to: CGPoint(x: 296, y: 710),
                control1: CGPoint(x: 364, y: 755), control2: CGPoint(x: 296, y: 755))
mascot.closeSubpath()

canvas.saveGState()
canvas.addPath(mascot)
canvas.clip()
gradient(in: canvas, colors: [0xF6BD73, 0xDD7846],
         from: CGPoint(x: 330, y: 244), to: CGPoint(x: 660, y: 872))
canvas.restoreGState()

canvas.setFillColor(color(0x0B1821))
canvas.fillEllipse(in: CGRect(x: 376, y: 416, width: 100, height: 112))
canvas.fillEllipse(in: CGRect(x: 548, y: 416, width: 100, height: 112))
canvas.restoreGState()

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
