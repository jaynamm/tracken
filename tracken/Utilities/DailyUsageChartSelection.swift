import Foundation

nonisolated enum DailyUsageChartSelection {
    /// Bars occupy a calendar day, not the interval nearest to midnight.
    static func day(at date: Date, in days: [DailyUsage], calendar: Calendar = .current) -> DailyUsage? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}
