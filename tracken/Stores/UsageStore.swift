//
//  UsageStore.swift
//  tracken
//

import Foundation
import Observation

@Observable
@MainActor
final class UsageStore {
    private(set) var providerStates: [AIProvider: ProviderState]
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?

    private let codexClient: any CodexUsageProviding
    private let anthropicService: any AnthropicUsageProviding
    private let apiKeyStore: any APIKeyStoring
    private var refreshingProviders: Set<AIProvider> = []

    init() {
        codexClient = CodexAppServerClient()
        anthropicService = UnavailableAnthropicUsageService()
        apiKeyStore = KeychainAPIKeyStore.shared
        providerStates = Self.makeInitialStates(apiKeyStore: apiKeyStore, anthropicService: anthropicService)
    }

    init(
        codexClient: any CodexUsageProviding,
        anthropicService: any AnthropicUsageProviding,
        apiKeyStore: any APIKeyStoring
    ) {
        self.codexClient = codexClient
        self.anthropicService = anthropicService
        self.apiKeyStore = apiKeyStore
        providerStates = Self.makeInitialStates(apiKeyStore: apiKeyStore, anthropicService: anthropicService)
    }

    private static func makeInitialStates(
        apiKeyStore: any APIKeyStoring,
        anthropicService: any AnthropicUsageProviding
    ) -> [AIProvider: ProviderState] {
        Dictionary(uniqueKeysWithValues: AIProvider.allCases.map { provider in
            if provider == .anthropic, let reason = anthropicService.unavailabilityReason {
                return (provider, ProviderState(status: .unavailable(reason), usage: nil))
            }
            let hasCredential = provider.authentication.requiresAPIKey
                && apiKeyStore.apiKey(for: provider) != nil
            return (
                provider,
                ProviderState(status: hasCredential ? .connected : .notConnected, usage: nil)
            )
        })
    }

    func state(for provider: AIProvider) -> ProviderState {
        providerStates[provider] ?? .disconnected
    }

    func usage(for provider: AIProvider) -> TokenUsage? {
        state(for: provider).usage
    }

    func status(for provider: AIProvider) -> ConnectionStatus {
        state(for: provider).status
    }

    func isConnected(_ provider: AIProvider) -> Bool {
        status(for: provider).isConnected
    }

    var connectedProviders: [AIProvider] {
        AIProvider.allCases.filter(isConnected)
    }

    var combinedLast14DaysTokens: Int {
        providerStates.values.reduce(0) {
            $0 + ($1.usage?.last14DaysTotalTokens ?? 0)
        }
    }

    // MARK: - Connections

    func connectAPIKey(_ provider: AIProvider, apiKey: String) async {
        guard provider.authentication.requiresAPIKey else { return }
        if markUnavailableIfNeeded(provider) { return }
        apiKeyStore.setAPIKey(apiKey, for: provider)
        await refresh(provider)
    }

    func disconnectAPIKey(_ provider: AIProvider) {
        guard provider.authentication.requiresAPIKey else { return }
        apiKeyStore.deleteAPIKey(for: provider)
        if markUnavailableIfNeeded(provider) { return }
        setState(.disconnected, for: provider)
    }

    func connectCodex() async {
        setStatus(.connecting, for: .codex)
        do {
            try await codexClient.connectWithChatGPT()
            await refresh(.codex)
        } catch {
            setStatus(.failed(Self.errorMessage(error)), for: .codex)
        }
    }

    func logoutCodex() async {
        do {
            try await codexClient.logout()
            setState(.disconnected, for: .codex)
        } catch {
            setStatus(.failed(Self.errorMessage(error)), for: .codex)
        }
    }

    // MARK: - Refresh

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var refreshedAnyProvider = await refreshProvider(.codex)
        if !markUnavailableIfNeeded(.anthropic), apiKeyStore.apiKey(for: .anthropic) != nil {
            refreshedAnyProvider = await refreshProvider(.anthropic) || refreshedAnyProvider
        }
        if refreshedAnyProvider {
            lastRefreshed = Date()
        }
    }

    func refresh(_ provider: AIProvider) async {
        _ = await refreshProvider(provider)
    }

    @discardableResult
    private func refreshProvider(_ provider: AIProvider) async -> Bool {
        if markUnavailableIfNeeded(provider) { return false }
        guard refreshingProviders.insert(provider).inserted else { return false }
        defer { refreshingProviders.remove(provider) }
        setStatus(.connecting, for: provider)

        do {
            let usage: TokenUsage
            switch provider {
            case .codex:
                usage = try await codexClient.fetchUsage()
            case .anthropic:
                guard let apiKey = apiKeyStore.apiKey(for: provider) else {
                    setState(.disconnected, for: provider)
                    return false
                }
                usage = try await anthropicService.fetchUsage(apiKey: apiKey)
            }

            setState(ProviderState(status: .connected, usage: usage), for: provider)
            return true
        } catch CodexAppServerError.notSignedIn where provider == .codex {
            setState(.disconnected, for: provider)
            return false
        } catch UsageServiceError.unavailable(let reason) {
            setState(ProviderState(status: .unavailable(reason), usage: nil), for: provider)
            return false
        } catch {
            setStatus(.failed(Self.errorMessage(error)), for: provider)
            return false
        }
    }

    private func markUnavailableIfNeeded(_ provider: AIProvider) -> Bool {
        guard provider == .anthropic, let reason = anthropicService.unavailabilityReason else {
            return false
        }
        setState(ProviderState(status: .unavailable(reason), usage: nil), for: provider)
        return true
    }

    private func setStatus(_ status: ConnectionStatus, for provider: AIProvider) {
        var state = state(for: provider)
        state.status = status
        setState(state, for: provider)
    }

    private func setState(_ state: ProviderState, for provider: AIProvider) {
        providerStates[provider] = state
    }

    private static func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private extension ProviderAuthentication {
    var requiresAPIKey: Bool {
        if case .apiKey = self { return true }
        return false
    }
}

#if DOCUMENTATION_SNAPSHOTS
extension UsageStore {
    func loadDocumentationSamples() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for (index, provider) in AIProvider.allCases.enumerated() {
            let daily = (0..<14).compactMap { offset -> DailyUsage? in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                    return nil
                }
                let input = 24_000 + ((13 - offset) * 2_850) + (index * 8_400)
                let output = 9_000 + ((offset % 4) * 2_300) + (index * 3_100)
                if provider == .codex {
                    let cachedInput = input * 4 / 5
                    let estimatedCost = Double(input - cachedInput) / 1_000_000 * 4
                        + Double(cachedInput) / 1_000_000 * 0.40
                        + Double(output) / 1_000_000 * 20
                    let model = ModelUsage(
                        modelName: "gpt-5.6-sol",
                        inputTokens: input,
                        outputTokens: output,
                        cachedInputTokens: cachedInput,
                        estimatedCostUSD: estimatedCost
                    )
                    return DailyUsage(
                        date: date,
                        totalTokens: input + output,
                        estimatedCostUSD: estimatedCost,
                        modelUsage: [model]
                    )
                }
                return DailyUsage(
                        date: date,
                        inputTokens: input,
                        outputTokens: output,
                        estimatedCostUSD: Double(input) / 1_000_000 * 5
                            + Double(output) / 1_000_000 * 25
                    )
            }

            let inputTokens = daily.compactMap(\.inputTokens).reduce(0, +)
            let outputTokens = daily.compactMap(\.outputTokens).reduce(0, +)
            let sonnetInput = inputTokens * 7 / 10
            let sonnetOutput = outputTokens * 7 / 10
            let opusInput = inputTokens - sonnetInput
            let opusOutput = outputTokens - sonnetOutput
            let modelUsage: [ModelUsage]
            if provider == .anthropic {
                modelUsage = [
                    ModelUsage(
                        modelName: "Claude Sonnet (demo)",
                        inputTokens: sonnetInput,
                        outputTokens: sonnetOutput,
                        estimatedCostUSD: Double(sonnetInput) / 1_000_000 * 5
                            + Double(sonnetOutput) / 1_000_000 * 25
                    ),
                    ModelUsage(
                        modelName: "Claude Opus (demo)",
                        inputTokens: opusInput,
                        outputTokens: opusOutput,
                        estimatedCostUSD: Double(opusInput) / 1_000_000 * 5
                            + Double(opusOutput) / 1_000_000 * 25
                    )
                ]
            } else {
                modelUsage = TokenUsage.aggregateModelUsage(daily.flatMap(\.modelUsage))
            }
            let estimatedCost = daily.compactMap(\.estimatedCostUSD).reduce(0, +)

            let usage = TokenUsage(
                provider: provider,
                daily: daily,
                modelUsage: modelUsage,
                granularity: provider == .codex ? .aggregate : .inputOutput,
                estimatedCostUSD: estimatedCost,
                updatedAt: Date().addingTimeInterval(-120),
                account: provider == .codex
                    ? ProviderAccount(email: "demo@example.com", planName: "plus")
                    : nil,
                lifetimeTokens: provider == .codex ? 2_480_000 : nil,
                rateLimit: provider == .codex
                    ? CodexRateLimit(
                        usedPercent: 42,
                        windowDurationMinutes: 300,
                        resetsAt: Date().addingTimeInterval(7_200)
                    )
                    : nil
            )
            setState(ProviderState(status: .connected, usage: usage), for: provider)
        }

        lastRefreshed = Date().addingTimeInterval(-120)
    }
}
#endif
