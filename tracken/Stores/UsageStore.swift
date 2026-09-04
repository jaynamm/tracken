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

    init() {
        codexClient = CodexAppServerClient()
        anthropicService = DemoAnthropicUsageService()
        apiKeyStore = KeychainAPIKeyStore.shared
        providerStates = Self.makeInitialStates(apiKeyStore: apiKeyStore)
    }

    init(
        codexClient: any CodexUsageProviding,
        anthropicService: any AnthropicUsageProviding,
        apiKeyStore: any APIKeyStoring
    ) {
        self.codexClient = codexClient
        self.anthropicService = anthropicService
        self.apiKeyStore = apiKeyStore
        providerStates = Self.makeInitialStates(apiKeyStore: apiKeyStore)
    }

    private static func makeInitialStates(
        apiKeyStore: any APIKeyStoring
    ) -> [AIProvider: ProviderState] {
        Dictionary(uniqueKeysWithValues: AIProvider.allCases.map { provider in
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
        apiKeyStore.setAPIKey(apiKey, for: provider)
        await refresh(provider)
    }

    func disconnectAPIKey(_ provider: AIProvider) {
        guard provider.authentication.requiresAPIKey else { return }
        apiKeyStore.deleteAPIKey(for: provider)
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
        if apiKeyStore.apiKey(for: .anthropic) != nil {
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
        setStatus(.connecting, for: provider)

        do {
            let usage: TokenUsage
            switch provider {
            case .codex:
                let fetchedUsage = try await codexClient.fetchUsage()
                usage = reconcileRecentCodexUsage(fetchedUsage)
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
        } catch {
            setStatus(.failed(Self.errorMessage(error)), for: provider)
            return false
        }
    }

    private func setStatus(_ status: ConnectionStatus, for provider: AIProvider) {
        var state = state(for: provider)
        state.status = status
        setState(state, for: provider)
    }

    private func setState(_ state: ProviderState, for provider: AIProvider) {
        providerStates[provider] = state
    }

    /// The lifetime summary can update before today's server-side daily bucket.
    /// When that happens, carry the observed delta into today's total until the
    /// authoritative daily bucket catches up on a later refresh.
    private func reconcileRecentCodexUsage(_ latest: TokenUsage) -> TokenUsage {
        guard
            let previous = usage(for: .codex),
            let previousLifetime = previous.lifetimeTokens,
            let latestLifetime = latest.lifetimeTokens,
            latestLifetime >= previousLifetime
        else { return latest }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let previousToday = previous.recentDays(count: 1).first?.totalTokens ?? 0
        let latestToday = latest.recentDays(count: 1).first?.totalTokens ?? 0
        let lifetimeDelta = latestLifetime - previousLifetime
        let reconciledToday = max(latestToday, previousToday + lifetimeDelta)
        guard reconciledToday > latestToday else { return latest }

        var daily = latest.daily.filter {
            !calendar.isDate($0.date, inSameDayAs: today)
        }
        daily.append(DailyUsage(date: today, totalTokens: reconciledToday))

        return TokenUsage(
            provider: latest.provider,
            daily: daily,
            modelUsage: latest.modelUsage,
            granularity: latest.granularity,
            estimatedCostUSD: latest.estimatedCostUSD,
            updatedAt: latest.updatedAt,
            account: latest.account,
            lifetimeTokens: latest.lifetimeTokens,
            rateLimit: latest.rateLimit
        )
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
                return provider == .codex
                    ? DailyUsage(date: date, totalTokens: input + output)
                    : DailyUsage(
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
            let modelUsage = provider == .anthropic
                ? [
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
                : []

            let usage = TokenUsage(
                provider: provider,
                daily: daily,
                modelUsage: modelUsage,
                granularity: provider == .codex ? .aggregate : .inputOutput,
                estimatedCostUSD: provider == .anthropic ? 18.76 : nil,
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
