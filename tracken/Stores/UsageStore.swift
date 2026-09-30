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
    private(set) var claudeRateLimits: ClaudeRateLimitSnapshot?
    private(set) var claudeRateLimitError: String?
    private(set) var isAutoRefreshEnabled = false
    private(set) var lastAutomaticRefresh: Date?
    static let automaticRefreshInterval: TimeInterval = 3_600
    private(set) var pricingSnapshots: [AIProvider: PricingSnapshot] = [:]
    private(set) var pricingErrors: [AIProvider: String] = [:]
    private(set) var isRefreshingPrices = false
    private(set) var codexRateLimits: CodexLimitSnapshot?
    private(set) var historyHealth: [AIProvider: RefreshHealth] = [:]
    private(set) var limitHealth: [AIProvider: RefreshHealth] = [:]
    private(set) var hasRecentActivity = false
    private(set) var isRefreshingLimits = false
    let notifications: QuotaNotificationService?
    private let settings: AppSettings
    private let activity: @Sendable (Date) async -> Bool
    private var lastActivityCheck: Date?
    private var lastLimitsAttempt: Date?
    private var lastHistoryAttempt: Date?
    private var monitoringTickInFlight = false
    private var codexGeneration = 0
    private var fullRefreshInFlight = false
    private let pricingCatalog: PricingCatalog?

    private var periodicRefresh: Task<Void, Never>?
    private var rateLimitService = ClaudeRateLimitService()

    private let codexClient: any CodexUsageProviding
    private let anthropicService: any AnthropicUsageProviding
    private let apiKeyStore: any APIKeyStoring
    private var refreshingProviders: Set<AIProvider> = []

    init() {
        settings = .shared
        notifications = QuotaNotificationService(settings: .shared)
        activity = { now in await LocalUsageActivity().hasRecentActivity(now: now) }
        pricingCatalog = .shared
        codexClient = CodexAppServerClient()
        anthropicService = ClaudeSessionUsageService()
        apiKeyStore = KeychainAPIKeyStore.shared
        providerStates = Self.makeInitialStates()
    }

    init(
        codexClient: any CodexUsageProviding,
        anthropicService: any AnthropicUsageProviding,
        apiKeyStore: any APIKeyStoring,
        pricingCatalog: PricingCatalog? = nil,
        settings: AppSettings? = nil,
        notifications: QuotaNotificationService? = nil,
        activity: @escaping @Sendable (Date) async -> Bool = { _ in false }
    ) {
        self.pricingCatalog = pricingCatalog
        self.settings = settings ?? .shared
        self.notifications = notifications
        self.activity = activity
        self.codexClient = codexClient
        self.anthropicService = anthropicService
        self.apiKeyStore = apiKeyStore
        providerStates = Self.makeInitialStates()
    }

    private static func makeInitialStates() -> [AIProvider: ProviderState] {
        Dictionary(uniqueKeysWithValues: AIProvider.allCases.map { ($0, .disconnected) })
    }

    func state(for provider: AIProvider) -> ProviderState {
        var state = providerStates[provider] ?? .disconnected
        if provider == .codex, let snapshot = codexRateLimits, let usage = state.usage,
           snapshot.accountKey == usage.account?.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            state.usage = usage.replacingLimits(snapshot)
        }
        return state
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

    var totalUsage: TotalUsage {
        TotalUsage(usages: AIProvider.allCases.compactMap { usage(for: $0) })
    }

    var combinedLast14DaysTokens: Int { totalUsage.totalTokens }

    // MARK: - App lifetime monitoring

    func startMonitoring(limitsDirectory: URL = ClaudeRateLimitService.defaultDirectory) {
        guard periodicRefresh == nil else { return }
        rateLimitService = ClaudeRateLimitService(directory: limitsDirectory)
        isAutoRefreshEnabled = true
        lastAutomaticRefresh = nil
        periodicRefresh = Task { @MainActor [weak self] in
            await self?.refreshAutomaticallyIfDue()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(UsageRefreshPolicy.tick)) }
                catch { return }
                await self?.refreshAutomaticallyIfDue()
            }
        }
    }

    func stopMonitoring() {
        periodicRefresh?.cancel()
        periodicRefresh = nil
        isAutoRefreshEnabled = false
    }

    func refreshAutomaticallyIfDue(now: Date = Date()) async {
        guard isAutoRefreshEnabled, !Task.isCancelled, !monitoringTickInFlight else { return }
        monitoringTickInFlight = true
        defer { monitoringTickInFlight = false }
        if UsageRefreshPolicy.isDue(last: lastActivityCheck, now: now, interval: 60) {
            lastActivityCheck = now
            hasRecentActivity = await activity(now)
        }
        guard isAutoRefreshEnabled, !Task.isCancelled else { return }
        await refreshLimitsIfDue(now: now)
        guard isAutoRefreshEnabled, !Task.isCancelled else { return }
        let interval = UsageRefreshPolicy.historyInterval(active: hasRecentActivity,
                                                          adaptive: settings.adaptiveRefreshEnabled)
        if UsageRefreshPolicy.isDue(last: lastHistoryAttempt, now: now, interval: interval) {
            lastAutomaticRefresh = now
            await refreshPrices(recalculateUsage: false)
            guard isAutoRefreshEnabled, !Task.isCancelled else { return }
            await refreshHistory(now: now)
        }
    }

    /// Opening the menu refreshes stale quotas without scanning history.
    func menuDidOpen(now: Date = Date()) async {
        await refreshLimitsIfDue(now: now, staleAfter: UsageRefreshPolicy.menuStaleAfter)
    }

    func limits(for provider: AIProvider) -> [CodexRateLimit] {
        if provider == .codex { return codexRateLimits?.limits ?? [] }
        let windows: [(ClaudeRateLimitSnapshot.Window?, Int)] = [
            (claudeRateLimits?.fiveHour, 300), (claudeRateLimits?.sevenDay, 10_080)
        ]
        return windows.compactMap { value, minutes in
            guard let value, value.isValid else { return nil }
            return CodexRateLimit(usedPercent: value.usedPercent, windowDurationMinutes: minutes,
                                  resetsAt: Date(timeIntervalSince1970: value.resetsAt))
        }
    }

    func refreshLimitsIfDue(now: Date = Date(), force: Bool = false, staleAfter: TimeInterval? = nil,
                           provider: AIProvider? = nil) async {
        guard !isRefreshingLimits else { return }
        isRefreshingLimits = true
        defer { isRefreshingLimits = false }
        // A tiny local cache can change between server polls. Never confuse the
        // time we read the file with the time Claude actually supplied its data.
        if provider != .codex && (force || settings.adaptiveRefreshEnabled || UsageRefreshPolicy.isDue(
            last: limitHealth[.anthropic]?.lastAttempt, now: now, interval: staleAfter ?? 3_600)) {
            refreshClaudeRateLimits(now: now)
            if let snapshot = claudeRateLimits {
                await notifications?.process(provider: .anthropic, account: "local-claude",
                    limits: limits(for: .anthropic), observedAt: snapshot.receivedDate, now: now)
            }
        }
        guard provider != .anthropic else { return }
        let interval = staleAfter ?? UsageRefreshPolicy.limitsInterval(
            active: hasRecentActivity, adaptive: settings.adaptiveRefreshEnabled)
        guard force || UsageRefreshPolicy.isDue(last: lastLimitsAttempt, now: now, interval: interval) else { return }
        lastLimitsAttempt = now
        limitHealth[.codex, default: RefreshHealth()].lastAttempt = now
        limitHealth[.codex, default: RefreshHealth()].isRefreshing = true
        defer { limitHealth[.codex, default: RefreshHealth()].isRefreshing = false }
        let generation = codexGeneration
        do {
            let snapshot = try await codexClient.fetchLimits()
            guard generation == codexGeneration else { return }
            let oldKey = codexRateLimits?.accountKey ?? usage(for: .codex)?.account?.email?.lowercased()
            if let oldKey, oldKey != snapshot.accountKey {
                codexGeneration += 1
                setState(.disconnected, for: .codex)
                historyHealth[.codex] = RefreshHealth()
                lastHistoryAttempt = nil
            }
            codexRateLimits = snapshot
            limitHealth[.codex, default: RefreshHealth()].lastSuccess = snapshot.receivedAt
            limitHealth[.codex, default: RefreshHealth()].error = nil
            if let accountKey = snapshot.accountKey {
                await notifications?.process(provider: .codex, account: accountKey,
                    limits: snapshot.limits, observedAt: snapshot.receivedAt, now: now)
            }
        } catch {
            guard generation == codexGeneration else { return }
            limitHealth[.codex, default: RefreshHealth()].error = Self.errorMessage(error)
            if case CodexAppServerError.notSignedIn = error {
                codexGeneration += 1
                codexRateLimits = nil
                setState(.disconnected, for: .codex)
            }
        }
    }

    func refreshClaudeRateLimits(now: Date = Date()) {
        limitHealth[.anthropic, default: RefreshHealth()].lastAttempt = now
        do {
            claudeRateLimits = try rateLimitService.read()
            claudeRateLimitError = nil
            if let snapshot = claudeRateLimits {
                limitHealth[.anthropic, default: RefreshHealth()].lastSuccess = snapshot.receivedDate
            }
            limitHealth[.anthropic, default: RefreshHealth()].error = nil
        } catch {
            claudeRateLimits = nil
            claudeRateLimitError = "Could not read Claude limits. Waiting for the next status-line update."
            limitHealth[.anthropic, default: RefreshHealth()].error = claudeRateLimitError
        }
    }

    // MARK: - Connections

    func removeSavedAnthropicAPIKey() {
        apiKeyStore.deleteAPIKey(for: .anthropic)
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
            codexGeneration += 1
            try await codexClient.logout()
            codexGeneration += 1
            codexRateLimits = nil
            limitHealth[.codex] = RefreshHealth()
            historyHealth[.codex] = RefreshHealth()
            lastLimitsAttempt = nil
            setState(.disconnected, for: .codex)
        } catch {
            setStatus(.failed(Self.errorMessage(error)), for: .codex)
        }
    }

    // MARK: - Refresh

    func refreshPrices(for provider: AIProvider? = nil, force: Bool = false, recalculateUsage: Bool = true) async {
        guard let pricingCatalog, !isRefreshingPrices else { return }
        isRefreshingPrices = true
        defer { isRefreshingPrices = false }
        // Display cached provenance while the public document downloads run.
        let providers = provider.map { [$0] } ?? AIProvider.allCases
        for provider in providers {
            pricingSnapshots[provider] = await pricingCatalog.snapshot(for: provider)
        }
        let changed: Bool
        if let provider {
            changed = await pricingCatalog.refresh(provider, force: force)
        } else {
            async let codexChanged = pricingCatalog.refresh(.codex, force: force)
            async let claudeChanged = pricingCatalog.refresh(.anthropic, force: force)
            let results = await (codexChanged, claudeChanged)
            changed = results.0 || results.1
        }
        for provider in providers {
            pricingSnapshots[provider] = await pricingCatalog.snapshot(for: provider)
            pricingErrors[provider] = await pricingCatalog.error(for: provider)
        }
        if recalculateUsage && changed {
            if let provider { await refresh(provider) }
            else { await refreshAll() }
        }
    }

    func refreshAll() async {
        guard !isRefreshing, !fullRefreshInFlight else { return }
        fullRefreshInFlight = true
        defer { fullRefreshInFlight = false }
        // Separate quotas from history: a failure in either source is visible
        // independently and must not prevent the other source from updating.
        await refreshLimitsIfDue(force: true)
        await refreshHistory(now: Date())
    }

    private func refreshHistory(now: Date) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastHistoryAttempt = now
        defer { isRefreshing = false }
        async let codexRefreshed = refreshProvider(.codex)
        async let claudeRefreshed = refreshProvider(.anthropic)
        let results = await (codexRefreshed, claudeRefreshed)
        if results.0 || results.1 { lastRefreshed = Date() }
    }

    func refresh(_ provider: AIProvider) async {
        await refreshLimitsIfDue(force: true, provider: provider)
        _ = await refreshProvider(provider)
    }

    @discardableResult
    private func refreshProvider(_ provider: AIProvider) async -> Bool {
        guard refreshingProviders.insert(provider).inserted else { return false }
        defer {
            refreshingProviders.remove(provider)
            historyHealth[provider, default: RefreshHealth()].isRefreshing = false
        }
        let generation = codexGeneration
        historyHealth[provider, default: RefreshHealth()].lastAttempt = Date()
        historyHealth[provider, default: RefreshHealth()].isRefreshing = true
        setStatus(.connecting, for: provider)

        do {
            let usage: TokenUsage
            switch provider {
            case .codex:
                usage = try await codexClient.fetchUsage()
            case .anthropic:
                usage = try await anthropicService.fetchUsage()
            }

            guard provider != .codex || generation == codexGeneration else { return false }
            if provider == .codex, let snapshot = codexRateLimits,
               snapshot.accountKey != usage.account?.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                codexGeneration += 1
                codexRateLimits = nil
                lastLimitsAttempt = nil
                limitHealth[.codex] = RefreshHealth(error: "Account changed. Waiting for fresh limits.")
            }
            historyHealth[provider, default: RefreshHealth()].lastSuccess = Date()
            historyHealth[provider, default: RefreshHealth()].error = usage.historyNotice
            setState(ProviderState(status: .connected, usage: usage), for: provider)
            return true
        } catch CodexAppServerError.notSignedIn where provider == .codex {
            guard generation == codexGeneration else { return false }
            codexGeneration += 1
            codexRateLimits = nil
            setState(.disconnected, for: provider)
            historyHealth[provider, default: RefreshHealth()].error = CodexAppServerError.notSignedIn.localizedDescription
            return false
        } catch UsageServiceError.unavailable(let reason) {
            guard provider != .codex || generation == codexGeneration else { return false }
            historyHealth[provider, default: RefreshHealth()].error = reason
            setState(ProviderState(status: .unavailable(reason), usage: nil), for: provider)
            return false
        } catch {
            guard provider != .codex || generation == codexGeneration else { return false }
            historyHealth[provider, default: RefreshHealth()].error = Self.errorMessage(error)
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

    private static func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        codexRateLimits = CodexLimitSnapshot(account: ProviderAccount(email: "demo@example.com", planName: "plus"),
            limits: [CodexRateLimit(usedPercent: 42, windowDurationMinutes: 300,
                                   resetsAt: Date().addingTimeInterval(7_200))],
            receivedAt: Date().addingTimeInterval(-25))
        claudeRateLimits = ClaudeRateLimitSnapshot(receivedAt: Date().addingTimeInterval(-40).timeIntervalSince1970,
            valuesChangedAt: Date().addingTimeInterval(-40).timeIntervalSince1970,
            fiveHour: .init(usedPercent: 81, resetsAt: Date().addingTimeInterval(6_000).timeIntervalSince1970),
            sevenDay: .init(usedPercent: 35, resetsAt: Date().addingTimeInterval(86_400).timeIntervalSince1970))
        for provider in AIProvider.allCases {
            historyHealth[provider] = RefreshHealth(lastAttempt: lastRefreshed, lastSuccess: lastRefreshed)
            limitHealth[provider] = RefreshHealth(lastAttempt: Date(), lastSuccess: Date().addingTimeInterval(-40))
        }
        hasRecentActivity = true
    }
}
#endif
