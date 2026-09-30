import Foundation
import Observation
import UserNotifications

nonisolated struct QuotaAlert: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case threshold(Int), recovered }
    let provider: AIProvider
    let windowMinutes: Int
    let usedPercent: Double
    let resetsAt: Date?
    let kind: Kind
    let id: String
}

/// Pure, persistent state machine. Reading an old cache or reaching its reset
/// timestamp cannot create a recovery notification.
nonisolated struct QuotaAlertLedger: Codable {
    struct Entry: Codable {
        var observedAt: Date
        var resetsAt: Date?
        var usedPercent: Double
        var sentThresholds: Set<Int>
    }
    var entries: [String: Entry] = [:]

    mutating func evaluate(provider: AIProvider, account: String, limits: [CodexRateLimit],
                           observedAt: Date, now: Date, thresholds: [Int], recovery: Bool) -> [QuotaAlert] {
        guard now.timeIntervalSince(observedAt) <= 120, observedAt <= now.addingTimeInterval(60) else { return [] }
        let valid = limits.filter {
            $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
                && $0.windowDurationMinutes > 0 && !$0.hasExpired(at: now)
                && ($0.resetsAt?.timeIntervalSince1970.isFinite ?? true)
        }
        let prefix = provider.rawValue + ":" + CodexHistoryKey.hash(account) + ":"
        let currentKeys = Set(valid.map { prefix + String($0.windowDurationMinutes) })
        let hasUnconfirmedExhaustedWindow = entries.contains {
            $0.key.hasPrefix(prefix) && $0.value.usedPercent >= 100 && !currentKeys.contains($0.key)
        }
        var alerts: [QuotaAlert] = []
        for limit in valid {
            let key = prefix + String(limit.windowDurationMinutes)
            let old = entries[key]
            if let old, observedAt <= old.observedAt { continue }
            var sent = old?.sentThresholds ?? []
            if let oldReset = old?.resetsAt, let newReset = limit.resetsAt,
               newReset.timeIntervalSince(oldReset) > 60,
               observedAt >= oldReset || limit.usedPercent < (old?.usedPercent ?? 0) {
                sent = []
            }
            let cycle = String(limit.resetsAt?.timeIntervalSince1970 ?? 0)
            if recovery, let old, old.usedPercent >= 100, limit.usedPercent < 100,
               !hasUnconfirmedExhaustedWindow, valid.allSatisfy({ $0.usedPercent < 100 }),
               !alerts.contains(where: { $0.kind == .recovered }) {
                alerts.append(QuotaAlert(provider: provider, windowMinutes: limit.windowDurationMinutes,
                    usedPercent: limit.usedPercent, resetsAt: limit.resetsAt, kind: .recovered,
                    id: key + ":" + cycle + ":recovered"))
            }
            let crossed = thresholds.filter { limit.usedPercent >= Double($0) && !sent.contains($0) }
            if let threshold = crossed.max() {
                alerts.append(QuotaAlert(provider: provider, windowMinutes: limit.windowDurationMinutes,
                    usedPercent: limit.usedPercent, resetsAt: limit.resetsAt, kind: .threshold(threshold),
                    id: key + ":" + cycle + ":" + String(threshold)))
                sent.formUnion(thresholds.filter { $0 <= threshold })
            }
            entries[key] = Entry(observedAt: observedAt, resetsAt: limit.resetsAt,
                                  usedPercent: limit.usedPercent, sentThresholds: sent)
        }
        // Keep only recent account/window state, without storing account names.
        entries = entries.filter { now.timeIntervalSince($0.value.observedAt) < 30 * 86_400 }
        return alerts
    }
}

nonisolated enum QuotaNotificationPermission: String {
    case notRequested, allowed, denied
    var titleKey: String {
        switch self {
        case .notRequested: "Notification permission not requested"
        case .allowed: "Notifications allowed"
        case .denied: "Notifications disabled in macOS Settings"
        }
    }
}

@MainActor protocol QuotaNotificationDelivering {
    func permission() async -> QuotaNotificationPermission
    func requestPermission() async throws -> Bool
    func deliver(_ alert: QuotaAlert) async throws
}

@MainActor final class SystemQuotaNotificationDelivery: NSObject, QuotaNotificationDelivering, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }

    func permission() async -> QuotaNotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        default: .notRequested
        }
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func deliver(_ alert: QuotaAlert) async throws {
        let content = UNMutableNotificationContent()
        let window = alert.windowMinutes.isMultiple(of: 1_440)
            ? L10n.format("%lld-day", alert.windowMinutes / 1_440)
            : (alert.windowMinutes.isMultiple(of: 60)
               ? L10n.format("%lld-hour", alert.windowMinutes / 60)
               : L10n.format("%lld-minute", alert.windowMinutes))
        switch alert.kind {
        case .threshold:
            content.title = L10n.format("%@ usage limit warning", alert.provider.shortName)
            content.body = L10n.format("%@ limit: %@ used.", window, "\(Int(alert.usedPercent.rounded()))%")
        case .recovered:
            content.title = L10n.format("%@ limit recovered", alert.provider.shortName)
            content.body = L10n.format("New data confirms the %@ limit is below 100%% again.", window)
        }
        if let reset = alert.resetsAt {
            let date = reset.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))
            content.body += " " + L10n.format("Resets at %@.", date)
        }
        content.sound = .default
        content.threadIdentifier = "tracken-quota-" + alert.provider.rawValue
        try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

@Observable @MainActor final class QuotaNotificationService {
    private(set) var permission: QuotaNotificationPermission = .notRequested
    private(set) var error: String?
    private(set) var isRequesting = false
    private let settings: AppSettings
    private let defaults: UserDefaults
    private let delivery: any QuotaNotificationDelivering
    private var ledger: QuotaAlertLedger
    private var isProcessing = false
    static let ledgerKey = "quotaAlertLedger.v1"

    init(settings: AppSettings, defaults: UserDefaults = .standard,
         delivery: (any QuotaNotificationDelivering)? = nil) {
        self.settings = settings
        self.defaults = defaults
        self.delivery = delivery ?? SystemQuotaNotificationDelivery()
        ledger = defaults.data(forKey: Self.ledgerKey)
            .flatMap { try? JSONDecoder().decode(QuotaAlertLedger.self, from: $0) } ?? QuotaAlertLedger()
    }

    func refreshPermission() async { permission = await delivery.permission() }

    func enable() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        do {
            settings.notificationsEnabled = try await delivery.requestPermission()
            error = nil
        } catch {
            settings.notificationsEnabled = false
            self.error = error.localizedDescription
        }
        await refreshPermission()
    }

    func process(provider: AIProvider, account: String, limits: [CodexRateLimit], observedAt: Date, now: Date) async {
        guard settings.notificationsEnabled, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        await refreshPermission()
        guard settings.notificationsEnabled, permission == .allowed else { return }
        var candidate = ledger
        let alerts = candidate.evaluate(provider: provider, account: account, limits: limits,
            observedAt: observedAt, now: now, thresholds: settings.alertThresholds(for: provider),
            recovery: settings.recoveryAlertsEnabled)
        do {
            for alert in alerts {
                guard settings.notificationsEnabled else { return }
                try await delivery.deliver(alert)
            }
            ledger = candidate
            defaults.set(try JSONEncoder().encode(ledger), forKey: Self.ledgerKey)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
