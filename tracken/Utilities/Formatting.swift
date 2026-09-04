//
//  Formatting.swift
//  tracken
//
//  Shared number/date formatting used across the dashboard and status bar.
//

import Foundation

enum Format {
    /// Formats a token count with grouping separators, e.g. "1,234,567".
    nonisolated static func tokens(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// Compact token count for tight spaces, e.g. "1.2M", "34.5K".
    nonisolated static func compactTokens(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    /// Formats a USD cost, e.g. "$12.34".
    nonisolated static func cost(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    nonisolated static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    nonisolated static func planName(_ value: String) -> String {
        switch value.lowercased() {
        case "prolite": "Pro Lite"
        case "plus": "Plus"
        case "pro": "Pro"
        case "team": "Team"
        case "enterprise": "Enterprise"
        default: value.capitalized
        }
    }

    nonisolated static func modelName(_ value: String) -> String {
        switch value.lowercased() {
        case let model where model.hasPrefix("gpt-5.6-sol"): "GPT-5.6 Sol"
        case let model where model.hasPrefix("gpt-5.6-terra"): "GPT-5.6 Terra"
        case let model where model.hasPrefix("gpt-5.6-luna"): "GPT-5.6 Luna"
        default: value
        }
    }

    /// Relative "updated 2 minutes ago" style string.
    nonisolated static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
