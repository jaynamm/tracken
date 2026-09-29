//
//  CodexAppServerClient.swift
//  tracken
//

import AppKit
import Foundation

@MainActor
protocol CodexUsageProviding: AnyObject {
    func fetchUsage() async throws -> TokenUsage
    func connectWithChatGPT() async throws
    func logout() async throws
}

/// Converts typed Codex App Server responses into the app's usage model.
@MainActor
final class CodexAppServerClient: CodexUsageProviding {
    private let transport: CodexAppServerTransport
    private let costEstimator: any CodexSessionCostEstimating
    private let history: CodexAccountUsageHistory

    init() {
        transport = CodexAppServerTransport()
        costEstimator = CodexSessionCostEstimator()
        history = CodexAccountUsageHistory()
    }

    init(
        transport: CodexAppServerTransport,
        costEstimator: any CodexSessionCostEstimating = CodexSessionCostEstimator(),
        history: CodexAccountUsageHistory = CodexAccountUsageHistory()
    ) {
        self.transport = transport
        self.costEstimator = costEstimator
        self.history = history
    }

    func fetchUsage() async throws -> TokenUsage {
        guard let account = try await readAccount() else {
            throw CodexAppServerError.notSignedIn
        }

        async let usageResponse = try? await transport.request(method: "account/usage/read", as: UsageResponse.self)
        async let limitsResponse = try? await transport.request(method: "account/rateLimits/read", as: RateLimitsResponse.self)
        async let localEstimates = costEstimator.estimateRecentUsage(dayCount: nil, now: Date())
        let (usage, limits, estimates) = try await (usageResponse, limitsResponse, localEstimates)

        let receivedDaily = usage?.dailyUsageBuckets.map { $0.compactMap(Self.makeDailyUsage) }
        let officialDaily: [DailyUsage]
        // Account/read exposes email, not a stable workspace identifier. Keep
        // account totals separate by normalized login email and never use a
        // shared fallback key when identity is absent.
        if let email = account.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            officialDaily = try await history.merge(account: email.lowercased(), daily: receivedDaily)
        } else {
            officialDaily = receivedDaily ?? []
        }
        let daily = Self.merge(officialDaily: officialDaily, localEstimates: estimates)
        let modelUsage = TokenUsage.aggregateModelUsage(estimates.values.flatMap { $0 })

        return TokenUsage(
            provider: .codex,
            daily: daily,
            modelUsage: modelUsage,
            granularity: .aggregate,
            estimatedCostUSD: TokenUsage.completeDailyEstimatedCost(for: daily),
            account: ProviderAccount(
                email: account.email,
                planName: account.planType ?? limits?.codexLimits?.planType
            ),
            lifetimeTokens: usage?.summary?.lifetimeTokens,
            rateLimit: limits?.codexLimits?.primary?.rateLimit,
            secondaryRateLimit: limits?.codexLimits?.secondary?.rateLimit,
            fillsMissingDaysWithZero: false,
            historyNotice: receivedDaily == nil
                ? "Account daily totals could not be refreshed. Showing saved totals and local history."
                : nil
        )
    }

    func connectWithChatGPT() async throws {
        if try await readAccount() != nil { return }

        let response: LoginStartResponse = try await transport.request(
            method: "account/login/start",
            params: [
                "type": "chatgpt",
                "useHostedLoginSuccessPage": true,
                "appBrand": "codex"
            ]
        )

        guard let url = URL(string: response.authUrl), NSWorkspace.shared.open(url) else {
            throw CodexAppServerError.protocolError("Codex did not return a valid sign-in URL.")
        }

        for _ in 0..<120 {
            try await Task.sleep(for: .seconds(1))
            if try await readAccount() != nil { return }
        }
        throw CodexAppServerError.loginTimedOut
    }

    func logout() async throws {
        let _: EmptyObject = try await transport.request(method: "account/logout")
    }

    private func readAccount() async throws -> AccountResponse.Account? {
        let response: AccountResponse = try await transport.request(method: "account/read")
        guard response.account?.type == "chatgpt" else { return nil }
        return response.account
    }

    private static func makeDailyUsage(from bucket: UsageResponse.DailyBucket) -> DailyUsage? {
        guard let date = usageDateFormatter.date(from: bucket.startDate) else { return nil }
        return DailyUsage(date: date, totalTokens: bucket.tokens)
    }

    static func merge(
        officialDaily: [DailyUsage],
        localEstimates: [Date: [ModelUsage]],
        calendar: Calendar = .current
    ) -> [DailyUsage] {
        var dailyByDate = Dictionary(grouping: officialDaily) {
            calendar.startOfDay(for: $0.date)
        }.mapValues { entries in
            DailyUsage(date: calendar.startOfDay(for: entries[0].date),
                       totalTokens: entries.reduce(0) { $0 + $1.totalTokens })
        }

        for (rawDate, models) in localEstimates {
            let date = calendar.startOfDay(for: rawDate)
            let estimatedCost = TokenUsage.completeEstimatedCost(for: models)
            let totalTokens = dailyByDate[date]?.totalTokens
                ?? models.reduce(0) { $0 + $1.totalTokens }
            dailyByDate[date] = DailyUsage(
                date: date,
                totalTokens: totalTokens,
                estimatedCostUSD: estimatedCost,
                modelUsage: models
            )
        }

        return dailyByDate.values.sorted { $0.date > $1.date }
    }

    private static let usageDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

nonisolated private struct EmptyObject: Decodable {}

nonisolated private struct AccountResponse: Decodable {
    let account: Account?

    nonisolated struct Account: Decodable {
        let type: String
        let email: String?
        let planType: String?
    }
}

nonisolated private struct LoginStartResponse: Decodable {
    let authUrl: String
}

nonisolated private struct UsageResponse: Decodable {
    let summary: Summary?
    let dailyUsageBuckets: [DailyBucket]?

    nonisolated struct Summary: Decodable {
        let lifetimeTokens: Int?
    }

    nonisolated struct DailyBucket: Decodable {
        let startDate: String
        let tokens: Int
    }
}

nonisolated struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimits?
    let rateLimitsByLimitId: [String: RateLimits]?

    var codexLimits: RateLimits? { rateLimitsByLimitId?["codex"] ?? rateLimits }

    nonisolated struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
        let planType: String?
    }

    nonisolated struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int
        let resetsAt: Double?

        var rateLimit: CodexRateLimit {
            CodexRateLimit(usedPercent: usedPercent, windowDurationMinutes: windowDurationMins,
                           resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)))
        }
    }
}
