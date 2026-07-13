//
//  DiceGenApp.swift
//  DiceGen
//

import SwiftUI

@main
@MainActor
struct DiceGenApp: App {
    @StateObject private var userSettings: UserSettings
    @StateObject private var passphraseGenerator: PassphraseGenerator
    @StateObject private var tipStore: TipStore

    private let reviewRequester: InAppReviewRequester
    private let reviewRequestsEnabled: Bool

    init() {
        let configuration = AppRuntimeConfiguration.current()
        _userSettings = StateObject(wrappedValue: UserSettings(defaults: configuration.defaults))
        _passphraseGenerator = StateObject(
            wrappedValue: PassphraseGenerator(randomSource: configuration.randomSource)
        )
        _tipStore = StateObject(wrappedValue: TipStore(client: configuration.storeClient))
        reviewRequester = InAppReviewRequester(defaults: configuration.defaults)
        reviewRequestsEnabled = configuration.reviewRequestsEnabled
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                reviewRequester: reviewRequester,
                reviewRequestsEnabled: reviewRequestsEnabled
            )
            .environmentObject(userSettings)
            .environmentObject(passphraseGenerator)
            .environmentObject(tipStore)
            .tint(Color(uiColor: DiceGenConstants.tintColor))
        }
    }
}

@MainActor
private struct AppRuntimeConfiguration {
    let defaults: UserDefaults
    let randomSource: any RandomIntegerSource
    let storeClient: any StoreClientProtocol
    let reviewRequestsEnabled: Bool

    static func current(
        processInfo: ProcessInfo = .processInfo
    ) -> AppRuntimeConfiguration {
        guard processInfo.arguments.contains("--ui-testing") else {
            return AppRuntimeConfiguration(
                defaults: .standard,
                randomSource: SystemRandomIntegerSource(),
                storeClient: StoreKitClient(),
                reviewRequestsEnabled: true
            )
        }

        let suiteName = "com.danielbyon.DiceGen.ui-tests"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated UI-test UserDefaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return AppRuntimeConfiguration(
            defaults: defaults,
            randomSource: LowerBoundRandomIntegerSource(),
            storeClient: UITestStoreClient(),
            reviewRequestsEnabled: false
        )
    }
}

private actor UITestStoreClient: StoreClientProtocol {
    func products(for identifiers: Set<String>) async throws -> [TipProduct] {
        [
            TipProduct(id: DiceGenProduct.smallTip, displayName: "Small Tip", displayPrice: "$0.99", price: 0.99),
            TipProduct(id: DiceGenProduct.mediumTip, displayName: "Medium Tip", displayPrice: "$1.99", price: 1.99),
            TipProduct(id: DiceGenProduct.largeTip, displayName: "Large Tip", displayPrice: "$2.99", price: 2.99)
        ]
        .filter { identifiers.contains($0.id) }
    }

    func purchase(productIdentifier: String) async throws -> StorePurchaseResult {
        .userCancelled
    }

    func listenForTransactions(
        _ handler: @escaping @Sendable (StoreTransactionUpdate) async -> Void
    ) async {
        let stream = AsyncStream<Void> { _ in }
        for await _ in stream where !Task.isCancelled {}
    }
}
