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
        let inputRate = 5.0
        let outputRate = 25.0
        var seed = UInt64(bitPattern: Int64(seedText.hashValue))
        func next(upperBound: UInt64) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed % upperBound)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var daily: [DailyUsage] = []
        var sonnetInput = 0
        var sonnetOutput = 0
        var opusInput = 0
        var opusOutput = 0

        for offset in 0..<Self.trackedDays {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                continue
            }

            let inputTokens = 4_000 + next(upperBound: 60_000)
            let outputTokens = 1_500 + next(upperBound: 24_000)
            let sonnetShare = 65 + next(upperBound: 21)
            let dailySonnetInput = inputTokens * sonnetShare / 100
            let dailySonnetOutput = outputTokens * sonnetShare / 100
            let dailyOpusInput = inputTokens - dailySonnetInput
            let dailyOpusOutput = outputTokens - dailySonnetOutput

            sonnetInput += dailySonnetInput
            sonnetOutput += dailySonnetOutput
            opusInput += dailyOpusInput
            opusOutput += dailyOpusOutput

            let estimatedCost = Self.estimatedCost(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                inputRate: inputRate,
                outputRate: outputRate
            )
            daily.append(DailyUsage(
                date: date,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                estimatedCostUSD: estimatedCost
            ))
        }

        let modelUsage = [
            Self.makeModelUsage(
                name: "Claude Sonnet (demo)",
                inputTokens: sonnetInput,
                outputTokens: sonnetOutput,
                inputRate: inputRate,
                outputRate: outputRate
            ),
            Self.makeModelUsage(
                name: "Claude Opus (demo)",
                inputTokens: opusInput,
                outputTokens: opusOutput,
                inputRate: inputRate,
                outputRate: outputRate
            )
        ]
        let cost = daily.compactMap(\.estimatedCostUSD).reduce(0, +)

        return TokenUsage(
            provider: .anthropic,
            daily: daily,
            modelUsage: modelUsage,
            estimatedCostUSD: cost
        )
    }

    private static func makeModelUsage(
        name: String,
        inputTokens: Int,
        outputTokens: Int,
        inputRate: Double,
        outputRate: Double
    ) -> ModelUsage {
        ModelUsage(
            modelName: name,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCostUSD: estimatedCost(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                inputRate: inputRate,
                outputRate: outputRate
            )
        )
    }

    private static func estimatedCost(
        inputTokens: Int,
        outputTokens: Int,
        inputRate: Double,
        outputRate: Double
    ) -> Double {
        Double(inputTokens) / 1_000_000 * inputRate
            + Double(outputTokens) / 1_000_000 * outputRate
    }
}
