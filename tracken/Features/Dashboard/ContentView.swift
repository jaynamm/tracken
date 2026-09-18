//
//  ContentView.swift
//  tracken
//

import SwiftUI

private enum DashboardPage: Hashable {
    case total
    case provider(AIProvider)
}

struct ContentView: View {
    @Environment(UsageStore.self) private var store

    @State private var showingSettings = false
    @State private var selectedPage: DashboardPage = .total
    @State private var claudeHistoryDays = 14

    private func dayCount(for provider: AIProvider) -> Int? {
        provider == .anthropic ? (claudeHistoryDays == 0 ? nil : claudeHistoryDays) : 14
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    providerPicker
                    switch selectedPage {
                    case .total:
                        TotalUsageView {
                            selectedPage = .provider($0)
                        }
                    case .provider(let provider):
                        if provider == .anthropic {
                            Picker("History period", selection: $claudeHistoryDays) {
                                Text("Last 14 days").tag(14)
                                Text("Last 30 days").tag(30)
                                Text("All local history").tag(0)
                            }
                            .pickerStyle(.segmented)
                        }
                        summary(for: provider)
                        todaySummary(for: provider)
                        UsageCard(provider: provider, dayCount: dayCount(for: provider))
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 460, minHeight: 520)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(store)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("tracken")
                    .font(.headline)
                Text("Codex & Claude · hourly refresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            .help("Refresh usage")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var providerPicker: some View {
        Picker("Dashboard", selection: $selectedPage) {
            Label("Total", systemImage: "sum")
                .tag(DashboardPage.total)
            ForEach(AIProvider.allCases) { provider in
                Label(provider.shortName, systemImage: provider.symbolName)
                    .tag(DashboardPage.provider(provider))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Usage dashboard")
    }

    private func summary(for provider: AIProvider) -> some View {
        let dayCount = dayCount(for: provider)
        let usage = store.usage(for: provider)?.displayUsage(dayCount: dayCount)
        let secondary = SecondarySummary(provider: provider, usage: usage)

        return HStack(spacing: 12) {
            DashboardSummaryTile(
                title: dayCount.map { "Last \($0) days" } ?? "All local history",
                value: usage.map { Format.tokens($0.totalTokens) } ?? "—",
                systemImage: "number"
            )
            DashboardSummaryTile(
                title: secondary.title,
                value: secondary.value,
                systemImage: secondary.systemImage
            )
        }
    }

    private func todaySummary(for provider: AIProvider) -> some View {
        let today = store.usage(for: provider)?.recentDays(count: 1).first
        return HStack(spacing: 12) {
            DashboardSummaryTile(
                title: "Today’s tokens",
                value: today.map { Format.tokens($0.totalTokens) } ?? "—",
                systemImage: "sun.max"
            )
            DashboardSummaryTile(
                title: today?.isPartialCostEstimate == true ? "Today’s partial cost (USD)" : "Today’s estimated cost (USD)",
                value: today?.knownEstimatedCostUSD.map(Format.cost) ?? "—",
                systemImage: "dollarsign.circle"
            )
        }
        .help("API-equivalent cost of recorded usage so far today, not a subscription charge or end-of-day forecast.")
    }
}

private struct SecondarySummary {
    let title: String
    let value: String
    let systemImage: String

    init(provider: AIProvider, usage: TokenUsage?) {
        switch provider {
        case .codex:
            title = "Usage limit"
            value = usage?.rateLimit.map { Format.percent($0.usedPercent) } ?? "—"
            systemImage = "gauge.with.dots.needle.50percent"
        case .anthropic:
            title = usage?.isPartialCostEstimate == true ? "Partial estimated cost" : "Estimated cost"
            value = usage?.knownEstimatedCostUSD.map(Format.cost) ?? "—"
            systemImage = "dollarsign.circle"
        }
    }
}

struct DashboardSummaryTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
        .environment(UsageStore())
}
