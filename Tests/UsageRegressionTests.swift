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

nonisolated private struct EmptyClaudeHistory: AnthropicUsageProviding {
    func fetchUsage() async throws -> TokenUsage {
        TokenUsage(provider: .anthropic, daily: [])
    }
}

@main struct UsageRegressionTests {
    @MainActor static func main() async throws {
        try await checkStore()
        try checkMergeAndLimits()
        try await checkSessionRecords()
        try checkClaudeHistory()
        print("PASS: usage store, Claude local history, concurrent refresh, daily merge, rate-limit selection, session deduplication, resumed tasks, pricing")
    }

    @MainActor private static func checkStore() async throws {
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let first = TokenUsage(provider: .codex, daily: [DailyUsage(date: today, totalTokens: 100)], granularity: .aggregate, lifetimeTokens: 1_000)
        let client = FakeCodex(first)
        let keys = MemoryKeys()
        let store = UsageStore(codexClient: client, anthropicService: EmptyClaudeHistory(), apiKeyStore: keys)
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
        await store.refresh(.anthropic)
        guard case .connected = store.status(for: .anthropic) else {
            throw CheckFailure(description: "Claude history must load without an API key")
        }
        try expect(store.usage(for: .anthropic)?.totalTokens == 0 && keys.reads == 0 && keys.writes == 0,
                   "Local history must not read keys or generate demo usage")
        store.removeSavedAnthropicAPIKey()
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

    @MainActor private static func checkClaudeHistory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("claude-history-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("project/subagents"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-09-07T12:00:00Z")!
        func record(_ id: String, model: String = "claude-sonnet-5", at date: String = "2026-09-03T12:00:00Z", output: Int = 40, type: String = "assistant") -> [String: Any] {
            ["type": type, "timestamp": date, "requestId": "request-" + id,
             "message": ["id": id, "model": model, "usage": [
                "input_tokens": 10, "cache_read_input_tokens": 20,
                "cache_creation_input_tokens": 30, "output_tokens": output,
                "cache_creation": ["ephemeral_1h_input_tokens": 20]
             ]]]
        }
        func write(_ name: String, _ rows: [[String: Any]]) throws {
            var data = Data()
            for row in rows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
            data.append(Data("{incomplete trailing line".utf8))
            try data.write(to: root.appendingPathComponent(name))
        }
        try write("project/a.jsonl", [record("one", output: 5), record("one"), record("old", at: "2026-07-02T12:00:00Z"),
                                      record("fake", model: "<synthetic>"), record("user", type: "user"),
                                      record("future", at: "2026-09-08T12:00:00Z")])
        try write("project/subagents/copy.jsonl", [record("one")])
        let usage = try ClaudeSessionUsageService.loadUsage(at: root, now: now)
        try expect(usage.totalTokens == 200, "Repeated content blocks and copied records count once")
        try expect(usage.modelUsage.first?.inputTokens == 120, "Claude input includes cache read and creation tokens")
        try expect(usage.modelUsage.first?.outputTokens == 80, "Keep final streaming output count")
        try expect(usage.recentDays(count: 1, now: now).first?.totalTokens == 0, "No Claude use today must display zero")
        let recent = usage.displayUsage(dayCount: 14, now: now)
        try expect(recent.totalTokens == 100 && recent.modelUsage.first?.totalTokens == 100, "Date filter must also filter model totals")
        try expect(usage.displayUsage(dayCount: nil, now: now).totalTokens == 200, "All history preserves older records")
        try expect(abs((recent.estimatedCostUSD ?? -1) - 0.000529) < 1e-10, "Cache TTL pricing uses separate 5-minute and 1-hour rates")
        try write("unknown.jsonl", [record("unknown", model: "unpriced-model")])
        let unknown = try ClaudeSessionUsageService.loadUsage(at: root, now: now)
        try expect(unknown.totalTokens == 300 && unknown.estimatedCostUSD == nil, "Unknown model usage is retained without inventing prices")
        do {
            _ = try ClaudeSessionUsageService.loadUsage(at: root.appendingPathComponent("missing"), now: now)
            throw CheckFailure(description: "Missing history must report unavailable")
        } catch UsageServiceError.unavailable { }
    }
}
