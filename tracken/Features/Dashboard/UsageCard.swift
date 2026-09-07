//
//  UsageCard.swift
//  tracken
//

import SwiftUI

struct UsageCard: View {
    @Environment(UsageStore.self) private var store
    let provider: AIProvider
    let dayCount: Int?

    private var state: ProviderState { store.state(for: provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(provider.shortName, systemImage: provider.symbolName)
                    .font(.headline)
                    .foregroundStyle(provider.accentColor)
                Spacer()
                ConnectionStatusBadge(status: state.status)
            }

            if provider == .anthropic {
                ClaudeLimitsView()
                Divider()
            }
            if let usage = state.usage {
                UsageDetails(usage: usage.displayUsage(dayCount: dayCount))
            } else {
                placeholder
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(provider.accentColor.opacity(0.2), lineWidth: 1)
        }
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            switch state.status {
            case .unavailable(let message):
                Image(systemName: "info.circle")
                Text(message)
            case .connecting:
                ProgressView().controlSize(.small)
                Text("Fetching usage…")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .foregroundStyle(.red)
            case .notConnected, .connected:
                Image(systemName: provider == .codex
                      ? "person.crop.circle.badge.checkmark"
                      : "folder")
                Text(provider == .codex
                     ? "Connect your ChatGPT account in Settings to see Codex usage."
                     : "Local Claude Code history is loaded automatically. Reload it in Settings.")
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct UsageDetails: View {
    let usage: TokenUsage

    private var provider: AIProvider { usage.provider }
    private var days: [DailyUsage] { usage.daily }
    private var inputTokens: Int { days.compactMap(\.inputTokens).reduce(0, +) }
    private var outputTokens: Int { days.compactMap(\.outputTokens).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline
            PricingStatusView(provider: provider)
            if provider == .anthropic {
                Text("Claude Code history on this Mac. Input includes cache reads and writes. Costs use current API rates, not subscription charges.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if usage.hasDetailedBreakdown {
                detailedSummary
            } else {
                codexSummary
            }

            Divider()
            DailyUsageChart(
                days: Array(days.reversed()),
                tint: provider.accentColor,
                showsBreakdown: usage.hasDetailedBreakdown
            )
            .id(provider)

            Divider()
            DailyUsageList(
                days: days,
                tint: provider.accentColor,
                showsBreakdown: usage.hasDetailedBreakdown
            )

            Divider()
            ModelUsageList(usage: usage, tint: provider.accentColor)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Format.tokens(usage.totalTokens))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
            Text("tokens")
                .foregroundStyle(.secondary)
            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let planName = usage.account?.planName {
                    Text("ChatGPT \(Format.planName(planName))")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let cost = usage.estimatedCostUSD {
                    Text("≈ \(Format.cost(cost)) API estimate")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(provider.accentColor)
                }
            }
        }
    }

    private var detailedSummary: some View {
        VStack(spacing: 10) {
            TokenSplitBar(
                input: inputTokens,
                output: outputTokens,
                tint: provider.accentColor
            )

            HStack {
                UsageMetric(title: "Input", value: Format.tokens(inputTokens))
                Spacer()
                UsageMetric(title: "Output", value: Format.tokens(outputTokens))
                Spacer()
                UpdatedLabel(date: usage.updatedAt)
            }
        }
    }

    private var codexSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let rateLimit = usage.rateLimit {
                    UsageMetric(title: "Usage limit", value: Format.percent(rateLimit.usedPercent))
                    Spacer()
                    if let resetsAt = rateLimit.resetsAt {
                        UsageMetric(
                            title: "Resets",
                            value: resetsAt.formatted(
                                .dateTime.month(.abbreviated).day().hour().minute()
                            )
                        )
                        Spacer()
                    }
                }
                UpdatedLabel(date: usage.updatedAt)
            }

            Label(
                "Daily totals use account data, with local records for missing days. Costs are local API estimates.",
                systemImage: "clock.arrow.circlepath"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

private struct ConnectionStatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        Label(status.label, systemImage: status.symbolName)
            .font(.caption)
            .foregroundStyle(status.color)
    }
}

private struct UsageMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
        }
    }
}

private struct UpdatedLabel: View {
    let date: Date

    var body: some View {
        Text("Updated \(Format.relative(date))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

private struct TokenSplitBar: View {
    let input: Int
    let output: Int
    let tint: Color

    private var inputFraction: Double {
        let total = input + output
        return total == 0 ? 0 : Double(input) / Double(total)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, geometry.size.width * inputFraction))
                Capsule()
                    .fill(tint.opacity(0.35))
            }
        }
        .frame(height: 8)
    }
}
