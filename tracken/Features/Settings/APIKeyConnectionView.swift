//
//  APIKeyConnectionView.swift
//  tracken
//

import SwiftUI

struct APIKeyConnectionView: View {
    @Environment(UsageStore.self) private var store

    let provider: AIProvider
    let credentialLabel: String

    @State private var keyInput = ""
    @State private var isWorking = false

    private var state: ProviderState { store.state(for: provider) }
    private var trimmedKey: String { keyInput.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsStatusRow(status: state.status, isWorking: isWorking)

            if let usage = state.usage {
                connectedContent(usage)
            } else {
                disconnectedContent
            }
        }
    }

    private func connectedContent(_ usage: TokenUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let cost = usage.estimatedCostUSD.map(Format.cost) ?? "—"
            Text("\(Format.tokens(usage.last14DaysTotalTokens)) tokens • \(cost) estimated")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    perform { await store.refresh(provider) }
                } label: {
                    Label("Sync now", systemImage: "arrow.clockwise")
                }
                .disabled(isWorking)

                Spacer()

                Button(role: .destructive) {
                    store.disconnectAPIKey(provider)
                    keyInput = ""
                } label: {
                    Label("Disconnect", systemImage: "trash")
                }
            }
        }
    }

    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your \(credentialLabel) to link the account and pull usage.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField(credentialLabel, text: $keyInput)
                .textFieldStyle(.roundedBorder)

            if case .failed(let message) = state.status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Connect") {
                    perform { await store.connectAPIKey(provider, apiKey: trimmedKey) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedKey.count < 8 || isWorking)
            }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async -> Void) {
        Task {
            isWorking = true
            defer { isWorking = false }
            await operation()
        }
    }
}

struct SettingsStatusRow: View {
    let status: ConnectionStatus
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.color)
            Text(status.label)
            Spacer()
            if isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .font(.callout)
    }
}
