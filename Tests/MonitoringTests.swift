import Foundation

private struct MonitoringFailure: Error { let message: String }
private func checkMonitoring(_ condition: Bool, _ message: String) throws {
    if !condition { throw MonitoringFailure(message: message) }
}

@MainActor private final class MonitoringCodex: CodexUsageProviding {
    var historyReads = 0
    var limitReads = 0
    var limitFailure: Error?
    var delay = false
    var email = "first@example.com"
    func fetchUsage() async throws -> TokenUsage {
        historyReads += 1
        return TokenUsage(provider: .codex, daily: [DailyUsage(date: Date(), totalTokens: 42)],
                          account: ProviderAccount(email: email, planName: "pro"))
    }
    func fetchLimits() async throws -> CodexLimitSnapshot {
        limitReads += 1
        if delay { try await Task.sleep(for: .milliseconds(80)) }
        if let limitFailure { throw limitFailure }
        return CodexLimitSnapshot(account: ProviderAccount(email: email, planName: "pro"),
            limits: [CodexRateLimit(usedPercent: 42, windowDurationMinutes: 300,
                                   resetsAt: Date().addingTimeInterval(3_600))], receivedAt: Date())
    }
    func connectWithChatGPT() async throws {}
    func logout() async throws {}
}

private actor MonitoringActivity {
    var active = true
    func set(_ value: Bool) { active = value }
}

nonisolated private struct MonitoringClaude: AnthropicUsageProviding {
    func fetchUsage() async throws -> TokenUsage { TokenUsage(provider: .anthropic, daily: []) }
}
nonisolated private struct MonitoringKeys: APIKeyStoring {
    func apiKey(for provider: AIProvider) -> String? { nil }
    func setAPIKey(_ key: String, for provider: AIProvider) {}
    func deleteAPIKey(for provider: AIProvider) {}
}

@MainActor enum MonitoringTests {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tracken-monitoring-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "tracken-monitoring-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = AppSettings(defaults: defaults)
        let codex = MonitoringCodex()
        let activity = MonitoringActivity()
        let store = UsageStore(codexClient: codex, anthropicService: MonitoringClaude(),
            apiKeyStore: MonitoringKeys(), settings: settings, activity: { _ in await activity.active })
        store.startMonitoring(limitsDirectory: directory)
        defer { store.stopMonitoring() }
        let deadline = Date().addingTimeInterval(5)
        while store.usage(for: .codex) == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try checkMonitoring(codex.historyReads == 1 && codex.limitReads == 1, "Startup must load history and quotas once")
        let started = store.lastAutomaticRefresh!
        await store.menuDidOpen(now: started.addingTimeInterval(30))
        try checkMonitoring(codex.limitReads == 1, "Opening a fresh menu must not poll again")
        await store.menuDidOpen(now: started.addingTimeInterval(61))
        try checkMonitoring(codex.limitReads == 2 && codex.historyReads == 1, "A stale menu must fetch quotas without scanning history")
        await store.refreshAutomaticallyIfDue(now: started.addingTimeInterval(121))
        try checkMonitoring(codex.limitReads == 3 && codex.historyReads == 1, "Active quota polling must run each minute independently of history")
        await store.refreshAutomaticallyIfDue(now: started.addingTimeInterval(301))
        try checkMonitoring(codex.historyReads == 2, "Active history must refresh at five minutes")
        await activity.set(false)
        await store.refreshAutomaticallyIfDue(now: started.addingTimeInterval(400))
        let reads = codex.limitReads
        await store.refreshAutomaticallyIfDue(now: started.addingTimeInterval(600))
        try checkMonitoring(codex.limitReads == reads && codex.historyReads == 2, "Idle polling must slow down")
        await store.refreshAutomaticallyIfDue(now: started.addingTimeInterval(601))
        try checkMonitoring(codex.limitReads == reads + 1 && codex.historyReads == 2, "Idle quotas must refresh at five minutes without history scans")

        let received = Date().addingTimeInterval(-20).timeIntervalSince1970
        let payload: [String: Any] = ["receivedAt": received, "valuesChangedAt": received,
            "fiveHour": ["usedPercent": 90, "resetsAt": received + 3_600]]
        try JSONSerialization.data(withJSONObject: payload).write(to: directory.appendingPathComponent("rate-limits.json"))
        await store.refreshLimitsIfDue(now: started.addingTimeInterval(630))
        try checkMonitoring(store.claudeRateLimits?.fiveHour?.usedPercent == 90 && codex.limitReads == reads + 1,
                            "A changed Claude cache must be read between Codex server polls")
        try checkMonitoring(store.limitHealth[.anthropic]?.lastSuccess == Date(timeIntervalSince1970: received),
                            "Claude freshness must use the source receipt time, not the read time")

        codex.limitFailure = CodexAppServerError.protocolError("fixture offline")
        await store.refreshAll()
        try checkMonitoring(store.limitHealth[.codex]?.error == "fixture offline"
                            && store.historyHealth[.codex]?.error == nil && store.codexRateLimits != nil,
                            "Quota failures must stay visible even when history refresh succeeds, preserving cached limits")
        codex.limitFailure = nil
        codex.delay = true
        let before = codex.limitReads
        async let first: Void = store.refreshLimitsIfDue(force: true)
        async let second: Void = store.refreshLimitsIfDue(force: true)
        _ = await (first, second)
        try checkMonitoring(codex.limitReads == before + 1, "Overlapping quota polls must be coalesced")
        codex.delay = false
        codex.email = "second@example.com"
        await store.refreshLimitsIfDue(force: true)
        try checkMonitoring(store.usage(for: .codex) == nil && store.codexRateLimits?.accountKey == "second@example.com",
                            "A new account must not display the prior account's token history")
        codex.delay = true
        let pending = Task { await store.refreshLimitsIfDue(force: true) }
        try await Task.sleep(for: .milliseconds(15))
        await store.logoutCodex()
        await pending.value
        try checkMonitoring(store.codexRateLimits == nil && store.usage(for: .codex) == nil,
                            "A late quota response must not restore data after logout")
        store.stopMonitoring()
        let stopped = codex.limitReads
        await store.refreshAutomaticallyIfDue(now: started.addingTimeInterval(7_200))
        try checkMonitoring(codex.limitReads == stopped, "Stopped monitoring must not query providers")

        let activityFile = directory.appendingPathComponent("activity.jsonl")
        try Data("content must never be parsed for activity".utf8).write(to: activityFile)
        let detector = LocalUsageActivity(roots: [directory])
        try checkMonitoring(await detector.hasRecentActivity(now: Date()), "Recent local file writes must activate fast refresh")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: activityFile.path)
        try checkMonitoring(!(await detector.hasRecentActivity(now: Date())), "Old local files must not keep fast refresh active")
        print("PASS: adaptive polling, menu freshness, independent quota/history errors, source timestamps, account changes and shutdown")
    }
}
