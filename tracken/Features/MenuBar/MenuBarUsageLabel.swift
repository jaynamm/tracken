import SwiftUI

struct MenuBarUsageLabel: View {
    let store: UsageStore
    @State private var now = Date()
    private var settings: AppSettings { .shared }

    var body: some View {
        Group {
            if settings.menuBarDisplayStyle == .iconOnly {
                Image("MenuBarIcon")
                    .accessibilityLabel("tracken")
            } else {
                let gauges: [MenuBarUsageGauge] = [
                    .codex(store.usage(for: .codex), now: now),
                    .claude(store.claudeRateLimits, now: now)
                ]
                let description = summary(gauges)
                Image(nsImage: MenuBarGaugeImage.make(
                    gauges: gauges, showsPercent: settings.menuBarDisplayStyle == .gaugesAndPercent))
                    .accessibilityLabel(Text(verbatim: description))
                    .help(description)
            }
        }
        // TimelineView in a MenuBarExtra label can repeatedly recreate the
        // status image before applicationDidFinishLaunching completes.
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
                now = Date()
            }
        }
    }

    private func summary(_ gauges: [MenuBarUsageGauge]) -> String {
        let rows = gauges.map { gauge in
            guard let limit = gauge.limit else {
                return L10n.format("%@: No current limit data", gauge.provider.shortName)
            }
            let minutes = limit.windowDurationMinutes
            let window = minutes.isMultiple(of: 1_440)
                ? L10n.format("%lld-day", minutes / 1_440)
                : (minutes.isMultiple(of: 60)
                   ? L10n.format("%lld-hour", minutes / 60)
                   : L10n.format("%lld-minute", minutes))
            return L10n.format("%@: %@ used (%@)", gauge.provider.shortName,
                               Format.percent(limit.usedPercent), window)
        }
        return (["tracken"] + rows + [L10n.text("Shows the highest usage among each provider's current subscription limits.")])
            .joined(separator: "\n")
    }
}
