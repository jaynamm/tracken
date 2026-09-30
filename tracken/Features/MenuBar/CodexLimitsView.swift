import SwiftUI

struct CodexLimitsView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let state = store.state(for: .codex)
            VStack(alignment: .leading, spacing: 4) {
                Label("Codex subscription limits", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.caption.weight(.medium))
                if let snapshot = store.codexRateLimits {
                    if snapshot.limits.isEmpty {
                        Text("Not reported").foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(Array(snapshot.limits.enumerated()), id: \.offset) { _, limit in
                                window(limit, now: context.date)
                            }
                        }
                    }
                    Text("Updated \(Format.date(snapshot.receivedAt, time: true))")
                        .foregroundStyle(.secondary)
                } else if case .notConnected = state.status {
                    Text("Connect in Settings").foregroundStyle(.secondary)
                }
                if let error = store.limitHealth[.codex]?.error {
                    Text(L10n.message(error)).foregroundStyle(.secondary)
                } else if store.limitHealth[.codex]?.isRefreshing == true {
                    Text("Loading…").foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func window(_ limit: CodexRateLimit, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(windowTitle(minutes: limit.windowDurationMinutes))
                Spacer(minLength: 4)
                Text(limit.hasExpired(at: now) ? "—" : Format.percent(limit.usedPercent))
                    .fontWeight(.semibold)
            }
            if limit.hasExpired(at: now) {
                Text("Window ended; awaiting update").foregroundStyle(.secondary)
            } else {
                ProgressView(value: min(100, max(0, limit.usedPercent)), total: 100)
                    .tint(AIProvider.codex.accentColor)
                if let resetsAt = limit.resetsAt {
                    Text("Resets \(Format.date(resetsAt, time: true))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func windowTitle(minutes: Int) -> String {
        if minutes > 0 && minutes.isMultiple(of: 1_440) {
            return L10n.format("%lld-day", minutes / 1_440)
        }
        if minutes > 0 && minutes.isMultiple(of: 60) {
            return L10n.format("%lld-hour", minutes / 60)
        }
        return L10n.format("%lld-minute", minutes)
    }
}
