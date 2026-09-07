import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description: message) }
}

nonisolated private final class MemoryKeys: APIKeyStoring {
    var value: String? = "old-demo-key"
    var reads = 0
    var writes = 0
    func apiKey(for provider: AIProvider) -> String? { reads += 1; return value }
    func setAPIKey(_ key: String, for provider: AIProvider) { writes += 1; value = key }
    func deleteAPIKey(for provider: AIProvider) { value = nil }
}

@MainActor private final class FakeCodex: CodexUsageProviding {
    var usage: TokenUsage
    var fetchCount = 0
    var delay = false
    init(_ usage: TokenUsage) { self.usage = usage }
    func fetchUsage() async throws -> TokenUsage {
        fetchCount += 1
        if delay { try await Task.sleep(for: .milliseconds(50)) }
        return usage
    }
    func connectWithChatGPT() async throws {}
    func logout() async throws {}
}

@main struct UsageRegressionTests {
    @MainActor static func main() async throws {
        try await checkStore()
        try checkMergeAndLimits()
        try await checkSessionRecords()
        print("PASS: usage store, Claude exclusion, concurrent refresh, daily merge, rate-limit selection, session deduplication, resumed tasks, pricing")
    }

    @MainActor private static func checkStore() async throws {
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let first = TokenUsage(provider: .codex, daily: [DailyUsage(date: today, totalTokens: 100)], granularity: .aggregate, lifetimeTokens: 1_000)
        let client = FakeCodex(first)
        let keys = MemoryKeys()
        let store = UsageStore(codexClient: client, anthropicService: UnavailableAnthropicUsageService(), apiKeyStore: keys)
        await store.refreshAll()
        // A late update belongs to yesterday, not today.
        client.usage = TokenUsage(provider: .codex, daily: [
            DailyUsage(date: today, totalTokens: 100),
            DailyUsage(date: yesterday, totalTokens: 50)
        ], granularity: .aggregate, lifetimeTokens: 1_050)
        await store.refresh(.codex)
        try expect(store.usage(for: .codex)?.recentDays(count: 1).first?.totalTokens == 100,
                   "Lifetime delta must not be added to today's bucket")
        try expect(store.combinedLast14DaysTokens == 150, "Only measured daily totals belong in Combined")
        client.usage = TokenUsage(provider: .codex, daily: [DailyUsage(date: today, totalTokens: 80)], granularity: .aggregate, lifetimeTokens: 1_050)
        await store.refresh(.codex)
        try expect(store.usage(for: .codex)?.totalTokens == 80, "Accept corrected daily totals")
        client.delay = true
        let before = client.fetchCount
        async let one: Void = store.refresh(.codex)
        async let two: Void = store.refresh(.codex)
        _ = await (one, two)
        try expect(client.fetchCount == before + 1, "Overlapping refreshes must not race")
        await store.connectAPIKey(.anthropic, apiKey: "must-not-save")
        await store.refresh(.anthropic)
        guard case .unavailable = store.status(for: .anthropic) else {
            throw CheckFailure(description: "Claude must stay unavailable")
        }
        try expect(store.usage(for: .anthropic) == nil && keys.reads == 0 && keys.writes == 0,
                   "Saved keys must not enable demo usage")
        store.disconnectAPIKey(.anthropic)
        try expect(keys.value == nil, "Old keys can still be removed")
    }

    @MainActor private static func checkMergeAndLimits() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let next = day.addingTimeInterval(86_400)
        let known = ModelUsage(modelName: "known", inputTokens: 60, outputTokens: 10, estimatedCostUSD: 0.5)
        let unknown = ModelUsage(modelName: "unknown", inputTokens: 30, outputTokens: 5)
        let result = CodexAppServerClient.merge(officialDaily: [
            DailyUsage(date: day, totalTokens: 80), DailyUsage(date: day, totalTokens: 20)
        ], localEstimates: [day: [known, unknown], next: [known]])
        try expect(result.first(where: { $0.date == day })?.totalTokens == 100,
                   "Official daily totals win; duplicate dates do not crash")
        try expect(result.first(where: { $0.date == next })?.totalTokens == 70,
                   "Local usage fills missing dates without adding to official totals")
        try expect(result.first(where: { $0.date == day })?.estimatedCostUSD == nil,
                   "Unknown rates must not produce a partial total disguised as a full estimate")
        try expect(TokenUsage.completeEstimatedCost(for: [known, unknown]) == nil, "Unknown aggregate price")
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":14,"windowDurationMins":10080}}}}"#.utf8)
        let limits = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        try expect(limits.codexLimits?.primary?.usedPercent == 14, "Prefer the current Codex bucket")
        let legacy = try JSONDecoder().decode(RateLimitsResponse.self, from: Data(#"{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300}}}"#.utf8))
        try expect(legacy.codexLimits?.primary?.usedPercent == 20, "Legacy rate-limit fallback")
    }

    @MainActor private static func checkSessionRecords() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("tracken-regression-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let stamp = ISO8601DateFormatter()
        // Deliberately omit fractional seconds to exercise older record formats.
        func timestamp(_ offset: TimeInterval) -> String { stamp.string(from: today.addingTimeInterval(offset)) }
        func tokens(_ input: Int, _ output: Int, cached: Int = 0, write: Int = 0) -> [String: Int] {
            ["input_tokens": input, "output_tokens": output, "cached_input_tokens": cached, "cache_write_input_tokens": write]
        }
        func context(_ model: String = "gpt-5.6-sol") -> [String: Any] {
            ["type": "turn_context", "payload": ["turn_id": "t", "model": model]]
        }
        func modern(_ id: String, _ usage: [String: Int], at offset: TimeInterval = 10) -> [String: Any] {
            ["type": "token_usage_record", "timestamp": timestamp(offset), "payload": ["response_id": id, "turn_id": "t", "usage": usage]]
        }
        func legacy(_ usage: [String: Int], total: [String: Int], at offset: TimeInterval = 10) -> [String: Any] {
            ["type": "event_msg", "timestamp": timestamp(offset), "payload": ["type": "token_count", "info": ["last_token_usage": usage, "total_token_usage": total]]]
        }
        func write(_ directory: String, _ name: String, _ records: [[String: Any]]) throws -> URL {
            let dir = root.appendingPathComponent(directory)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var data = Data()
            for record in records {
                data.append(try JSONSerialization.data(withJSONObject: record)); data.append(10)
            }
            try data.write(to: dir.appendingPathComponent(name + ".jsonl"))
            return dir
        }
        func read(_ directory: String) async -> [ModelUsage] {
            let usage = await CodexSessionCostEstimator(sessionsURL: root.appendingPathComponent(directory))
                .estimateRecentUsage(dayCount: 14, now: now)
            return usage.values.flatMap { $0 }
        }
        let u = tokens(100, 10)
        _ = try write("legacy", "a", [context(), legacy(u, total: u), legacy(u, total: u, at: 11), legacy(u, total: tokens(200, 20), at: 12)])
        try expect(await read("legacy").first?.totalTokens == 220, "Repeated legacy notification counted twice")
        _ = try write("modern/2020/01/01", "a", [context(), modern("shared", u), legacy(u, total: u)])
        _ = try write("modern/2020/01/01", "fork", [context(), modern("shared", u), modern("new", u, at: 20)])
        try expect(await read("modern").first?.totalTokens == 220, "Resumed old task, copied response, modern/legacy pair")
        _ = try write("upgrade", "a", [context(), legacy(tokens(40, 10), total: tokens(40, 10), at: 1), modern("after-upgrade", u), legacy(u, total: tokens(140, 20))])
        try expect(await read("upgrade").first?.totalTokens == 160, "Pre-upgrade usage must be retained")
        _ = try write("outside", "a", [context(), modern("old", u, at: -20 * 86_400), modern("future", u, at: 2 * 86_400)])
        try expect(await read("outside").isEmpty, "Out-of-window records must not be counted")
        _ = try write("unknown", "a", [context("unknown-model"), modern("unknown", u)])
        let unknown = await read("unknown")
        try expect(unknown.first?.totalTokens == 110 && unknown.first?.estimatedCostUSD == nil, "No invented model price")
        _ = try write("cache", "a", [context(), modern("cached", tokens(100, 10, cached: 60, write: 10))])
        let cache = await read("cache")
        let expected: Double = 394.0 / 1_000_000.0
        try expect(abs((cache.first?.estimatedCostUSD ?? -1) - expected) < 1e-10, "Cache tokens priced once")
        _ = try write("long", "a", [context(), modern("long", tokens(272_001, 100))])
        let long = await read("long")
        let longExpected: Double = 2_179_008.0 / 1_000_000.0
        try expect(abs((long.first?.estimatedCostUSD ?? -1) - longExpected) < 1e-10, "Long-context price multiplier")
        for (model, inputRate, outputRate) in [("gpt-5.6-terra", 2.0, 12.0), ("gpt-5.6-luna", 0.2, 1.2)] {
            _ = try write(model, "a", [context(model), modern(model, u)])
            let usage = await read(model)
            try expect(abs((usage.first?.estimatedCostUSD ?? -1) - (100 * inputRate + 10 * outputRate) / 1_000_000) < 1e-10,
                       "Standard pricing for \(model)")
        }
    }
}
