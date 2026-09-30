import Foundation

nonisolated enum MenuBarDisplayStyle: String, CaseIterable, Identifiable {
    case iconOnly, gauges, gaugesAndPercent

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .iconOnly: "Icon only"
        case .gauges: "Usage gauges"
        case .gaugesAndPercent: "Gauges and percentages"
        }
    }
}

nonisolated enum MenuBarGaugeLayout: String, CaseIterable, Identifiable {
    case vertical, horizontal

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        }
    }
}

/// Subscription quota only: token totals are not a percentage of a plan's limit.
nonisolated struct MenuBarUsageGauge: Equatable, Sendable {
    let provider: AIProvider
    let limit: CodexRateLimit?

    var usedPercent: Double? { limit?.usedPercent }

    init(provider: AIProvider, limits: [CodexRateLimit], now: Date) {
        self.provider = provider
        limit = limits.filter {
            $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
                && $0.windowDurationMinutes > 0
                && ($0.resetsAt?.timeIntervalSince1970.isFinite ?? true)
                && !$0.hasExpired(at: now)
        }.sorted {
            if $0.usedPercent != $1.usedPercent { return $0.usedPercent > $1.usedPercent }
            return $0.windowDurationMinutes < $1.windowDurationMinutes
        }.first
    }

    static func codex(_ usage: TokenUsage?, now: Date) -> Self {
        Self(provider: .codex, limits: usage?.rateLimits ?? [], now: now)
    }

    static func claude(_ snapshot: ClaudeRateLimitSnapshot?, now: Date) -> Self {
        let windows: [(ClaudeRateLimitSnapshot.Window?, Int)] = [
            (snapshot?.fiveHour, 300), (snapshot?.sevenDay, 10_080)
        ]
        let limits = windows.compactMap { window, minutes -> CodexRateLimit? in
            guard let window, window.isValid else { return nil }
            return CodexRateLimit(usedPercent: window.usedPercent, windowDurationMinutes: minutes,
                                  resetsAt: Date(timeIntervalSince1970: window.resetsAt))
        }
        return Self(provider: .anthropic, limits: limits, now: now)
    }
}
