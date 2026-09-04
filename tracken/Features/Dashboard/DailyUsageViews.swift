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
                Text("\(day.date.formatted(.dateTime.month(.abbreviated).day())): \(Format.tokens(day.totalTokens))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tint)
            }
        }
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
