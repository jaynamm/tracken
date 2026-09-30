import Foundation

nonisolated struct CodexLimitSnapshot: Equatable, Sendable {
    let account: ProviderAccount
    let limits: [CodexRateLimit]
    let receivedAt: Date

    var accountKey: String? {
        account.email.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}

nonisolated struct RefreshHealth: Equatable, Sendable {
    var lastAttempt: Date?
    var lastSuccess: Date?
    var error: String?
    var isRefreshing = false
}

nonisolated enum UsageRefreshPolicy {
    static let tick: TimeInterval = 30
    static let activityWindow: TimeInterval = 300
    static let menuStaleAfter: TimeInterval = 60
    static func limitsInterval(active: Bool, adaptive: Bool) -> TimeInterval {
        adaptive ? (active ? 60 : 300) : 3_600
    }
    static func historyInterval(active: Bool, adaptive: Bool) -> TimeInterval {
        adaptive && active ? 300 : 3_600
    }
    static func isDue(last: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval || now < last
    }
}

nonisolated struct LocalUsageActivity: Sendable {
    let roots: [URL]

    static var codexHome: URL {
        ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
    static var claudeProjects: URL {
        let root = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return root.appendingPathComponent("projects")
    }

    init(roots: [URL] = [Self.codexHome.appendingPathComponent("sessions"), Self.claudeProjects]) {
        self.roots = roots
    }

    /// Only file metadata is inspected; transcripts are never decoded for activity detection.
    func hasRecentActivity(now: Date) async -> Bool {
        await Task.detached(priority: .utility) { scan(now: now) }.value
    }

    private func scan(now: Date) -> Bool {
        for root in roots {
            guard let entries = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let file as URL in entries where file.pathExtension == "jsonl" {
                if Task.isCancelled { return false }
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true, let modified = values.contentModificationDate else { continue }
                let age = now.timeIntervalSince(modified)
                if age >= -60 && age <= UsageRefreshPolicy.activityWindow { return true }
            }
        }
        return false
    }
}
