import Foundation
import Observation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }
    var displayName: String { self == .korean ? "한국어 (Korean)" : "English" }
    var locale: Locale { Locale(identifier: self == .korean ? "ko_KR" : "en_US") }
}

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()
    static let languageKey = "appLanguage"
    static let menuBarDisplayStyleKey = "menuBarDisplayStyle"
    static let menuBarGaugeLayoutKey = "menuBarGaugeLayout"

    var adaptiveRefreshEnabled: Bool {
        didSet { defaults.set(adaptiveRefreshEnabled, forKey: "adaptiveRefreshEnabled") }
    }
    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: "quotaNotificationsEnabled") }
    }
    var codexAlert80: Bool { didSet { defaults.set(codexAlert80, forKey: "codexAlert80") } }
    var codexAlert90: Bool { didSet { defaults.set(codexAlert90, forKey: "codexAlert90") } }
    var claudeAlert80: Bool { didSet { defaults.set(claudeAlert80, forKey: "claudeAlert80") } }
    var claudeAlert90: Bool { didSet { defaults.set(claudeAlert90, forKey: "claudeAlert90") } }
    var recoveryAlertsEnabled: Bool {
        didSet { defaults.set(recoveryAlertsEnabled, forKey: "recoveryAlertsEnabled") }
    }

    func alertThresholds(for provider: AIProvider) -> [Int] {
        let low = provider == .codex ? codexAlert80 : claudeAlert80
        let high = provider == .codex ? codexAlert90 : claudeAlert90
        return [(80, low), (90, high)].compactMap { $0.1 ? $0.0 : nil }
    }

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.languageKey) }
    }
    var menuBarDisplayStyle: MenuBarDisplayStyle {
        didSet { defaults.set(menuBarDisplayStyle.rawValue, forKey: Self.menuBarDisplayStyleKey) }
    }
    var menuBarGaugeLayout: MenuBarGaugeLayout {
        didSet { defaults.set(menuBarGaugeLayout.rawValue, forKey: Self.menuBarGaugeLayoutKey) }
    }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        adaptiveRefreshEnabled = defaults.object(forKey: "adaptiveRefreshEnabled") as? Bool ?? true
        notificationsEnabled = defaults.bool(forKey: "quotaNotificationsEnabled")
        codexAlert80 = defaults.object(forKey: "codexAlert80") as? Bool ?? true
        codexAlert90 = defaults.object(forKey: "codexAlert90") as? Bool ?? true
        claudeAlert80 = defaults.object(forKey: "claudeAlert80") as? Bool ?? true
        claudeAlert90 = defaults.object(forKey: "claudeAlert90") as? Bool ?? true
        recoveryAlertsEnabled = defaults.object(forKey: "recoveryAlertsEnabled") as? Bool ?? true
        language = defaults.string(forKey: Self.languageKey).flatMap(AppLanguage.init(rawValue:))
            ?? (preferredLanguages.first?.hasPrefix("ko") == true ? .korean : .english)
        menuBarDisplayStyle = defaults.string(forKey: Self.menuBarDisplayStyleKey)
            .flatMap(MenuBarDisplayStyle.init(rawValue:)) ?? .gaugesAndPercent
        menuBarGaugeLayout = defaults.string(forKey: Self.menuBarGaugeLayoutKey)
            .flatMap(MenuBarGaugeLayout.init(rawValue:)) ?? .vertical
    }
}

/// Localizes strings assembled outside SwiftUI's LocalizedStringKey interpolation.
/// Reading the observable language also refreshes formatted values when it changes.
@MainActor
enum L10n {
    static var locale: Locale { AppSettings.shared.language.locale }

    static func text(_ key: String) -> String {
        text(key, language: AppSettings.shared.language)
    }

    static func text(_ key: String, language: AppLanguage, bundle: Bundle = .main) -> String {
        guard let path = bundle.path(forResource: language.rawValue, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else { return key }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    static func message(_ message: String) -> String {
        let prefix = "Could not start Codex: "
        if message.hasPrefix(prefix) {
            return format("Could not start Codex: %@", text(String(message.dropFirst(prefix.count))))
        }
        return text(message)
    }
}
