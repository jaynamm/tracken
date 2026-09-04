//
//  CodexConnectionView.swift
//  tracken
//

import SwiftUI

struct CodexConnectionView: View {
    @Environment(UsageStore.self) private var store
    @State private var isWorking = false
    @State private var showingLogoutConfirmation = false

    private var state: ProviderState { store.state(for: .codex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsStatusRow(status: state.status, isWorking: isWorking)

            if let usage = state.usage {
                accountDetails(usage)
                connectedActions
            } else {
                disconnectedContent
            }
        }
        .confirmationDialog(
            "Sign out of the shared Codex CLI account?",
            isPresented: $showingLogoutConfirmation
        ) {
            Button("Sign out of Codex CLI", role: .destructive) {
                perform { await store.logoutCodex() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also signs the Codex CLI out outside tracken.")
        }
    }

    private func accountDetails(_ usage: TokenUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let email = usage.account?.email {
                Text(email)
                    .font(.callout.weight(.medium))
            }

            HStack(spacing: 8) {
                if let planName = usage.account?.planName {
                    Text("ChatGPT \(Format.planName(planName))")
                }
                Text("\(Format.tokens(usage.last14DaysTotalTokens)) tokens in the last 14 days")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var connectedActions: some View {
        HStack {
            Button {
                perform { await store.refresh(.codex) }
            } label: {
                Label("Sync now", systemImage: "arrow.clockwise")
            }
            .disabled(isWorking)

            Spacer()

            Button(role: .destructive) {
                showingLogoutConfirmation = true
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(isWorking)
        }
    }

    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Uses your local Codex CLI login to read Codex usage. Your ChatGPT credentials stay managed by Codex.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if case .failed(let message) = state.status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button {
                    perform { await store.connectCodex() }
                } label: {
                    Label("Connect with ChatGPT", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async -> Void) {
        Task {
            isWorking = true
            defer { isWorking = false }
            await operation()
        }
    }
}
