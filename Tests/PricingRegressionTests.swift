import Foundation

private struct PricingTestFailure: Error { let message: String }
private func checkPrice(_ condition: Bool, _ message: String) throws {
    if !condition { throw PricingTestFailure(message: message) }
}

private actor PricingHTTPFixture {
    var requests: [URLRequest] = []
    var status = 200
    var document = PricingDefaults.openAI
    func set(status: Int, document: String = PricingDefaults.openAI) {
        self.status = status
        self.document = document
    }
    func fetch(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (Data(document.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                    httpVersion: nil, headerFields: ["ETag": "test-v1"])!)
    }
}

@MainActor enum PricingRegressionTests {
    static func run() async throws {
        let openAI = try OfficialPricingParser.parse(PricingDefaults.openAI + "\n### Batch pricing data\n| invalid |", provider: .codex)
        let claude = try OfficialPricingParser.parse(PricingDefaults.claude, provider: .anthropic)
        try checkPrice(openAI["gpt-6-astra"]?.input == 10 && openAI["gpt-5.4-mini"]?.cachedInput == 0.075,
                       "Parse standard rates without batch contamination")
        try checkPrice(claude["claude-fable-5-1"]?.cachedInput == 0.25 && claude["claude-sonnet-5"]?.cacheWrite1h == 4,
                       "Read actual per-model cache rates, including footnotes and TTL")
        let short = openAI["gpt-6-astra"]!.cost(input: 100, cached: 50, write: 10, output: 20, contextTokens: 272_000)!
        let long = openAI["gpt-6-astra"]!.cost(input: 100, cached: 50, write: 10, output: 20, contextTokens: 272_001)!
        try checkPrice(abs(short - 0.002175) < 1e-10 && abs(long - 0.00385) < 1e-10, "Long-context threshold and exact table rates")
        try checkPrice(openAI["gpt-5.4-mini"]?.cost(input: 10, cached: 0, write: 1, output: 10) == nil,
                       "Missing cache-write price is not zero")
        let snapshot = PricingSnapshot.bundled(for: .codex)
        try checkPrice(snapshot.rate(for: "gpt-5.6-sol-2026-09-01") != nil && snapshot.rate(for: "gpt-5.6-sol-pro") == nil,
                       "Only dated aliases inherit model rates")
        for broken in ["<html>blocked</html>", PricingDefaults.openAI.replacingOccurrences(of: "$4.00", with: "$NaN"),
                       PricingDefaults.claude.replacingOccurrences(of: "Base input tokens", with: "Price per 1000 tokens")] {
            do {
                _ = try OfficialPricingParser.parse(broken, provider: broken.contains("Claude") ? .anthropic : .codex)
                throw PricingTestFailure(message: "Malformed pricing accepted")
            } catch is PricingError { }
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tracken-price-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let http = PricingHTTPFixture()
        let catalog = PricingCatalog(directory: root, fetch: { await http.fetch($0) })
        // Past test times keep the on-disk cache valid when a new actor reloads it.
        let start = Date().addingTimeInterval(-200_000)
        _ = await catalog.refresh(.codex, now: start)
        let first = await catalog.snapshot(for: .codex)
        try checkPrice(!first.isBundled && first.checkedAt == start, "Save validated official catalog")
        _ = await catalog.refresh(.codex, now: start.addingTimeInterval(3_700))
        try checkPrice(await http.requests.count == 1, "No network before daily TTL")
        await http.set(status: 304)
        _ = await catalog.refresh(.codex, now: start.addingTimeInterval(86_401))
        try checkPrice(await http.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "test-v1", "Conditional download")
        let unchanged = await catalog.snapshot(for: .codex)
        try checkPrice(unchanged.checkedAt > first.checkedAt && unchanged.rates == first.rates, "304 updates verification time only")
        await http.set(status: 200, document: "not a price table")
        _ = await catalog.refresh(.codex, force: true, now: start.addingTimeInterval(90_000))
        try checkPrice(await catalog.snapshot(for: .codex) == unchanged, "Invalid document preserves previous cache and timestamp")
        try checkPrice(await catalog.error(for: .codex) != nil, "Failure is visible")
        _ = await catalog.refresh(.codex, now: start.addingTimeInterval(90_001))
        try checkPrice(await http.requests.count == 3, "Failed requests back off")
        let restored = PricingCatalog(directory: root, fetch: { _ in throw PricingError.downloadFailed })
        try checkPrice(await restored.snapshot(for: .codex) == unchanged, "Offline restart uses saved prices")
        _ = await restored.refresh(.codex, force: true)
        try checkPrice(await restored.snapshot(for: .codex) == unchanged, "Network failure retains saved prices")

        let changedText = PricingDefaults.openAI.replacingOccurrences(of: "| gpt-5.6-sol | $4.00 |", with: "| gpt-5.6-sol | $8.00 |")
        await http.set(status: 200, document: changedText)
        try checkPrice(await catalog.refresh(.codex, force: true), "Changed price triggers recomputation")
        try await checkRepricing(catalog: catalog, root: root)
        await http.set(status: 200, document: PricingDefaults.claude)
        _ = await catalog.refresh(.anthropic, force: true)
        try checkPrice(await catalog.snapshot(for: .anthropic).rates["claude-sonnet-5"]?.input == 2,
                       "Provider caches are independent")
        try Data("broken cache".utf8).write(to: root.appendingPathComponent("codex.json"))
        let recovered = PricingCatalog(directory: root)
        try checkPrice(await recovered.snapshot(for: .codex).isBundled, "Corrupt disk cache falls back to bundled prices")
        try checkDays()
        print("PASS: official price parsing, daily cache TTL, conditional download, offline fallback, repricing, complete daily estimates")
    }

    private static func checkRepricing(catalog: PricingCatalog, root: URL) async throws {
        let session = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now)
        let lines = """
        {"type":"turn_context","payload":{"turn_id":"pricing-test","model":"gpt-5.6-sol"}}
        {"type":"token_usage_record","timestamp":"\(stamp)","payload":{"turn_id":"pricing-test","response_id":"one","usage":{"input_tokens":100000,"output_tokens":0}}}
        """
        try lines.write(to: session.appendingPathComponent("sample.jsonl"), atomically: true, encoding: .utf8)
        let usage = await CodexSessionCostEstimator(sessionsURL: session, pricingCatalog: catalog)
            .estimateRecentUsage(dayCount: 1, now: now)
        try checkPrice(abs((usage.values.first?.first?.estimatedCostUSD ?? -1) - 0.8) < 1e-10,
                       "Codex estimator consumes refreshed catalog")
        let claudeLine = """
        {"type":"assistant","timestamp":"\(stamp)","message":{"id":"one","model":"claude-sonnet-5","usage":{"input_tokens":100000,"output_tokens":0}}}
        """
        try claudeLine.write(to: session.appendingPathComponent("claude.jsonl"), atomically: true, encoding: .utf8)
        let prices = PricingSnapshot(providerID: "anthropic", checkedAt: now, isBundled: false,
                                     rates: ["claude-sonnet-5": TokenPrice(input: 4, cachedInput: 0.2, cacheWrite: 2.5, output: 10)])
        let claudeUsage = try ClaudeSessionUsageService.loadUsage(at: session, now: now, prices: prices)
        try checkPrice(abs((claudeUsage.estimatedCostUSD ?? -1) - 0.4) < 1e-10, "Claude estimator consumes refreshed catalog")
    }

    private static func checkDays() throws {
        let now = Date()
        let known = DailyUsage(date: now, totalTokens: 10, estimatedCostUSD: 0.25)
        let unknown = DailyUsage(date: now, totalTokens: 5)
        let usage = TokenUsage(provider: .codex, daily: [known, unknown], granularity: .aggregate)
        try checkPrice(usage.recentDays(count: 1, now: now).first?.estimatedCostUSD == nil,
                       "Same-day unpriced usage prevents a misleading partial sum")
        try checkPrice(usage.displayUsage(dayCount: 14, now: now).estimatedCostUSD == nil, "Period total respects unpriced dates")
        let partial = usage.displayUsage(dayCount: 14, now: now)
        try checkPrice(partial.knownEstimatedCostUSD == 0.25 && partial.isPartialCostEstimate,
                       "Known same-day costs survive normalization with an explicit partial status")
        try checkPrice(partial.daily.first?.knownEstimatedCostUSD == 0.25
                       && partial.daily.first?.isPartialCostEstimate == true,
                       "Day and period show the same known subtotal")
        let unpriced = TokenUsage(provider: .codex, daily: [unknown], granularity: .aggregate)
            .displayUsage(dayCount: 14, now: now)
        try checkPrice(unpriced.knownEstimatedCostUSD == nil && !unpriced.isPartialCostEstimate,
                       "Zero padding must not invent a $0 partial estimate for unpriced usage")
        let sameModel = TokenUsage.aggregateModelUsage([
            ModelUsage(modelName: "gpt-6-astra", inputTokens: 10, outputTokens: 5, estimatedCostUSD: 0.25),
            ModelUsage(modelName: "gpt-6-astra", totalTokens: 30)
        ])
        try checkPrice(sameModel.first?.knownEstimatedCostUSD == 0.25
                       && sameModel.first?.isPartialCostEstimate == true
                       && sameModel.first?.totalTokens == 45,
                       "Mixed records for the same model preserve the priced subtotal and all tokens")
        let knownModel = ModelUsage(modelName: "gpt-6-astra", inputTokens: 10, outputTokens: 5, estimatedCostUSD: 0.25)
        let unknownModel = ModelUsage(modelName: "Unknown Codex model", totalTokens: 27_186)
        let mixedDay = DailyUsage(date: now, totalTokens: 30_000, modelUsage: [knownModel, unknownModel])
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let completeDay = DailyUsage(date: yesterday, totalTokens: 20, estimatedCostUSD: 0.5)
        let mixedUsage = TokenUsage(provider: .codex, daily: [mixedDay, completeDay], granularity: .aggregate)
        let period = mixedUsage.displayUsage(dayCount: 14, now: now)
        try checkPrice(period.knownEstimatedCostUSD == 0.75 && period.isPartialCostEstimate
                       && period.totalTokens == 30_020,
                       "Partial and complete days sum known cost once while retaining official totals")
        try checkPrice(mixedUsage.displayUsage(dayCount: 1, now: now).knownEstimatedCostUSD == 0.25,
                       "Partial estimate follows the selected date window")
        let empty = TokenUsage(provider: .anthropic, daily: []).recentDays(count: 2, now: now)
        try checkPrice(empty.allSatisfy { $0.estimatedCostUSD == 0 && $0.totalTokens == 0 }, "Unused dates have zero cost")
        let priced = TokenUsage(provider: .codex, daily: [known], granularity: .aggregate).displayUsage(dayCount: 14, now: now)
        try checkPrice(priced.estimatedCostUSD == 0.25, "Padded zero days do not erase period cost")
        try checkPrice(priced.knownEstimatedCostUSD == 0.25 && !priced.isPartialCostEstimate,
                       "Complete estimates retain their original presentation")
    }
}
