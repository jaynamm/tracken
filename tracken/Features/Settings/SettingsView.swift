//
//  SettingsView.swift
//  tracken
//

import SwiftUI

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared

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
                Section("Language") {
                    Picker("Display language", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(verbatim: language.displayName).tag(language)
                        }
                    }
                    Text("Changes apply immediately to the dashboard, menu bar, and settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                PricingSettingsView()
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
        .environment(\.locale, settings.language.locale)
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
