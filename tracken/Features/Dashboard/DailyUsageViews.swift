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

    @State private var selectedDay: DailyUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) {
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
            .chartXSelection(value: selectedDate)
            .frame(height: 120)
        }
    }

    @ChartContentBuilder
    private func marks(for day: DailyUsage) -> some ChartContent {
        if showsBreakdown {
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
        HStack {
            Text("14-day trend")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
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
        let cost = day.estimatedCostUSD.map(Format.cost) ?? (showsBreakdown ? "—" : "Included")
        return "\(date): \(tokens) • \(cost)"
    }

    private var selectedDate: Binding<Date?> {
        Binding(
            get: { selectedDay?.date },
            set: { date in
                guard let date else {
                    selectedDay = nil
                    return
                }
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

struct DailyUsageList: View {
    let days: [DailyUsage]
    let tint: Color
    let showsBreakdown: Bool

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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.callout.weight(.medium))
                Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64, alignment: .leading)

            if showsBreakdown {
                compactMetric("Input", value: day.inputTokens ?? 0)
                compactMetric("Output", value: day.outputTokens ?? 0)
            }

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
                Text(day.estimatedCostUSD.map(Format.cost) ?? (showsBreakdown ? "—" : "Included"))
                    .font(.callout.weight(.medium))
                Text(day.estimatedCostUSD == nil && !showsBreakdown ? "ChatGPT plan" : "estimated cost")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 82, alignment: .trailing)
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
                        ? "Codex account summaries do not include model-level usage."
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
                        tint: tint,
                        includedInPlan: usage.provider == .codex
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
    let includedInPlan: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.modelName)
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
                    Text(model.estimatedCostUSD.map(Format.cost) ?? (includedInPlan ? "Included" : "—"))
                        .font(.callout.weight(.medium))
                    Text(includedInPlan ? "ChatGPT plan" : "estimated cost")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 82, alignment: .trailing)
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
