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
}
