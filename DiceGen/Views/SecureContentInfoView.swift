//
//  SecureContentInfoView.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/30/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI

struct SecureContentInfoView: View {

    @EnvironmentObject var historyStorage: HistoryStorage
    @EnvironmentObject var userSettings: UserSettings
    @ObservedObject var passphraseGenerator: PassphraseGenerator
    @State private var showingCopiedMessage = false

    private var copyButtonTitle: String {
        showingCopiedMessage ? "Copied!" : "Copy to Clipboard"
    }

    private let copiedMessageDismissDelay: TimeInterval = 1.0

    var body: some View {
        Section {
            VStack {
                PassphraseText(text: passphraseGenerator.passphrase)
                HStack {
                    Spacer()
                    Text("\(passphraseGenerator.passphrase.count) characters")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            Button(action: {
                self.passphraseGenerator.generatePassphrase()
            }) {
                Text("Generate Passphrase")
                    .centered()
            }
            Button(action: {
                let passphrase = self.passphraseGenerator.passphrase
                UIPasteboard.general.string = passphrase
                self.historyStorage.saveItem(passphrase)

                InAppReviewManager.recordPassphraseCopied()

                self.showingCopiedMessage = true
                DispatchQueue.main.asyncAfter(deadline: .now() + self.copiedMessageDismissDelay) {
                    self.showingCopiedMessage = false
                }
            }) {
                Text(copyButtonTitle)
                    .centered()
            }
            .disabled(showingCopiedMessage)
        }
    }

}

struct SecureInfoView_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            SecureContentInfoView(passphraseGenerator: .default)
                .environmentObject(HistoryStorage())
                .environmentObject(UserSettings())
        }
    }
}
