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

    init() {
        transport = CodexAppServerTransport()
    }

    init(transport: CodexAppServerTransport) {
        self.transport = transport
    }

    func fetchUsage() async throws -> TokenUsage {
        guard let account = try await readAccount() else {
            throw CodexAppServerError.notSignedIn
        }

        async let usageResponse: UsageResponse = transport.request(method: "account/usage/read")
        async let limitsResponse: RateLimitsResponse = transport.request(method: "account/rateLimits/read")
        let (usage, limits) = try await (usageResponse, limitsResponse)

        return TokenUsage(
            provider: .codex,
            daily: (usage.dailyUsageBuckets ?? []).compactMap(Self.makeDailyUsage),
            granularity: .aggregate,
            account: ProviderAccount(
                email: account.email,
                planName: account.planType ?? limits.rateLimits?.planType
            ),
            lifetimeTokens: usage.summary?.lifetimeTokens,
            rateLimit: limits.rateLimits?.primary.map(Self.makeRateLimit)
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

    private static func makeRateLimit(from window: RateLimitsResponse.Window) -> CodexRateLimit {
        CodexRateLimit(
            usedPercent: window.usedPercent,
            windowDurationMinutes: window.windowDurationMins,
            resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:))
        )
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

nonisolated private struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimits?

    nonisolated struct RateLimits: Decodable {
        let primary: Window?
        let planType: String?
    }

    nonisolated struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int
        let resetsAt: Double?
    }
}
