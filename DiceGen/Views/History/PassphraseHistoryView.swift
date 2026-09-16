//
//  PassphraseHistoryView.swift
//  DiceGen
//

import SwiftUI

/// Shows passphrase history only after the vault has authorized the current session.
struct PassphraseHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyVault: HistoryVault
    @State private var showingClearConfirmation = false

    private let copyAction: PassphraseCopyAction

    init(
        reviewRequester: InAppReviewRequester,
        clipboardWriter: any PassphraseClipboardWriting = SystemPassphraseClipboardWriter()
    ) {
        copyAction = PassphraseCopyAction(
            clipboardWriter: clipboardWriter,
            reviewRequester: reviewRequester
        )
    }

    var body: some View {
        content
            .navigationTitle("Passphrase History")
            .toolbar {
                if historyVault.state == .unlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear All", role: .destructive) {
                            showingClearConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear all saved passphrases?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) {
                    Task { await historyVault.clearAll() }
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var content: some View {
        switch historyVault.state {
        case .initializing:
            ProgressView("Loading History…")
        case .locked:
            HistoryUnlockView(onReset: { dismiss() })
        case .unlocked:
            unlockedContent
        case .disabled:
            unavailableContent(message: "History is disabled.")
        case .setupRequired:
            unavailableContent(message: "Set up History in Settings before viewing saved passphrases.")
        case .failed:
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "History Needs Reset",
                    systemImage: "exclamationmark.lock",
                    description: Text("History is unavailable until its local security state is reset.")
                )
                Button("Reset History", role: .destructive) {
                    Task {
                        await historyVault.resetHistory()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unlockedContent: some View {
        if historyVault.entries.isEmpty {
            ContentUnavailableView("No History Yet", systemImage: "clock")
        } else {
            List {
                ForEach(historyVault.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.content)
                        Text(entry.savedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Copy") { copy(entry) }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await historyVault.deleteEntry(id: entry.id) }
                        }
                    }
                }
            }
        }
    }

    private func unavailableContent(message: String) -> some View {
        ContentUnavailableView("History Unavailable", systemImage: "lock", description: Text(message))
    }

    private func copy(_ entry: HistoryEntry) {
        guard copyAction.copy(entry.content) else { return }
        Task { await historyVault.recordCopiedPassphrase(entry.content) }
    }
}
