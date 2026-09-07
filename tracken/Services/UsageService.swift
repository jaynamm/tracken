//
//  UsageService.swift
//  tracken
//

import Foundation

nonisolated enum UsageServiceError: LocalizedError {
    case unavailable(String)
    case historyReadFailed

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .historyReadFailed: "Could not read Claude Code history. Check access to the local projects folder and try again."
        }
    }
}

nonisolated protocol AnthropicUsageProviding: Sendable {
    func fetchUsage() async throws -> TokenUsage
}
