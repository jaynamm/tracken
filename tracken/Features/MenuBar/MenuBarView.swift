//
//  MenuBarView.swift
//  tracken
//
//  Compact popover shown from the macOS menu bar item.
//

import SwiftUI

struct MenuBarView: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Token usage")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing || store.connectedProviders.isEmpty)
            }

            if store.connectedProviders.isEmpty {
                Text("No accounts connected yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(AIProvider.allCases) { provider in
                    if store.isConnected(provider) {
                        row(for: provider)
                    }
                }

                Divider()

                HStack {
                    Text("Total")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text(Format.compactTokens(store.combinedTokens))
                        .font(.callout.weight(.semibold))
                    Text(Format.cost(store.combinedCostUSD))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

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
        .padding(14)
        .frame(width: 280)
        .task {
            if store.usage.isEmpty {
                await store.refreshAll()
            }
        }
    }

    private func row(for provider: AIProvider) -> some View {
        HStack {
            Label(provider.shortName, systemImage: provider.symbolName)
                .foregroundStyle(provider.accentColor)
            Spacer()
            if let usage = store.usage[provider] {
                Text(Format.compactTokens(usage.totalTokens))
                    .font(.callout.weight(.medium))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .font(.callout)
    }
}

#Preview {
    MenuBarView()
        .environment(UsageStore())
}
