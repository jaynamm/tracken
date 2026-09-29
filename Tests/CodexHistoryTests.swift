import Foundation

private struct HistoryFailure: Error { let message: String }
private func checkHistory(_ condition: Bool, _ message: String) throws {
    if !condition { throw HistoryFailure(message: message) }
}

@MainActor enum CodexHistoryTests {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tracken-history-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        let stamp = ISO8601DateFormatter()
        func record(_ id: String, _ offset: Int, input: Int, output: Int = 0) -> String {
            """
            {"type":"token_usage_record","timestamp":"\(stamp.string(from: day(offset)))","payload":{"response_id":"\(id)","turn_id":"one","usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
            """
        }
        let context = #"{"type":"turn_context","payload":{"turn_id":"one","model":"gpt-5.6-sol"}}"#
        let file = sessions.appendingPathComponent("session.jsonl")
        let archive = root.appendingPathComponent("history/codex-local.json")
        func write(_ lines: [String]) throws {
            try ([context] + lines).joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        }
        try write([record("old", -60, input: 100), record("middle", -20, input: 200), record("new", 0, input: 300)])
        let estimator = CodexSessionCostEstimator(sessionsURL: sessions, archiveURL: archive)
        let all = try await estimator.estimateRecentUsage(dayCount: nil, now: now)
        try checkHistory(all.count == 3 && all[day(-60)]?.first?.totalTokens == 100,
                         "Initial import backfills dates older than the server window")
        let repeatRead = try await estimator.estimateRecentUsage(dayCount: nil, now: now)
        try checkHistory(repeatRead == all, "Repeated polling must not double-count imported records")
        let recent = try await estimator.estimateRecentUsage(dayCount: 14, now: now)
        let month = try await estimator.estimateRecentUsage(dayCount: 30, now: now)
        try checkHistory(recent.count == 1 && month.count == 2, "Window boundaries filter retained history")

        try write([record("old", -60, input: 100), record("middle", -20, input: 200), record("new", 0, input: 350),
                   record("added", 0, input: 50)])
        let refreshed = try await estimator.estimateRecentUsage(dayCount: nil, now: now)
        try checkHistory(refreshed[today]?.first?.totalTokens == 400, "A rewritten response replaces its old value")
        let source = try Data(contentsOf: file)
        try Data().write(to: file)
        let whileEmpty = try await estimator.estimateRecentUsage(dayCount: nil, now: now)
        try checkHistory(whileEmpty == refreshed, "Temporarily empty sources do not erase collected history")
        try source.write(to: file)
        try FileManager.default.copyItem(at: file, to: sessions.appendingPathComponent("fork.jsonl"))
        let duplicated = try await estimator.estimateRecentUsage(dayCount: nil, now: now)
        try checkHistory(duplicated == refreshed, "Copied and forked responses remain unique in the archive")
        try FileManager.default.removeItem(at: sessions)
        let restarted = CodexSessionCostEstimator(sessionsURL: sessions, archiveURL: archive)
        let saved = try await restarted.estimateRecentUsage(dayCount: nil, now: now)
        try checkHistory(saved == refreshed, "Restart and removed source files preserve previously collected metadata")
        let contents = try String(contentsOf: archive, encoding: .utf8)
        try checkHistory(!contents.contains(sessions.path) && !contents.contains("response_id") && !contents.contains("turn_id"),
                         "The archive does not store raw source paths or session/response identifiers")

        // Reprice saved token metadata without the original session files.
        let catalog = PricingCatalog(directory: root.appendingPathComponent("prices"), fetch: { request in
            let text = PricingDefaults.openAI.replacingOccurrences(of: "| gpt-5.6-sol | $4.00 |", with: "| gpt-5.6-sol | $8.00 |")
            return (Data(text.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        _ = await catalog.refresh(.codex, force: true)
        let repriced = try await CodexSessionCostEstimator(sessionsURL: sessions, pricingCatalog: catalog, archiveURL: archive)
            .estimateRecentUsage(dayCount: nil, now: now)
        try checkHistory(abs((repriced[today]?.first?.estimatedCostUSD ?? -1) - 0.0032) < 1e-10,
                         "Persist raw token data so removed sessions can use updated prices")

        let totals = root.appendingPathComponent("accounts")
        let history = CodexAccountUsageHistory(directory: totals)
        _ = try await history.merge(account: "account-a", daily: [DailyUsage(date: day(-60), totalTokens: 1_000),
                                                                 DailyUsage(date: today, totalTokens: 500)])
        let changed = try await history.merge(account: "account-a", daily: [DailyUsage(date: today, totalTokens: 450)])
        try checkHistory(changed.map(\.totalTokens) == [450, 1_000],
                         "Official corrections replace a date while rolled-off days are retained")
        let restore = CodexAccountUsageHistory(directory: totals)
        let cached = try await restore.merge(account: "account-a", daily: nil)
        try checkHistory(cached == changed, "Account history survives restart and unavailable daily buckets")
        let other = try await restore.merge(account: "account-b", daily: nil)
        try checkHistory(other.isEmpty, "Different login identities must not share official totals")
        let merged = CodexAppServerClient.merge(officialDaily: cached, localEstimates: saved)
        try checkHistory(merged.first?.totalTokens == 450 && merged.last?.totalTokens == 1_000
                         && merged.first(where: { $0.date == day(-20) })?.totalTokens == 200,
                         "Official totals win without adding local totals a second time")
        let usage = TokenUsage(provider: .codex, daily: merged, granularity: .aggregate, fillsMissingDaysWithZero: false)
        let fortnight = usage.displayUsage(dayCount: 14, now: now)
        let thirty = usage.displayUsage(dayCount: 30, now: now)
        let entire = usage.displayUsage(dayCount: nil, now: now)
        try checkHistory(fortnight.totalTokens == 450 && thirty.totalTokens == 650 && entire.totalTokens == 1_650,
                         "The 14-day, 30-day and all-history totals use the selected range")
        try checkHistory(entire.daily.count == 61 && entire.daily.filter(\.isMissing).count == 58
                         && entire.estimatedCostUSD == nil && entire.hasIncompleteHistory,
                         "Unknown dates remain missing rather than becoming measured zero usage")
        let missing = TokenUsage(provider: .codex, daily: [], fillsMissingDaysWithZero: false).displayUsage(dayCount: 14, now: now)
        try checkHistory(!missing.hasRecordedDays && missing.knownEstimatedCostUSD == nil,
                         "An entirely unknown window has no fabricated zero cost")
        let total = TotalUsage(usages: [missing], now: now)
        try checkHistory(!total.hasRecordedDays && total.hasIncompleteHistory && total.daily.allSatisfy(\.isMissing),
                         "Combined views must not turn missing Codex dates into measured zeroes")
        let zero = TokenUsage(provider: .codex, daily: [DailyUsage(date: today, totalTokens: 0)], fillsMissingDaysWithZero: false)
            .displayUsage(dayCount: 1, now: now)
        try checkHistory(zero.daily.first?.isMissing == false && zero.estimatedCostUSD == 0,
                         "Explicit zero usage is different from an absent day")

        let boundaries = TokenUsage(provider: .codex,
            daily: [0, -13, -14, -29, -30].map { DailyUsage(date: day($0), totalTokens: 10) },
            granularity: .aggregate, fillsMissingDaysWithZero: false)
        try checkHistory(boundaries.displayUsage(dayCount: 14, now: now).totalTokens == 20
                         && boundaries.displayUsage(dayCount: 30, now: now).totalTokens == 40
                         && boundaries.displayUsage(dayCount: nil, now: now).totalTokens == 50,
                         "Calendar windows include today and exactly 13 or 29 preceding days")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try write([record("", 0, input: 50), record("", 0, input: 60)])
        let emptyIDs = try await CodexSessionCostEstimator(sessionsURL: sessions)
            .estimateRecentUsage(dayCount: nil, now: now)
        try checkHistory(emptyIDs[today]?.first?.totalTokens == 110,
                         "Empty response IDs must not collapse unrelated usage records")

        let damaged = Data("invalid archive".utf8)
        try damaged.write(to: archive)
        do {
            _ = try await restarted.estimateRecentUsage(dayCount: nil, now: now)
            throw HistoryFailure(message: "Corrupt archive unexpectedly accepted")
        } catch is CodexHistoryError { }
        try checkHistory(try Data(contentsOf: archive) == damaged, "A damaged history file is never silently overwritten")
        print("PASS: Codex historical backfill, persistence, deduplication, repricing, account isolation, corrections, missing dates and period selection")
    }
}
