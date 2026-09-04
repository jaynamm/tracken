//
//  ContentView.swift
//  tracken
//
//  The main window: a dashboard showing token usage per provider.
//

import SwiftUI
import Charts

struct ContentView: View {
    @Environment(UsageStore.self) private var store

    @State private var showingSettings = false
    @State private var selectedProvider: AIProvider = .openAI

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    providerTabs

                    summaryBar

                    UsageCard(provider: selectedProvider)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 460, minHeight: 520)
        .task {
            await store.refreshAll()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(store)
        }
    }

    private var providerTabs: some View {
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

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("tracken")
                    .font(.headline)
                Text("ChatGPT & Claude token usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(store.isRefreshing || store.connectedProviders.isEmpty)
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

    private var summaryBar: some View {
        let usage = store.usage[selectedProvider]

        return HStack(spacing: 12) {
            SummaryTile(
                title: "Last 14 days",
                value: Format.tokens(usage?.last14DaysTotalTokens ?? 0),
                systemImage: "number"
            )
            SummaryTile(
                title: "Estimated cost",
                value: Format.cost(usage?.estimatedCostUSD ?? 0),
                systemImage: "dollarsign.circle"
            )
        }
    }
}

/// A small headline tile used in the summary bar.
private struct SummaryTile: View {
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

/// A per-provider usage card shown on the dashboard.
struct UsageCard: View {
    @Environment(UsageStore.self) private var store
    let provider: AIProvider

    private var status: ConnectionStatus {
        store.status[provider] ?? .notConnected
    }

    private var usage: TokenUsage? {
        store.usage[provider]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(provider.shortName, systemImage: provider.symbolName)
                    .font(.headline)
                    .foregroundStyle(provider.accentColor)
                Spacer()
                statusBadge
            }

            if let usage {
                usageBody(usage)
            } else {
                placeholder
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(provider.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName)
            Text(status.label)
        }
        .font(.caption)
        .foregroundStyle(status.color)
    }

    private func usageBody(_ usage: TokenUsage) -> some View {
        let days = usage.last14Days
        let inputTokens = usage.last14DaysInputTokens
        let outputTokens = usage.last14DaysOutputTokens

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.tokens(usage.last14DaysTotalTokens))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                Text("tokens")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Format.cost(usage.estimatedCostUSD))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            TokenSplitBar(input: inputTokens, output: outputTokens, tint: provider.accentColor)

            HStack {
                metric("Input", value: inputTokens)
                Spacer()
                metric("Output", value: outputTokens)
                Spacer()
                Text("Updated \(Format.relative(usage.updatedAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()
            DailyUsageChart(days: Array(days.reversed()), tint: provider.accentColor)
                .id(provider)

            Divider()
            DailyUsageList(days: days, tint: provider.accentColor)
        }
    }

    private func metric(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Format.tokens(value))
                .font(.callout.weight(.medium))
        }
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            if case .connecting = status {
                ProgressView().controlSize(.small)
                Text("Fetching usage…")
            } else if case .failed(let message) = status {
                Text(message).foregroundStyle(.red)
            } else {
                Image(systemName: "key.horizontal")
                Text("Add an API key in Settings to see usage.")
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

/// A stacked bar chart of daily input/output tokens over the tracked window.
struct DailyUsageChart: View {
    let days: [DailyUsage]
    let tint: Color

    @State private var selectedDay: DailyUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("14-day trend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let day = selectedDay ?? peakDay {
                    Text("\(day.date.formatted(.dateTime.month(.abbreviated).day())): \(Format.tokens(day.totalTokens))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tint)
                }
            }

            Chart {
                ForEach(days) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Output", day.outputTokens),
                        stacking: .standard
                    )
                    .foregroundStyle(by: .value("Type", "Output"))

                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Input", day.inputTokens),
                        stacking: .standard
                    )
                    .foregroundStyle(by: .value("Type", "Input"))
                }

                if let day = selectedDay {
                    RuleMark(x: .value("Day", day.date, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .chartForegroundStyleScale([
                "Input": tint,
                "Output": tint.opacity(0.4)
            ])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(Format.compactTokens(tokens))
                        }
                    }
                }
            }
            .chartXSelection(value: selectedDaySelection)
            .frame(height: 120)
        }
    }

    /// Bridges the chart's `Date?` selection onto the nearest `DailyUsage`.
    private var selectedDaySelection: Binding<Date?> {
        Binding(
            get: { selectedDay?.date },
            set: { date in
                guard let date else { selectedDay = nil; return }
                selectedDay = days.min {
                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                }
            }
        )
    }

    private var peakDay: DailyUsage? {
        days.max { $0.totalTokens < $1.totalTokens }
    }
}

/// Exact per-day figures for the latest two weeks, ordered newest first.
struct DailyUsageList: View {
    let days: [DailyUsage]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Daily usage")
                    .font(.headline)
                Spacer()
                Text("Newest first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            ForEach(days) { day in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.callout.weight(.medium))
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 64, alignment: .leading)

                    dailyMetric("Input", value: day.inputTokens)
                    dailyMetric("Output", value: day.outputTokens)

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.tokens(day.totalTokens))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(day.totalTokens == 0 ? Color.secondary : tint)
                        Text("tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 72, alignment: .trailing)
                }
                .padding(.vertical, 8)

                if day.id != days.last?.id {
                    Divider()
                }
            }
        }
    }

    private func dailyMetric(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Format.compactTokens(value))
                .font(.caption.weight(.medium))
        }
        .frame(width: 58, alignment: .leading)
    }
}

/// A horizontal bar visualizing the input vs. output token split.
struct TokenSplitBar: View {
    let input: Int
    let output: Int
    let tint: Color

    private var inputFraction: Double {
        let total = input + output
        return total == 0 ? 0 : Double(input) / Double(total)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, geo.size.width * inputFraction))
                Capsule()
                    .fill(tint.opacity(0.35))
            }
        }
        .frame(height: 8)
    }
}

#Preview {
    ContentView()
        .environment(UsageStore())
}
