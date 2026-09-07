//
//  ContentView.swift
//  tracken
//

import SwiftUI

struct ContentView: View {
    @Environment(UsageStore.self) private var store

    @State private var showingSettings = false
    @State private var selectedProvider: AIProvider = .codex
    @State private var claudeHistoryDays = 14

    private var dayCount: Int? {
        selectedProvider == .anthropic ? (claudeHistoryDays == 0 ? nil : claudeHistoryDays) : 14
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    providerPicker
                    if selectedProvider == .anthropic {
                        Picker("History period", selection: $claudeHistoryDays) {
                            Text("Last 14 days").tag(14)
                            Text("Last 30 days").tag(30)
                            Text("All local history").tag(0)
                        }
                        .pickerStyle(.segmented)
                    }
                    summary
                    todaySummary
                    UsageCard(provider: selectedProvider, dayCount: dayCount)
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
        Picker("Provider", selection: $selectedProvider) {
            ForEach(AIProvider.allCases) { provider in
                Label(provider.shortName, systemImage: provider.symbolName)
                    .tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("AI provider")
    }

    private var summary: some View {
        let usage = store.usage(for: selectedProvider)?.displayUsage(dayCount: dayCount)
        let secondary = SecondarySummary(provider: selectedProvider, usage: usage)

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

    private var todaySummary: some View {
        let today = store.usage(for: selectedProvider)?.recentDays(count: 1).first
        return HStack(spacing: 12) {
            DashboardSummaryTile(
                title: "Today’s tokens",
                value: today.map { Format.tokens($0.totalTokens) } ?? "—",
                systemImage: "sun.max"
            )
            DashboardSummaryTile(
                title: "Today’s estimated cost (USD)",
                value: today?.estimatedCostUSD.map(Format.cost) ?? "—",
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
            title = "Estimated cost"
            value = usage?.estimatedCostUSD.map(Format.cost) ?? "—"
            systemImage = "dollarsign.circle"
        }
    }
}

private struct DashboardSummaryTile: View {
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
