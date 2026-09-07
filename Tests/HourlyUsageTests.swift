import Foundation

private struct HourlyFailure: Error { let message: String }
private func verifyHourly(_ condition: Bool, _ message: String) throws {
    if !condition { throw HourlyFailure(message: message) }
}

@MainActor private final class OfflineCodex: CodexUsageProviding {
    var fetchCount = 0
    func fetchUsage() async throws -> TokenUsage {
        fetchCount += 1
        return TokenUsage(provider: .codex, daily: [], granularity: .aggregate)
    }
    func connectWithChatGPT() async throws {}
    func logout() async throws {}
}
nonisolated private struct OfflineKeys: APIKeyStoring {
    func apiKey(for provider: AIProvider) -> String? { nil }
    func setAPIKey(_ key: String, for provider: AIProvider) {}
    func deleteAPIKey(for provider: AIProvider) {}
}

@MainActor enum HourlyUsageTests {
    static func run() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("tracken-hourly-test-\(UUID().uuidString)")
        let projects = root.appendingPathComponent("projects")
        let limits = root.appendingPathComponent("limits")
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        try fm.createDirectory(at: limits, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func record(_ id: String, tokens: Int) throws -> Data {
            let row: [String: Any] = ["type": "assistant", "timestamp": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1)),
                                     "requestId": id, "message": ["id": id, "model": "claude-sonnet-5", "usage": ["input_tokens": tokens, "output_tokens": 0]]]
            var data = try JSONSerialization.data(withJSONObject: row)
            data.append(10)
            return data
        }
        func writeLimits(percent: Double, age: Double = 0, reset: Double = 3600) throws {
            let now = Date().timeIntervalSince1970
            let value: [String: Any] = ["receivedAt": now, "valuesChangedAt": now - age,
                                       "fiveHour": ["usedPercent": percent, "resetsAt": now + reset]]
            try JSONSerialization.data(withJSONObject: value).write(to: limits.appendingPathComponent("rate-limits.json"), options: .atomic)
        }
        try record("initial", tokens: 5).write(to: projects.appendingPathComponent("a.jsonl"))
        try writeLimits(percent: 12)
        let codex = OfflineCodex()
        let store = UsageStore(codexClient: codex,
                               anthropicService: ClaudeSessionUsageService(projectsURL: projects), apiKeyStore: OfflineKeys())
        store.startMonitoring(limitsDirectory: limits)
        defer { store.stopMonitoring() }
        try verifyHourly(store.isAutoRefreshEnabled, "Hourly refresh did not start")
        try await eventually { store.usage(for: .anthropic)?.totalTokens == 5 && store.claudeRateLimits?.fiveHour?.usedPercent == 12 }
        let started = store.lastAutomaticRefresh!
        store.startMonitoring(limitsDirectory: limits)
        try verifyHourly(codex.fetchCount == 1, "Starting twice must not create another initial refresh")
        // File writes must remain invisible until a scheduled or manual read.
        let nested = projects.appendingPathComponent("new-project/subagents")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try record("nested", tokens: 7).write(to: nested.appendingPathComponent("b.jsonl"))
        try writeLimits(percent: 20, age: 600)
        try await Task.sleep(for: .seconds(1))
        try verifyHourly(store.usage(for: .anthropic)?.totalTokens == 5 && store.claudeRateLimits?.fiveHour?.usedPercent == 12,
                         "File changes must not refresh usage or limits")
        await store.refreshAutomaticallyIfDue(now: started.addingTimeInterval(3_599))
        try verifyHourly(codex.fetchCount == 1 && store.usage(for: .anthropic)?.totalTokens == 5,
                         "Automatic refresh fired before one hour")
        await store.refreshAutomaticallyIfDue(now: started.addingTimeInterval(3_600))
        try verifyHourly(codex.fetchCount == 2 && store.usage(for: .anthropic)?.totalTokens == 12
                         && store.claudeRateLimits?.fiveHour?.usedPercent == 20,
                         "Hourly boundary must read both providers and the latest limit cache once")
        try verifyHourly(store.claudeRateLimits?.mayBeOutdated(at: Date()) == true, "Repeated unchanged samples must retain age")
        try writeLimits(percent: 80, reset: -1)
        await store.refresh(.anthropic)
        try verifyHourly(store.claudeRateLimits?.fiveHour?.usedPercent == 80, "Manual refresh must read limits immediately")
        try verifyHourly(store.claudeRateLimits?.fiveHour?.hasExpired(at: Date()) == true, "Expired windows cannot be presented as current quota")
        try verifyHourly(store.claudeRateLimits?.sevenDay == nil, "An absent window must not become zero")
        try Data("not json".utf8).write(to: limits.appendingPathComponent("rate-limits.json"), options: .atomic)
        await store.refreshAll()
        try verifyHourly(store.claudeRateLimits == nil && store.claudeRateLimitError != nil, "Manual refresh reports malformed limits")
        try writeLimits(percent: -1)
        do {
            _ = try ClaudeRateLimitService(directory: limits).read()
            throw HourlyFailure(message: "Invalid percentage was accepted")
        } catch UsageServiceError.unavailable { }
        try record("manual", tokens: 3).write(to: projects.appendingPathComponent("manual.jsonl"))
        await store.refresh(.anthropic)
        try verifyHourly(store.usage(for: .anthropic)?.totalTokens == 15, "Manual refresh must read usage immediately")
        store.stopMonitoring()
        try record("after-stop", tokens: 30).write(to: projects.appendingPathComponent("c.jsonl"))
        await store.refreshAutomaticallyIfDue(now: started.addingTimeInterval(7_200))
        try verifyHourly(store.usage(for: .anthropic)?.totalTokens == 15, "Stopped scheduler still refreshes")
        print("PASS: hourly scheduling, no reads on file changes, immediate manual refresh, quota validation and scheduler shutdown")
    }

    private static func eventually(_ check: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if check() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw HourlyFailure(message: "Initial refresh did not reach the store")
    }
}
