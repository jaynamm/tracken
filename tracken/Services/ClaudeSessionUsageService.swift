import Foundation

/// Reads usage metadata only; never authenticates or sends a model request.
nonisolated struct ClaudeSessionUsageService: AnthropicUsageProviding {
    let projectsURL: URL
    private let pricingCatalog: PricingCatalog?

    init() {
        pricingCatalog = .shared
        let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        projectsURL = config.appendingPathComponent("projects", isDirectory: true)
    }

    init(projectsURL: URL, pricingCatalog: PricingCatalog? = nil) {
        self.projectsURL = projectsURL
        self.pricingCatalog = pricingCatalog
    }

    func fetchUsage() async throws -> TokenUsage {
        let projectsURL = projectsURL
        let prices = await pricingCatalog?.snapshot(for: .anthropic) ?? .bundled(for: .anthropic)
        return try await Task.detached(priority: .utility) {
            try Self.loadUsage(at: projectsURL, now: Date(), prices: prices)
        }.value
    }

    static func loadUsage(at root: URL, now: Date, calendar: Calendar = .current,
                          prices: PricingSnapshot = .bundled(for: .anthropic)) throws -> TokenUsage {
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw UsageServiceError.unavailable("No local Claude Code history found. Existing sessions are read automatically when available; no API key is needed.")
        }
        var enumerationFailed = false
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles],
            errorHandler: { _, _ in enumerationFailed = true; return false }
        ) else { throw UsageServiceError.historyReadFailed }
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSeconds = ISO8601DateFormatter()
        var records: [String: ClaudeUsageRecord] = [:]
        var readAnyFile = false
        for case let file as URL in files where file.pathExtension == "jsonl" {
            let data: Data
            do { data = try Data(contentsOf: file, options: .mappedIfSafe) }
            catch { throw UsageServiceError.historyReadFailed }
            readAnyFile = true
            for line in data.split(separator: 10) where !line.isEmpty {
                // Incomplete trailing lines are expected while Claude is writing.
                guard let entry = try? decoder.decode(ClaudeSessionEntry.self, from: Data(line)),
                      entry.type == "assistant", let message = entry.message,
                      let model = message.model, model != "<synthetic>",
                      let usage = message.usage, let id = message.id, !id.isEmpty,
                      let rawTimestamp = entry.timestamp,
                      let timestamp = fractional.date(from: rawTimestamp) ?? wholeSeconds.date(from: rawTimestamp),
                      timestamp <= now else { continue }
                let key = id + ":" + (entry.requestId ?? "")
                let candidate = ClaudeUsageRecord(timestamp: timestamp, model: model, usage: usage)
                if let previous = records[key] {
                    // Content blocks repeat the same message usage; streaming
                    // updates may increase output_tokens. Keep one final count.
                    let final = usage.outputTokens >= previous.usage.outputTokens ? candidate : previous
                    records[key] = ClaudeUsageRecord(timestamp: min(timestamp, previous.timestamp),
                                                     model: final.model, usage: final.usage)
                } else {
                    records[key] = candidate
                }
            }
        }
        if enumerationFailed { throw UsageServiceError.historyReadFailed }
        guard readAnyFile else {
            throw UsageServiceError.unavailable("No local Claude Code session files found. Past usage will appear when local history is available.")
        }

        let daily = Dictionary(grouping: records.values) { calendar.startOfDay(for: $0.timestamp) }
            .map { date, records in
                let models = TokenUsage.aggregateModelUsage(records.map { $0.modelUsage(prices: prices) })
                return DailyUsage(date: date,
                                  inputTokens: models.compactMap(\.inputTokens).reduce(0, +),
                                  outputTokens: models.compactMap(\.outputTokens).reduce(0, +),
                                  estimatedCostUSD: TokenUsage.completeEstimatedCost(for: models),
                                  modelUsage: models)
            }.sorted { $0.date > $1.date }
        let models = TokenUsage.aggregateModelUsage(daily.flatMap(\.modelUsage))
        return TokenUsage(provider: .anthropic, daily: daily, modelUsage: models,
                          estimatedCostUSD: TokenUsage.completeEstimatedCost(for: models), updatedAt: now)
    }
}

nonisolated private struct ClaudeSessionEntry: Decodable {
    let type: String
    let timestamp: String?
    let requestId: String?
    let message: Message?

    struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: ClaudeTokenUsage?
    }
}

nonisolated private struct ClaudeUsageRecord {
    let timestamp: Date
    let model: String
    let usage: ClaudeTokenUsage

    func modelUsage(prices: PricingSnapshot) -> ModelUsage {
        ModelUsage(modelName: model,
                   inputTokens: usage.inputTokens + usage.cacheRead + usage.cacheWrite,
                   outputTokens: usage.outputTokens, cachedInputTokens: usage.cacheRead,
                   cacheWriteInputTokens: usage.cacheWrite, estimatedCostUSD: usage.estimatedCost(for: model, prices: prices))
    }
}

nonisolated private struct ClaudeTokenUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheRead: Int
    let cacheWrite: Int
    let cacheWrite1h: Int
    let speed: String?
    let serviceTier: String?
    let inferenceGeo: String?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens", outputTokens = "output_tokens"
        case cacheRead = "cache_read_input_tokens", cacheWrite = "cache_creation_input_tokens"
        case cacheCreation = "cache_creation", speed
        case serviceTier = "service_tier", inferenceGeo = "inference_geo"
    }
    private struct CacheCreation: Decodable { let ephemeral_1h_input_tokens: Int? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = max(0, try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0)
        outputTokens = max(0, try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0)
        cacheRead = max(0, try c.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0)
        cacheWrite = max(0, try c.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0)
        let creation = try c.decodeIfPresent(CacheCreation.self, forKey: .cacheCreation)
        cacheWrite1h = min(cacheWrite, max(0, creation?.ephemeral_1h_input_tokens ?? 0))
        speed = try c.decodeIfPresent(String.self, forKey: .speed)
        serviceTier = try c.decodeIfPresent(String.self, forKey: .serviceTier)
        inferenceGeo = try c.decodeIfPresent(String.self, forKey: .inferenceGeo)
    }

    /// Current standard API-equivalent token prices, not historical bills or
    /// subscription charges. https://platform.claude.com/docs/en/about-claude/pricing
    /// Verified 2026-09-07. Unrecognized models or pricing modes stay unpriced.
    func estimatedCost(for model: String, prices: PricingSnapshot) -> Double? {
        guard speed == nil || speed == "standard",
              serviceTier == nil || serviceTier == "standard",
              inferenceGeo == nil || ["not_available", "global", "us"].contains(inferenceGeo!) else { return nil }
        // Older Claude versions had model-specific long-context conditions.
        // Leave those requests unpriced instead of applying a newer model's rules.
        let olderModel = model.range(of: #"^claude-(opus|sonnet|haiku)-(3|4(?:-[015])?)(?:-\d{8})?$"#,
                                     options: .regularExpression) != nil
        if olderModel && inputTokens + cacheRead + cacheWrite > 200_000 { return nil }
        guard let cost = prices.rate(for: model)?.cost(
            input: inputTokens, cached: cacheRead, write: cacheWrite - cacheWrite1h,
            write1h: cacheWrite1h, output: outputTokens) else { return nil }
        let geoMultiplier = inferenceGeo == "us" ? 1.1 : 1.0
        return cost * geoMultiplier
    }
}
