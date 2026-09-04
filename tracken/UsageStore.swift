//
//  UsageStore.swift
//  tracken
//
//  Observable state for the whole app: which providers are connected,
//  their latest usage, and refresh coordination.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class UsageStore {
    /// Latest usage snapshot per provider.
    private(set) var usage: [AIProvider: TokenUsage] = [:]

    /// Connection status per provider.
    private(set) var status: [AIProvider: ConnectionStatus] = [:]

    /// Whether a refresh is currently running.
    private(set) var isRefreshing = false

    /// Timestamp of the last successful refresh across all providers.
    private(set) var lastRefreshed: Date?

    private let service = UsageService()

    init() {
        for provider in AIProvider.allCases {
            let hasKey = KeychainHelper.shared.apiKey(for: provider) != nil
            status[provider] = hasKey ? .connected : .notConnected
        }
    }

    // MARK: - Queries

    func isConnected(_ provider: AIProvider) -> Bool {
        status[provider]?.isConnected ?? false
    }

    func hasKey(_ provider: AIProvider) -> Bool {
        KeychainHelper.shared.apiKey(for: provider) != nil
    }

    /// Providers that currently have a saved credential.
    var connectedProviders: [AIProvider] {
        AIProvider.allCases.filter { isConnected($0) }
    }

    /// Combined token total across all connected providers.
    var combinedTokens: Int {
        usage.values.reduce(0) { $0 + $1.totalTokens }
    }

    /// Combined estimated cost across all connected providers.
    var combinedCostUSD: Double {
        usage.values.reduce(0) { $0 + $1.estimatedCostUSD }
    }

    // MARK: - Credentials

    /// Saves a key, marks the provider connected, and pulls fresh usage.
    func connect(_ provider: AIProvider, apiKey: String) async {
        KeychainHelper.shared.setAPIKey(apiKey, for: provider)
        status[provider] = .connecting
        await refresh(provider)
    }

    /// Removes the saved key and clears any cached usage.
    func disconnect(_ provider: AIProvider) {
        KeychainHelper.shared.deleteAPIKey(for: provider)
        usage[provider] = nil
        status[provider] = .notConnected
    }

    // MARK: - Refresh

    /// Refreshes usage for every connected provider.
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await withTaskGroup(of: Void.self) { group in
            for provider in AIProvider.allCases where hasKey(provider) {
                group.addTask { await self.refresh(provider) }
            }
        }
        lastRefreshed = Date()
    }

    /// Refreshes usage for a single provider.
    func refresh(_ provider: AIProvider) async {
        guard let key = KeychainHelper.shared.apiKey(for: provider) else {
            status[provider] = .notConnected
            return
        }

        if status[provider]?.isConnected != true {
            status[provider] = .connecting
        }

        do {
            let result = try await service.fetchUsage(for: provider, apiKey: key)
            usage[provider] = result
            status[provider] = .connected
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status[provider] = .failed(message)
        }
    }
}
