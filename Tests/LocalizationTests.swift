import Foundation

private struct LocalizationFailure: Error { let message: String }

@MainActor enum LocalizationTests {
    static func run() throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw LocalizationFailure(message: message) }
        }
        let domain = "tracken-language-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = AppSettings(defaults: defaults, preferredLanguages: ["ko-KR"])
        try check(settings.language == .korean, "First launch should follow a Korean system language")
        settings.language = .english
        try check(AppSettings(defaults: defaults, preferredLanguages: ["ko"]).language == .english,
                  "The saved English choice must survive restart and override the system language")
        settings.language = .korean
        try check(AppSettings(defaults: defaults, preferredLanguages: ["en"]).language == .korean,
                  "The saved Korean choice must survive restart")
        defaults.set("unsupported", forKey: AppSettings.languageKey)
        try check(AppSettings(defaults: defaults, preferredLanguages: ["fr-FR"]).language == .english,
                  "Unsupported saved and system languages must fall back to English")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain + ".bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let info = ["CFBundleIdentifier": domain, "CFBundleDevelopmentRegion": "en"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Info.plist"))
        let catalogURL = URL(fileURLWithPath: "tracken/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as! [String: Any]
        let strings = catalog["strings"] as! [String: [String: Any]]
        for language in AppLanguage.allCases {
            let localizedDirectory = directory.appendingPathComponent(language.rawValue + ".lproj")
            try FileManager.default.createDirectory(at: localizedDirectory, withIntermediateDirectories: true)
            let translations = strings.mapValues { entry -> String in
                let localizations = entry["localizations"] as! [String: [String: Any]]
                let unit = localizations[language.rawValue]!["stringUnit"] as! [String: String]
                return unit["value"]!
            }
            try PropertyListSerialization.data(fromPropertyList: translations, format: .binary, options: 0)
                .write(to: localizedDirectory.appendingPathComponent("Localizable.strings"))
        }
        let bundle = Bundle(url: directory)!
        try check(L10n.text("Connected", language: .korean, bundle: bundle) == "연결됨"
                  && L10n.text("Connected", language: .english, bundle: bundle) == "Connected",
                  "Dynamic status copy must use the selected language independently of the system locale")
        try check(L10n.text("Unrecognized system diagnostic", language: .korean, bundle: bundle)
                  == "Unrecognized system diagnostic", "Unknown external errors must retain their original details")
        print("PASS: language defaults, persistence, fallback and Korean/English resource lookup")
    }
}
