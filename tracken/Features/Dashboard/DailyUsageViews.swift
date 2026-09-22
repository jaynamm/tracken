//
//  DailyUsageViews.swift
//  tracken
//

import Charts
import SwiftUI

struct DailyUsageChart: View {
    let days: [DailyUsage]
    let tint: Color
    let showsBreakdown: Bool
    var providerDays: [AIProvider: [DailyUsage]] = [:]
    var provider: AIProvider?

    @State private var selectedDayDate: Date?
    @State private var showsCost = true

    private var selectedDay: DailyUsage? { days.first { $0.date == selectedDayDate } }
    private var chartProviders: [AIProvider] {
        AIProvider.allCases.filter { providerDays[$0] != nil }
    }
    private var stacksProviders: Bool { !chartProviders.isEmpty }
    private var costDays: [DailyUsage] {
        stacksProviders ? chartProviders.flatMap { providerDays[$0] ?? [] } : days
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Daily chart", selection: $showsCost) {
                Text("Estimated cost (USD)").tag(true)
                Text("Tokens").tag(false)
            }
            .pickerStyle(.segmented)
            chartHeader

            Chart {
                if stacksProviders {
                    ForEach(chartProviders) { provider in
                        ForEach(providerDays[provider] ?? []) { day in
                            providerMarks(for: day, provider: provider)
                        }
                    }
                } else {
                    ForEach(days) { day in
                        marks(for: day)
                    }
                }

                if let selectedDay {
                    RuleMark(x: .value(L10n.text("Day"), selectedDay.date, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .chartForegroundStyleScale(
                domain: stacksProviders ? chartProviders.map(\.shortName) : [L10n.text("Input"), L10n.text("Output")],
                range: stacksProviders ? chartProviders.map(\.accentColor) : [tint, tint.opacity(0.4)]
            )
            .chartLegend(stacksProviders ? .visible : .hidden)
            .chartXScale(domain: chartDateRange)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, days.count / 5))) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if showsCost, let cost = value.as(Double.self) {
                            Text(Format.cost(cost))
                        } else if let tokens = value.as(Int.self) {
                            Text(Format.compactTokens(tokens))
                        }
                    }
                }
            }
            .chartXSelection(value: selectedDate)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame,
                                      geometry[plotFrame].contains(location) else {
                                    selectedDayDate = nil
                                    return
                                }
                                let date: Date? = proxy.value(
                                    atX: location.x - geometry[plotFrame].minX
                                )
                                selectedDate.wrappedValue = date
                            case .ended:
                                selectedDayDate = nil
                            }
                        }
                }
            }
            .frame(height: stacksProviders ? 150 : 120)
            .onChange(of: days.map(\.date)) {
                selectedDayDate = nil
            }

            if showsCost {
                Text("API-equivalent cost of recorded usage. Not a subscription charge.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if costDays.contains(where: \.isPartialCostEstimate) {
                    Text(L10n.text(stacksProviders
                         ? "Lighter segments are partial estimates for priced records only."
                         : "Lighter bars are partial estimates for priced records only."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if costDays.contains(where: { $0.knownEstimatedCostUSD == nil }) {
                    Text(L10n.text(stacksProviders
                         ? "Platforms without priced records have no cost segment for that day; daily totals may be partial."
                         : "Days without any priced records have no cost bar; see the list below."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func selectionDetails(for day: DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Format.date(day.date))
                .font(.caption.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    Text("Platform")
                    Text("Tokens")
                        .gridColumnAlignment(.trailing)
                    Text("Estimated cost (USD)")
                        .multilineTextAlignment(.trailing)
                        .gridColumnAlignment(.trailing)
                }
                .foregroundStyle(.secondary)

                if stacksProviders {
                    ForEach(chartProviders) { provider in
                        selectionRow(
                            title: provider.shortName,
                            color: provider.accentColor,
                            day: DailyUsageChartSelection.day(
                                at: day.date, in: providerDays[provider] ?? []
                            )
                        )
                    }
                    if chartProviders.count > 1 {
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                        selectionRow(title: L10n.text("Total"), color: tint, day: day)
                    }
                } else {
                    selectionRow(title: provider?.shortName ?? L10n.text("Total"), color: tint, day: day)
                }
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func selectionRow(title: String, color: Color, day: DailyUsage?) -> some View {
        GridRow(alignment: .top) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).fontWeight(.medium)
            }
            Text(day.map { Format.tokens($0.totalTokens) } ?? "—")
                .monospacedDigit()
            VStack(alignment: .trailing, spacing: 2) {
                Text(day?.knownEstimatedCostUSD.map { "≈ \(Format.cost($0))" } ?? "—")
                    .monospacedDigit()
                // Keep every row two lines tall so hovering never moves the plot.
                Text(L10n.text(day?.isPartialCostEstimate == true ? "partial estimate"
                     : (day?.knownEstimatedCostUSD == nil ? "no estimate" : "estimated cost")))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ChartContentBuilder
    private func providerMarks(for day: DailyUsage, provider: AIProvider) -> some ChartContent {
        if showsCost {
            if let cost = day.knownEstimatedCostUSD {
                BarMark(
                    x: .value(L10n.text("Day"), day.date, unit: .day),
                    y: .value(L10n.text("Estimated cost (USD)"), cost),
                    stacking: .standard
                )
                .foregroundStyle(by: .value(L10n.text("Platform"), provider.shortName))
                .opacity(day.isPartialCostEstimate ? 0.45 : 1)
                .accessibilityLabel("\(provider.shortName), \(Format.date(day.date))")
                .accessibilityValue("\(Format.cost(cost)), \(L10n.text(day.isPartialCostEstimate ? "partial estimate" : "estimated cost"))")
            }
        } else {
            BarMark(
                x: .value(L10n.text("Day"), day.date, unit: .day),
                y: .value(L10n.text("Tokens"), day.totalTokens),
                stacking: .standard
            )
            .foregroundStyle(by: .value(L10n.text("Platform"), provider.shortName))
            .accessibilityLabel("\(provider.shortName), \(Format.date(day.date))")
            .accessibilityValue("\(Format.tokens(day.totalTokens)) tokens")
        }
    }

    @ChartContentBuilder
    private func marks(for day: DailyUsage) -> some ChartContent {
        if showsCost {
            if let cost = day.knownEstimatedCostUSD {
                BarMark(x: .value(L10n.text("Day"), day.date, unit: .day),
                        y: .value(L10n.text("Estimated cost (USD)"), cost))
                    .foregroundStyle(day.isPartialCostEstimate ? tint.opacity(0.45) : tint)
                    .accessibilityLabel(L10n.text(day.isPartialCostEstimate ? "Partial estimated cost" : "Estimated cost"))
            }
        } else if showsBreakdown {
            BarMark(
                x: .value(L10n.text("Day"), day.date, unit: .day),
                y: .value(L10n.text("Output"), day.outputTokens ?? 0),
                stacking: .standard
            )
            .foregroundStyle(by: .value(L10n.text("Type"), L10n.text("Output")))

            BarMark(
                x: .value(L10n.text("Day"), day.date, unit: .day),
                y: .value(L10n.text("Input"), day.inputTokens ?? 0),
                stacking: .standard
            )
            .foregroundStyle(by: .value(L10n.text("Type"), L10n.text("Input")))
        } else {
            BarMark(
                x: .value(L10n.text("Day"), day.date, unit: .day),
                y: .value(L10n.text("Tokens"), day.totalTokens)
            )
            .foregroundStyle(tint)
        }
    }

    private var chartHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daily trend")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Keep the detail panel in the layout even when the pointer leaves.
            // Only its values change; the bars stay in the same place.
            if let day = selectedDay ?? peakDay ?? days.last {
                selectionDetails(for: day)
            }
        }
    }

    private var selectedDate: Binding<Date?> {
        Binding(
            get: { selectedDayDate },
            set: { date in
                guard let date else {
                    selectedDayDate = nil
                    return
                }
                selectedDayDate = DailyUsageChartSelection.day(at: date, in: days)?.date
            }
        )
    }

    private var peakDay: DailyUsage? {
        if showsCost {
            return days.filter { $0.knownEstimatedCostUSD != nil }.max {
                ($0.knownEstimatedCostUSD ?? 0) < ($1.knownEstimatedCostUSD ?? 0)
            }
        }
        return days.max { $0.totalTokens < $1.totalTokens }
    }

    private var chartDateRange: ClosedRange<Date> {
        let start = days.map(\.date).min() ?? Calendar.current.startOfDay(for: Date())
        let last = days.map(\.date).max() ?? start
        let end = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last
        return start...end
    }
}

struct DailyUsageList: View {
    let days: [DailyUsage]
    let tint: Color
    let showsBreakdown: Bool
    var providerDays: [AIProvider: [DailyUsage]] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Daily usage & estimated cost")
                    .font(.headline)
                Spacer()
                Text("Newest first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            if days.contains(where: { !$0.modelUsage.isEmpty }) {
                Text("Model costs are API-equivalent estimates from local session metadata.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }

            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                DailyUsageRow(
                    day: day, tint: tint, showsBreakdown: showsBreakdown,
                    providerDays: providerDays.compactMapValues { rows in
                        DailyUsageChartSelection.day(at: day.date, in: rows)
                    }
                )
                    .padding(.vertical, 8)

                if index < days.count - 1 {
                    Divider()
                }
            }
        }
    }
}

private struct DailyUsageRow: View {
    let day: DailyUsage
    let tint: Color
    let showsBreakdown: Bool
    let providerDays: [AIProvider: DailyUsage]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.day(day.date))
                        .font(.callout.weight(.medium))
                    Text(Format.weekday(day.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, alignment: .leading)

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

                VStack(alignment: .trailing, spacing: 2) {
                    Text(day.knownEstimatedCostUSD.map { Format.cost($0) } ?? "—")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(day.knownEstimatedCostUSD == nil ? Color.secondary : tint)
                    Text(L10n.text(day.isPartialCostEstimate ? "partial estimate"
                         : (day.estimatedCostUSD == nil ? "no estimate" : "estimated cost")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 82, alignment: .trailing)
            }

            if !providerDays.isEmpty {
                VStack(spacing: 6) {
                    ForEach(AIProvider.allCases) { provider in
                        if let usage = providerDays[provider] {
                            DailyPlatformUsageRow(provider: provider, day: usage)
                        }
                    }
                }
                .padding(.leading, 20)
            }

            if showsBreakdown {
                HStack(spacing: 16) {
                    compactMetric("Input", value: day.inputTokens ?? 0)
                    compactMetric("Output", value: day.outputTokens ?? 0)
                    Spacer()
                }
                .padding(.leading, 76)
            }

            if !day.modelUsage.isEmpty {
                VStack(spacing: 6) {
                    ForEach(day.modelUsage) { model in
                        DailyModelCostRow(model: model, tint: tint)
                    }
                }
                .padding(.leading, 76)
            }
        }
    }

    private func compactMetric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Format.compactTokens(value))
                .font(.caption.weight(.medium))
        }
        .frame(width: 58, alignment: .leading)
    }
}

private struct DailyPlatformUsageRow: View {
    let provider: AIProvider
    let day: DailyUsage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(provider.accentColor).frame(width: 6, height: 6)
                Text(provider.shortName)
                    .font(.caption.weight(.medium))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.tokens(day.totalTokens))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                Text("tokens")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 72, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                Text(day.knownEstimatedCostUSD.map { Format.cost($0) } ?? "—")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                Text(L10n.text(day.isPartialCostEstimate ? "partial estimate"
                     : (day.estimatedCostUSD == nil ? "no estimate" : "estimated cost")))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 82, alignment: .trailing)
        }
        .padding(8)
        .background(provider.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }
}

private struct DailyModelCostRow: View {
    let model: ModelUsage
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.modelName(model.modelName))
                    .font(.caption.weight(.medium))
                Text(tokenBreakdown)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Format.compactTokens(model.totalTokens))
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.knownEstimatedCostUSD.map { Format.cost($0) }
                     ?? L10n.text(model.inputTokens == nil ? "Details unavailable" : "Rate unavailable"))
                    .font(.caption.weight(.medium))
                if model.isPartialCostEstimate {
                    Text("partial estimate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 82, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }

    private var tokenBreakdown: String {
        var parts: [String] = []
        if let input = model.inputTokens {
            parts.append(L10n.format("Input %@", Format.compactTokens(input)))
        }
        if model.cachedInputTokens > 0 {
            parts.append(L10n.format("Cached %@", Format.compactTokens(model.cachedInputTokens)))
        }
        if model.cacheWriteInputTokens > 0 {
            parts.append(L10n.format("Cache write %@", Format.compactTokens(model.cacheWriteInputTokens)))
        }
        if let output = model.outputTokens {
            parts.append(L10n.format("Output %@", Format.compactTokens(output)))
        }
        return parts.isEmpty ? L10n.text("Input/output breakdown unavailable") : parts.joined(separator: " · ")
    }
}

struct ModelUsageList: View {
    let usage: TokenUsage
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Usage by model")
                .font(.headline)
                .padding(.bottom, 8)

            if usage.modelUsage.isEmpty {
                Label(
                    L10n.text(usage.provider == .codex
                        ? "No model token metadata was found in recent local Codex sessions."
                        : "No model usage is available."),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            } else {
                ForEach(Array(usage.modelUsage.enumerated()), id: \.element.id) { index, model in
                    ModelUsageRow(
                        model: model,
                        tint: tint
                    )
                        .padding(.vertical, 8)

                    if index < usage.modelUsage.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct ModelUsageRow: View {
    let model: ModelUsage
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Format.modelName(model.modelName))
                .font(.callout.weight(.medium))

            HStack(spacing: 12) {
                if let inputTokens = model.inputTokens, let outputTokens = model.outputTokens {
                    compactMetric("Input", value: inputTokens)
                    compactMetric("Output", value: outputTokens)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.tokens(model.totalTokens))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(tint)
                    Text("tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 72, alignment: .trailing)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.knownEstimatedCostUSD.map { Format.cost($0) } ?? "—")
                        .font(.callout.weight(.medium))
                    Text(L10n.text(model.isPartialCostEstimate ? "partial estimate" : model.estimatedCostUSD == nil
                         ? (model.inputTokens == nil ? "Details unavailable" : "Rate unavailable")
                         : "estimated cost"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 82, alignment: .trailing)
            }

            if model.cachedInputTokens > 0 || model.cacheWriteInputTokens > 0 {
                Text(cacheSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cacheSummary: String {
        var parts: [String] = []
        if model.cachedInputTokens > 0 {
            parts.append(L10n.format("Cached input %@", Format.tokens(model.cachedInputTokens)))
        }
        if model.cacheWriteInputTokens > 0 {
            parts.append(L10n.format("Cache write %@", Format.tokens(model.cacheWriteInputTokens)))
        }
        return parts.joined(separator: " · ")
    }

    private func compactMetric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Format.compactTokens(value))
                .font(.caption.weight(.medium))
        }
        .frame(width: 58, alignment: .leading)
    }
}
