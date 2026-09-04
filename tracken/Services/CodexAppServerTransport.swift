//
//  CodexAppServerTransport.swift
//  tracken
//

import Foundation

enum CodexAppServerError: LocalizedError {
    case cliNotFound
    case launchFailed(String)
    case protocolError(String)
    case notSignedIn
    case loginTimedOut

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "Codex CLI was not found. Install it, then try again."
        case .launchFailed(let message):
            "Could not start Codex: \(message)"
        case .protocolError(let message):
            message
        case .notSignedIn:
            "Sign in to Codex with your ChatGPT account."
        case .loginTimedOut:
            "ChatGPT sign-in timed out. Please try again."
        }
    }
}

/// Owns one `codex app-server` process and handles its JSONL request/response stream.
@MainActor
final class CodexAppServerTransport {
    private typealias Completion = (Result<Data, Error>) -> Void

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var nextRequestID = 1
    private var pendingRequests: [Int: Completion] = [:]
    private var isInitialized = false

    deinit {
        outputHandle?.readabilityHandler = nil
        try? inputHandle?.close()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func request<Response: Decodable>(
        method: String,
        params: [String: Any] = [:],
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        try await startIfNeeded()
        return try await sendRequest(method: method, params: params, as: responseType)
    }

    private func startIfNeeded() async throws {
        guard !isInitialized else { return }
        guard let executableURL = Self.findCodexExecutable() else {
            throw CodexAppServerError.cliNotFound
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consume(data)
            }
        }

        process.terminationHandler = { [weak self, weak process] terminatedProcess in
            Task { @MainActor [weak self, weak process] in
                guard let self, self.process === process else { return }
                self.process = nil
                self.inputHandle = nil
                self.outputHandle?.readabilityHandler = nil
                self.outputHandle = nil
                self.isInitialized = false
                self.failPendingRequests(
                    with: CodexAppServerError.launchFailed(
                        "process exited with status \(terminatedProcess.terminationStatus)"
                    )
                )
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            throw CodexAppServerError.launchFailed(error.localizedDescription)
        }

        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputHandle

        do {
            let _: EmptyResponse = try await sendRequest(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "tracken",
                        "title": "tracken",
                        "version": Bundle.main.object(
                            forInfoDictionaryKey: "CFBundleShortVersionString"
                        ) as? String ?? "1.0"
                    ],
                    "capabilities": ["experimentalApi": true]
                ],
                as: EmptyResponse.self
            )
            try sendNotification(method: "initialized")
            isInitialized = true
        } catch {
            stopProcess()
            throw error
        }
    }

    private func sendRequest<Response: Decodable>(
        method: String,
        params: [String: Any],
        as responseType: Response.Type
    ) async throws -> Response {
        let requestID = nextRequestID
        nextRequestID += 1

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestID] = { continuation.resume(with: $0) }

            do {
                try writeJSON(["id": requestID, "method": method, "params": params])
                scheduleTimeout(for: requestID, method: method)
            } catch {
                pendingRequests[requestID] = nil
                continuation.resume(throwing: error)
            }
        }

        do {
            return try JSONDecoder().decode(responseType, from: responseData)
        } catch {
            throw CodexAppServerError.protocolError(
                "Codex returned an unexpected response for \(method)."
            )
        }
    }

    private func scheduleTimeout(for requestID: Int, method: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let completion = self?.pendingRequests.removeValue(forKey: requestID) else {
                return
            }
            completion(
                .failure(
                    CodexAppServerError.protocolError("Codex request timed out: \(method)")
                )
            )
        }
    }

    private func sendNotification(method: String) throws {
        try writeJSON(["method": method, "params": [:]])
    }

    private func writeJSON(_ object: [String: Any]) throws {
        guard let inputHandle else {
            throw CodexAppServerError.launchFailed("standard input is unavailable")
        }

        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)

        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newlineIndex])
            outputBuffer.removeSubrange(...newlineIndex)
            resolveResponse(from: line)
        }
    }

    private func resolveResponse(from line: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let requestID = (object["id"] as? NSNumber)?.intValue,
            let completion = pendingRequests.removeValue(forKey: requestID)
        else { return }

        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Codex returned an unknown error."
            completion(.failure(CodexAppServerError.protocolError(message)))
            return
        }

        let result = object["result"] ?? [:]
        do {
            let data = try JSONSerialization.data(withJSONObject: result)
            completion(.success(data))
        } catch {
            completion(.failure(CodexAppServerError.protocolError("Invalid Codex response.")))
        }
    }

    private func stopProcess() {
        outputHandle?.readabilityHandler = nil
        try? inputHandle?.close()
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        inputHandle = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: true)
        isInitialized = false
    }

    private func failPendingRequests(with error: Error) {
        let completions = pendingRequests.values
        pendingRequests.removeAll()
        completions.forEach { $0(.failure(error)) }
    }

    private static func findCodexExecutable() -> URL? {
        var paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        if let environmentPath = ProcessInfo.processInfo.environment["PATH"] {
            paths += environmentPath.split(separator: ":").map { "\($0)/codex" }
        }

        return paths
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

nonisolated private struct EmptyResponse: Decodable {}
