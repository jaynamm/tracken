//
//  Models.swift
//  tracken
//

import Foundation

nonisolated enum AIProvider: String, CaseIterable, Identifiable {
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
        case .anthropic: .apiKey(label: "Anthropic API Key")
        }
    }
}

nonisolated enum ProviderAuthentication: Equatable {
    case codexCLI
    case apiKey(label: String)
}

nonisolated struct DailyUsage: Identifiable, Equatable {
    let date: Date
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int
    let estimatedCostUSD: Double?

    var id: Date { date }
    var hasDetailedBreakdown: Bool { inputTokens != nil && outputTokens != nil }

    init(
        date: Date,
        inputTokens: Int,
        outputTokens: Int,
        estimatedCostUSD: Double? = nil
    ) {
        self.date = date
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        totalTokens = inputTokens + outputTokens
        self.estimatedCostUSD = estimatedCostUSD
    }

    init(date: Date, totalTokens: Int, estimatedCostUSD: Double? = nil) {
        self.date = date
        inputTokens = nil
        outputTokens = nil
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}

nonisolated struct ModelUsage: Identifiable, Equatable {
    let modelName: String
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int
    let estimatedCostUSD: Double?

    var id: String { modelName }

    init(
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        estimatedCostUSD: Double? = nil
    ) {
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        totalTokens = inputTokens + outputTokens
        self.estimatedCostUSD = estimatedCostUSD
    }

    init(modelName: String, totalTokens: Int, estimatedCostUSD: Double? = nil) {
        self.modelName = modelName
        inputTokens = nil
        outputTokens = nil
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}

nonisolated struct ProviderAccount: Equatable {
    let email: String?
    let planName: String?
}

nonisolated struct CodexRateLimit: Equatable {
    let usedPercent: Double
    let windowDurationMinutes: Int
    let resetsAt: Date?
}

nonisolated enum UsageGranularity: Equatable {
    case aggregate
    case inputOutput
}

nonisolated struct TokenUsage: Identifiable, Equatable {
    let provider: AIProvider
    let daily: [DailyUsage]
    let modelUsage: [ModelUsage]
    let granularity: UsageGranularity
    let estimatedCostUSD: Double?
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
            let costs = entries.compactMap(\.estimatedCostUSD)
            let estimatedCost = costs.isEmpty
                ? (estimatedCostUSD == nil ? nil : 0)
                : costs.reduce(0, +)
            if hasDetailedBreakdown {
                return DailyUsage(
                    date: date,
                    inputTokens: entries.compactMap(\.inputTokens).reduce(0, +),
                    outputTokens: entries.compactMap(\.outputTokens).reduce(0, +),
                    estimatedCostUSD: estimatedCost
                )
            }

            return DailyUsage(
                date: date,
                totalTokens: entries.reduce(0) { $0 + $1.totalTokens },
                estimatedCostUSD: estimatedCost
            )
        }
    }

    var last14Days: [DailyUsage] { recentDays(count: 14) }
    var last14DaysInputTokens: Int { last14Days.compactMap(\.inputTokens).reduce(0, +) }
    var last14DaysOutputTokens: Int { last14Days.compactMap(\.outputTokens).reduce(0, +) }
    var last14DaysTotalTokens: Int { last14Days.reduce(0) { $0 + $1.totalTokens } }
}

nonisolated enum ConnectionStatus: Equatable {
    case notConnected
    case connecting
    case connected
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

nonisolated struct ProviderState: Equatable {
    var status: ConnectionStatus
    var usage: TokenUsage?

    static let disconnected = ProviderState(status: .notConnected, usage: nil)
}
