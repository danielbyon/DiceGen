//
//  StoreClient.swift
//  DiceGen
//
//  Created by Daniel Byon on 4/3/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation
import StoreKit

typealias ProductIdentifier = String
typealias ProductsRequestCompletion = (Result<[SKProduct], Error>) -> Void

enum StoreClientError: Error {
    case unableToMakePayments
}

final class StoreClient: NSObject {

    static let purchasedNotification = Notification.Name("tipPurchased")

    private let productIdentifiers: Set<ProductIdentifier>
    private var request: SKProductsRequest?
    private var completionHandler: ProductsRequestCompletion?

    init(productIdentifiers: Set<ProductIdentifier>) {
        self.productIdentifiers = productIdentifiers
        super.init()
        SKPaymentQueue.default().add(self)
    }

    func requestProducts(completion: @escaping ProductsRequestCompletion) {
        request?.cancel()

        guard SKPaymentQueue.canMakePayments() else {
            completion(.failure(StoreClientError.unableToMakePayments))
            return
        }

        self.completionHandler = completion

        let request = SKProductsRequest(productIdentifiers: productIdentifiers)
        request.delegate = self
        request.start()
        self.request = request
    }

    func purchaseProduct(_ product: SKProduct) {
        let payment = SKPayment(product: product)
//        let payment = SKMutablePayment(product: product)
//        payment.simulatesAskToBuyInSandbox = true
        SKPaymentQueue.default().add(payment)
    }

}

// MARK: - SKPaymentTransactionObserver
extension StoreClient: SKPaymentTransactionObserver {

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            let identfier = String(describing: transaction.transactionIdentifier)
            switch transaction.transactionState {
            case .purchased:
                debugPrint("Transaction \(identfier) purchased!")
                NotificationCenter.default.post(name: Self.purchasedNotification, object: nil)
            case .failed where (transaction.error as NSError?)?.code == SKError.paymentCancelled.rawValue:
                debugPrint("Transaction \(identfier) cancelled, nothing left to do")
            case .failed:
                debugPrint("Transaction \(identfier) failed with error \(String(describing: transaction.error))")
            case .deferred:
                debugPrint("Transaction \(identfier) in deferred state")
            case .purchasing:
                debugPrint("Transaction \(identfier) in purchasing state")
            case .restored:
                debugPrint("Transaction \(identfier) restored")
            @unknown default:
                debugPrint("Transaction \(identfier) in unknown state: \(transaction.transactionState)")
            }

            if transaction.transactionState != .purchasing && transaction.transactionState != .deferred {
                queue.finishTransaction(transaction)
            }
        }
    }

}

// MARK: - SKProductsRequestDelegate
extension StoreClient: SKProductsRequestDelegate {

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        guard request === self.request else { return }
        self.request = nil
        if !response.invalidProductIdentifiers.isEmpty {
            debugPrint("Invalid product identifiers returned: \(response.invalidProductIdentifiers)")
        }
        completionHandler?(.success(response.products))
        self.completionHandler = nil
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        guard request === self.request else { return }
        self.request = nil
        completionHandler?(.failure(error))
        self.completionHandler = nil
    }

}
