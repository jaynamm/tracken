import SwiftUI

struct TotalUsageView: View {
    @Environment(UsageStore.self) private var store
    let selectProvider: (AIProvider) -> Void

    var body: some View {
        let total = store.totalUsage

        VStack(alignment: .leading, spacing: 16) {
            overview(total)
            summary(total)

            VStack(alignment: .leading, spacing: 10) {
                Text("Platforms")
                    .font(.headline)
                ForEach(AIProvider.allCases) { provider in
                    TotalProviderCard(provider: provider, state: store.state(for: provider)) {
                        selectProvider(provider)
                    }
                }
            }

            if total.hasUsageData {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Combined daily usage", systemImage: "chart.bar")
                        .font(.headline)
                    DailyUsageChart(
                        days: Array(total.daily.reversed()), tint: .accentColor, showsBreakdown: false,
                        providerDays: total.dailyByProvider
                    )
                    Divider()
                    DailyUsageList(
                        days: total.daily, tint: .accentColor, showsBreakdown: false,
                        providerDays: total.dailyByProvider
                    )
                }
                .padding(16)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            } else {
                ContentUnavailableView(
                    LocalizedStringKey(store.isRefreshing ? "Loading platform usage…" : "No usage available"),
                    systemImage: store.isRefreshing ? "arrow.triangle.2.circlepath" : "chart.bar",
                    description: Text("Connect Codex or load local Claude Code history in Settings to see combined usage.")
                )
            }
        }
    }

    private func overview(_ total: TotalUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Total", systemImage: "sum")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("Last 14 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Usage from \(total.providerCount) of \(AIProvider.allCases.count) platforms · hourly refresh")
                .font(.caption)
                .foregroundStyle(.secondary)
            if total.providerCount < AIProvider.allCases.count {
                Text("Platforms without usage data are excluded from totals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if AIProvider.allCases.contains(where: { provider in
                if case .failed = store.status(for: provider) { return store.usage(for: provider) != nil }
                return false
            }) {
                Label("Some platforms could not refresh. Totals include their last available usage.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("Costs use current API rates for recorded local usage, not subscription charges.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if total.isPartialCostEstimate {
                Text("Partial estimates include priced records only. Some usage has no cost estimate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summary(_ total: TotalUsage) -> some View {
        let today = total.daily.first
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                DashboardSummaryTile(
                    title: "Last 14 days · tokens",
                    value: total.hasUsageData ? Format.tokens(total.totalTokens) : "—",
                    systemImage: "number"
                )
                DashboardSummaryTile(
                    title: total.isPartialCostEstimate ? "Partial estimated cost (USD)" : "Estimated cost (USD)",
                    value: total.knownEstimatedCostUSD.map { Format.cost($0) } ?? "—",
                    systemImage: "dollarsign.circle"
                )
            }
            HStack(spacing: 12) {
                DashboardSummaryTile(
                    title: "Today’s tokens",
                    value: today.map { Format.tokens($0.totalTokens) } ?? "—",
                    systemImage: "sun.max"
                )
                DashboardSummaryTile(
                    title: today?.isPartialCostEstimate == true ? "Today’s partial cost (USD)" : "Today’s estimated cost (USD)",
                    value: today?.knownEstimatedCostUSD.map { Format.cost($0) } ?? "—",
                    systemImage: "dollarsign.circle"
                )
            }
        }
    }
}

private struct TotalProviderCard: View {
    let provider: AIProvider
    let state: ProviderState
    let showDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(provider.shortName, systemImage: provider.symbolName)
                    .font(.headline)
                    .foregroundStyle(provider.accentColor)
                Spacer()
                Button(action: showDetails) {
                    Label("Details", systemImage: "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("View \(provider.shortName) details")
            }
            Label(state.status.label, systemImage: state.status.symbolName)
                .font(.caption)
                .foregroundStyle(state.status.color)

            if let usage = state.usage?.displayUsage(dayCount: 14) {
                HStack(alignment: .top, spacing: 16) {
                    metric("Last 14 days", tokens: usage.totalTokens, cost: usage)
                    if let today = usage.daily.first {
                        metric("Today", tokens: today.totalTokens, cost: today)
                    }
                }
                if let limit = usage.rateLimit {
                    HStack {
                        Label("Usage limit · \(Format.percent(limit.usedPercent))",
                              systemImage: "gauge.with.dots.needle.50percent")
                        Spacer(minLength: 4)
                        if let resetsAt = limit.resetsAt {
                            Text("Resets \(Format.date(resetsAt, time: true))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                if provider == .anthropic {
                    ClaudeLimitsView(compact: true, showsUpdateDate: false)
                }
                Text("Updated \(Format.date(usage.updatedAt, time: true))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.message(emptyMessage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(provider.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(provider.accentColor.opacity(0.2), lineWidth: 1)
        }
    }

    private func metric(_ title: String, tokens: Int, cost: some CostEstimating) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.text(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Format.tokens(tokens)) tokens")
                .font(.callout.weight(.semibold))
            Text(cost.knownEstimatedCostUSD.map {
                L10n.format(cost.isPartialCostEstimate ? "≈ %@ · partial estimate" : "≈ %@ · API estimate", Format.cost($0))
            } ?? L10n.text("Cost estimate unavailable"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyMessage: String {
        switch state.status {
        case .connecting:
            "Fetching usage…"
        case .failed:
            "Refresh usage to try again."
        case .unavailable(let reason):
            reason
        case .notConnected, .connected:
            provider == .codex
                ? "Connect your ChatGPT account in Settings to include Codex."
                : "Local Claude Code history loads automatically. Reload it in Settings."
        }
    }
}
