import SwiftUI

struct PricingStatusView: View {
    @Environment(UsageStore.self) private var store
    let provider: AIProvider

    var body: some View {
        let snapshot = store.pricingSnapshots[provider] ?? .bundled(for: provider)
        VStack(alignment: .leading, spacing: 4) {
            Text("\(snapshot.isBundled ? "Bundled rates verified" : "Official rates checked") \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let error = store.pricingErrors[provider] {
                Label(error, systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if Date().timeIntervalSince(snapshot.checkedAt) > 86_400 {
                Text("Using saved rates; an update is due.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct PricingSettingsView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        Section("API price tables") {
            Text("Checks official prices daily while tracken is running. Saved prices work offline. Past usage is recalculated at the latest saved rates; these are not historical bills.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Update prices now") {
                    Task { await store.refreshPrices(force: true) }
                }
                .disabled(store.isRefreshingPrices)
                if store.isRefreshingPrices { ProgressView().controlSize(.small) }
            }
            ForEach(AIProvider.allCases) { provider in
                VStack(alignment: .leading, spacing: 8) {
                    PricingStatusView(provider: provider)
                    let snapshot = store.pricingSnapshots[provider] ?? .bundled(for: provider)
                    DisclosureGroup("\(provider.shortName) · \(snapshot.rates.count) model prices") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("USD per 1 million tokens · standard API rates")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(snapshot.rates.keys.sorted(), id: \.self) { model in
                                if let price = snapshot.rates[model] {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(model).font(.caption.weight(.semibold))
                                        Text("Input \(rate(price.input)) · Output \(rate(price.output))")
                                        Text("Cache read \(rate(price.cachedInput)) · Write \(rate(price.cacheWrite))")
                                        if let oneHour = price.cacheWrite1h {
                                            Text("1h cache write \(rate(oneHour))")
                                        }
                                        if let long = price.longContext {
                                            Text("Over 272K input: \(rate(long.input)) input · \(rate(long.output)) output")
                                            Text("Long cache read \(rate(long.cachedInput)) · Write \(rate(long.cacheWrite))")
                                        }
                                    }
                                    .font(.caption2)
                                    .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    Link("Official \(provider == .codex ? "OpenAI" : "Anthropic") pricing", destination: PricingCatalog.source(for: provider))
                        .font(.caption)
                }
            }
        }
    }

    private func rate(_ value: Double?) -> String {
        value.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(2...5))) } ?? "—"
    }
}
