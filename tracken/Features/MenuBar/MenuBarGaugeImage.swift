import AppKit

/// A template image keeps the tiny gauges legible in light, dark and selected menu bars.
/// Drawing a single image also avoids MenuBarExtra dropping custom SwiftUI shapes.
@MainActor enum MenuBarGaugeImage {
    private static var cached: (gauges: [MenuBarUsageGauge], showsPercent: Bool,
                                layout: MenuBarGaugeLayout, image: NSImage)?

    static func make(gauges: [MenuBarUsageGauge], showsPercent: Bool,
                     layout: MenuBarGaugeLayout = .vertical) -> NSImage {
        // MenuBarExtra can reevaluate its label after setting the status image.
        // Keep image identity stable until the displayed values actually change.
        if let cached, cached.gauges == gauges, cached.showsPercent == showsPercent,
           cached.layout == layout {
            return cached.image
        }
        let icon = NSImage(named: "MenuBarIcon")
        let leading: CGFloat = icon == nil ? 0 : 24
        let isHorizontal = layout == .horizontal
        let fontSize: CGFloat = isHorizontal ? 11 : 9
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        // Fixed columns keep the label still as percentages change, including 100%.
        let labelWidth = ceil(AIProvider.allCases.map {
            ($0.shortName as NSString).size(withAttributes: labelAttributes).width
        }.max() ?? 0)
        let numberWidth = ceil(("100%" as NSString).size(withAttributes: numberAttributes).width)
        let labelGap: CGFloat = isHorizontal ? 6 : 4
        let numberGap: CGFloat = isHorizontal ? 5 : 4
        let trackWidth: CGFloat = isHorizontal ? 34 : 32
        let trackHeight: CGFloat = isHorizontal ? 8 : 6
        let providerWidth = labelWidth + labelGap + trackWidth
            + (showsPercent ? numberGap + numberWidth : 0)
        let gap: CGFloat = 14
        let count = min(2, gauges.count)
        let width = leading + (isHorizontal
            ? CGFloat(count) * providerWidth + CGFloat(max(0, count - 1)) * gap
            : providerWidth)
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            icon?.draw(in: NSRect(x: 0, y: 2, width: 18, height: 18))
            // Align the tracks to device pixels at both standard and Retina scale.
            let scale = max(1, abs(NSGraphicsContext.current?.cgContext.ctm.d ?? 1))
            func aligned(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }

            for (index, gauge) in gauges.prefix(2).enumerated() {
                let originX = leading + (isHorizontal ? CGFloat(index) * (providerWidth + gap) : 0)
                let centerY: CGFloat = isHorizontal ? 11 : (index == 0 ? 16.5 : 5.5)
                let label = gauge.provider.shortName as NSString
                let labelSize = label.size(withAttributes: labelAttributes)
                label.draw(at: NSPoint(x: originX, y: aligned(centerY - labelSize.height / 2)),
                           withAttributes: labelAttributes)

                let track = NSRect(x: originX + labelWidth + labelGap,
                                   y: aligned(centerY - trackHeight / 2),
                                   width: trackWidth, height: trackHeight)
                let radius = trackHeight / 2
                if let percent = gauge.usedPercent {
                    NSColor.black.withAlphaComponent(0.26).setFill()
                    NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
                    if percent > 0 {
                        NSGraphicsContext.saveGraphicsState()
                        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).addClip()
                        NSColor.black.setFill()
                        let fill = NSRect(x: track.minX, y: track.minY,
                                          width: track.width * percent / 100, height: track.height)
                        // Round only the fixed track. Rounding a short fill again
                        // turns low usage into an oval that looks thinner.
                        fill.fill()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                } else {
                    // Unknown/expired is a dash, visibly different from an empty 0% gauge.
                    NSColor.black.withAlphaComponent(0.55).setFill()
                    let dash = NSRect(x: track.midX - 4, y: aligned(centerY - 0.75), width: 8, height: 1.5)
                    NSBezierPath(roundedRect: dash, xRadius: 0.75, yRadius: 0.75).fill()
                }

                if showsPercent {
                    let text = gauge.usedPercent.map { "\(Int($0.rounded()))%" } ?? "—"
                    let size = (text as NSString).size(withAttributes: numberAttributes)
                    (text as NSString).draw(at: NSPoint(x: originX + providerWidth - size.width,
                                                       y: aligned(centerY - size.height / 2)),
                                            withAttributes: numberAttributes)
                }
            }
            return true
        }
        image.isTemplate = true
        cached = (gauges, showsPercent, layout, image)
        return image
    }
}
