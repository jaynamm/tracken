//
//  SettingsView.swift
//  tracken
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
                        connectionView(for: provider)
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

    @ViewBuilder
    private func connectionView(for provider: AIProvider) -> some View {
        switch provider.authentication {
        case .codexCLI:
            CodexConnectionView()
        case .localSessions:
            ClaudeHistoryConnectionView()
        }
    }
}

#Preview {
    SettingsView()
        .environment(UsageStore())
}
