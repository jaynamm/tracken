//
//  Models.swift
//  tracken
//

import Foundation

/// A known subtotal is shown only with an explicit partial-estimate label.
nonisolated protocol CostEstimating {
    var estimatedCostUSD: Double? { get }
    var knownEstimatedCostUSD: Double? { get }
}

extension CostEstimating {
    nonisolated var isPartialCostEstimate: Bool {
        estimatedCostUSD == nil && knownEstimatedCostUSD != nil
    }
}

nonisolated private func sumKnownCosts(_ costs: [Double?]) -> Double? {
    let known = costs.compactMap { $0 }
    return known.isEmpty ? nil : known.reduce(0, +)
}

nonisolated enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case codex
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex (ChatGPT)"
        case .anthropic: "Claude (Anthropic)"
        }
    }

    var shortName: String {
        switch self {
        case .codex: "Codex"
        case .anthropic: "Claude"
        }
    }

    var authentication: ProviderAuthentication {
        switch self {
        case .codex: .codexCLI
        case .anthropic: .localSessions
        }
    }
}

nonisolated enum ProviderAuthentication: Equatable, Sendable {
    case codexCLI
    case localSessions
}

nonisolated struct DailyUsage: Identifiable, Equatable, Sendable, CostEstimating {
    let date: Date
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int
    let estimatedCostUSD: Double?
    let knownEstimatedCostUSD: Double?
    let modelUsage: [ModelUsage]

    var id: Date { date }
    var hasDetailedBreakdown: Bool { inputTokens != nil && outputTokens != nil }

    init(
        date: Date,
        inputTokens: Int,
        outputTokens: Int,
        estimatedCostUSD: Double? = nil,
        knownEstimatedCostUSD: Double? = nil,
        modelUsage: [ModelUsage] = []
    ) {
        self.date = date
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        totalTokens = inputTokens + outputTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.knownEstimatedCostUSD = estimatedCostUSD ?? knownEstimatedCostUSD
            ?? sumKnownCosts(modelUsage.map(\.knownEstimatedCostUSD))
        self.modelUsage = modelUsage
    }

    init(
        date: Date,
        totalTokens: Int,
        estimatedCostUSD: Double? = nil,
        knownEstimatedCostUSD: Double? = nil,
        modelUsage: [ModelUsage] = []
    ) {
        self.date = date
        inputTokens = nil
        outputTokens = nil
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.knownEstimatedCostUSD = estimatedCostUSD ?? knownEstimatedCostUSD
            ?? sumKnownCosts(modelUsage.map(\.knownEstimatedCostUSD))
        self.modelUsage = modelUsage
    }
}

nonisolated struct ModelUsage: Identifiable, Equatable, Sendable, CostEstimating {
    let modelName: String
    let inputTokens: Int?
    let outputTokens: Int?
    let cachedInputTokens: Int
    let cacheWriteInputTokens: Int
    let totalTokens: Int
    let estimatedCostUSD: Double?
    let knownEstimatedCostUSD: Double?

    var id: String { modelName }

    init(
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int = 0,
        cacheWriteInputTokens: Int = 0,
        estimatedCostUSD: Double? = nil,
        knownEstimatedCostUSD: Double? = nil
    ) {
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        totalTokens = inputTokens + outputTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.knownEstimatedCostUSD = estimatedCostUSD ?? knownEstimatedCostUSD
    }

    init(modelName: String, totalTokens: Int, estimatedCostUSD: Double? = nil,
         knownEstimatedCostUSD: Double? = nil) {
        self.modelName = modelName
        inputTokens = nil
        outputTokens = nil
        cachedInputTokens = 0
        cacheWriteInputTokens = 0
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.knownEstimatedCostUSD = estimatedCostUSD ?? knownEstimatedCostUSD
    }
}

nonisolated struct ProviderAccount: Equatable, Sendable {
    let email: String?
    let planName: String?
}

nonisolated struct CodexRateLimit: Equatable, Sendable {
    let usedPercent: Double
    let windowDurationMinutes: Int
    let resetsAt: Date?
}

nonisolated enum UsageGranularity: Equatable, Sendable {
    case aggregate
    case inputOutput
}

nonisolated struct TokenUsage: Identifiable, Equatable, Sendable, CostEstimating {
    let provider: AIProvider
    let daily: [DailyUsage]
    let modelUsage: [ModelUsage]
    let granularity: UsageGranularity
    let estimatedCostUSD: Double?
    let knownEstimatedCostUSD: Double?
    let updatedAt: Date
    let account: ProviderAccount?
    let lifetimeTokens: Int?
    let rateLimit: CodexRateLimit?

    var id: String { provider.id }
    var hasDetailedBreakdown: Bool { granularity == .inputOutput }
    var totalTokens: Int { daily.reduce(0) { $0 + $1.totalTokens } }

    init(
        provider: AIProvider,
        daily: [DailyUsage],
        modelUsage: [ModelUsage] = [],
        granularity: UsageGranularity = .inputOutput,
        estimatedCostUSD: Double? = nil,
        updatedAt: Date = Date(),
        account: ProviderAccount? = nil,
        lifetimeTokens: Int? = nil,
        rateLimit: CodexRateLimit? = nil
    ) {
        self.provider = provider
        self.daily = daily
        self.modelUsage = modelUsage
        self.granularity = granularity
        self.estimatedCostUSD = estimatedCostUSD
        // Padding days with zero usage must not turn an entirely unpriced
        // period into a misleading $0 partial estimate.
        self.knownEstimatedCostUSD = estimatedCostUSD ?? sumKnownCosts(daily.filter {
            $0.totalTokens > 0 || !$0.modelUsage.isEmpty || ($0.knownEstimatedCostUSD ?? 0) > 0
        }.map(\.knownEstimatedCostUSD))
        self.updatedAt = updatedAt
        self.account = account
        self.lifetimeTokens = lifetimeTokens
        self.rateLimit = rateLimit
    }

    /// Returns a complete, newest-first calendar window and fills missing dates.
    func recentDays(
        count: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyUsage] {
        let today = calendar.startOfDay(for: now)
        let usageByDay = Dictionary(grouping: daily) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }

            let entries = usageByDay[date] ?? []
            let estimatedCost = Self.completeDailyEstimatedCost(for: entries)
            let knownCost = sumKnownCosts(entries.filter {
                $0.totalTokens > 0 || !$0.modelUsage.isEmpty || ($0.knownEstimatedCostUSD ?? 0) > 0
            }.map(\.knownEstimatedCostUSD))
            let modelUsage = Self.aggregateModelUsage(entries.flatMap(\.modelUsage))
            if hasDetailedBreakdown {
                return DailyUsage(
                    date: date,
                    inputTokens: entries.compactMap(\.inputTokens).reduce(0, +),
                    outputTokens: entries.compactMap(\.outputTokens).reduce(0, +),
                    estimatedCostUSD: estimatedCost,
                    knownEstimatedCostUSD: knownCost,
                    modelUsage: modelUsage
                )
            }

            return DailyUsage(
                date: date,
                totalTokens: entries.reduce(0) { $0 + $1.totalTokens },
                estimatedCostUSD: estimatedCost,
                knownEstimatedCostUSD: knownCost,
                modelUsage: modelUsage
            )
        }
    }

    nonisolated static func aggregateModelUsage(_ rows: [ModelUsage]) -> [ModelUsage] {
        Dictionary(grouping: rows, by: \.modelName)
            .map { modelName, entries in
                let costs = entries.compactMap(\.estimatedCostUSD)
                let knownCost = sumKnownCosts(entries.map(\.knownEstimatedCostUSD))
                if entries.contains(where: { $0.inputTokens == nil || $0.outputTokens == nil }) {
                    return ModelUsage(
                        modelName: modelName,
                        totalTokens: entries.reduce(0) { $0 + $1.totalTokens },
                        estimatedCostUSD: costs.count == entries.count ? costs.reduce(0, +) : nil,
                        knownEstimatedCostUSD: knownCost
                    )
                }
                return ModelUsage(
                    modelName: modelName,
                    inputTokens: entries.compactMap(\.inputTokens).reduce(0, +),
                    outputTokens: entries.compactMap(\.outputTokens).reduce(0, +),
                    cachedInputTokens: entries.reduce(0) { $0 + $1.cachedInputTokens },
                    cacheWriteInputTokens: entries.reduce(0) { $0 + $1.cacheWriteInputTokens },
                    estimatedCostUSD: costs.count == entries.count ? costs.reduce(0, +) : nil,
                    knownEstimatedCostUSD: knownCost
                )
            }
            .sorted {
                if $0.totalTokens == $1.totalTokens {
                    return $0.modelName < $1.modelName
                }
                return $0.totalTokens > $1.totalTokens
            }
    }

    func displayUsage(dayCount: Int?, now: Date = Date()) -> TokenUsage {
        let days = dayCount.map { recentDays(count: $0, now: now) }
            ?? daily.sorted { $0.date > $1.date }
        let models = Self.aggregateModelUsage(days.flatMap(\.modelUsage))
        return TokenUsage(provider: provider, daily: days, modelUsage: models,
                          granularity: granularity,
                          estimatedCostUSD: Self.completeDailyEstimatedCost(for: days),
                          updatedAt: updatedAt, account: account,
                          lifetimeTokens: lifetimeTokens, rateLimit: rateLimit)
    }

    var last14Days: [DailyUsage] { recentDays(count: 14) }

    /// Empty dates cost zero; a date with unpriced usage makes the sum unavailable.
    nonisolated static func completeDailyEstimatedCost(for days: [DailyUsage]) -> Double? {
        guard !days.contains(where: {
            ($0.totalTokens > 0 || !$0.modelUsage.isEmpty) && $0.estimatedCostUSD == nil
        }) else {
            return nil
        }
        return days.compactMap(\.estimatedCostUSD).reduce(0, +)
    }

    /// A partial price sum must not look like an estimate for every model.
    nonisolated static func completeEstimatedCost(for models: [ModelUsage]) -> Double? {
        let costs = models.compactMap(\.estimatedCostUSD)
        guard !models.isEmpty, costs.count == models.count else { return nil }
        return costs.reduce(0, +)
    }
    var last14DaysInputTokens: Int { last14Days.compactMap(\.inputTokens).reduce(0, +) }
    var last14DaysOutputTokens: Int { last14Days.compactMap(\.outputTokens).reduce(0, +) }
    var last14DaysTotalTokens: Int { last14Days.reduce(0) { $0 + $1.totalTokens } }
}

nonisolated enum ConnectionStatus: Equatable, Sendable {
    case notConnected
    case connecting
    case connected
    case failed(String)
    case unavailable(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

nonisolated struct ProviderState: Equatable, Sendable {
    var status: ConnectionStatus
    var usage: TokenUsage?

    static let disconnected = ProviderState(status: .notConnected, usage: nil)
}
