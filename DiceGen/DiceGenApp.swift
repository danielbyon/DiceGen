//
//  DiceGenApp.swift
//  DiceGen
//

import Foundation
import SwiftUI

@main
@MainActor
struct DiceGenApp: App {
    @StateObject private var userSettings: UserSettings
    @StateObject private var passphraseGenerator: PassphraseGenerator
    @StateObject private var tipStore: TipStore
    @StateObject private var historyVault: HistoryVault

    private let reviewRequester: InAppReviewRequester
    private let reviewRequestsEnabled: Bool

    init() {
        let configuration = AppRuntimeConfiguration.current()
        _userSettings = StateObject(wrappedValue: UserSettings(defaults: configuration.defaults))
        _passphraseGenerator = StateObject(
            wrappedValue: PassphraseGenerator(randomSource: configuration.randomSource)
        )
        _tipStore = StateObject(wrappedValue: TipStore(client: configuration.storeClient))
        let historyStore = HistoryStore(rootURL: configuration.historyRootURL)
        let historyMigration = HistoryMigration(defaults: configuration.defaults, store: historyStore)
        _historyVault = StateObject(
            wrappedValue: HistoryVault(
                store: historyStore,
                credentials: configuration.historyCredentialStore,
                authenticator: configuration.historyAuthenticator,
                migration: historyMigration
            )
        )
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
            .environmentObject(historyVault)
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
    let historyRootURL: URL
    let historyCredentialStore: any PINCredentialStoring
    let historyAuthenticator: any HistoryAuthenticating

    static func current(
        processInfo: ProcessInfo = .processInfo
    ) -> AppRuntimeConfiguration {
        guard processInfo.arguments.contains("--ui-testing") else {
            return AppRuntimeConfiguration(
                defaults: .standard,
                randomSource: SystemRandomIntegerSource(),
                storeClient: StoreKitClient(),
                reviewRequestsEnabled: true,
                historyRootURL: HistoryStore.defaultRootURL(),
                historyCredentialStore: KeychainPINCredentialStore(),
                historyAuthenticator: LocalHistoryAuthenticator()
            )
        }

        let suiteName = "com.danielbyon.DiceGen.ui-tests"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated UI-test UserDefaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let historyRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiceGen-ui-tests-history", isDirectory: true)
        try? FileManager.default.removeItem(at: historyRootURL)
        let suspendsSystemAuthentication = processInfo.arguments.contains(
            "--ui-testing-local-auth-suspended"
        )
        if processInfo.arguments.contains("--ui-testing-seeded-legacy-history") {
            defaults.set(
                [["content": "seeded legacy history", "savedAt": Date(timeIntervalSince1970: 100)]],
                forKey: HistoryMigration.savedItemsKey
            )
            defaults.set(true, forKey: HistoryMigration.shouldSaveItemsKey)
        }
        return AppRuntimeConfiguration(
            defaults: defaults,
            randomSource: LowerBoundRandomIntegerSource(),
            storeClient: UITestStoreClient(),
            reviewRequestsEnabled: false,
            historyRootURL: historyRootURL,
            historyCredentialStore: UITestPINCredentialStore(),
            historyAuthenticator: UITestHistoryAuthenticator(
                result: processInfo.arguments.contains("--ui-testing-local-auth-success") || suspendsSystemAuthentication
                    ? .success
                    : .cancelled,
                waitsForRelease: suspendsSystemAuthentication
            )
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

private actor UITestPINCredentialStore: PINCredentialStoring {
    private var pin: String?

    func hasCredential() async throws -> Bool { pin != nil }

    func setPIN(_ pin: String) async throws {
        self.pin = pin
    }

    func verifyPIN(_ pin: String) async throws -> Bool {
        self.pin == pin
    }

    func deleteCredential() async throws {
        pin = nil
    }
}

private final class UITestAuthenticationContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HistoryAuthenticationResult, Never>?
    private var hasResumed = false

    func install(
        _ continuation: CheckedContinuation<HistoryAuthenticationResult, Never>,
        result: HistoryAuthenticationResult
    ) {
        lock.lock()
        let resumeImmediately = hasResumed
        if !resumeImmediately {
            self.continuation = continuation
        }
        lock.unlock()

        if resumeImmediately {
            continuation.resume(returning: result)
        }
    }

    func resume(with result: HistoryAuthenticationResult) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: result)
    }
}

private struct UITestHistoryAuthenticator: HistoryAuthenticating {
    let result: HistoryAuthenticationResult
    let waitsForRelease: Bool

    func authenticate(reason: String) async -> HistoryAuthenticationResult {
        guard waitsForRelease else { return result }

        let continuationBox = UITestAuthenticationContinuationBox()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                continuationBox.install(continuation, result: result)
                if Task.isCancelled {
                    continuationBox.resume(with: result)
                }
            }
        }, onCancel: {
            // Scene-task cancellation releases the suspended request for the UI test.
            continuationBox.resume(with: result)
        })
    }
}
