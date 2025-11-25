//
//  TipJarView.swift
//  DiceGen
//
//  Created by Daniel Byon on 4/3/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI
import StoreKit

struct TipJarView: View {

    @Environment(\.presentationMode) var presentation
    @State private var products: [SKProduct] = []
    @State private var showingTipThanks = false
    @State private var error: ErrorInfo?

    private let storeClient = DiceGenProduct.store

    private var appName: String { DiceGenConstants.appName ?? "This app" }

    private var tipPrompt: String {
        "\(appName) is completely free, with no in-app purchase required to use all features. However, if you enjoy using the app and would like to support an indie developer, please use the buttons below to leave a tip."
    }

    var body: some View {
        List {
            Text(tipPrompt)
                .padding(.vertical)
            Section {
                if products.isEmpty {
                    HStack {
                        Text("Loading...")
                    }
                } else {
                    ForEach(products, id: \.self) { product in
                        Button(action: {
                            self.storeClient.purchaseProduct(product)
                        }) {
                            HStack {
                                Text(product.localizedTitle + product.emojiSuffix)
                                Spacer()
                                if product.localizedPrice != nil {
                                    Text(product.localizedPrice!)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
        }
        .listStyle(GroupedListStyle())
        .navigationBarTitle(Text("Why no ads?"))
        .onAppear {
            self.storeClient.requestProducts { result in
                switch result {
                case .success(let products):
                    self.products = products.sorted { $0.price.decimalValue < $1.price.decimalValue }
                case .failure(let error):
                    debugPrint(error)
                    self.error = ErrorInfo(error: error)
                }
            }
        }
        .alert(item: $error) { error in
            Alert(
                title: Text("Failed to fetch products"),
                message: Text("Check your network settings and try again."),
                dismissButton: .default(
                    Text("Dismiss"),
                    action: {
                        self.presentation.wrappedValue.dismiss()
                }))
        }
        .alert(isPresented: $showingTipThanks) {
            Alert(
                title: Text("Thank you!"),
                dismissButton: .default(
                    Text("Dismiss"),
                    action: {
                        self.showingTipThanks = false
                }))
        }
        .onReceive(NotificationCenter.default.publisher(for: StoreClient.purchasedNotification)) { _ in
            self.showingTipThanks.toggle()
        }
    }

}

struct TipJar_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TipJarView()
        }
    }
}

private struct ErrorInfo: Identifiable {
    let error: Error
    var id: String = UUID().uuidString
}

private extension SKProduct {

    var localizedPrice: String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        return formatter.string(from: price)
    }

    var emojiSuffix: String {
        switch productIdentifier {
        case DiceGenProduct.smallTip:
            return " 🍫"
        case DiceGenProduct.mediumTip:
            return " ☕️"
        case DiceGenProduct.largeTip:
            return " 🍕"
        default:
            return ""
        }
    }

}
