import Foundation

private struct TotalUsageFailure: Error { let message: String }

@MainActor enum TotalUsageTests {
    static func run() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // This window crosses a daylight-saving boundary.
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func total(_ usages: [TokenUsage]) -> TotalUsage {
            TotalUsage(usages: usages, now: now, calendar: calendar)
        }
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw TotalUsageFailure(message: message) }
        }

        let noData = total([])
        try check(!noData.hasUsageData && noData.daily.isEmpty && noData.knownEstimatedCostUSD == nil,
                  "No platforms must show unavailable data instead of a measured zero")

        let emptyClaude = TokenUsage(provider: .anthropic, daily: [])
        let noActivity = total([emptyClaude])
        try check(noActivity.hasUsageData && noActivity.totalTokens == 0 && noActivity.estimatedCostUSD == 0,
                  "A loaded platform with no activity must have zero usage and cost")
        try check(noData.dailyByProvider.isEmpty && Set(noActivity.dailyByProvider.keys) == [.anthropic],
                  "Chart series must include only platforms with loaded usage")

        let codex = TokenUsage(provider: .codex, daily: [
            DailyUsage(date: today.addingTimeInterval(60), totalTokens: 100, estimatedCostUSD: 0.5,
                       modelUsage: [ModelUsage(modelName: "local", inputTokens: 50, outputTokens: 10, estimatedCostUSD: 0.5)]),
            DailyUsage(date: today.addingTimeInterval(120), totalTokens: 20, estimatedCostUSD: 0.25),
            DailyUsage(date: day(-13), totalTokens: 30, estimatedCostUSD: 0.25)
        ], granularity: .aggregate)
        let claude = TokenUsage(provider: .anthropic, daily: [
            DailyUsage(date: today, inputTokens: 200, outputTokens: 50, estimatedCostUSD: 1.25),
            DailyUsage(date: day(-1), inputTokens: 40, outputTokens: 10, estimatedCostUSD: 0.5),
            DailyUsage(date: day(-14), inputTokens: 9_000, outputTokens: 1_000, estimatedCostUSD: 50),
            DailyUsage(date: day(1), inputTokens: 9_000, outputTokens: 1_000, estimatedCostUSD: 50)
        ])
        let combined = total([codex, claude])
        try check(combined.providerCount == 2 && combined.daily.count == 14
                  && combined.daily.first?.date == today && combined.daily.last?.date == day(-13),
                  "Providers must share a newest-first calendar window, including across DST")
        try check(combined.totalTokens == 450 && combined.daily.first?.totalTokens == 370,
                  "Total must sum authoritative daily counts, exclude older/future records, and avoid adding model subtotals")
        try check(combined.estimatedCostUSD == 2.75 && combined.daily.first?.estimatedCostUSD == 2,
                  "Daily and period costs must sum both platforms within the same window")
        try check(combined.daily[2].totalTokens == 0 && combined.daily[2].estimatedCostUSD == 0,
                  "Missing dates for loaded platforms must be zero-filled")
        try check(combined.dailyByProvider[.codex]?.first?.totalTokens == 120
                  && combined.dailyByProvider[.anthropic]?.first?.totalTokens == 250
                  && combined.dailyByProvider[.codex]?.first?.estimatedCostUSD == 0.75
                  && combined.dailyByProvider[.anthropic]?.first?.estimatedCostUSD == 1.25,
                  "Chart segments must preserve each platform's authoritative tokens and cost")
        for daily in combined.daily {
            let segments = combined.dailyByProvider.values.flatMap { $0 }.filter { $0.date == daily.date }
            try check(segments.count == 2 && segments.reduce(0) { $0 + $1.totalTokens } == daily.totalTokens
                      && TokenUsage.completeDailyEstimatedCost(for: segments) == daily.estimatedCostUSD,
                      "Stacked bars must match the combined daily totals across the entire calendar window")
        }

        let unpriced = TokenUsage(provider: .codex, daily: [
            DailyUsage(date: today, totalTokens: 75)
        ], granularity: .aggregate)
        let unknownCost = total([unpriced, emptyClaude])
        try check(unknownCost.totalTokens == 75 && unknownCost.estimatedCostUSD == nil
                  && unknownCost.knownEstimatedCostUSD == nil
                  && unknownCost.daily.first?.knownEstimatedCostUSD == nil,
                  "An idle platform and padding dates must not turn unpriced usage into a $0 estimate")

        let partial = total([unpriced, claude])
        try check(partial.estimatedCostUSD == nil && partial.knownEstimatedCostUSD == 1.75
                  && partial.isPartialCostEstimate && partial.daily.first?.isPartialCostEstimate == true
                  && partial.daily.first?.knownEstimatedCostUSD == 1.25,
                  "One unpriced platform must preserve the priced subtotal with partial labels")

        let partialCodex = TokenUsage(provider: .codex, daily: [
            DailyUsage(date: today, totalTokens: 75, knownEstimatedCostUSD: 0.5)
        ], granularity: .aggregate)
        let partialPlatform = total([partialCodex, claude])
        try check(partialPlatform.knownEstimatedCostUSD == 2.25 && partialPlatform.isPartialCostEstimate
                  && partialPlatform.daily.first?.knownEstimatedCostUSD == 1.75,
                  "A platform's existing partial subtotal must survive combined aggregation")
        try check(partial.dailyByProvider[.codex]?.first?.knownEstimatedCostUSD == nil
                  && partialPlatform.dailyByProvider[.codex]?.first?.isPartialCostEstimate == true
                  && partialPlatform.dailyByProvider[.anthropic]?.first?.isPartialCostEstimate == false,
                  "Unknown costs must stay absent and partial shading must apply only to the affected platform")
        print("PASS: Total dashboard aggregation, calendar boundaries, absent platforms, zero activity and partial costs")
    }
}
