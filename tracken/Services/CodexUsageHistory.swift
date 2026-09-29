import CryptoKit
import Foundation

nonisolated enum CodexHistoryKey {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/tracken/UsageHistory", isDirectory: true)

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

nonisolated enum CodexHistoryError: Error, LocalizedError {
    case invalidArchive
    var errorDescription: String? {
        "Saved Codex history could not be read. The existing file has been kept."
    }
}

/// Stores only token metadata; source and response identifiers are hashed.
nonisolated struct CodexArchivedTokenRecord: Codable, Sendable {
    let id: String
    let timestamp: Date
    let model: String
    let usage: SessionTokenUsage
}

actor CodexLocalUsageArchive {
    private struct Snapshot: Codable {
        var version = 1
        var sources: [String: [CodexArchivedTokenRecord]] = [:]
    }
    private let url: URL

    init(url: URL = CodexHistoryKey.directory.appendingPathComponent("codex-local.json")) { self.url = url }

    func merge(_ scanned: [String: [CodexArchivedTokenRecord]]) throws -> [CodexArchivedTokenRecord] {
        var snapshot = Snapshot()
        if FileManager.default.fileExists(atPath: url.path) {
            guard let decoded = try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url)),
                  decoded.version == 1 else { throw CodexHistoryError.invalidArchive }
            snapshot = decoded
        }
        for (source, records) in scanned where !records.isEmpty {
            snapshot.sources[source] = records
        }
        try CodexHistoryKey.save(snapshot, to: url)
        return Self.uniqueRecords(in: snapshot.sources)
    }

    nonisolated static func uniqueRecords(in sources: [String: [CodexArchivedTokenRecord]]) -> [CodexArchivedTokenRecord] {
        var unique: [String: CodexArchivedTokenRecord] = [:]
        for source in sources.keys.sorted() {
            for record in sources[source] ?? [] {
                if let previous = unique[record.id],
                   previous.usage.effectiveTotalTokens > record.usage.effectiveTotalTokens { continue }
                unique[record.id] = record
            }
        }
        return unique.values.sorted { $0.id < $1.id }
    }
}

/// Account totals use civil-date keys and replace overlapping dates rather than
/// accumulating repeated polling results. Local token history is device-scoped.
actor CodexAccountUsageHistory {
    private struct Snapshot: Codable {
        var version = 1
        var days: [String: Int] = [:]
    }
    private let directory: URL

    init(directory: URL = CodexHistoryKey.directory) { self.directory = directory }

    func merge(account: String, daily: [DailyUsage]?, calendar: Calendar = .current) throws -> [DailyUsage] {
        let url = directory.appendingPathComponent("codex-account-" + CodexHistoryKey.hash(account) + ".json")
        var snapshot = Snapshot()
        if FileManager.default.fileExists(atPath: url.path) {
            guard let decoded = try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url)),
                  decoded.version == 1, decoded.days.values.allSatisfy({ $0 >= 0 }) else {
                throw CodexHistoryError.invalidArchive
            }
            snapshot = decoded
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        if let daily {
            let days = Dictionary(grouping: daily) { formatter.string(from: $0.date) }
            for (day, values) in days {
                snapshot.days[day] = values.reduce(0) { $0 + max(0, $1.totalTokens) }
            }
            try CodexHistoryKey.save(snapshot, to: url)
        }
        return snapshot.days.compactMap { day, tokens in
            formatter.date(from: day).map { DailyUsage(date: $0, totalTokens: tokens) }
        }.sorted { $0.date > $1.date }
    }
}
