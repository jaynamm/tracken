import Foundation

private struct QuotaFailure: Error { let message: String }
private func checkQuota(_ condition: Bool, _ message: String) throws {
    if !condition { throw QuotaFailure(message: message) }
}

@MainActor private final class TestQuotaDelivery: QuotaNotificationDelivering {
    var allowed = true
    var fails = false
    var delivered: [QuotaAlert] = []
    func permission() async -> QuotaNotificationPermission { allowed ? .allowed : .denied }
    func requestPermission() async throws -> Bool { allowed }
    func deliver(_ alert: QuotaAlert) async throws {
        if fails { throw QuotaFailure(message: "fixture delivery failure") }
        delivered.append(alert)
    }
}

@MainActor enum QuotaNotificationTests {
    static func run() async throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func limit(_ percent: Double, reset: Double = 300, minutes: Int = 300) -> CodexRateLimit {
            CodexRateLimit(usedPercent: percent, windowDurationMinutes: minutes, resetsAt: base.addingTimeInterval(reset))
        }
        var ledger = QuotaAlertLedger()
        func evaluate(_ percent: Double, time: Double, reset: Double = 300, account: String = "one") -> [QuotaAlert] {
            ledger.evaluate(provider: .codex, account: account, limits: [limit(percent, reset: reset)],
                            observedAt: base.addingTimeInterval(time), now: base.addingTimeInterval(time),
                            thresholds: [80, 90], recovery: true)
        }
        try checkQuota(evaluate(79, time: 0).isEmpty, "Below-threshold usage must not notify")
        try checkQuota(evaluate(80, time: 1).map(\.kind) == [.threshold(80)], "80% must notify once")
        try checkQuota(evaluate(85, time: 2).isEmpty, "Further usage in a warned tier must not repeat")
        try checkQuota(evaluate(92, time: 3).map(\.kind) == [.threshold(90)], "Crossing the next tier must notify")
        _ = evaluate(70, time: 4)
        try checkQuota(evaluate(95, time: 5).isEmpty, "Corrections within a window must not re-arm thresholds")
        ledger = try JSONDecoder().decode(QuotaAlertLedger.self, from: JSONEncoder().encode(ledger))
        try checkQuota(evaluate(99, time: 6).isEmpty, "Restart persistence must prevent duplicate warnings")
        try checkQuota(evaluate(95, time: 7, account: "two").map(\.kind) == [.threshold(90)], "Accounts must have independent alert state; jumps produce one warning")
        _ = evaluate(100, time: 8)
        try checkQuota(ledger.evaluate(provider: .codex, account: "one", limits: [],
            observedAt: base.addingTimeInterval(301), now: base.addingTimeInterval(301),
            thresholds: [80, 90], recovery: true).isEmpty, "Missing data must never imply recovery")
        try checkQuota(evaluate(100, time: 301).isEmpty, "An expired 100% snapshot cannot trigger recovery")
        try checkQuota(ledger.evaluate(provider: .codex, account: "one", limits: [limit(0, reset: 600)],
            observedAt: base, now: base.addingTimeInterval(301), thresholds: [80, 90], recovery: true).isEmpty,
                       "Old cache data must not trigger recovery")
        try checkQuota(evaluate(5, time: 302, reset: 600).map(\.kind) == [.recovered], "New lower usage must confirm recovery")
        try checkQuota(evaluate(6, time: 303, reset: 600).isEmpty, "Recovery must not repeat")
        try checkQuota(evaluate(85, time: 304, reset: 600).map(\.kind) == [.threshold(80)], "A confirmed new window must re-arm thresholds")
        for value in [Double.nan, .infinity, -1, 101] {
            try checkQuota(evaluate(value, time: 305, reset: 600).isEmpty, "Invalid usage must not trigger alerts")
        }
        var blocked = QuotaAlertLedger()
        _ = blocked.evaluate(provider: .anthropic, account: "local", limits: [limit(100), limit(100, minutes: 10_080)],
            observedAt: base, now: base, thresholds: [80, 90], recovery: true)
        let partial = blocked.evaluate(provider: .anthropic, account: "local",
            limits: [limit(0, reset: 600), limit(100, reset: 600, minutes: 10_080)],
            observedAt: base.addingTimeInterval(301), now: base.addingTimeInterval(301), thresholds: [80, 90], recovery: true)
        try checkQuota(!partial.contains(where: { $0.kind == .recovered }), "Another exhausted window must suppress a recovery notice")
        var missing = QuotaAlertLedger()
        _ = missing.evaluate(provider: .anthropic, account: "local", limits: [limit(100), limit(100, minutes: 10_080)],
            observedAt: base, now: base, thresholds: [80, 90], recovery: true)
        let incomplete = missing.evaluate(provider: .anthropic, account: "local", limits: [limit(0, reset: 600)],
            observedAt: base.addingTimeInterval(301), now: base.addingTimeInterval(301), thresholds: [80, 90], recovery: true)
        try checkQuota(!incomplete.contains(where: { $0.kind == .recovered }), "A missing previously exhausted window must not be assumed to have recovered")

        let domain = "tracken-alerts-\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = AppSettings(defaults: defaults)
        let delivery = TestQuotaDelivery()
        var service = QuotaNotificationService(settings: settings, defaults: defaults, delivery: delivery)
        await service.process(provider: .codex, account: "fixture", limits: [limit(90)], observedAt: base, now: base)
        try checkQuota(delivery.delivered.isEmpty, "Notifications are opt-in and must not send while disabled")
        delivery.allowed = false
        await service.enable()
        try checkQuota(!settings.notificationsEnabled && service.permission == .denied, "Denied authorization must remain visible and disabled")
        delivery.allowed = true
        await service.enable()
        delivery.fails = true
        await service.process(provider: .codex, account: "fixture", limits: [limit(90)], observedAt: base, now: base)
        try checkQuota(service.error != nil, "Delivery failures must be visible")
        delivery.fails = false
        await service.process(provider: .codex, account: "fixture", limits: [limit(90)], observedAt: base, now: base)
        try checkQuota(delivery.delivered.count == 1 && service.error == nil, "Failed alerts must remain eligible for retry")
        service = QuotaNotificationService(settings: settings, defaults: defaults, delivery: delivery)
        await service.process(provider: .codex, account: "fixture", limits: [limit(91)],
                              observedAt: base.addingTimeInterval(1), now: base.addingTimeInterval(1))
        try checkQuota(delivery.delivered.count == 1, "The notification service must persist delivery state across restart")
        settings.codexAlert80 = false
        settings.claudeAlert90 = false
        let restored = AppSettings(defaults: defaults)
        try checkQuota(restored.alertThresholds(for: .codex) == [90] && restored.alertThresholds(for: .anthropic) == [80],
                       "Provider-specific thresholds must persist independently")
        print("PASS: notification thresholds, deduplication, fresh-data recovery, account isolation, authorization and delivery retries")
    }
}
