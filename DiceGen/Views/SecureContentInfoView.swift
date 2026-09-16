//
//  SecureContentInfoView.swift
//  DiceGen
//

import SwiftUI

struct SecureContentInfoView: View {
    @EnvironmentObject private var passphraseGenerator: PassphraseGenerator
    @EnvironmentObject private var userSettings: UserSettings
    @EnvironmentObject private var historyVault: HistoryVault
    @State private var showingCopiedMessage = false
    @State private var copyFeedbackGeneration = 0

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

    private var copyButtonTitle: String {
        showingCopiedMessage ? "Copied!" : "Copy to Clipboard"
    }

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
            Button("Generate Passphrase") {
                passphraseGenerator.generate(options: userSettings.generationOptions)
            }
            .centered()
            Button(copyButtonTitle) {
                let passphrase = passphraseGenerator.passphrase
                guard copyAction.copy(passphrase) else { return }
                showingCopiedMessage = true
                copyFeedbackGeneration += 1
                Task {
                    await historyVault.recordCopiedPassphrase(passphrase)
                }
            }
            .centered()
            .disabled(showingCopiedMessage || passphraseGenerator.passphrase.isEmpty)
        }
        .task(id: copyFeedbackGeneration) {
            guard showingCopiedMessage else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            showingCopiedMessage = false
        }
    }
}

struct SecureInfoView_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            SecureContentInfoView(reviewRequester: InAppReviewRequester())
        }
        .environmentObject(PassphraseGenerator())
        .environmentObject(UserSettings())
        .environmentObject(HistoryVault.preview())
    }
}
