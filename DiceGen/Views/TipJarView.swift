//
//  TipJarView.swift
//  DiceGen
//

import SwiftUI

struct TipJarView: View {
    @EnvironmentObject private var tipStore: TipStore

    private var appName: String { DiceGenConstants.appName ?? "This app" }

    private var tipPrompt: String {
        "\(appName) is completely free, with no in-app purchase required to use all features. However, if you enjoy using the app and would like to support an indie developer, please use the buttons below to leave a tip."
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { tipStore.alert != nil },
            set: { isPresented in
                if !isPresented { tipStore.dismissAlert() }
            }
        )
    }

    var body: some View {
        List {
            Text(tipPrompt)
                .padding(.vertical)

            Section {
                if !tipStore.products.isEmpty {
                    ForEach(tipStore.products) { product in
                        Button {
                            Task { await tipStore.purchase(product) }
                        } label: {
                            HStack {
                                Text(product.displayName + DiceGenProduct.emojiSuffix(for: product.id))
                                Spacer()
                                Text(product.displayPrice)
                            }
                        }
                        .foregroundStyle(.primary)
                        .disabled(isPurchasing)
                    }
                } else {
                    loadStateView
                }
            } footer: {
                if !tipStore.missingProductIdentifiers.isEmpty, !tipStore.products.isEmpty {
                    Text("Some tip options are unavailable: \(tipStore.missingProductIdentifiers.sorted().joined(separator: ", ")).")
                }
            }

            if case let .pending(productIdentifier) = tipStore.purchaseState {
                Section {
                    Text("The purchase for \(productIdentifier) is pending approval.")
                }
            }

            if let warning = tipStore.backgroundVerificationWarning {
                Section {
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Why no ads?")
        .task {
            await tipStore.loadProductsIfNeeded()
        }
        .onAppear { tipStore.tipJarDidAppear() }
        .onDisappear { tipStore.tipJarDidDisappear() }
        .alert(
            tipStore.alert?.title ?? "",
            isPresented: alertIsPresented,
            presenting: tipStore.alert
        ) { _ in
            Button("Dismiss", role: .cancel) {
                tipStore.dismissAlert()
            }
        } message: { alert in
            Text(alert.message)
        }
    }

    @ViewBuilder
    private var loadStateView: some View {
        switch tipStore.loadState {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Loading...")
            }
        case .loaded:
            Text("No tip products are available.")
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                Button("Try Again") {
                    Task { await tipStore.retryLoadingProducts() }
                }
            }
        }
    }

    private var isPurchasing: Bool {
        if case .purchasing = tipStore.purchaseState { return true }
        return false
    }
}

struct TipJar_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TipJarView()
        }
        .environmentObject(TipStore(client: StoreKitClient(), startTransactionListener: false))
    }
}
