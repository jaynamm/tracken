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
        value.formatted(.number.grouping(.automatic).locale(L10n.locale))
    }

    /// Compact token count for tight spaces, e.g. "1.2M", "34.5K".
    static func compactTokens(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).locale(L10n.locale))
    }

    /// Formats a USD cost, e.g. "$12.34".
    static func cost(_ value: Double) -> String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: "USD").locale(L10n.locale)
        if value > 0 && value < 0.01 { return "< " + 0.01.formatted(style) }
        return value.formatted(style)
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

    static func modelName(_ value: String) -> String {
        switch value.lowercased() {
        case "unknown codex model": L10n.text("Unknown Codex model")
        case let model where model.hasPrefix("gpt-5.6-sol"): "GPT-5.6 Sol"
        case let model where model.hasPrefix("gpt-5.6-terra"): "GPT-5.6 Terra"
        case let model where model.hasPrefix("gpt-5.6-luna"): "GPT-5.6 Luna"
        default: value
        }
    }

    /// Relative "updated 2 minutes ago" style string.
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func date(_ date: Date, time: Bool = false) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: time ? .shortened : .omitted).locale(L10n.locale))
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
    }

    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale))
    }
}
