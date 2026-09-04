//
//  Formatting.swift
//  tracken
//
//  Shared number/date formatting used across the dashboard and status bar.
//

import Foundation

enum Format {
    /// Formats a token count with grouping separators, e.g. "1,234,567".
    static func tokens(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// Compact token count for tight spaces, e.g. "1.2M", "34.5K".
    static func compactTokens(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    /// Formats a USD cost, e.g. "$12.34".
    static func cost(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    /// Relative "updated 2 minutes ago" style string.
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
