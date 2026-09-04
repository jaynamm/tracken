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

    init() {
        let environment = ProcessInfo.processInfo.environment
        let codexHome = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        sessionsURL = codexHome.appendingPathComponent("sessions", isDirectory: true)
    }

    init(sessionsURL: URL) {
        self.sessionsURL = sessionsURL
    }

    func estimateRecentUsage(dayCount: Int, now: Date = Date()) async -> [Date: [ModelUsage]] {
        guard dayCount > 0 else { return [:] }
        let sessionsURL = sessionsURL
        return await Task.detached(priority: .utility) {
            Self.loadUsage(from: sessionsURL, dayCount: dayCount, now: now)
        }.value
    }

    private static func loadUsage(
        from sessionsURL: URL,
        dayCount: Int,
        now: Date
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

        // Include adjacent directories because session paths use a calendar date
        // that can differ from the user's local date around midnight.
        for offset in -1...dayCount {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                continue
            }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard
                let year = components.year,
                let month = components.month,
                let day = components.day
            else { continue }

            let dayDirectory = sessionsURL
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)

            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dayDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for fileURL in files where fileURL.pathExtension == "jsonl" {
                loadSession(
                    at: fileURL,
                    cutoff: cutoff,
                    tomorrow: calendar.date(byAdding: .day, value: 1, to: today) ?? now,
                    calendar: calendar,
                    decoder: decoder,
                    timestampFormatter: timestampFormatter,
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
        cutoff: Date,
        tomorrow: Date,
        calendar: Calendar,
        decoder: JSONDecoder,
        timestampFormatter: ISO8601DateFormatter,
        into accumulators: inout [Date: [String: UsageAccumulator]]
    ) {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return }

        var modelByTurnID: [String: String] = [:]
        var currentModel: String?
        var records: [PendingUsageRecord] = []
        var legacyRecords: [PendingUsageRecord] = []

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
                    turnID: entry.payload.turnID,
                    fallbackModel: currentModel,
                    usage: usage
                ))
            case "event_msg" where entry.payload.eventType == "token_count":
                guard
                    let timestamp = entry.timestamp,
                    let usage = entry.payload.info?.lastTokenUsage
                else { continue }
                legacyRecords.append(PendingUsageRecord(
                    timestamp: timestamp,
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
        for record in records.isEmpty ? legacyRecords : records {
            guard
                let timestamp = timestampFormatter.date(from: record.timestamp),
                timestamp >= cutoff,
                timestamp < tomorrow
            else { continue }

            let model = record.turnID.flatMap { modelByTurnID[$0] }
                ?? record.fallbackModel
                ?? "Unknown Codex model"
            let date = calendar.startOfDay(for: timestamp)
            var accumulator = accumulators[date]?[model] ?? UsageAccumulator()
            accumulator.add(record.usage, price: CodexPrice.standardRate(for: model))
            accumulators[date, default: [:]][model] = accumulator
        }
    }
}

nonisolated private struct SessionEntry: Decodable {
    let timestamp: String?
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let turnID: String?
        let model: String?
        let usage: SessionTokenUsage?
        let eventType: String?
        let info: TokenCountInfo?

        enum CodingKeys: String, CodingKey {
            case turnID = "turn_id"
            case model
            case usage
            case eventType = "type"
            case info
        }
    }
}

nonisolated private struct SessionTokenUsage: Decodable {
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

    enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
    }
}

nonisolated private struct PendingUsageRecord {
    let timestamp: String
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

    mutating func add(_ usage: SessionTokenUsage, price: CodexPrice?) {
        let input = max(0, usage.inputTokens)
        let cached = min(input, max(0, usage.cachedInputTokens))
        let cacheWrite = min(input - cached, max(0, usage.cacheWriteInputTokens))
        let uncached = input - cached - cacheWrite
        let output = max(0, usage.outputTokens)

        inputTokens += input
        outputTokens += output
        cachedInputTokens += cached
        cacheWriteInputTokens += cacheWrite

        guard let price else {
            hasKnownPrice = false
            return
        }
        estimatedCostUSD += Double(uncached) / 1_000_000 * price.input
            + Double(cached) / 1_000_000 * price.cachedInput
            + Double(cacheWrite) / 1_000_000 * price.cacheWriteInput
            + Double(output) / 1_000_000 * price.output
    }
}

nonisolated private struct CodexPrice {
    let input: Double
    let cachedInput: Double
    let cacheWriteInput: Double
    let output: Double

    /// Standard API rates in USD per million tokens, checked 2026-09-04.
    static func standardRate(for model: String) -> CodexPrice? {
        let normalized = model.lowercased()
        if normalized.hasPrefix("gpt-5.6-sol") {
            return CodexPrice(input: 4, cachedInput: 0.40, cacheWriteInput: 5, output: 20)
        }
        if normalized.hasPrefix("gpt-5.6-terra") {
            return CodexPrice(input: 2, cachedInput: 0.20, cacheWriteInput: 2.50, output: 12)
        }
        if normalized.hasPrefix("gpt-5.6-luna") {
            return CodexPrice(input: 0.20, cachedInput: 0.02, cacheWriteInput: 0.25, output: 1.20)
        }
        return nil
    }
}
