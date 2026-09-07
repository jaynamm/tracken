import Foundation

nonisolated struct ClaudeRateLimitSnapshot: Decodable, Equatable, Sendable {
    let receivedAt: Double
    let valuesChangedAt: Double
    let fiveHour: Window?
    let sevenDay: Window?

    struct Window: Decodable, Equatable, Sendable {
        let usedPercent: Double
        let resetsAt: Double

        var isValid: Bool { usedPercent.isFinite && (0...100).contains(usedPercent) && resetsAt.isFinite && resetsAt > 0 }
        func hasExpired(at date: Date) -> Bool { resetsAt <= date.timeIntervalSince1970 }
    }

    var receivedDate: Date { Date(timeIntervalSince1970: receivedAt) }
    var valuesChangedDate: Date { Date(timeIntervalSince1970: valuesChangedAt) }
    func mayBeOutdated(at date: Date) -> Bool {
        date.timeIntervalSince(valuesChangedDate) > 300 || date.timeIntervalSince(receivedDate) > 300
    }
}

nonisolated struct ClaudeRateLimitService: Sendable {
    let directory: URL

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/tracken/Claude", isDirectory: true)
    }

    init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    func read() throws -> ClaudeRateLimitSnapshot? {
        let file = directory.appendingPathComponent("rate-limits.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let snapshot = try JSONDecoder().decode(ClaudeRateLimitSnapshot.self, from: Data(contentsOf: file))
        guard snapshot.receivedAt.isFinite, snapshot.receivedAt > 0,
              snapshot.valuesChangedAt.isFinite, snapshot.valuesChangedAt > 0,
              snapshot.valuesChangedAt <= snapshot.receivedAt,
              snapshot.receivedAt <= Date().timeIntervalSince1970 + 60,
              snapshot.fiveHour?.isValid != false, snapshot.sevenDay?.isValid != false,
              snapshot.fiveHour != nil || snapshot.sevenDay != nil else {
            throw UsageServiceError.unavailable("Invalid Claude rate-limit snapshot.")
        }
        return snapshot
    }
}
