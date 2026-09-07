//
//  CodexSessionCostEstimator.swift
//  tracken
//
//  Estimates API-equivalent cost from token metadata in local Codex sessions.
//  Only timestamp, model, turn ID, and token-count fields are decoded.
//

import Foundation

nonisolated protocol CodexSessionCostEstimating: Sendable {
    func estimateRecentUsage(dayCount: Int, now: Date) async -> [Date: [ModelUsage]]
}

nonisolated struct CodexSessionCostEstimator: CodexSessionCostEstimating, Sendable {
    private let sessionsURL: URL
    private let pricingCatalog: PricingCatalog?

    init() {
        pricingCatalog = .shared
        let environment = ProcessInfo.processInfo.environment
        let codexHome = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        sessionsURL = codexHome.appendingPathComponent("sessions", isDirectory: true)
    }

    init(sessionsURL: URL, pricingCatalog: PricingCatalog? = nil) {
        self.sessionsURL = sessionsURL
        self.pricingCatalog = pricingCatalog
    }

    func estimateRecentUsage(dayCount: Int, now: Date = Date()) async -> [Date: [ModelUsage]] {
        guard dayCount > 0 else { return [:] }
        let sessionsURL = sessionsURL
        let prices = await pricingCatalog?.snapshot(for: .codex) ?? .bundled(for: .codex)
        return await Task.detached(priority: .utility) {
            Self.loadUsage(from: sessionsURL, dayCount: dayCount, now: now, prices: prices)
        }.value
    }

    private static func loadUsage(
        from sessionsURL: URL,
        dayCount: Int,
        now: Date,
        prices: PricingSnapshot
    ) -> [Date: [ModelUsage]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) else {
            return [:]
        }

        var accumulators: [Date: [String: UsageAccumulator]] = [:]
        let decoder = JSONDecoder()
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // A resumed task keeps its original directory. Filter by record time,
        // not the date in the path, so recent work in old tasks is included.
        var seenResponseIDs: Set<String> = []
        if let files = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in files where fileURL.pathExtension == "jsonl" {
                loadSession(
                    at: fileURL,
                    prices: prices,
                    cutoff: cutoff,
                    tomorrow: calendar.date(byAdding: .day, value: 1, to: today) ?? now,
                    calendar: calendar,
                    decoder: decoder,
                    timestampFormatter: timestampFormatter,
                    seenResponseIDs: &seenResponseIDs,
                    into: &accumulators
                )
            }
        }

        return accumulators.mapValues { models in
            models.map { modelName, usage in
                ModelUsage(
                    modelName: modelName,
                    inputTokens: usage.inputTokens,
                    outputTokens: usage.outputTokens,
                    cachedInputTokens: usage.cachedInputTokens,
                    cacheWriteInputTokens: usage.cacheWriteInputTokens,
                    estimatedCostUSD: usage.hasKnownPrice ? usage.estimatedCostUSD : nil
                )
            }
            .sorted {
                if $0.totalTokens == $1.totalTokens {
                    return $0.modelName < $1.modelName
                }
                return $0.totalTokens > $1.totalTokens
            }
        }
    }

    private static func loadSession(
        at fileURL: URL,
        prices: PricingSnapshot,
        cutoff: Date,
        tomorrow: Date,
        calendar: Calendar,
        decoder: JSONDecoder,
        timestampFormatter: ISO8601DateFormatter,
        seenResponseIDs: inout Set<String>,
        into accumulators: inout [Date: [String: UsageAccumulator]]
    ) {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return }

        var modelByTurnID: [String: String] = [:]
        var currentModel: String?
        var records: [PendingUsageRecord] = []
        var legacyRecords: [PendingUsageRecord] = []
        var previousLegacyTotal: SessionTokenUsage?

        for line in data.split(separator: 0x0A) where !line.isEmpty {
            guard let entry = try? decoder.decode(SessionEntry.self, from: Data(line)) else {
                continue
            }

            switch entry.type {
            case "turn_context":
                guard let model = entry.payload.model, !model.isEmpty else { continue }
                currentModel = model
                if let turnID = entry.payload.turnID {
                    modelByTurnID[turnID] = model
                }
            case "token_usage_record":
                guard let timestamp = entry.timestamp, let usage = entry.payload.usage else {
                    continue
                }
                records.append(PendingUsageRecord(
                    timestamp: timestamp,
                    responseID: entry.payload.responseID,
                    turnID: entry.payload.turnID,
                    fallbackModel: currentModel,
                    usage: usage
                ))
            case "event_msg" where entry.payload.eventType == "token_count":
                guard
                    let timestamp = entry.timestamp,
                    let usage = entry.payload.info?.lastTokenUsage
                else { continue }
                // Rate-limit updates can repeat last_token_usage without a new
                // response. An unchanged cumulative total is not new usage.
                if let total = entry.payload.info?.totalTokenUsage {
                    guard total != previousLegacyTotal else { continue }
                    previousLegacyTotal = total
                }
                legacyRecords.append(PendingUsageRecord(
                    timestamp: timestamp,
                    responseID: nil,
                    turnID: entry.payload.turnID,
                    fallbackModel: currentModel,
                    usage: usage
                ))
            default:
                continue
            }
        }

        // Older Codex versions only emitted event_msg/token_count. Newer
        // versions also emit token_usage_record, so prefer the latter to avoid
        // counting the same model response twice.
        // A task may span a CLI upgrade. Retain legacy records preceding the
        // first modern record, but do not count its matching legacy event.
        let firstModernDate = records.compactMap { parseTimestamp($0.timestamp) }.min()
        let earlierLegacyRecords = legacyRecords.filter { record in
            guard let firstModernDate else { return true }
            guard let date = parseTimestamp(record.timestamp) else { return false }
            return date < firstModernDate
        }
        for record in earlierLegacyRecords + records {
            guard
                let timestamp = parseTimestamp(record.timestamp),
                timestamp >= cutoff,
                timestamp < tomorrow
            else { continue }
            if let responseID = record.responseID, !responseID.isEmpty,
               !seenResponseIDs.insert(responseID).inserted { continue }

            let model = record.turnID.flatMap { modelByTurnID[$0] }
                ?? record.fallbackModel
                ?? "Unknown Codex model"
            let date = calendar.startOfDay(for: timestamp)
            var accumulator = accumulators[date]?[model] ?? UsageAccumulator()
            accumulator.add(record.usage, price: prices.rate(for: model))
            accumulators[date, default: [:]][model] = accumulator
        }

        func parseTimestamp(_ value: String) -> Date? {
            if let date = timestampFormatter.date(from: value) { return date }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }
    }
}

nonisolated private struct SessionEntry: Decodable {
    let timestamp: String?
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let turnID: String?
        let responseID: String?
        let model: String?
        let usage: SessionTokenUsage?
        let eventType: String?
        let info: TokenCountInfo?

        enum CodingKeys: String, CodingKey {
            case turnID = "turn_id"
            case responseID = "response_id"
            case model
            case usage
            case eventType = "type"
            case info
        }
    }
}

nonisolated private struct SessionTokenUsage: Decodable, Equatable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let cacheWriteInputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case cacheWriteInputTokens = "cache_write_input_tokens"
        case outputTokens = "output_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        cacheWriteInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheWriteInputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
    }
}

nonisolated private struct TokenCountInfo: Decodable {
    let lastTokenUsage: SessionTokenUsage?
    let totalTokenUsage: SessionTokenUsage?

    enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
    }
}

nonisolated private struct PendingUsageRecord {
    let timestamp: String
    let responseID: String?
    let turnID: String?
    let fallbackModel: String?
    let usage: SessionTokenUsage
}

nonisolated private struct UsageAccumulator {
    var inputTokens = 0
    var outputTokens = 0
    var cachedInputTokens = 0
    var cacheWriteInputTokens = 0
    var estimatedCostUSD = 0.0
    var hasKnownPrice = true

    mutating func add(_ usage: SessionTokenUsage, price: TokenPrice?) {
        let input = max(0, usage.inputTokens)
        let cached = min(input, max(0, usage.cachedInputTokens))
        let cacheWrite = min(input - cached, max(0, usage.cacheWriteInputTokens))
        let uncached = input - cached - cacheWrite
        let output = max(0, usage.outputTokens)

        inputTokens += input
        outputTokens += output
        cachedInputTokens += cached
        cacheWriteInputTokens += cacheWrite

        guard let cost = price?.cost(input: uncached, cached: cached, write: cacheWrite,
                                     output: output, contextTokens: input) else {
            hasKnownPrice = false
            return
        }
        estimatedCostUSD += cost
    }
}
