//
//  KeychainHelper.swift
//  tracken
//
//  Stores provider API keys in the macOS Keychain instead of UserDefaults,
//  so sensitive credentials are never written to disk in plain text.
//

import Foundation
import Security

/// Lightweight wrapper around the Keychain for reading and writing API keys.
struct KeychainHelper {
    static let shared = KeychainHelper()

    /// Service identifier that groups all of tracken's stored credentials.
    private let service = "com.tracken.apikeys"

    private init() {}

    /// Returns the stored API key for a provider, or `nil` if none is saved.
    func apiKey(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    /// Saves (or replaces) the API key for a provider.
    func setAPIKey(_ key: String, for provider: AIProvider) {
        let data = Data(key.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]

        // Remove any existing item first so we can write a fresh value.
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// Removes the stored API key for a provider.
    func deleteAPIKey(for provider: AIProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
