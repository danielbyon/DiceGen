//
//  PassphraseClipboard.swift
//  DiceGen
//

import UIKit
import UniformTypeIdentifiers

@MainActor
protocol PassphraseClipboardWriting {
    func copy(_ value: String)
}

@MainActor
struct SystemPassphraseClipboardWriter: PassphraseClipboardWriting {
    func copy(_ value: String) {
        #if targetEnvironment(macCatalyst)
        UIPasteboard.general.string = value
        #else
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: value]],
            options: [.localOnly: true]
        )
        #endif
    }
}

@MainActor
struct PassphraseCopyAction {
    private let clipboardWriter: any PassphraseClipboardWriting
    private let reviewRequester: InAppReviewRequester

    init(
        clipboardWriter: any PassphraseClipboardWriting,
        reviewRequester: InAppReviewRequester
    ) {
        self.clipboardWriter = clipboardWriter
        self.reviewRequester = reviewRequester
    }

    @discardableResult
    func copy(_ passphrase: String) -> Bool {
        guard !passphrase.isEmpty else { return false }
        clipboardWriter.copy(passphrase)
        reviewRequester.recordPassphraseCopied()
        return true
    }
}
