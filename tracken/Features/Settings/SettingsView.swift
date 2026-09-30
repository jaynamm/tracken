//
//  SettingsView.swift
//  tracken
//

import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case monitoring, notifications, menuBar, language, codex, claude

    var id: Self { self }

    var title: String {
        switch self {
        case .monitoring: L10n.text("Connection status")
        case .notifications: L10n.text("Notifications")
        case .menuBar: L10n.text("Menu bar")
        case .language: L10n.text("Language")
        case .codex: AIProvider.codex.shortName
        case .claude: AIProvider.anthropic.shortName
        }
    }

    var symbolName: String {
        switch self {
        case .monitoring: "antenna.radiowaves.left.and.right"
        case .notifications: "bell"
        case .menuBar: "menubar.rectangle"
        case .language: "globe"
        case .codex: AIProvider.codex.symbolName
        case .claude: AIProvider.anthropic.symbolName
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared
    @State private var selectedPage: SettingsPage? = .monitoring

    private var currentPage: SettingsPage { selectedPage ?? .monitoring }

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
                .frame(width: 196)
                .accessibilityLabel(Text("Settings"))

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    Text(currentPage.title)
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    Form {
                        switch currentPage {
                        case .monitoring:
                            MonitoringSettingsView()
                        case .notifications:
                            NotificationSettingsView()
                        case .menuBar:
                            menuBarSettings
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

    private var menuBarSettings: some View {
        Section {
            Picker("Menu bar display", selection: $settings.menuBarDisplayStyle) {
                ForEach(MenuBarDisplayStyle.allCases) { style in
                    Text(L10n.text(style.titleKey)).tag(style)
                }
            }
            Picker("Gauge layout", selection: $settings.menuBarGaugeLayout) {
                ForEach(MenuBarGaugeLayout.allCases) { layout in
                    Text(L10n.text(layout.titleKey)).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .disabled(settings.menuBarDisplayStyle == .iconOnly)
            Text("Shows the highest usage among each provider's current subscription limits.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Gauges show the percentage used. Missing or expired limits appear as —. Refresh frequency is managed in Connection status.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
