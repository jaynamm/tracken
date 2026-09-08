//
//  MenuBarView.swift
//  tracken
//

import SwiftUI

struct MenuBarView: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 10) {
                ForEach(AIProvider.allCases) { provider in
                    MenuBarProviderCard(provider: provider, state: store.state(for: provider))
                }
            }

            ClaudeLimitsView(compact: true)

            if !store.connectedProviders.isEmpty {
                combinedUsage
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Usage overview")
                    .font(.headline)
                Text("Last 14 days · hourly refresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
        }
    }

    private var combinedUsage: some View {
        Group {
            Divider()
            HStack {
                Label("Combined", systemImage: "sum")
                    .font(.callout.weight(.medium))
                Spacer()
                Text(Format.compactTokens(store.combinedLast14DaysTokens))
                    .font(.callout.weight(.semibold))
                Text("14d")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open tracken") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .font(.callout)
    }
}

private struct MenuBarProviderCard: View {
    let provider: AIProvider
    let state: ProviderState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader

            if let usage = state.usage {
                usageContent(usage)
            } else {
                emptyContent
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(12)
        .background(provider.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(provider.accentColor.opacity(0.2), lineWidth: 1)
        }
    }

    private var cardHeader: some View {
        HStack(spacing: 6) {
            Label(provider.shortName, systemImage: provider.symbolName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(provider.accentColor)
            Spacer(minLength: 4)
            Image(systemName: state.status.symbolName)
                .font(.caption)
                .foregroundStyle(state.status.color)
                .help(state.status.label)
        }
    }

    private func usageContent(_ usage: TokenUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.compactTokens(usage.last14DaysTotalTokens))
                    .font(.title2.weight(.bold))
                    .contentTransition(.numericText())
                Text("tokens")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                CompactMetric(
                    title: "Today",
                    value: Format.compactTokens(usage.last14Days.first?.totalTokens ?? 0)
                )
                Spacer()
                secondaryMetric(for: usage)
            }
        }
    }

    private func secondaryMetric(for usage: TokenUsage) -> some View {
        let today = usage.last14Days.first
        return CompactMetric(
            title: today?.isPartialCostEstimate == true ? "Today partial est." : "Today est.",
            value: today?.knownEstimatedCostUSD.map(Format.cost) ?? "—"
        )
    }

    private var emptyHint: String {
        if provider == .anthropic { return "Reload local history in Settings" }
        if case .unavailable = state.status { return "Usage unavailable" }
        return "Connect in Settings"
    }

    private var emptyContent: some View {
        Group {
            if case .connecting = state.status {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading…")
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.status.label)
                        .fontWeight(.medium)
                        .foregroundStyle(state.status.color)
                        .lineLimit(2)
                    Text(emptyHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct CompactMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
        }
    }
}

#Preview {
    MenuBarView()
        .environment(UsageStore())
}
