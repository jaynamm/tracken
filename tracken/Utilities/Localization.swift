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

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.languageKey) }
    }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        language = defaults.string(forKey: Self.languageKey).flatMap(AppLanguage.init(rawValue:))
            ?? (preferredLanguages.first?.hasPrefix("ko") == true ? .korean : .english)
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
