import SwiftUI

struct ClaudeLimitsView: View {
    @Environment(UsageStore.self) private var store
    var compact = false
    var showsUpdateDate = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                Label("Claude subscription limits", systemImage: "gauge.with.dots.needle.50percent")
                    .font(compact ? .caption.weight(.medium) : .callout.weight(.medium))
                if let error = store.claudeRateLimitError {
                    Text(L10n.message(error)).foregroundStyle(.secondary)
                } else if let snapshot = store.claudeRateLimits {
                    HStack(alignment: .top, spacing: 16) {
                        window("5-hour", value: snapshot.fiveHour, now: context.date)
                        window("7-day", value: snapshot.sevenDay, now: context.date)
                    }
                    if showsUpdateDate {
                        Text("Updated \(Format.date(snapshot.receivedDate, time: true))")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No limits received from the Claude Code terminal status line yet.")
                        .foregroundStyle(.secondary)
                    Text("VS Code chat usage alone may not send this data. With the status-line bridge configured, run claude in a terminal, receive a Pro/Max response, then refresh tracken.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(compact ? .caption2 : .caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func window(_ title: String, value: ClaudeRateLimitSnapshot.Window?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(L10n.text(title))
                Spacer(minLength: 4)
                if let value, !value.hasExpired(at: now) {
                    Text(Format.percent(value.usedPercent)).fontWeight(.semibold)
                } else {
                    Text("—")
                }
            }
            if let value, !value.hasExpired(at: now) {
                ProgressView(value: value.usedPercent, total: 100).tint(.orange)
                Text("Resets \(Format.date(Date(timeIntervalSince1970: value.resetsAt), time: true))")
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.text(value == nil ? "Not reported" : "Window ended; awaiting update"))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
