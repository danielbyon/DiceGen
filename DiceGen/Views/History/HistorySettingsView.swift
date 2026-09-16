//
//  HistorySettingsView.swift
//  DiceGen
//

import SwiftUI

/// Routes History settings through setup, authentication, enabled controls, or recovery.
struct HistorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyVault: HistoryVault
    @State private var showingDisableConfirmation = false

    var body: some View {
        content
            .navigationTitle("History")
            .confirmationDialog(
                "Disable History?",
                isPresented: $showingDisableConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete History and Disable", role: .destructive) {
                    Task {
                        await historyVault.disableHistory()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved history and its protection settings will be permanently removed.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch historyVault.state {
        case .initializing:
            ProgressView("Loading History…")
        case .disabled:
            setupContent(
                message: "History is off. Enable it to save copied passphrases behind a DiceGen PIN."
            )
        case .setupRequired:
            setupContent(
                message: "History setup is required. Migrated history will become accessible after you set a new PIN."
            )
        case .locked:
            HistoryUnlockView(onReset: { dismiss() })
        case .unlocked:
            enabledContent
        case .failed:
            recoveryContent
        }
    }

    private func setupContent(message: String) -> some View {
        VStack(spacing: 20) {
            ContentUnavailableView("History Setup Required", systemImage: "lock", description: Text(message))
            NavigationLink("Enable History") {
                HistorySetupView()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var enabledContent: some View {
        Form {
            Section {
                Toggle(
                    "Use Face ID / Touch ID / Device Passcode",
                    isOn: Binding(
                        get: { historyVault.localAuthenticationEnabled },
                        set: { enabled in
                            Task { _ = await historyVault.setLocalAuthenticationEnabled(enabled) }
                        }
                    )
                )
            }

            Section {
                NavigationLink("Change PIN") {
                    ChangeHistoryPINView()
                }
            }

            Section {
                Button("Disable History", role: .destructive) {
                    showingDisableConfirmation = true
                }
            }
        }
    }

    private var recoveryContent: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "History Needs Reset",
                systemImage: "exclamationmark.lock",
                description: Text("History security state is unavailable. Reset it before setting up History again.")
            )
            Button("Reset History", role: .destructive) {
                Task {
                    await historyVault.resetHistory()
                    dismiss()
                }
            }
        }
        .padding()
    }
}
