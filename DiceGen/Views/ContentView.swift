//
//  ContentView.swift
//  DiceGen
//

import StoreKit
import SwiftUI

struct ContentView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var historyVault: HistoryVault
    @State private var recordedLaunch = false
    @State private var historyDidInitialize = false
    @State private var showingMigrationNotice = false

    let reviewRequester: InAppReviewRequester
    let reviewRequestsEnabled: Bool

    var body: some View {
        ZStack {
            NavigationStack {
                PassphraseGeneratorView(reviewRequester: reviewRequester)
            }

            if scenePhase != .active {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

        }
        .alert("History now requires a PIN", isPresented: $showingMigrationNotice) {
            Button("OK") {
                Task { await historyVault.consumeMigrationNotice() }
            }
        } message: {
            Text("Existing history was moved to private local storage. Set a PIN in Settings > History to access it and resume saving copied passphrases.")
        }
        .task {
            historyVault.setScenePhase(historyScenePhase(for: scenePhase))
            await historyVault.initialize()
            historyDidInitialize = true
            presentMigrationNoticeIfNeeded()
            guard !recordedLaunch else { return }
            recordedLaunch = true
            guard reviewRequestsEnabled else { return }
            reviewRequester.recordAppLaunch {
                requestReview()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            historyVault.setScenePhase(historyScenePhase(for: newPhase))
            if newPhase == .active {
                presentMigrationNoticeIfNeeded()
            } else {
                showingMigrationNotice = false
            }
        }
    }

    private func historyScenePhase(for phase: ScenePhase) -> HistoryScenePhase {
        switch phase {
        case .active:
            return .active
        case .inactive:
            return .inactive
        case .background:
            return .background
        @unknown default:
            return .background
        }
    }

    private func presentMigrationNoticeIfNeeded() {
        guard historyDidInitialize,
              historyVault.sceneIsActive,
              historyVault.migrationNoticePending else { return }
        showingMigrationNotice = true
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(reviewRequester: InAppReviewRequester(), reviewRequestsEnabled: false)
            .environmentObject(UserSettings())
            .environmentObject(PassphraseGenerator())
            .environmentObject(TipStore(client: StoreKitClient(), startTransactionListener: false))
            .environmentObject(HistoryVault.preview())
    }
}
