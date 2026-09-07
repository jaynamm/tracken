import Foundation

private struct RealtimeFailure: Error { let message: String }
private func verifyRealtime(_ condition: Bool, _ message: String) throws {
    if !condition { throw RealtimeFailure(message: message) }
}

@MainActor private final class OfflineCodex: CodexUsageProviding {
    func fetchUsage() async throws -> TokenUsage { TokenUsage(provider: .codex, daily: [], granularity: .aggregate) }
    func connectWithChatGPT() async throws {}
    func logout() async throws {}
}
nonisolated private struct OfflineKeys: APIKeyStoring {
    func apiKey(for provider: AIProvider) -> String? { nil }
    func setAPIKey(_ key: String, for provider: AIProvider) {}
    func deleteAPIKey(for provider: AIProvider) {}
}

@MainActor enum RealtimeUsageTests {
    static func run() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("tracken-realtime-test-\(UUID().uuidString)")
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
        let store = UsageStore(codexClient: OfflineCodex(),
                               anthropicService: ClaudeSessionUsageService(projectsURL: projects), apiKeyStore: OfflineKeys())
        store.startMonitoring(projectsURL: projects, limitsDirectory: limits)
        defer { store.stopMonitoring() }
        try verifyRealtime(store.isMonitoringClaude, "Recursive filesystem monitoring did not start")
        try await eventually { store.usage(for: .anthropic)?.totalTokens == 5 && store.claudeRateLimits?.fiveHour?.usedPercent == 12 }
        // No views or menu popovers exist in this test: the app store owns updates.
        let nested = projects.appendingPathComponent("new-project/subagents")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try record("nested", tokens: 7).write(to: nested.appendingPathComponent("b.jsonl"))
        try await eventually { store.usage(for: .anthropic)?.totalTokens == 12 }
        try writeLimits(percent: 20, age: 600)
        try await eventually { store.claudeRateLimits?.fiveHour?.usedPercent == 20 }
        try verifyRealtime(store.claudeRateLimits?.mayBeOutdated(at: Date()) == true, "Repeated unchanged samples must retain age")
        try writeLimits(percent: 80, reset: -1)
        try await eventually { store.claudeRateLimits?.fiveHour?.usedPercent == 80 }
        try verifyRealtime(store.claudeRateLimits?.fiveHour?.hasExpired(at: Date()) == true, "Expired windows cannot be presented as current quota")
        try verifyRealtime(store.claudeRateLimits?.sevenDay == nil, "An absent window must not become zero")
        try Data("not json".utf8).write(to: limits.appendingPathComponent("rate-limits.json"), options: .atomic)
        try await eventually { store.claudeRateLimits == nil && store.claudeRateLimitError != nil }
        try writeLimits(percent: -1)
        do {
            _ = try ClaudeRateLimitService(directory: limits).read()
            throw RealtimeFailure(message: "Invalid percentage was accepted")
        } catch UsageServiceError.unavailable { }
        store.stopMonitoring()
        try record("after-stop", tokens: 30).write(to: projects.appendingPathComponent("c.jsonl"))
        try await Task.sleep(for: .seconds(1))
        try verifyRealtime(store.usage(for: .anthropic)?.totalTokens == 12, "Stopped monitor still refreshes")
        print("PASS: recursive history and quota file updates without views; missing, stale, expired and malformed quota; monitor shutdown")
    }

    private static func eventually(_ check: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if check() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw RealtimeFailure(message: "Filesystem update did not reach the store")
    }
}
