//
//  HistoryUnlockView.swift
//  DiceGen
//

import SwiftUI

/// Presents the optional system-authentication route and the required DiceGen PIN fallback.
struct HistoryUnlockView: View {
    @EnvironmentObject private var historyVault: HistoryVault
    @State private var pin = ""
    @State private var usingPIN = false
    @State private var attemptedSystemAuthentication = false
    @State private var isAuthenticating = false
    @State private var message: String?
    @State private var showingResetConfirmation = false

    let onReset: () -> Void

    init(onReset: @escaping () -> Void = {}) {
        self.onReset = onReset
    }

    var body: some View {
        Form {
            Section {
                if historyVault.localAuthenticationEnabled && !usingPIN {
                    if isAuthenticating {
                        ProgressView("Unlocking History…")
                    }
                    Button("Use DiceGen PIN") {
                        usingPIN = true
                        message = nil
                    }
                    .disabled(isAuthenticating)
                }

                if !historyVault.localAuthenticationEnabled || usingPIN {
                    SecureField("History PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    Button("Unlock") {
                        unlockWithPIN()
                    }
                    .disabled(isAuthenticating)
                }

                if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Forgot PIN?", role: .destructive) {
                    showingResetConfirmation = true
                }
            }
        }
        .navigationTitle("Passphrase History")
        .confirmationDialog(
            "Delete private history?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete History", role: .destructive) {
                Task {
                    await historyVault.resetHistory()
                    onReset()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Forgotten PINs cannot be recovered. Deleting history is permanent.")
        }
        .task {
            guard historyVault.sceneIsActive else { return }
            await attemptSystemAuthenticationIfNeeded()
        }
        .onChange(of: historyVault.sceneIsActive) { _, isActive in
            guard isActive else { return }
            Task {
                await attemptSystemAuthenticationIfNeeded()
            }
        }
        .overlay {
            if let lockoutUntil = historyVault.lockoutUntil, lockoutUntil > Date() {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .overlay(alignment: .bottom) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = max(0, Int(ceil(lockoutUntil.timeIntervalSince(context.date))))
                            Text("Try again in \(seconds) seconds")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                        }
                    }
            }
        }
    }

    private func attemptSystemAuthenticationIfNeeded() async {
        guard historyVault.sceneIsActive else { return }

        if historyVault.systemAuthenticationRequiresPIN {
            usingPIN = true
            return
        }

        guard !attemptedSystemAuthentication, !usingPIN else { return }
        attemptedSystemAuthentication = true
        guard historyVault.localAuthenticationEnabled else { return }

        isAuthenticating = true
        let result = await historyVault.authenticateWithSystem()
        isAuthenticating = false
        guard result == .success, historyVault.state == .unlocked else {
            usingPIN = true
            if result == .failed {
                message = "Unable to use system authentication. Enter your History PIN."
            }
            return
        }
    }

    private func unlockWithPIN() {
        message = nil
        isAuthenticating = true
        Task {
            let result = await historyVault.authenticateWithPIN(pin)
            isAuthenticating = false
            switch result {
            case .success:
                pin = ""
            case .incorrect:
                pin = ""
                message = "Incorrect PIN."
            case let .locked(until):
                pin = ""
                let seconds = max(1, Int(ceil(until.timeIntervalSince(Date()))))
                message = "Too many attempts. Try again in \(seconds) seconds."
            case .failed:
                pin = ""
                message = "Unable to unlock History."
            }
        }
    }
}
