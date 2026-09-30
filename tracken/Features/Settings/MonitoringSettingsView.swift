import SwiftUI

struct CompactRefreshStatus: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AIProvider.allCases) { provider in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: store.limitHealth[provider]?.error == nil ? "clock" : "exclamationmark.triangle")
                        Text(verbatim: provider.shortName)
                        Text(limitStatus(provider, now: context.date))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func limitStatus(_ provider: AIProvider, now: Date) -> String {
        let health = store.limitHealth[provider] ?? RefreshHealth()
        if health.isRefreshing { return L10n.text("Refreshing limits…") }
        if health.error != nil { return L10n.text("Limit refresh failed · see Settings") }
        if store.limits(for: provider).isEmpty { return L10n.text("No limits received") }
        if store.limits(for: provider).allSatisfy({ $0.hasExpired(at: now) }) {
            return L10n.text("Window ended; awaiting update")
        }
        guard let received = health.lastSuccess else { return L10n.text("Not checked yet") }
        return L10n.format("Received %@", Format.relative(received))
    }
}

struct MonitoringSettingsView: View {
    @Environment(UsageStore.self) private var store
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Section {
            Toggle("Adaptive refresh", isOn: $settings.adaptiveRefreshEnabled)
            Text("While local usage is active: limits every minute, history every 5 minutes. When idle: limits every 5 minutes, history every hour. Claude's limit cache is checked every 30 seconds.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Turning adaptive refresh off uses hourly polling. Opening the menu still checks limits if the previous attempt was over a minute ago.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Recent local activity") {
                Text(L10n.text(store.hasRecentActivity ? "Detected in the last 5 minutes" : "No recent activity detected"))
            }
            Button("Check now") { Task { await store.refreshAll() } }
                .disabled(store.isRefreshing || store.isRefreshingLimits)
        }
        ForEach(AIProvider.allCases) { provider in
            Section {
                if provider == .codex,
                   let account = store.codexRateLimits?.account ?? store.usage(for: .codex)?.account {
                    if let email = account.email { LabeledContent("Connected account", value: email) }
                    if let plan = account.planName { LabeledContent("Plan", value: Format.planName(plan)) }
                }
                RefreshHealthView(title: "Usage history", health: store.historyHealth[provider] ?? RefreshHealth())
                RefreshHealthView(title: "Subscription limits", health: store.limitHealth[provider] ?? RefreshHealth())
                if store.limits(for: provider).isEmpty {
                    Text(provider == .anthropic
                         ? "Claude limits require the terminal status-line bridge. Local token history alone does not provide limits."
                         : "No current Codex limits. Check your CLI login and use Check now.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if store.limits(for: provider).allSatisfy({ $0.hasExpired(at: Date()) }) {
                    Text("Window ended; awaiting update").font(.caption).foregroundStyle(.secondary)
                }
                if provider == .anthropic {
                    Text("The received time is when Claude supplied data, not when tracken last read the file.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Data sources") {
                    if provider == .codex {
                        Text(CodexAppServerTransport.findCodexExecutable()?.path
                             ?? L10n.text("Codex CLI was not found. Install it, then try again."))
                        Text(LocalUsageActivity.codexHome.path)
                    } else {
                        Text(LocalUsageActivity.claudeProjects.path)
                        Text(ClaudeRateLimitService.defaultDirectory.appendingPathComponent("rate-limits.json").path)
                    }
                }
                .font(.caption)
                .textSelection(.enabled)
            } header: {
                Label(provider.shortName, systemImage: provider.symbolName)
            }
        }
    }
}

private struct RefreshHealthView: View {
    let title: String
    let health: RefreshHealth

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.text(title)).fontWeight(.medium)
                    Spacer()
                    if health.isRefreshing { ProgressView().controlSize(.mini) }
                    if let date = health.lastSuccess {
                        Text(L10n.format("Received %@", Format.relative(date)))
                            .foregroundStyle(.secondary)
                            .help(Format.date(date, time: true))
                    } else { Text("No data received yet").foregroundStyle(.secondary) }
                }
                if let error = health.error {
                    Text(L10n.message(error)).foregroundStyle(.orange).textSelection(.enabled)
                }
                if let attempted = health.lastAttempt {
                    Text(L10n.format("Last checked %@", Format.date(attempted, time: true)))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}

struct NotificationSettingsView: View {
    @Environment(UsageStore.self) private var store
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        if let notifications = store.notifications {
            Section {
                Toggle("Enable limit notifications", isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { enabled in
                        if enabled { Task { await notifications.enable() } }
                        else { settings.notificationsEnabled = false }
                    }))
                    .disabled(notifications.isRequesting)
                Text(L10n.text(notifications.permission.titleKey))
                    .font(.caption).foregroundStyle(.secondary)
                if notifications.permission == .denied {
                    Text("Allow tracken in System Settings → Notifications, then enable notifications here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = notifications.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Text("Warnings are sent once per threshold in each limit window. If usage jumps past both thresholds, only the higher warning is sent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Codex") {
                Toggle("Warn at 80% used", isOn: $settings.codexAlert80)
                Toggle("Warn at 90% used", isOn: $settings.codexAlert90)
            }.disabled(!settings.notificationsEnabled)
            Section("Claude") {
                Toggle("Warn at 80% used", isOn: $settings.claudeAlert80)
                Toggle("Warn at 90% used", isOn: $settings.claudeAlert90)
            }.disabled(!settings.notificationsEnabled)
            Section {
                Toggle("Notify when an exhausted limit recovers", isOn: $settings.recoveryAlertsEnabled)
                Text("Recovery requires new limit data below 100%. Expired or missing data never triggers a recovery notification.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Notifications require tracken to be running. macOS notification and Focus settings control delivery.")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(!settings.notificationsEnabled)
            .task { await notifications.refreshPermission() }
        }
    }
}
