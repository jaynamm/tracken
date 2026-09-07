//
//  UsageService.swift
//  tracken
//

import Foundation

nonisolated enum UsageServiceError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}

nonisolated protocol AnthropicUsageProviding {
    var unavailabilityReason: String? { get }
    func fetchUsage(apiKey: String) async throws -> TokenUsage
}

nonisolated extension AnthropicUsageProviding {
    var unavailabilityReason: String? { nil }
}

/// Never substitute generated tokens for usage that has not been measured.
nonisolated struct UnavailableAnthropicUsageService: AnthropicUsageProviding {
    private let message = "Claude usage is not supported yet. Previously displayed demo tokens and costs were not actual usage."

    var unavailabilityReason: String? { message }

    func fetchUsage(apiKey: String) async throws -> TokenUsage {
        throw UsageServiceError.unavailable(message)
    }
}
