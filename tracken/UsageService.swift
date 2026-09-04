//
//  UsageService.swift
//  tracken
//
//  Fetches token-usage data for a provider given its API key.
//
//  NOTE: This sample returns representative (mock) data so the app is fully
//  runnable without live credentials. The real network calls are outlined in
//  comments — drop a URLSession request in where indicated and map the JSON
//  response onto `TokenUsage`.
//

import Foundation

/// Errors surfaced while fetching usage.
enum UsageServiceError: LocalizedError {
    case missingKey
    case invalidKey
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "No API key provided."
        case .invalidKey: "The API key looks invalid."
        case .network(let message): message
        }
    }
}

/// Retrieves token usage from each provider's usage endpoint.
struct UsageService {

    /// Fetches the current billing-period usage for a provider.
    ///
    /// - Parameters:
    ///   - provider: The provider to query.
    ///   - apiKey: The credential to authenticate with.
    func fetchUsage(for provider: AIProvider, apiKey: String) async throws -> TokenUsage {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw UsageServiceError.missingKey }
        guard key.count >= 8 else { throw UsageServiceError.invalidKey }

        switch provider {
        case .openAI:
            return try await fetchOpenAIUsage(apiKey: key)
        case .anthropic:
            return try await fetchAnthropicUsage(apiKey: key)
        }
    }

    // MARK: - OpenAI

    private func fetchOpenAIUsage(apiKey: String) async throws -> TokenUsage {
        // Real implementation:
        //
        //   let start = ISO8601 start-of-month timestamp
        //   var request = URLRequest(
        //       url: URL(string: "https://api.openai.com/v1/organization/usage/completions?start_time=\(start)")!)
        //   request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        //   let (data, response) = try await URLSession.shared.data(for: request)
        //   // decode `input_tokens` / `output_tokens` from the aggregated buckets.
        //
        // For this sample we simulate a short round trip and return mock data.
        try await Self.simulateLatency()
        return Self.mockUsage(for: .openAI, apiKey: apiKey)
    }

    // MARK: - Anthropic

    private func fetchAnthropicUsage(apiKey: String) async throws -> TokenUsage {
        // Real implementation (requires an Admin API key, `sk-ant-admin…`):
        //
        //   var request = URLRequest(
        //       url: URL(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!)
        //   request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        //   request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        //   let (data, response) = try await URLSession.shared.data(for: request)
        //   // sum `uncached_input_tokens` + `output_tokens` across the returned buckets.
        //
        // For this sample we simulate a short round trip and return mock data.
        try await Self.simulateLatency()
        return Self.mockUsage(for: .anthropic, apiKey: apiKey)
    }

    // MARK: - Mock helpers

    private static func simulateLatency() async throws {
        try await Task.sleep(nanoseconds: 600_000_000)
    }

    /// Number of days of history the sample generates.
    static let trackedDays = 14

    /// Deterministic mock usage derived from the key, so a given key always
    /// produces the same numbers within a session — making the sample feel real.
    /// Builds a per-day breakdown first, then derives the period totals from it.
    private static func mockUsage(for provider: AIProvider, apiKey: String) -> TokenUsage {
        var seed = UInt64(abs(apiKey.hashValue))
        func next(_ upper: UInt64) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed % upper)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var daily: [DailyUsage] = []
        for offset in stride(from: trackedDays - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            daily.append(
                DailyUsage(
                    date: day,
                    inputTokens: 4_000 + next(60_000),
                    outputTokens: 1_500 + next(24_000)
                )
            )
        }

        let input = daily.reduce(0) { $0 + $1.inputTokens }
        let output = daily.reduce(0) { $0 + $1.outputTokens }

        // Rough per-million-token pricing for a plausible cost estimate.
        let (inRate, outRate): (Double, Double)
        switch provider {
        case .openAI: (inRate, outRate) = (2.5, 10.0)
        case .anthropic: (inRate, outRate) = (5.0, 25.0)
        }
        let cost = Double(input) / 1_000_000 * inRate + Double(output) / 1_000_000 * outRate

        return TokenUsage(
            provider: provider,
            inputTokens: input,
            outputTokens: output,
            estimatedCostUSD: cost,
            updatedAt: Date(),
            daily: daily
        )
    }
}
