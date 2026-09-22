import Foundation

private struct ChartSelectionFailure: Error { let message: String }

@MainActor enum DailyUsageChartTests {
    static func run() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
        }
        let days = [
            DailyUsage(date: date(7), totalTokens: 100, estimatedCostUSD: 0.5),
            DailyUsage(date: date(8), totalTokens: 200, knownEstimatedCostUSD: 0.75),
            DailyUsage(date: date(9), totalTokens: 300)
        ]
        func selected(_ date: Date, in rows: [DailyUsage]? = nil) -> DailyUsage? {
            DailyUsageChartSelection.day(at: date, in: rows ?? days, calendar: calendar)
        }
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw ChartSelectionFailure(message: message) }
        }

        try check(selected(date(7, 23, 59)) == days[0],
                  "The right side of a bar must not select the following date")
        try check(selected(date(8)) == days[1] && selected(date(8, 23, 59)) == days[1],
                  "Selection must cover the entire calendar day across daylight saving")
        try check(selected(date(9)) == days[2], "Midnight must select the new day's bar")
        try check(selected(date(6, 23, 59)) == nil && selected(date(10)) == nil,
                  "Dates outside the chart must not snap to the first or last bar")
        try check(selected(date(8, 12), in: [days[0], days[2]]) == nil,
                  "Missing dates must not borrow another date's usage")
        try check(selected(date(8), in: []) == nil, "An empty chart must have no selection")
        try check(selected(date(8, 18))?.isPartialCostEstimate == true
                  && selected(date(8, 18))?.knownEstimatedCostUSD == 0.75
                  && selected(date(9, 18))?.knownEstimatedCostUSD == nil,
                  "Hover details must preserve partial and unavailable cost estimates")
        print("PASS: chart selection uses calendar-day boundaries, handles DST and missing days, and preserves cost availability")
    }
}
