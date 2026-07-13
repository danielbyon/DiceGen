//
//  UserSettings.swift
//  DiceGen
//

import Combine
import Foundation

@MainActor
final class UserSettings: ObservableObject {
    private enum Key {
        static let wordListIdentifier = "wordListIdentifier"
        static let numberOfWords = "numberOfWords"
        static let capitalizeWords = "capitalizeWords"
        static let includeRandomNumber = "includeRandomNumber"
        static let includeRandomSpecialCharacter = "includeRandomSpecialCharacter"
        static let validSpecialCharacters = "validSpecialCharacters"
        static let wordSeparator = "wordSeparator"

        // These keys are intentionally retained only to delete plaintext history from earlier releases.
        static let legacySavedItems = "savedItems"
        static let legacyShouldSaveItems = "shouldSaveItems"
    }

    static let defaultNumberOfWords = 5
    static let defaultWordSeparator = " "
    static let validWordSeparators: Set<String> = [" ", ".", "-"]

    private let defaults: UserDefaults

    @Published private var defaultIdentifierStorage: WordListIdentifier
    @Published private var numberOfWordsStorage: Int
    @Published private var capitalizeWordsStorage: Bool
    @Published private var includeRandomNumberStorage: Bool
    @Published private var includeRandomSpecialCharacterStorage: Bool
    @Published private var validSpecialCharactersStorage: String
    @Published private var wordSeparatorStorage: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.removeObject(forKey: Key.legacySavedItems)
        defaults.removeObject(forKey: Key.legacyShouldSaveItems)

        let storedIdentifier = defaults.object(forKey: Key.wordListIdentifier) as? String
        defaultIdentifierStorage = storedIdentifier.flatMap(WordListIdentifier.init(rawValue:)) ?? .english

        let storedWordCount = defaults.object(forKey: Key.numberOfWords) as? Int
        numberOfWordsStorage = Self.clampNumberOfWords(storedWordCount ?? Self.defaultNumberOfWords)

        capitalizeWordsStorage = defaults.object(forKey: Key.capitalizeWords) as? Bool ?? false
        includeRandomNumberStorage = defaults.object(forKey: Key.includeRandomNumber) as? Bool ?? false
        includeRandomSpecialCharacterStorage = defaults.object(forKey: Key.includeRandomSpecialCharacter) as? Bool ?? false

        if let storedCharacters = defaults.object(forKey: Key.validSpecialCharacters) as? String {
            validSpecialCharactersStorage = Self.normalizeSpecialCharacters(storedCharacters)
        } else {
            validSpecialCharactersStorage = SpecialCharacter.allCharacters
        }
        let storedSeparator = defaults.object(forKey: Key.wordSeparator) as? String
        wordSeparatorStorage = Self.normalizeWordSeparator(storedSeparator)
        if validSpecialCharactersStorage.isEmpty {
            includeRandomSpecialCharacterStorage = false
        }

        persistNormalizedValues()
    }

    var defaultIdentifier: WordListIdentifier {
        get { defaultIdentifierStorage }
        set {
            defaultIdentifierStorage = newValue
            defaults.set(newValue.rawValue, forKey: Key.wordListIdentifier)
        }
    }

    var numberOfWords: Int {
        get { numberOfWordsStorage }
        set {
            let value = Self.clampNumberOfWords(newValue)
            numberOfWordsStorage = value
            defaults.set(value, forKey: Key.numberOfWords)
        }
    }

    var capitalizeWords: Bool {
        get { capitalizeWordsStorage }
        set {
            capitalizeWordsStorage = newValue
            defaults.set(newValue, forKey: Key.capitalizeWords)
        }
    }

    var includeRandomNumber: Bool {
        get { includeRandomNumberStorage }
        set {
            includeRandomNumberStorage = newValue
            defaults.set(newValue, forKey: Key.includeRandomNumber)
        }
    }

    var includeRandomSpecialCharacter: Bool {
        get { includeRandomSpecialCharacterStorage }
        set {
            let value = newValue && !validSpecialCharactersStorage.isEmpty
            includeRandomSpecialCharacterStorage = value
            defaults.set(value, forKey: Key.includeRandomSpecialCharacter)
        }
    }

    var validSpecialCharacters: String {
        get { validSpecialCharactersStorage }
        set {
            let value = Self.normalizeSpecialCharacters(newValue)
            validSpecialCharactersStorage = value
            defaults.set(value, forKey: Key.validSpecialCharacters)
            if value.isEmpty {
                includeRandomSpecialCharacterStorage = false
                defaults.set(false, forKey: Key.includeRandomSpecialCharacter)
            }
        }
    }

    var wordSeparator: String {
        get { wordSeparatorStorage }
        set {
            let value = Self.normalizeWordSeparator(newValue)
            wordSeparatorStorage = value
            defaults.set(value, forKey: Key.wordSeparator)
        }
    }

    var generationOptions: PassphraseGenerationOptions {
        PassphraseGenerationOptions(
            wordListIdentifier: defaultIdentifier,
            numberOfWords: numberOfWords,
            capitalizeWords: capitalizeWords,
            includeRandomNumber: includeRandomNumber,
            includeRandomSpecialCharacter: includeRandomSpecialCharacter,
            validSpecialCharacters: validSpecialCharacters,
            wordSeparator: wordSeparator
        )
    }

    static func clampNumberOfWords(_ value: Int) -> Int {
        min(max(value, PassphraseConstraints.numberOfWords.lowerBound), PassphraseConstraints.numberOfWords.upperBound)
    }

    static func normalizeWordSeparator(_ value: String?) -> String {
        guard let value, validWordSeparators.contains(value) else {
            return defaultWordSeparator
        }
        return value
    }

    static func normalizeSpecialCharacters(_ value: String) -> String {
        let supported = Set(SpecialCharacter.allCases.map(\.symbol))
        var seen = Set<String>()
        return value.reduce(into: "") { result, character in
            let symbol = String(character)
            guard supported.contains(symbol), seen.insert(symbol).inserted else { return }
            result.append(character)
        }
    }

    private func persistNormalizedValues() {
        defaults.set(defaultIdentifierStorage.rawValue, forKey: Key.wordListIdentifier)
        defaults.set(numberOfWordsStorage, forKey: Key.numberOfWords)
        defaults.set(capitalizeWordsStorage, forKey: Key.capitalizeWords)
        defaults.set(includeRandomNumberStorage, forKey: Key.includeRandomNumber)
        defaults.set(includeRandomSpecialCharacterStorage, forKey: Key.includeRandomSpecialCharacter)
        defaults.set(validSpecialCharactersStorage, forKey: Key.validSpecialCharacters)
        defaults.set(wordSeparatorStorage, forKey: Key.wordSeparator)
    }
}
