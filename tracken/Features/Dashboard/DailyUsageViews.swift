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

    @State private var selectedDayDate: Date?
    @State private var showsCost = true

    private var selectedDay: DailyUsage? { days.first { $0.date == selectedDayDate } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Daily chart", selection: $showsCost) {
                Text("Estimated cost (USD)").tag(true)
                Text("Tokens").tag(false)
            }
            .pickerStyle(.segmented)
            chartHeader

            Chart {
                ForEach(days) { day in
                    marks(for: day)
                }

                if let selectedDay {
                    RuleMark(x: .value("Day", selectedDay.date, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .chartForegroundStyleScale([
                "Input": tint,
                "Output": tint.opacity(0.4)
            ])
            .chartLegend(.hidden)
            .chartXScale(domain: chartDateRange)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, days.count / 5))) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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
            .frame(height: 120)

            if showsCost {
                Text("API-equivalent cost of recorded usage. Not a subscription charge.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if days.contains(where: { $0.estimatedCostUSD == nil }) {
                    Text("Days without a complete estimate have no cost bar; see the list below.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ChartContentBuilder
    private func marks(for day: DailyUsage) -> some ChartContent {
        if showsCost {
            if let cost = day.estimatedCostUSD {
                BarMark(x: .value("Day", day.date, unit: .day),
                        y: .value("Estimated cost (USD)", cost))
                    .foregroundStyle(tint)
            }
        } else if showsBreakdown {
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Output", day.outputTokens ?? 0),
                stacking: .standard
            )
            .foregroundStyle(by: .value("Type", "Output"))

            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Input", day.inputTokens ?? 0),
                stacking: .standard
            )
            .foregroundStyle(by: .value("Type", "Input"))
        } else {
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Tokens", day.totalTokens)
            )
            .foregroundStyle(tint)
        }
    }

    private var chartHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily trend")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let day = selectedDay ?? peakDay {
                Text(chartSummary(for: day))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tint)
            }
        }
    }

    private func chartSummary(for day: DailyUsage) -> String {
        let date = day.date.formatted(.dateTime.month(.abbreviated).day())
        let tokens = Format.tokens(day.totalTokens)
        let cost = day.estimatedCostUSD.map { "≈ \(Format.cost($0))" } ?? "Estimate unavailable"
        return "\(date): \(tokens) • \(cost)"
    }

    private var selectedDate: Binding<Date?> {
        Binding(
            get: { selectedDayDate },
            set: { date in
                guard let date else {
                    selectedDayDate = nil
                    return
                }
                selectedDayDate = days.min {
                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                }?.date
            }
        )
    }

    private var peakDay: DailyUsage? {
        if showsCost {
            return days.filter { $0.estimatedCostUSD != nil }.max {
                ($0.estimatedCostUSD ?? 0) < ($1.estimatedCostUSD ?? 0)
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
                DailyUsageRow(day: day, tint: tint, showsBreakdown: showsBreakdown)
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

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.callout.weight(.medium))
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
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
                    Text(day.estimatedCostUSD.map(Format.cost) ?? "—")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(day.estimatedCostUSD == nil ? Color.secondary : tint)
                    Text(day.estimatedCostUSD == nil ? "no estimate" : "estimated cost")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 82, alignment: .trailing)
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
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Format.compactTokens(value))
                .font(.caption.weight(.medium))
        }
        .frame(width: 58, alignment: .leading)
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
            Text(model.estimatedCostUSD.map(Format.cost) ?? "Rate unavailable")
                .font(.caption.weight(.medium))
                .frame(minWidth: 82, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }

    private var tokenBreakdown: String {
        var parts: [String] = []
        if let input = model.inputTokens {
            parts.append("Input \(Format.compactTokens(input))")
        }
        if model.cachedInputTokens > 0 {
            parts.append("Cached \(Format.compactTokens(model.cachedInputTokens))")
        }
        if model.cacheWriteInputTokens > 0 {
            parts.append("Cache write \(Format.compactTokens(model.cacheWriteInputTokens))")
        }
        if let output = model.outputTokens {
            parts.append("Output \(Format.compactTokens(output))")
        }
        return parts.joined(separator: " · ")
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
                    usage.provider == .codex
                        ? "No model token metadata was found in recent local Codex sessions."
                        : "No model usage is available.",
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
                    Text(model.estimatedCostUSD.map(Format.cost) ?? "—")
                        .font(.callout.weight(.medium))
                    Text(model.estimatedCostUSD == nil ? "Rate unavailable" : "estimated cost")
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
            parts.append("Cached input \(Format.tokens(model.cachedInputTokens))")
        }
        if model.cacheWriteInputTokens > 0 {
            parts.append("Cache write \(Format.tokens(model.cacheWriteInputTokens))")
        }
        return parts.joined(separator: " · ")
    }

    private func compactMetric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Format.compactTokens(value))
                .font(.caption.weight(.medium))
        }
        .frame(width: 58, alignment: .leading)
    }
}
