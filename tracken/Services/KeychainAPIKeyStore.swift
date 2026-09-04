//
//  KeychainAPIKeyStore.swift
//  tracken
//

import Foundation
import Security

nonisolated protocol APIKeyStoring {
    func apiKey(for provider: AIProvider) -> String?
    func setAPIKey(_ key: String, for provider: AIProvider)
    func deleteAPIKey(for provider: AIProvider)
}

nonisolated struct KeychainAPIKeyStore: APIKeyStoring {
    nonisolated static let shared = KeychainAPIKeyStore()

    private let service = "com.tracken.apikeys"

    private init() {}

    func apiKey(for provider: AIProvider) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(readQuery(for: provider) as CFDictionary, &result)

        guard
            status == errSecSuccess,
            let data = result as? Data,
            let key = String(data: data, encoding: .utf8),
            !key.isEmpty
        else { return nil }

        return key
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        let query = identityQuery(for: provider)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func deleteAPIKey(for provider: AIProvider) {
        SecItemDelete(identityQuery(for: provider) as CFDictionary)
    }

    private func identityQuery(for provider: AIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }

    private func readQuery(for provider: AIProvider) -> [String: Any] {
        var query = identityQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
}
