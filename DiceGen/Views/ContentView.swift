//
//  ContentView.swift
//  DiceGen
//

import StoreKit
import SwiftUI

struct ContentView: View {
    @Environment(\.requestReview) private var requestReview
    @State private var recordedLaunch = false

    let reviewRequester: InAppReviewRequester
    let reviewRequestsEnabled: Bool

    var body: some View {
        NavigationStack {
            PassphraseGeneratorView(reviewRequester: reviewRequester)
        }
        .task {
            guard !recordedLaunch else { return }
            recordedLaunch = true
            guard reviewRequestsEnabled else { return }
            reviewRequester.recordAppLaunch {
                requestReview()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(reviewRequester: InAppReviewRequester(), reviewRequestsEnabled: false)
            .environmentObject(UserSettings())
            .environmentObject(PassphraseGenerator())
            .environmentObject(TipStore(client: StoreKitClient(), startTransactionListener: false))
    }
}
