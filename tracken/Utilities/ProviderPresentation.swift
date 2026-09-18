//
//  ProviderPresentation.swift
//  tracken
//

import SwiftUI

extension AIProvider {
    var symbolName: String {
        switch self {
        case .codex: "terminal"
        case .anthropic: "sparkles"
        }
    }

    var accentColor: Color {
        switch self {
        case .codex: .blue
        case .anthropic: .orange
        }
    }
}

extension ConnectionStatus {
    var label: String {
        switch self {
        case .unavailable: L10n.text("No local history")
        case .notConnected: L10n.text("Not connected")
        case .connecting: L10n.text("Connecting…")
        case .connected: L10n.text("Connected")
        case .failed(let message): L10n.format("Error: %@", L10n.message(message))
        }
    }

    var symbolName: String {
        switch self {
        case .unavailable: "info.circle"
        case .notConnected: "circle.dashed"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .unavailable: .secondary
        case .notConnected: .secondary
        case .connecting: .blue
        case .connected: .green
        case .failed: .red
        }
    }
}
