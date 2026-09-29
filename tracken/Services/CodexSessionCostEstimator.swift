//
//  CodexSessionCostEstimator.swift
//  tracken
//
//  Estimates API-equivalent cost from token metadata in local Codex sessions.
//  Only timestamps, model, token counts, and deduplication IDs are decoded.
//

import Foundation

nonisolated protocol CodexSessionCostEstimating: Sendable {
    func estimateRecentUsage(dayCount: Int?, now: Date) async throws -> [Date: [ModelUsage]]
}

nonisolated struct CodexSessionCostEstimator: CodexSessionCostEstimating, Sendable {
    private let sessionDirectories: [URL]
    private let archive: CodexLocalUsageArchive?
    private let pricingCatalog: PricingCatalog?

    init() {
        pricingCatalog = .shared
        let environment = ProcessInfo.processInfo.environment
        let codexHome = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        sessionDirectories = ["sessions", "archived_sessions"].map { codexHome.appendingPathComponent($0, isDirectory: true) }
        archive = CodexLocalUsageArchive()
    }

    init(sessionsURL: URL, pricingCatalog: PricingCatalog? = nil, archiveURL: URL? = nil) {
        sessionDirectories = [sessionsURL]
        self.pricingCatalog = pricingCatalog
        archive = archiveURL.map { CodexLocalUsageArchive(url: $0) }
    }

    func estimateRecentUsage(dayCount: Int?, now: Date = Date()) async throws -> [Date: [ModelUsage]] {
        if let dayCount, dayCount <= 0 { return [:] }
        let directories = sessionDirectories
        let prices = await pricingCatalog?.snapshot(for: .codex) ?? .bundled(for: .codex)
        let scanned = await Task.detached(priority: .utility) { Self.scan(directories) }.value
        let records: [CodexArchivedTokenRecord]
        if let archive {
            records = try await archive.merge(scanned)
        } else {
            records = CodexLocalUsageArchive.uniqueRecords(in: scanned)
        }
        return await Task.detached(priority: .utility) {
            Self.aggregate(records, dayCount: dayCount, now: now, prices: prices)
        }.value
    }

    private static func scan(_ directories: [URL]) -> [String: [CodexArchivedTokenRecord]] {
        var snapshots: [String: [CodexArchivedTokenRecord]] = [:]
        let decoder = JSONDecoder()
        for directory in directories {
            guard let files = FileManager.default.enumerator(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in files where file.pathExtension == "jsonl" {
                // Files with usage replace their prior snapshot. Missing,
                // unreadable, or temporarily empty files retain saved records.
                if let records = loadSession(at: file, decoder: decoder) {
                    snapshots[CodexHistoryKey.hash(file.standardizedFileURL.path)] = records
                }
            }
        }
        return snapshots
    }

    private static func aggregate(_ records: [CodexArchivedTokenRecord], dayCount: Int?, now: Date,
                                  prices: PricingSnapshot) -> [Date: [ModelUsage]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let cutoff = dayCount.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: today) }
            ?? Date.distantPast
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        var accumulators: [Date: [String: UsageAccumulator]] = [:]
        for record in records where record.timestamp >= cutoff && record.timestamp < tomorrow {
            let date = calendar.startOfDay(for: record.timestamp)
            var accumulator = accumulators[date]?[record.model] ?? UsageAccumulator()
            accumulator.add(record.usage, price: prices.rate(for: record.model))
            accumulators[date, default: [:]][record.model] = accumulator
        }

        return accumulators.mapValues { models in
            models.map { modelName, usage in
                if !usage.hasCompleteBreakdown {
                    return ModelUsage(modelName: modelName, totalTokens: usage.totalTokens,
                                      knownEstimatedCostUSD: usage.hasPricedUsage ? usage.estimatedCostUSD : nil)
                }
                return ModelUsage(
                    modelName: modelName,
                    inputTokens: usage.inputTokens,
                    outputTokens: usage.outputTokens,
                    cachedInputTokens: usage.cachedInputTokens,
                    cacheWriteInputTokens: usage.cacheWriteInputTokens,
                    estimatedCostUSD: usage.hasKnownPrice ? usage.estimatedCostUSD : nil,
                    knownEstimatedCostUSD: usage.hasPricedUsage ? usage.estimatedCostUSD : nil
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

    private static func loadSession(at fileURL: URL, decoder: JSONDecoder) -> [CodexArchivedTokenRecord]? {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var sessionID = fileURL.lastPathComponent
        var saved: [CodexArchivedTokenRecord] = []
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
            case "session_meta":
                sessionID = entry.payload.id ?? sessionID
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
        for (index, record) in (earlierLegacyRecords + records).enumerated() {
            guard let timestamp = parseTimestamp(record.timestamp),
                  record.usage.effectiveTotalTokens > 0 else { continue }
            let model = record.turnID.flatMap { modelByTurnID[$0] }
                ?? record.fallbackModel ?? "Unknown Codex model"
            let identity = record.responseID.flatMap { $0.isEmpty ? nil : "response:" + $0 }
                ?? "legacy:\(sessionID):\(index):\(record.timestamp)"
            saved.append(CodexArchivedTokenRecord(id: CodexHistoryKey.hash(identity),
                                                 timestamp: timestamp, model: model, usage: record.usage))
        }
        return saved

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
        let id: String?
        let turnID: String?
        let responseID: String?
        let model: String?
        let usage: SessionTokenUsage?
        let eventType: String?
        let info: TokenCountInfo?

        enum CodingKeys: String, CodingKey {
            case id
            case turnID = "turn_id"
            case responseID = "response_id"
            case model
            case usage
            case eventType = "type"
            case info
        }
    }
}

nonisolated struct SessionTokenUsage: Codable, Equatable, Sendable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let cacheWriteInputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    var effectiveTotalTokens: Int {
        max(totalTokens, max(0, inputTokens) + max(0, outputTokens))
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case cacheWriteInputTokens = "cache_write_input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        cacheWriteInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheWriteInputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
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
    var totalTokens = 0
    var hasCompleteBreakdown = true
    var hasPricedUsage = false

    mutating func add(_ usage: SessionTokenUsage, price: TokenPrice?) {
        let input = max(0, usage.inputTokens)
        let cached = min(input, max(0, usage.cachedInputTokens))
        let cacheWrite = min(input - cached, max(0, usage.cacheWriteInputTokens))
        let uncached = input - cached - cacheWrite
        let output = max(0, usage.outputTokens)

        totalTokens += usage.effectiveTotalTokens
        // Imported summaries can contain only total_tokens, with zero-valued
        // input/output fields. Preserve their usage without inventing a price.
        if usage.effectiveTotalTokens > input + output {
            hasCompleteBreakdown = false
            hasKnownPrice = false
        }

        inputTokens += input
        outputTokens += output
        cachedInputTokens += cached
        cacheWriteInputTokens += cacheWrite

        guard usage.effectiveTotalTokens == input + output,
              let cost = price?.cost(input: uncached, cached: cached, write: cacheWrite,
                                     output: output, contextTokens: input) else {
            hasKnownPrice = false
            return
        }
        hasPricedUsage = true
        estimatedCostUSD += cost
    }
}
