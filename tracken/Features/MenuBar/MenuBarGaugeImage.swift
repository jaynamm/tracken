import AppKit

/// A template image keeps the tiny gauges legible in light, dark and selected menu bars.
/// Drawing a single image also avoids MenuBarExtra dropping custom SwiftUI shapes.
@MainActor enum MenuBarGaugeImage {
    private static var cached: (gauges: [MenuBarUsageGauge], showsPercent: Bool, image: NSImage)?

    static func make(gauges: [MenuBarUsageGauge], showsPercent: Bool) -> NSImage {
        // MenuBarExtra can reevaluate its label after setting the status image.
        // Keep image identity stable until the displayed values actually change.
        if let cached, cached.gauges == gauges, cached.showsPercent == showsPercent {
            return cached.image
        }
        let icon = NSImage(named: "MenuBarIcon")
        let leading: CGFloat = icon == nil ? 0 : 24
        let width = leading + (showsPercent ? 94 : 65)
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            icon?.draw(in: NSRect(x: 0, y: 2, width: 18, height: 18))
            let labelFont = NSFont.systemFont(ofSize: 9, weight: .medium)
            let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

            for (index, gauge) in gauges.prefix(2).enumerated() {
                let rowY: CGFloat = index == 0 ? 11 : 0
                (gauge.provider.shortName as NSString).draw(
                    at: NSPoint(x: leading, y: rowY),
                    withAttributes: [.font: labelFont, .foregroundColor: NSColor.black])

                let track = NSRect(x: leading + 35, y: rowY + 3.5, width: 28, height: 5)
                if let percent = gauge.usedPercent {
                    NSColor.black.withAlphaComponent(0.22).setFill()
                    NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
                    if percent > 0 {
                        NSGraphicsContext.saveGraphicsState()
                        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).addClip()
                        NSColor.black.setFill()
                        NSRect(x: track.minX, y: track.minY,
                               width: track.width * percent / 100, height: track.height).fill()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                } else {
                    // Unknown/expired is a dash, visibly different from an empty 0% gauge.
                    NSColor.black.withAlphaComponent(0.55).setFill()
                    NSRect(x: track.midX - 3, y: track.midY - 0.5, width: 6, height: 1).fill()
                }

                if showsPercent {
                    let text = gauge.usedPercent.map { "\(Int($0.rounded()))%" } ?? "—"
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: numberFont, .foregroundColor: NSColor.black
                    ]
                    let size = (text as NSString).size(withAttributes: attributes)
                    (text as NSString).draw(at: NSPoint(x: width - size.width, y: rowY),
                                            withAttributes: attributes)
                }
            }
            return true
        }
        image.isTemplate = true
        cached = (gauges, showsPercent, image)
        return image
    }
}
