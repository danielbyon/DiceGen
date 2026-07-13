//
//  StoreClient.swift
//  DiceGen
//

import Combine
import Foundation
import StoreKit

struct TipProduct: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
    let price: Decimal
}

enum StorePurchaseResult: Equatable, Sendable {
    case verified(productIdentifier: String)
    case unverified(productIdentifier: String)
    case userCancelled
    case pending(productIdentifier: String)
}

enum StoreTransactionUpdate: Equatable, Sendable {
    case verified(productIdentifier: String)
    case unverified(productIdentifier: String)
}

protocol StoreClientProtocol: Sendable {
    func products(for identifiers: Set<String>) async throws -> [TipProduct]
    func purchase(productIdentifier: String) async throws -> StorePurchaseResult
    func listenForTransactions(
        _ handler: @escaping @Sendable (StoreTransactionUpdate) async -> Void
    ) async
}

enum StoreClientError: LocalizedError {
    case productNotLoaded(String)

    var errorDescription: String? {
        switch self {
        case let .productNotLoaded(identifier):
            return "The StoreKit product '\(identifier)' is not currently available."
        }
    }
}

actor StoreKitClient: StoreClientProtocol {
    private var productsByIdentifier: [String: Product] = [:]

    func products(for identifiers: Set<String>) async throws -> [TipProduct] {
        let products = try await Product.products(for: identifiers)
        productsByIdentifier = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        return products.map {
            TipProduct(
                id: $0.id,
                displayName: $0.displayName,
                displayPrice: $0.displayPrice,
                price: $0.price
            )
        }
    }

    func purchase(productIdentifier: String) async throws -> StorePurchaseResult {
        guard let product = productsByIdentifier[productIdentifier] else {
            throw StoreClientError.productNotLoaded(productIdentifier)
        }

        switch try await product.purchase() {
        case let .success(verificationResult):
            switch verificationResult {
            case let .verified(transaction):
                // Tips are consumable acknowledgements, so verification is followed by finishing; no entitlement is stored.
                await transaction.finish()
                return .verified(productIdentifier: transaction.productID)
            case let .unverified(transaction, _):
                return .unverified(productIdentifier: transaction.productID)
            }
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending(productIdentifier: productIdentifier)
        @unknown default:
            return .pending(productIdentifier: productIdentifier)
        }
    }

    func listenForTransactions(
        _ handler: @escaping @Sendable (StoreTransactionUpdate) async -> Void
    ) async {
        for await verificationResult in Transaction.updates {
            guard !Task.isCancelled else { return }
            switch verificationResult {
            case let .verified(transaction):
                await transaction.finish()
                await handler(.verified(productIdentifier: transaction.productID))
            case let .unverified(transaction, _):
                await handler(.unverified(productIdentifier: transaction.productID))
            }
        }
    }
}

enum TipStoreLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

enum TipPurchaseState: Equatable {
    case idle
    case purchasing(productIdentifier: String)
    case pending(productIdentifier: String)
    case cancelled
    case succeeded(productIdentifier: String)
    case failed(productIdentifier: String?, message: String)
}

struct TipStoreAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        case thankYou
        case error
    }

    let kind: Kind
    let title: String
    let message: String

    var id: String { "\(kind)-\(title)-\(message)" }
}

@MainActor
final class TipStore: ObservableObject {
    @Published private(set) var products: [TipProduct] = []
    @Published private(set) var missingProductIdentifiers: Set<String> = []
    @Published private(set) var loadState: TipStoreLoadState = .idle
    @Published private(set) var purchaseState: TipPurchaseState = .idle
    @Published private(set) var lastBackgroundVerifiedProductIdentifier: String?
    @Published private(set) var backgroundVerificationWarning: String?
    @Published var alert: TipStoreAlert?

    private let client: any StoreClientProtocol
    private let expectedProductIdentifiers: Set<String>
    private var transactionListenerTask: Task<Void, Never>?
    private var isTipJarVisible = false

    init(
        client: any StoreClientProtocol,
        expectedProductIdentifiers: Set<String> = DiceGenProduct.allIdentifiers,
        startTransactionListener: Bool = true
    ) {
        self.client = client
        self.expectedProductIdentifiers = expectedProductIdentifiers
        if startTransactionListener {
            startListeningForTransactions()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    /// The store owns one listener attempt for its lifetime; natural completion does not reopen the stream.
    func startListeningForTransactions() {
        guard transactionListenerTask == nil else { return }
        let client = client
        transactionListenerTask = Task { [weak self] in
            await client.listenForTransactions { [weak self] update in
                await self?.handleBackground(update)
            }
        }
    }

    func loadProductsIfNeeded() async {
        guard loadState == .idle else { return }
        await loadProducts()
    }

    func retryLoadingProducts() async {
        await loadProducts()
    }

    func purchase(_ product: TipProduct) async {
        purchaseState = .purchasing(productIdentifier: product.id)
        do {
            switch try await client.purchase(productIdentifier: product.id) {
            case let .verified(productIdentifier):
                purchaseState = .succeeded(productIdentifier: productIdentifier)
                alert = TipStoreAlert(kind: .thankYou, title: "Thank you!", message: "Your tip is appreciated.")
            case let .unverified(productIdentifier):
                let message = "The App Store returned a purchase that could not be verified. No tip acknowledgement was recorded."
                purchaseState = .failed(productIdentifier: productIdentifier, message: message)
                alert = TipStoreAlert(kind: .error, title: "Purchase could not be verified", message: message)
            case .userCancelled:
                purchaseState = .cancelled
            case let .pending(productIdentifier):
                purchaseState = .pending(productIdentifier: productIdentifier)
            }
        } catch {
            let message = error.localizedDescription
            purchaseState = .failed(productIdentifier: product.id, message: message)
            alert = TipStoreAlert(kind: .error, title: "Purchase failed", message: message)
        }
    }

    func tipJarDidAppear() {
        isTipJarVisible = true
    }

    func tipJarDidDisappear() {
        isTipJarVisible = false
    }

    func dismissAlert() {
        alert = nil
    }

    private func loadProducts() async {
        loadState = .loading
        do {
            let returnedProducts = try await client.products(for: expectedProductIdentifiers)
            products = returnedProducts.sorted { $0.price < $1.price }
            missingProductIdentifiers = expectedProductIdentifiers.subtracting(products.map(\.id))
            if products.isEmpty {
                loadState = .failed(message: "No tip products are currently available from the App Store.")
            } else {
                loadState = .loaded
            }
        } catch {
            products = []
            missingProductIdentifiers = expectedProductIdentifiers
            loadState = .failed(message: error.localizedDescription)
        }
    }

    private func handleBackground(_ update: StoreTransactionUpdate) {
        switch update {
        case let .verified(productIdentifier):
            lastBackgroundVerifiedProductIdentifier = productIdentifier
            if isTipJarVisible {
                alert = TipStoreAlert(kind: .thankYou, title: "Thank you!", message: "Your tip is appreciated.")
            }
        case .unverified:
            backgroundVerificationWarning = "A StoreKit transaction update could not be verified."
        }
    }
}
