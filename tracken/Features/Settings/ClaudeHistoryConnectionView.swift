import SwiftUI

struct ClaudeHistoryConnectionView: View {
    @Environment(UsageStore.self) private var store
    @State private var isWorking = false
    @State private var removedKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Claude Code local history", systemImage: "folder")
            Text("Reads saved usage from this Mac automatically. No API key is needed. Claude web and other devices are not included.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(store.isAutoRefreshEnabled ? "Refreshes every hour, even with the window closed" : "Automatic refresh paused",
                  systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            ClaudeLimitsView(compact: true)
            SettingsStatusRow(status: store.status(for: .anthropic), isWorking: isWorking)
            if case .unavailable(let message) = store.status(for: .anthropic) {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Reload history") {
                    Task {
                        isWorking = true
                        defer { isWorking = false }
                        await store.refresh(.anthropic)
                    }
                }
                .disabled(isWorking)
                Spacer()
                Button(removedKey ? "Saved key removed" : "Remove old API key", role: .destructive) {
                    store.removeSavedAnthropicAPIKey()
                    removedKey = true
                }
                .disabled(removedKey)
            }
        }
    }
}

struct SettingsStatusRow: View {
    let status: ConnectionStatus
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.color)
            Text(status.label)
            Spacer()
            if isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .font(.callout)
    }
}
