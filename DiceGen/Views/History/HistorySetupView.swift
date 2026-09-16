//
//  HistorySetupView.swift
//  DiceGen
//

import SwiftUI

/// Collects the new DiceGen PIN before enabling protected history.
struct HistorySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyVault: HistoryVault
    @State private var pin = ""
    @State private var confirmationPIN = ""
    @State private var isSaving = false
    @State private var message: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case pin
        case confirmation
    }

    private var canSubmit: Bool {
        HistoryPINPolicy.isValid(pin) && pin == confirmationPIN
    }

    var body: some View {
        Form {
            Section {
                SecureField("PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .pin)
                SecureField("Confirm PIN", text: $confirmationPIN)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .confirmation)
            }

            Section {
                Button("Enable History") {
                    enableHistory()
                }
                .disabled(!canSubmit || isSaving)
            }

            Section {
                Text("Use 4-12 digits. DiceGen cannot recover this PIN without deleting history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Enable History")
        .task {
            focusedField = .pin
        }
        .overlay {
            if isSaving {
                ProgressView()
            }
        }
    }

    private func enableHistory() {
        guard canSubmit else { return }
        message = nil
        isSaving = true
        Task {
            let didEnable = await historyVault.configureHistory(pin: pin)
            isSaving = false
            guard didEnable else {
                message = "History could not be enabled. Try again or reset its security state."
                return
            }
            pin = ""
            confirmationPIN = ""
            dismiss()
        }
    }
}
