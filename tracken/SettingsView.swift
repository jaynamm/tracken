//
//  SettingsView.swift
//  tracken
//
//  Connect accounts / enter API keys, and control app behavior.
//

import SwiftUI

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                ForEach(AIProvider.allCases) { provider in
                    Section {
                        ProviderCredentialRow(provider: provider)
                    } header: {
                        Label(provider.displayName, systemImage: provider.symbolName)
                            .foregroundStyle(provider.accentColor)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 560)
    }
}

/// One row per provider: enter/save/remove the credential and see status.
private struct ProviderCredentialRow: View {
    @Environment(UsageStore.self) private var store
    let provider: AIProvider

    @State private var keyInput = ""
    @State private var isWorking = false

    private var status: ConnectionStatus {
        store.status[provider] ?? .notConnected
    }

    var body: some View {
        if store.isConnected(provider) {
            connectedView
        } else {
            entryView
        }
    }

    // MARK: Connected

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: status.symbolName)
                    .foregroundStyle(status.color)
                Text(status.label)
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
            }
            .font(.callout)

            if let usage = store.usage[provider] {
                Text("\(Format.tokens(usage.totalTokens)) tokens • \(Format.cost(usage.estimatedCostUSD)) this period")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    Task {
                        isWorking = true
                        await store.refresh(provider)
                        isWorking = false
                    }
                } label: {
                    Label("Sync now", systemImage: "arrow.clockwise")
                }
                .disabled(isWorking)

                Spacer()

                Button(role: .destructive) {
                    store.disconnect(provider)
                    keyInput = ""
                } label: {
                    Label("Disconnect", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Entry

    private var entryView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your \(provider.credentialLabel) to link the account and pull usage.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField(provider.credentialLabel, text: $keyInput)
                .textFieldStyle(.roundedBorder)

            if case .failed(let message) = status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button {
                    Task {
                        isWorking = true
                        await store.connect(provider, apiKey: keyInput)
                        isWorking = false
                    }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).count < 8 || isWorking)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(UsageStore())
}
