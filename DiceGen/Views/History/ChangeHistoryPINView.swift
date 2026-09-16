//
//  ChangeHistoryPINView.swift
//  DiceGen
//

import SwiftUI

/// Changes the app-specific PIN only after verifying the current PIN.
struct ChangeHistoryPINView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyVault: HistoryVault
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmationPIN = ""
    @State private var isSaving = false
    @State private var message: String?

    private var canSubmit: Bool {
        HistoryPINPolicy.isValid(currentPIN)
            && HistoryPINPolicy.isValid(newPIN)
            && newPIN == confirmationPIN
    }

    var body: some View {
        Form {
            Section {
                SecureField("Current PIN", text: $currentPIN)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                SecureField("New PIN", text: $newPIN)
                    .keyboardType(.numberPad)
                    .textContentType(.newPassword)
                SecureField("Confirm New PIN", text: $confirmationPIN)
                    .keyboardType(.numberPad)
                    .textContentType(.newPassword)
            }

            Section {
                Button("Change PIN") {
                    changePIN()
                }
                .disabled(!canSubmit || isSaving)
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Change PIN")
        .overlay {
            if isSaving {
                ProgressView()
            }
        }
    }

    private func changePIN() {
        guard canSubmit else { return }
        message = nil
        isSaving = true
        Task {
            let result = await historyVault.changePIN(currentPIN: currentPIN, newPIN: newPIN)
            isSaving = false
            switch result {
            case .success:
                currentPIN = ""
                newPIN = ""
                confirmationPIN = ""
                dismiss()
            case .incorrect:
                currentPIN = ""
                message = "Incorrect current PIN."
            case let .locked(until):
                currentPIN = ""
                let seconds = max(1, Int(ceil(until.timeIntervalSince(Date()))))
                message = "Too many attempts. Try again in \(seconds) seconds."
            case .failed:
                currentPIN = ""
                message = "The PIN could not be changed."
            }
        }
    }
}
