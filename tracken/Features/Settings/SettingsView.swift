//
//  SettingsView.swift
//  tracken
//

import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case language, codex, claude

    var id: Self { self }

    var title: String {
        switch self {
        case .language: L10n.text("Language")
        case .codex: AIProvider.codex.shortName
        case .claude: AIProvider.anthropic.shortName
        }
    }

    var symbolName: String {
        switch self {
        case .language: "globe"
        case .codex: AIProvider.codex.symbolName
        case .claude: AIProvider.anthropic.symbolName
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared
    @State private var selectedPage: SettingsPage? = .language

    private var currentPage: SettingsPage { selectedPage ?? .language }

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

            HStack(spacing: 0) {
                List(SettingsPage.allCases, selection: $selectedPage) { page in
                    Label(page.title, systemImage: page.symbolName)
                        .padding(.vertical, 6)
                        .tag(page)
                }
                .listStyle(.sidebar)
                .scrollDisabled(true)
                .frame(width: 172)
                .accessibilityLabel(Text("Settings"))

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    Text(currentPage.title)
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    Form {
                        switch currentPage {
                        case .language:
                            languageSettings
                        case .codex:
                            providerSettings(for: .codex)
                        case .claude:
                            providerSettings(for: .anthropic)
                        }
                    }
                    .formStyle(.grouped)
                    .id(currentPage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 760, height: 620)
        .environment(\.locale, settings.language.locale)
    }

    private var languageSettings: some View {
        Section {
            Picker("Display language", selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: language.displayName).tag(language)
                }
            }
            Text("Changes apply immediately to the dashboard, menu bar, and settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func providerSettings(for provider: AIProvider) -> some View {
        Section {
            connectionView(for: provider)
        } header: {
            Label(provider.displayName, systemImage: provider.symbolName)
                .foregroundStyle(provider.accentColor)
        }
        PricingSettingsView(provider: provider)
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
