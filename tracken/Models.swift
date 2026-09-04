//
//  Models.swift
//  tracken
//
//  Data models describing the AI providers we track and their token usage.
//

import SwiftUI

/// An AI provider whose token usage we can track.
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openAI
    case anthropic

    var id: String { rawValue }

    /// Full, user-facing name shown in settings.
    var displayName: String {
        switch self {
        case .openAI: "ChatGPT (OpenAI)"
        case .anthropic: "Claude (Anthropic)"
        }
    }

    /// Short name shown in compact UI like the status bar.
    var shortName: String {
        switch self {
        case .openAI: "ChatGPT"
        case .anthropic: "Claude"
        }
    }

    /// SF Symbol used as the provider's icon.
    var symbolName: String {
        switch self {
        case .openAI: "bubble.left.and.text.bubble.right"
        case .anthropic: "sparkles"
        }
    }

    /// Accent color used for the provider's card and charts.
    var accentColor: Color {
        switch self {
        case .openAI: .green
        case .anthropic: .orange
        }
    }

    /// Whether the credential is an API key or a linked account token.
    var credentialLabel: String {
        switch self {
        case .openAI: "OpenAI API Key"
        case .anthropic: "Anthropic API Key"
        }
    }
}

/// A single day's token usage.
struct DailyUsage: Identifiable, Codable, Equatable {
    var date: Date
    var inputTokens: Int
    var outputTokens: Int

    var id: Date { date }
    var totalTokens: Int { inputTokens + outputTokens }
}

/// A snapshot of a provider's token usage for the current billing period.
struct TokenUsage: Identifiable, Codable, Equatable {
    var provider: AIProvider
    var inputTokens: Int
    var outputTokens: Int
    var estimatedCostUSD: Double
    var updatedAt: Date

    /// Per-day breakdown returned by the provider.
    var daily: [DailyUsage] = []

    var id: String { provider.id }

    var totalTokens: Int { inputTokens + outputTokens }

    /// The latest 14 calendar days, newest first. Missing dates are represented
    /// with zero usage so the dashboard always shows a complete two-week window.
    var last14Days: [DailyUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let usageByDay = Dictionary(grouping: daily) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<14).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }

            let entries = usageByDay[date] ?? []
            return DailyUsage(
                date: date,
                inputTokens: entries.reduce(0) { $0 + $1.inputTokens },
                outputTokens: entries.reduce(0) { $0 + $1.outputTokens }
            )
        }
    }

    var last14DaysInputTokens: Int {
        last14Days.reduce(0) { $0 + $1.inputTokens }
    }

    var last14DaysOutputTokens: Int {
        last14Days.reduce(0) { $0 + $1.outputTokens }
    }

    var last14DaysTotalTokens: Int {
        last14Days.reduce(0) { $0 + $1.totalTokens }
    }

    /// The single busiest day in the tracked window, if any.
    var peakDay: DailyUsage? {
        last14Days.max { $0.totalTokens < $1.totalTokens }
    }
}

/// Connection state for a provider's credential.
enum ConnectionStatus: Equatable {
    case notConnected
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .notConnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .failed(let message): "Error: \(message)"
        }
    }

    var symbolName: String {
        switch self {
        case .notConnected: "circle.dashed"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notConnected: .secondary
        case .connecting: .blue
        case .connected: .green
        case .failed: .red
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
