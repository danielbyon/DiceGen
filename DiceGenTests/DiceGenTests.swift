//
//  DiceGenTests.swift
//  DiceGenTests
//

import XCTest
@testable import DiceGen

@MainActor
final class DiceGenTests: XCTestCase {
    private var appBundle: Bundle {
        Bundle(for: PassphraseGenerator.self)
    }

    func testEverySelectableWordListHasExactlyOneValidResource() throws {
        for identifier in WordListIdentifier.allCases {
            let resourceURLs = WordListLoader.resourceURLs(for: identifier, bundle: appBundle)
            XCTAssertEqual(resourceURLs.count, 1, "Expected exactly one resource for \(identifier.rawValue)")

            let wordList = try WordListLoader.load(identifier: identifier, bundle: appBundle)
            let expectedKeys = DiceKeySpace.keys(numberOfRolls: identifier.numberOfRollsPerWord)
            XCTAssertEqual(wordList.keys, expectedKeys, "Wrong key space for \(identifier.rawValue)")
            XCTAssertEqual(wordList.count, expectedKeys.count)
            for key in expectedKeys {
                XCTAssertFalse(
                    wordList.word(for: key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Empty word for \(identifier.rawValue) key \(key)"
                )
            }
        }
    }

    func testUnreferencedDicewareResourcesAreReportedWithoutFailing() throws {
        let classification = try WordListResourceClassifier.classify(bundle: appBundle)
        let expectedSelectableResources = Set(WordListIdentifier.allCases.map { "\($0.filename).txt" })
        XCTAssertEqual(Set(classification.referencedSelectableResources), expectedSelectableResources)

        let dicewareReport = classification.unreferencedDicewareResources.joined(separator: ", ")
        let otherReport = classification.otherTextResources.joined(separator: ", ")
        XCTContext.runActivity(
            named: "Unreferenced Diceware resources: \(dicewareReport.isEmpty ? "none" : dicewareReport)"
        ) { _ in
            XCTContext.runActivity(
                named: "Other text resources: \(otherReport.isEmpty ? "none" : otherReport)"
            ) { _ in }
        }
    }

    func testWordListResourceClassifierSeparatesControlledResourceData() throws {
        let classification = try WordListResourceClassifier.classify(
            resources: [
                WordListTextResource(filename: "effShort.txt", data: validWordListData(numberOfRolls: 4)),
                WordListTextResource(filename: "dormant.txt", data: validWordListData(numberOfRolls: 5)),
                WordListTextResource(filename: "attribution.txt", data: Data("Attribution text".utf8))
            ],
            selectableIdentifiers: [.effShort]
        )

        XCTAssertEqual(classification.referencedSelectableResources, ["effShort.txt"])
        XCTAssertEqual(classification.unreferencedDicewareResources, ["dormant.txt"])
        XCTAssertEqual(classification.otherTextResources, ["attribution.txt"])
    }

    func testWordListResourceClassifierRejectsMissingAndDuplicateSelectableResources() {
        XCTAssertThrowsError(
            try WordListResourceClassifier.classify(resources: [], selectableIdentifiers: [.effShort])
        )

        let duplicate = WordListTextResource(
            filename: "effShort.txt",
            data: validWordListData(numberOfRolls: 4)
        )
        XCTAssertThrowsError(
            try WordListResourceClassifier.classify(
                resources: [duplicate, duplicate],
                selectableIdentifiers: [.effShort]
            )
        )
    }

    func testWordListValidationAcceptsTrailingBlankLines() throws {
        var data = validWordListData(numberOfRolls: 4)
        data.append(Data("\n \t\n".utf8))
        let words = try WordListLoader.validate(data: data, numberOfRolls: 4, resourceName: "valid.txt")
        XCTAssertEqual(Set(words.keys), DiceKeySpace.keys(numberOfRolls: 4))
    }

    func testWordListValidationRejectsInvalidUTF8() {
        XCTAssertThrowsError(
            try WordListLoader.validate(data: Data([0xFF]), numberOfRolls: 4, resourceName: "invalid.txt")
        )
    }

    func testWordListValidationRejectsMalformedRow() {
        let data = replacingFirstRow(in: validWordListText(numberOfRolls: 4), with: "1111word")
        XCTAssertThrowsError(
            try WordListLoader.validate(data: Data(data.utf8), numberOfRolls: 4, resourceName: "malformed.txt")
        )
    }

    func testWordListValidationRejectsInternalBlankRow() {
        var rows = validWordListText(numberOfRolls: 4).split(separator: "\n").map(String.init)
        rows.insert(" \t", at: 1)
        let text = rows.joined(separator: "\n")
        XCTAssertThrowsError(
            try WordListLoader.validate(data: Data(text.utf8), numberOfRolls: 4, resourceName: "blank.txt")
        )
    }

    func testWordListValidationRejectsInvalidKey() {
        let text = replacingFirstRow(in: validWordListText(numberOfRolls: 4), with: "nope word")
        XCTAssertThrowsError(
            try WordListLoader.validate(data: Data(text.utf8), numberOfRolls: 4, resourceName: "key.txt")
        )
    }

    func testWordListValidationRejectsDuplicateKey() {
        let text = validWordListText(numberOfRolls: 4) + "\n1111 duplicate"
        XCTAssertThrowsError(
            try WordListLoader.validate(data: Data(text.utf8), numberOfRolls: 4, resourceName: "duplicate.txt")
        )
    }

    func testWordListValidationRejectsEmptyWord() {
        let text = replacingFirstRow(in: validWordListText(numberOfRolls: 4), with: "1111    ")
        XCTAssertThrowsError(
            try WordListLoader.validate(data: Data(text.utf8), numberOfRolls: 4, resourceName: "empty.txt")
        )
    }

    func testWordListValidationRejectsMissingKey() {
        let rows = validWordListText(numberOfRolls: 4).split(separator: "\n").dropLast()
        XCTAssertThrowsError(
            try WordListLoader.validate(
                data: Data(rows.joined(separator: "\n").utf8),
                numberOfRolls: 4,
                resourceName: "missing.txt"
            )
        )
    }

    func testWordListValidationRejectsUnexpectedKey() {
        let text = validWordListText(numberOfRolls: 4) + "\n7777 unexpected"
        XCTAssertThrowsError(
            try WordListLoader.validate(data: Data(text.utf8), numberOfRolls: 4, resourceName: "unexpected.txt")
        )
    }

    func testSpecialCharacterValuesAreUniqueAndBackslashIsCorrect() {
        let symbols = SpecialCharacter.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count)
        XCTAssertEqual(SpecialCharacter.backslash.symbol, "\\")
        XCTAssertEqual(SpecialCharacter.quotationMark.symbol, "\"")
        XCTAssertNotEqual(SpecialCharacter.backslash.symbol, SpecialCharacter.quotationMark.symbol)
    }

    func testPersistedWordCountIsClampedOnReadAndWrite() {
        withIsolatedDefaults { defaults in
            defaults.set(-100, forKey: "numberOfWords")
            let settings = UserSettings(defaults: defaults)
            XCTAssertEqual(settings.numberOfWords, PassphraseConstraints.numberOfWords.lowerBound)
            XCTAssertEqual(defaults.integer(forKey: "numberOfWords"), PassphraseConstraints.numberOfWords.lowerBound)

            settings.numberOfWords = 500
            XCTAssertEqual(settings.numberOfWords, PassphraseConstraints.numberOfWords.upperBound)
            XCTAssertEqual(defaults.integer(forKey: "numberOfWords"), PassphraseConstraints.numberOfWords.upperBound)

            settings.numberOfWords = 12
            XCTAssertEqual(settings.numberOfWords, 12)
        }
    }

    func testPersistedIdentifierAndSeparatorFallbacksPreserveKnownValues() {
        withIsolatedDefaults { defaults in
            defaults.set("not-a-list", forKey: "wordListIdentifier")
            defaults.set("/", forKey: "wordSeparator")
            var settings = UserSettings(defaults: defaults)
            XCTAssertEqual(settings.defaultIdentifier, .english)
            XCTAssertEqual(settings.wordSeparator, UserSettings.defaultWordSeparator)

            for separator in UserSettings.validWordSeparators {
                defaults.set(separator, forKey: "wordSeparator")
                settings = UserSettings(defaults: defaults)
                XCTAssertEqual(settings.wordSeparator, separator)
            }
        }
    }

    func testPersistedSpecialCharactersAreFilteredAndDeduplicatedInOrder() {
        withIsolatedDefaults { defaults in
            let persisted = ["!", "!", "x", "\\", "\"", "?", "\\"].joined()
            defaults.set(persisted, forKey: "validSpecialCharacters")
            let settings = UserSettings(defaults: defaults)
            XCTAssertEqual(settings.validSpecialCharacters, ["!", "\\", "\"", "?"].joined())

            settings.validSpecialCharacters = ""
            XCTAssertEqual(settings.validSpecialCharacters, "")
        }
    }

    func testEmptySpecialCharacterSelectionDisablesAndPersistsInsertionState() {
        withIsolatedDefaults { defaults in
            let settings = UserSettings(defaults: defaults)
            settings.validSpecialCharacters = "!"
            settings.includeRandomSpecialCharacter = true

            settings.validSpecialCharacters = ""
            XCTAssertEqual(settings.validSpecialCharacters, "")
            XCTAssertFalse(settings.includeRandomSpecialCharacter)
            XCTAssertFalse(settings.generationOptions.includeRandomSpecialCharacter)

            let reloaded = UserSettings(defaults: defaults)
            XCTAssertEqual(reloaded.validSpecialCharacters, "")
            XCTAssertFalse(reloaded.includeRandomSpecialCharacter)
        }
    }

    func testInvalidPersistedEmptySpecialCharacterStateIsNormalized() {
        withIsolatedDefaults { defaults in
            defaults.set("", forKey: "validSpecialCharacters")
            defaults.set(true, forKey: "includeRandomSpecialCharacter")

            let settings = UserSettings(defaults: defaults)
            XCTAssertFalse(settings.includeRandomSpecialCharacter)
            XCTAssertFalse(defaults.bool(forKey: "includeRandomSpecialCharacter"))

            settings.includeRandomSpecialCharacter = true
            XCTAssertFalse(settings.includeRandomSpecialCharacter)
        }
    }

    func testSettingsRoundTripIntoCanonicalGenerationOptions() {
        withIsolatedDefaults { defaults in
            let settings = UserSettings(defaults: defaults)
            settings.defaultIdentifier = .french
            settings.numberOfWords = 12
            settings.capitalizeWords = true
            settings.includeRandomNumber = true
            settings.includeRandomSpecialCharacter = true
            settings.validSpecialCharacters = "!?"
            settings.wordSeparator = "."

            XCTAssertEqual(
                settings.generationOptions,
                PassphraseGenerationOptions(
                    wordListIdentifier: .french,
                    numberOfWords: 12,
                    capitalizeWords: true,
                    includeRandomNumber: true,
                    includeRandomSpecialCharacter: true,
                    validSpecialCharacters: "!?",
                    wordSeparator: "."
                )
            )

            let reloaded = UserSettings(defaults: defaults)
            XCTAssertEqual(reloaded.generationOptions, settings.generationOptions)
        }
    }

    func testLegacyHistoryKeysAreDeletedDuringSettingsInitialization() {
        withIsolatedDefaults { defaults in
            defaults.set([["content": "secret"]], forKey: "savedItems")
            defaults.set(true, forKey: "shouldSaveItems")
            _ = UserSettings(defaults: defaults)
            XCTAssertNil(defaults.object(forKey: "savedItems"))
            XCTAssertNil(defaults.object(forKey: "shouldSaveItems"))
        }
    }

    func testGenerationSucceedsAtMinimumAndMaximumSupportedLengths() throws {
        let wordList = try WordListLoader.load(identifier: .english, bundle: appBundle)
        let engine = PassphraseGeneratorEngine()
        for count in [PassphraseConstraints.numberOfWords.lowerBound, PassphraseConstraints.numberOfWords.upperBound] {
            let options = options(numberOfWords: count)
            let passphrase = engine.generate(
                options: options,
                wordList: wordList,
                randomSource: LowerBoundRandomIntegerSource()
            )
            XCTAssertEqual(passphrase.split(separator: " ").count, count)
        }
    }

    func testGenerationCoversCapitalizationNumberSpecialCharacterAndSeparator() throws {
        let wordList = try WordListLoader.load(identifier: .english, bundle: appBundle)
        let options = PassphraseGenerationOptions(
            wordListIdentifier: .english,
            numberOfWords: 3,
            capitalizeWords: true,
            includeRandomNumber: true,
            includeRandomSpecialCharacter: true,
            validSpecialCharacters: "~!",
            wordSeparator: "-"
        )
        let result = PassphraseGeneratorEngine().generate(
            options: options,
            wordList: wordList,
            randomSource: LowerBoundRandomIntegerSource()
        )
        let words = result.split(separator: "-")
        XCTAssertEqual(words.count, 3)
        XCTAssertTrue(words[0].hasSuffix("0~"))
        XCTAssertTrue(words.allSatisfy { $0.first?.isUppercase == true })
    }

    func testGenerationSkipsSpecialInsertionWhenSelectionIsEmpty() throws {
        let wordList = try WordListLoader.load(identifier: .english, bundle: appBundle)
        var options = options(numberOfWords: 3)
        options = PassphraseGenerationOptions(
            wordListIdentifier: options.wordListIdentifier,
            numberOfWords: options.numberOfWords,
            capitalizeWords: false,
            includeRandomNumber: false,
            includeRandomSpecialCharacter: true,
            validSpecialCharacters: "",
            wordSeparator: " "
        )
        let result = PassphraseGeneratorEngine().generate(
            options: options,
            wordList: wordList,
            randomSource: LowerBoundRandomIntegerSource()
        )
        XCTAssertEqual(result.split(separator: " ").count, 3)
    }

    func testFirstGraphemeCapitalizationPreservesWordRemainder() {
        XCTAssertEqual("word".uppercasingFirstGrapheme(), "Word")
        XCTAssertEqual("iPhone".uppercasingFirstGrapheme(), "IPhone")
        XCTAssertEqual("don't-stop".uppercasingFirstGrapheme(), "Don't-stop")
        XCTAssertEqual("élan".uppercasingFirstGrapheme(), "Élan")
        XCTAssertEqual("".uppercasingFirstGrapheme(), "")
    }

    func testObservableGeneratorPublishesGeneratedPassphrase() {
        let generator = PassphraseGenerator(bundle: appBundle, randomSource: LowerBoundRandomIntegerSource())
        generator.generate(options: options(numberOfWords: 3))
        XCTAssertFalse(generator.passphrase.isEmpty)
    }

    func testReviewRequesterPreservesThresholdAndDatePolicy() {
        withIsolatedDefaults { defaults in
            let now = Date(timeIntervalSince1970: 10_000_000)
            defaults.set(2, forKey: "appLaunchCount")
            defaults.set(3, forKey: "passphraseCopyCount")
            defaults.set(Date.distantPast, forKey: "lastDateRequested")
            let requester = InAppReviewRequester(defaults: defaults, currentDate: { now })
            var requestCount = 0
            requester.recordAppLaunch { requestCount += 1 }
            XCTAssertEqual(requestCount, 1)
            XCTAssertEqual(defaults.object(forKey: "lastDateRequested") as? Date, now)

            requester.recordAppLaunch { requestCount += 1 }
            XCTAssertEqual(requestCount, 1, "The 30-day interval should suppress a second request")
        }
    }

    func testReviewRequesterRecordsCopiesWithoutRequestingImmediately() {
        withIsolatedDefaults { defaults in
            let requester = InAppReviewRequester(defaults: defaults)
            requester.recordPassphraseCopied()
            requester.recordPassphraseCopied()
            requester.recordPassphraseCopied()
            XCTAssertEqual(defaults.integer(forKey: "passphraseCopyCount"), 3)
            XCTAssertNil(defaults.object(forKey: "lastDateRequested"))
        }
    }

    func testReviewRequesterRequiresBothUsageThresholds() {
        withIsolatedDefaults { defaults in
            defaults.set(1, forKey: "appLaunchCount")
            defaults.set(3, forKey: "passphraseCopyCount")
            let requester = InAppReviewRequester(defaults: defaults)
            var requestCount = 0
            requester.recordAppLaunch { requestCount += 1 }
            XCTAssertEqual(requestCount, 0)

            defaults.set(2, forKey: "appLaunchCount")
            defaults.set(2, forKey: "passphraseCopyCount")
            requester.recordAppLaunch { requestCount += 1 }
            XCTAssertEqual(requestCount, 0)
        }
    }

    func testCopyActionCopiesGeneratedPassphraseAndOnlyRecordsActualCopies() {
        withIsolatedDefaults { defaults in
            let generator = PassphraseGenerator(bundle: appBundle, randomSource: LowerBoundRandomIntegerSource())
            generator.generate(options: options(numberOfWords: 3))
            let clipboard = RecordingPassphraseClipboardWriter()
            let copyAction = PassphraseCopyAction(
                clipboardWriter: clipboard,
                reviewRequester: InAppReviewRequester(defaults: defaults)
            )

            XCTAssertTrue(copyAction.copy(generator.passphrase))
            XCTAssertEqual(clipboard.copiedValues, [generator.passphrase])
            XCTAssertEqual(defaults.integer(forKey: "passphraseCopyCount"), 1)

            XCTAssertFalse(copyAction.copy(""))
            XCTAssertEqual(clipboard.copiedValues, [generator.passphrase])
            XCTAssertEqual(defaults.integer(forKey: "passphraseCopyCount"), 1)
        }
    }

    func testTipStoreLoadsAllProductsInPriceOrder() async {
        let fake = FakeStoreClient(productsResult: .success(Self.allTipProducts))
        let store = TipStore(client: fake, startTransactionListener: false)
        await store.loadProductsIfNeeded()
        await store.loadProductsIfNeeded()
        XCTAssertEqual(store.products.map(\.id), [DiceGenProduct.smallTip, DiceGenProduct.mediumTip, DiceGenProduct.largeTip])
        XCTAssertTrue(store.missingProductIdentifiers.isEmpty)
        XCTAssertEqual(store.loadState, .loaded)
        let productRequests = await fake.productRequests
        XCTAssertEqual(productRequests, 1)
    }

    func testTipStoreKeepsPartialProductResultsUsable() async {
        let partial = [Self.allTipProducts[1]]
        let store = TipStore(client: FakeStoreClient(productsResult: .success(partial)), startTransactionListener: false)
        await store.loadProductsIfNeeded()
        XCTAssertEqual(store.products, partial)
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(
            store.missingProductIdentifiers,
            [DiceGenProduct.mediumTip, DiceGenProduct.largeTip]
        )
    }

    func testTipStoreReportsAllProductsMissing() async {
        let store = TipStore(client: FakeStoreClient(productsResult: .success([])), startTransactionListener: false)
        await store.loadProductsIfNeeded()
        XCTAssertTrue(store.products.isEmpty)
        XCTAssertEqual(store.missingProductIdentifiers, DiceGenProduct.allIdentifiers)
        guard case .failed = store.loadState else { return XCTFail("Expected a failed load state") }
    }

    func testTipStoreReportsProductRequestFailure() async {
        let store = TipStore(client: FakeStoreClient(productsResult: .failure(.requestFailed)), startTransactionListener: false)
        await store.loadProductsIfNeeded()
        XCTAssertTrue(store.products.isEmpty)
        guard case let .failed(message) = store.loadState else { return XCTFail("Expected a failed load state") }
        XCTAssertFalse(message.isEmpty)
    }

    func testTipStoreRepresentsVerifiedPurchaseAndThankYou() async {
        let product = Self.allTipProducts[0]
        let fake = FakeStoreClient(purchaseResult: .success(.verified(productIdentifier: product.id)))
        let store = TipStore(client: fake, startTransactionListener: false)
        await store.purchase(product)
        XCTAssertEqual(store.purchaseState, .succeeded(productIdentifier: product.id))
        XCTAssertEqual(store.alert?.kind, .thankYou)
    }

    func testTipStoreRepresentsUnverifiedPurchaseAsForegroundError() async {
        let product = Self.allTipProducts[0]
        let fake = FakeStoreClient(purchaseResult: .success(.unverified(productIdentifier: product.id)))
        let store = TipStore(client: fake, startTransactionListener: false)
        await store.purchase(product)
        guard case .failed = store.purchaseState else { return XCTFail("Expected failed purchase state") }
        XCTAssertEqual(store.alert?.kind, .error)
    }

    func testTipStoreKeepsCancellationSilentAndPendingVisible() async {
        let product = Self.allTipProducts[0]
        var store = TipStore(
            client: FakeStoreClient(purchaseResult: .success(.userCancelled)),
            startTransactionListener: false
        )
        await store.purchase(product)
        XCTAssertEqual(store.purchaseState, .cancelled)
        XCTAssertNil(store.alert)

        store = TipStore(
            client: FakeStoreClient(purchaseResult: .success(.pending(productIdentifier: product.id))),
            startTransactionListener: false
        )
        await store.purchase(product)
        XCTAssertEqual(store.purchaseState, .pending(productIdentifier: product.id))
        XCTAssertNil(store.alert)
    }

    func testTipStoreRepresentsPurchaseFailure() async {
        let product = Self.allTipProducts[0]
        let store = TipStore(
            client: FakeStoreClient(purchaseResult: .failure(.purchaseFailed)),
            startTransactionListener: false
        )
        await store.purchase(product)
        guard case .failed = store.purchaseState else { return XCTFail("Expected failed purchase state") }
        XCTAssertEqual(store.alert?.kind, .error)
    }

    func testBackgroundUnverifiedUpdateIsPassive() async {
        let fake = FakeStoreClient()
        let store = TipStore(client: fake, startTransactionListener: false)
        store.startListeningForTransactions()
        let didStart = await waitUntil { await fake.listenerStarts == 1 }
        XCTAssertTrue(didStart)
        await fake.send(.unverified(productIdentifier: DiceGenProduct.smallTip))
        let didReceiveWarning = await waitUntil { store.backgroundVerificationWarning != nil }
        XCTAssertTrue(didReceiveWarning)
        XCTAssertNil(store.alert)
        await fake.finishUpdates()
    }

    func testBackgroundVerifiedUpdateOnlyThanksWhileTipJarIsVisible() async {
        let fake = FakeStoreClient()
        let store = TipStore(client: fake, startTransactionListener: false)
        store.startListeningForTransactions()
        let didStart = await waitUntil { await fake.listenerStarts == 1 }
        XCTAssertTrue(didStart)

        store.tipJarDidAppear()
        await fake.send(.verified(productIdentifier: DiceGenProduct.smallTip))
        let didShowThanks = await waitUntil { store.alert?.kind == .thankYou }
        XCTAssertTrue(didShowThanks)
        XCTAssertEqual(store.purchaseState, .idle)
        store.dismissAlert()

        store.tipJarDidDisappear()
        await fake.send(.verified(productIdentifier: DiceGenProduct.mediumTip))
        let didRecordBackgroundUpdate = await waitUntil {
            store.lastBackgroundVerifiedProductIdentifier == DiceGenProduct.mediumTip
        }
        XCTAssertTrue(didRecordBackgroundUpdate)
        XCTAssertEqual(store.purchaseState, .idle)
        XCTAssertNil(store.alert)
        await fake.finishUpdates()
    }

    func testBackgroundVerifiedUpdatesNeverOverwriteForegroundPurchaseState() async {
        let product = Self.allTipProducts[0]

        let pendingClient = FakeStoreClient(
            purchaseResult: .success(.pending(productIdentifier: product.id))
        )
        let pendingStore = TipStore(client: pendingClient, startTransactionListener: false)
        pendingStore.startListeningForTransactions()
        await pendingStore.purchase(product)
        await pendingClient.send(.verified(productIdentifier: DiceGenProduct.mediumTip))
        let pendingUpdateReceived = await waitUntil {
            pendingStore.lastBackgroundVerifiedProductIdentifier == DiceGenProduct.mediumTip
        }
        XCTAssertTrue(pendingUpdateReceived)
        XCTAssertEqual(pendingStore.purchaseState, .pending(productIdentifier: product.id))
        XCTAssertNil(pendingStore.alert)
        await pendingClient.finishUpdates()

        let purchasingClient = FakeStoreClient(
            purchaseResult: .success(.verified(productIdentifier: product.id)),
            purchaseDelay: .milliseconds(250)
        )
        let purchasingStore = TipStore(client: purchasingClient, startTransactionListener: false)
        purchasingStore.startListeningForTransactions()
        let purchaseTask = Task { await purchasingStore.purchase(product) }
        let didEnterPurchasing = await waitUntil {
            purchasingStore.purchaseState == .purchasing(productIdentifier: product.id)
        }
        XCTAssertTrue(didEnterPurchasing)
        await purchasingClient.send(.verified(productIdentifier: DiceGenProduct.mediumTip))
        let purchasingUpdateReceived = await waitUntil {
            purchasingStore.lastBackgroundVerifiedProductIdentifier == DiceGenProduct.mediumTip
        }
        XCTAssertTrue(purchasingUpdateReceived)
        XCTAssertEqual(purchasingStore.purchaseState, .purchasing(productIdentifier: product.id))
        await purchaseTask.value
        await purchasingClient.finishUpdates()

        let failedClient = FakeStoreClient(purchaseResult: .failure(.purchaseFailed))
        let failedStore = TipStore(client: failedClient, startTransactionListener: false)
        failedStore.startListeningForTransactions()
        await failedStore.purchase(product)
        let failedState = failedStore.purchaseState
        failedStore.dismissAlert()
        await failedClient.send(.verified(productIdentifier: DiceGenProduct.mediumTip))
        let failedUpdateReceived = await waitUntil {
            failedStore.lastBackgroundVerifiedProductIdentifier == DiceGenProduct.mediumTip
        }
        XCTAssertTrue(failedUpdateReceived)
        XCTAssertEqual(failedStore.purchaseState, failedState)
        XCTAssertNil(failedStore.alert)
        await failedClient.finishUpdates()
    }

    func testTipStoreRetryAndUserFacingMetadata() async {
        let fake = FakeStoreClient(productsResult: .success(Self.allTipProducts))
        let store = TipStore(client: fake, startTransactionListener: false)
        await store.retryLoadingProducts()
        XCTAssertEqual(store.loadState, .loaded)
        let productRequests = await fake.productRequests
        XCTAssertEqual(productRequests, 1)

        let alert = TipStoreAlert(kind: .error, title: "Title", message: "Message")
        store.alert = alert
        XCTAssertFalse(alert.id.isEmpty)
        store.dismissAlert()
        XCTAssertNil(store.alert)

        XCTAssertEqual(DiceGenProduct.emojiSuffix(for: DiceGenProduct.smallTip), " 🍫")
        XCTAssertEqual(DiceGenProduct.emojiSuffix(for: DiceGenProduct.mediumTip), " ☕️")
        XCTAssertEqual(DiceGenProduct.emojiSuffix(for: DiceGenProduct.largeTip), " 🍕")
        XCTAssertEqual(DiceGenProduct.emojiSuffix(for: "unknown"), "")
        XCTAssertFalse(StoreClientError.productNotLoaded("missing").localizedDescription.isEmpty)
    }

    func testTransactionListenerStartsOnlyOnceAndCancelsWithStore() async {
        let fake = FakeStoreClient()
        var store: TipStore? = TipStore(client: fake, startTransactionListener: false)
        store?.startListeningForTransactions()
        store?.startListeningForTransactions()
        let didStart = await waitUntil { await fake.listenerStarts == 1 }
        XCTAssertTrue(didStart)

        store = nil
        let didCancel = await waitUntil { await fake.listenerCancellations == 1 }
        XCTAssertTrue(didCancel)
    }

    func testNaturallyCompletedTransactionListenerDoesNotRestart() async {
        let fake = FakeStoreClient()
        let store = TipStore(client: fake, startTransactionListener: false)
        store.startListeningForTransactions()
        let didStart = await waitUntil { await fake.listenerStarts == 1 }
        XCTAssertTrue(didStart)

        await fake.finishUpdates()
        try? await Task.sleep(for: .milliseconds(20))
        store.startListeningForTransactions()
        try? await Task.sleep(for: .milliseconds(20))
        let listenerStarts = await fake.listenerStarts
        XCTAssertEqual(listenerStarts, 1)
    }

    private static let allTipProducts = [
        TipProduct(id: DiceGenProduct.largeTip, displayName: "Large", displayPrice: "$3", price: 3),
        TipProduct(id: DiceGenProduct.smallTip, displayName: "Small", displayPrice: "$1", price: 1),
        TipProduct(id: DiceGenProduct.mediumTip, displayName: "Medium", displayPrice: "$2", price: 2)
    ]

    private func options(numberOfWords: Int) -> PassphraseGenerationOptions {
        PassphraseGenerationOptions(
            wordListIdentifier: .english,
            numberOfWords: numberOfWords,
            capitalizeWords: false,
            includeRandomNumber: false,
            includeRandomSpecialCharacter: false,
            validSpecialCharacters: SpecialCharacter.allCharacters,
            wordSeparator: " "
        )
    }

    private func validWordListData(numberOfRolls: Int) -> Data {
        Data(validWordListText(numberOfRolls: numberOfRolls).utf8)
    }

    private func validWordListText(numberOfRolls: Int) -> String {
        DiceKeySpace.keys(numberOfRolls: numberOfRolls)
            .sorted()
            .map { "\($0) word\($0)" }
            .joined(separator: "\n")
    }

    private func replacingFirstRow(in text: String, with replacement: String) -> String {
        guard let newline = text.firstIndex(of: "\n") else { return replacement }
        return replacement + text[newline...]
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "DiceGenTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated UserDefaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    private func waitUntil(
        attempts: Int = 100,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

@MainActor
private final class RecordingPassphraseClipboardWriter: PassphraseClipboardWriting {
    private(set) var copiedValues: [String] = []

    func copy(_ value: String) {
        copiedValues.append(value)
    }
}

private enum TestStoreError: LocalizedError, Sendable {
    case requestFailed
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed: return "The product request failed."
        case .purchaseFailed: return "The purchase failed."
        }
    }
}

private actor FakeStoreClient: StoreClientProtocol {
    private let productsResult: Result<[TipProduct], TestStoreError>
    private let purchaseResult: Result<StorePurchaseResult, TestStoreError>
    private let purchaseDelay: Duration?
    private let updates: AsyncStream<StoreTransactionUpdate>
    private let updateContinuation: AsyncStream<StoreTransactionUpdate>.Continuation

    private(set) var listenerStarts = 0
    private(set) var listenerCancellations = 0
    private(set) var productRequests = 0

    init(
        productsResult: Result<[TipProduct], TestStoreError> = .success([]),
        purchaseResult: Result<StorePurchaseResult, TestStoreError> = .success(.userCancelled),
        purchaseDelay: Duration? = nil
    ) {
        self.productsResult = productsResult
        self.purchaseResult = purchaseResult
        self.purchaseDelay = purchaseDelay
        (updates, updateContinuation) = AsyncStream.makeStream(of: StoreTransactionUpdate.self)
    }

    func products(for identifiers: Set<String>) async throws -> [TipProduct] {
        productRequests += 1
        return try productsResult.get()
    }

    func purchase(productIdentifier: String) async throws -> StorePurchaseResult {
        if let purchaseDelay {
            try? await Task.sleep(for: purchaseDelay)
        }
        return try purchaseResult.get()
    }

    func listenForTransactions(
        _ handler: @escaping @Sendable (StoreTransactionUpdate) async -> Void
    ) async {
        listenerStarts += 1
        let continuation = updateContinuation
        await withTaskCancellationHandler {
            for await update in updates {
                guard !Task.isCancelled else { return }
                await handler(update)
            }
        } onCancel: {
            continuation.finish()
            Task { await self.recordCancellation() }
        }
    }

    func send(_ update: StoreTransactionUpdate) {
        updateContinuation.yield(update)
    }

    func finishUpdates() {
        updateContinuation.finish()
    }

    private func recordCancellation() {
        listenerCancellations += 1
    }
}
