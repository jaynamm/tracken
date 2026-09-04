//
//  UsageService.swift
//  tracken
//

import Foundation

enum UsageServiceError: LocalizedError {
    case missingKey
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .missingKey: "No API key provided."
        case .invalidKey: "The API key looks invalid."
        }
    }
}

nonisolated protocol AnthropicUsageProviding {
    func fetchUsage(apiKey: String) async throws -> TokenUsage
}

/// Temporary deterministic provider used until the Anthropic Admin Usage API
/// is wired in. Keeping it provider-specific prevents mock behavior leaking
/// into the rest of the app.
nonisolated struct DemoAnthropicUsageService: AnthropicUsageProviding {
    private static let trackedDays = 14

    func fetchUsage(apiKey: String) async throws -> TokenUsage {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw UsageServiceError.missingKey }
        guard key.count >= 8 else { throw UsageServiceError.invalidKey }

        try await Task.sleep(for: .milliseconds(600))
        return makeUsage(seedText: key)
    }

    private func makeUsage(seedText: String) -> TokenUsage {
        var seed = UInt64(bitPattern: Int64(seedText.hashValue))
        func next(upperBound: UInt64) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed % upperBound)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daily = (0..<Self.trackedDays).compactMap { offset -> DailyUsage? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return DailyUsage(
                date: date,
                inputTokens: 4_000 + next(upperBound: 60_000),
                outputTokens: 1_500 + next(upperBound: 24_000)
            )
        }

        let inputTokens = daily.compactMap(\.inputTokens).reduce(0, +)
        let outputTokens = daily.compactMap(\.outputTokens).reduce(0, +)
        let cost = Double(inputTokens) / 1_000_000 * 5
            + Double(outputTokens) / 1_000_000 * 25

        return TokenUsage(
            provider: .anthropic,
            daily: daily,
            estimatedCostUSD: cost
        )
    }
}
