import Foundation

private struct MenuBarGaugeFailure: Error { let message: String }

@MainActor enum MenuBarGaugeTests {
    static func run() throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw MenuBarGaugeFailure(message: message) }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let future = now.addingTimeInterval(60)
        func limit(_ percent: Double, _ minutes: Int = 300, reset: Date? = nil) -> CodexRateLimit {
            CodexRateLimit(usedPercent: percent, windowDurationMinutes: minutes,
                           resetsAt: reset ?? future)
        }
        let usage = TokenUsage(provider: .codex, daily: [], rateLimit: limit(35),
                               secondaryRateLimit: limit(82, 10_080))
        let codex = MenuBarUsageGauge.codex(usage, now: now)
        try check(codex.usedPercent == 82 && codex.limit?.windowDurationMinutes == 10_080,
                  "The gauge must select the more-used weekly quota, not combine quota percentages")
        let short = MenuBarUsageGauge(provider: .codex, limits: [limit(91), limit(42, 10_080)], now: now)
        try check(short.usedPercent == 91 && short.limit?.windowDurationMinutes == 300,
                  "The shorter window must win when it is more used")
        try check(MenuBarUsageGauge.codex(nil, now: now).usedPercent == nil,
                  "Missing account data must not be displayed as zero usage")
        let weeklyOnly = TokenUsage(provider: .codex, daily: [], secondaryRateLimit: limit(67, 10_080))
        try check(MenuBarUsageGauge.codex(weeklyOnly, now: now).usedPercent == 67,
                  "A weekly-only response must still produce a gauge")
        let expired = MenuBarUsageGauge(provider: .codex,
            limits: [limit(99, reset: now), limit(42, 10_080)], now: now)
        try check(expired.usedPercent == 42,
                  "Expired windows must yield to another valid window at the exact reset boundary")
        try check(MenuBarUsageGauge.codex(usage, now: future).usedPercent == nil,
                  "Time passing without a refresh must turn all expired windows into unknown")
        for invalid in [Double.nan, .infinity, -.infinity, -1, 101] {
            try check(MenuBarUsageGauge(provider: .codex, limits: [limit(invalid)], now: now).usedPercent == nil,
                      "Non-finite and out-of-range usage must never reach the image renderer")
        }
        try check(MenuBarUsageGauge(provider: .codex, limits: [limit(50, 0)], now: now).usedPercent == nil,
                  "Unknown quota durations must not be selected")
        for percent in [0.0, 100.0] {
            try check(MenuBarUsageGauge(provider: .codex, limits: [limit(percent)], now: now).usedPercent == percent,
                      "Actual 0% and 100% must remain valid and distinct from missing data")
        }
        let snapshot = ClaudeRateLimitSnapshot(receivedAt: now.timeIntervalSince1970,
            valuesChangedAt: now.timeIntervalSince1970,
            fiveHour: .init(usedPercent: 76, resetsAt: future.timeIntervalSince1970),
            sevenDay: .init(usedPercent: 99, resetsAt: now.timeIntervalSince1970))
        try check(MenuBarUsageGauge.claude(snapshot, now: now).usedPercent == 76,
                  "Claude must use the live 5-hour quota when its weekly snapshot has expired")
        try check(MenuBarUsageGauge.claude(nil, now: now).usedPercent == nil,
                  "Claude local token history alone must not imply a subscription quota")
        let weeklyClaude = ClaudeRateLimitSnapshot(receivedAt: now.timeIntervalSince1970,
            valuesChangedAt: now.timeIntervalSince1970, fiveHour: nil,
            sevenDay: .init(usedPercent: 100, resetsAt: future.timeIntervalSince1970))
        try check(MenuBarUsageGauge.claude(weeklyClaude, now: now).usedPercent == 100,
                  "Claude weekly-only and exhausted quotas must remain visible")

        let image = MenuBarGaugeImage.make(gauges: [codex], showsPercent: true)
        let unchanged = MenuBarGaugeImage.make(gauges: [codex], showsPercent: true)
        try check(image === unchanged,
                  "Unchanged status labels must reuse image identity to avoid a MenuBarExtra update loop")
        let updated = MenuBarGaugeImage.make(gauges: [short], showsPercent: true)
        try check(image !== updated && updated.isTemplate,
                  "Changed quota values must draw a new template image")
        try check(MenuBarGaugeImage.make(gauges: [short], showsPercent: false) !== updated,
                  "Display-style changes must invalidate the cached image")

        let pair = [codex, MenuBarUsageGauge.claude(snapshot, now: now)]
        for showsPercent in [false, true] {
            let vertical = MenuBarGaugeImage.make(gauges: pair, showsPercent: showsPercent, layout: .vertical)
            let horizontal = MenuBarGaugeImage.make(gauges: pair, showsPercent: showsPercent, layout: .horizontal)
            try check(horizontal !== vertical && horizontal.isTemplate
                      && horizontal.size.width > vertical.size.width
                      && horizontal.size.height == vertical.size.height,
                      "Changing layout must replace the cached image and fit both providers at menu bar height")
            try check(horizontal === MenuBarGaugeImage.make(gauges: pair, showsPercent: showsPercent, layout: .horizontal),
                      "Unchanged horizontal labels must also avoid a MenuBarExtra update loop")
        }

        let domain = "tracken-menu-bar-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = AppSettings(defaults: defaults)
        try check(settings.menuBarDisplayStyle == .gaugesAndPercent,
                  "Gauges should be visible by default, including for existing installations")
        for style in MenuBarDisplayStyle.allCases {
            settings.menuBarDisplayStyle = style
            try check(AppSettings(defaults: defaults).menuBarDisplayStyle == style,
                      "Every menu bar style must survive a restart")
        }
        defaults.set("invalid", forKey: AppSettings.menuBarDisplayStyleKey)
        try check(AppSettings(defaults: defaults).menuBarDisplayStyle == .gaugesAndPercent,
                  "An unknown saved style must fall back to visible gauges")
        try check(settings.menuBarGaugeLayout == .vertical, "Existing installations must retain their vertical layout")
        settings.menuBarGaugeLayout = .horizontal
        try check(AppSettings(defaults: defaults).menuBarGaugeLayout == .horizontal,
                  "The chosen horizontal layout must survive a restart")
        defaults.set("invalid", forKey: AppSettings.menuBarGaugeLayoutKey)
        try check(AppSettings(defaults: defaults).menuBarGaugeLayout == .vertical,
                  "An unknown layout must fall back to the original vertical layout")
        print("PASS: menu bar quota selection, expiry, missing/invalid values, layout caching and display preference persistence")
    }
}
