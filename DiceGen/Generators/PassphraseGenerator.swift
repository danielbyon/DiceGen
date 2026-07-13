//
//  PassphraseGenerator.swift
//  DiceGen
//

import Combine
import Foundation

enum PassphraseConstraints {
    static let numberOfWords = 3...50
}

struct PassphraseGenerationOptions: Equatable, Hashable, Sendable {
    let wordListIdentifier: WordListIdentifier
    let numberOfWords: Int
    let capitalizeWords: Bool
    let includeRandomNumber: Bool
    let includeRandomSpecialCharacter: Bool
    let validSpecialCharacters: String
    let wordSeparator: String
}

protocol RandomIntegerSource: Sendable {
    func integer(in range: ClosedRange<Int>) -> Int
}

struct SystemRandomIntegerSource: RandomIntegerSource {
    func integer(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range)
    }
}

struct LowerBoundRandomIntegerSource: RandomIntegerSource {
    func integer(in range: ClosedRange<Int>) -> Int {
        range.lowerBound
    }
}

extension String {
    /// Uppercases only the first grapheme so capitalization never rewrites the remainder of a word-list entry.
    func uppercasingFirstGrapheme() -> String {
        guard let first else { return self }
        return first.uppercased() + String(dropFirst())
    }
}

struct PassphraseGeneratorEngine {
    func generate(
        options: PassphraseGenerationOptions,
        wordList: WordList,
        randomSource: any RandomIntegerSource
    ) -> String {
        precondition(PassphraseConstraints.numberOfWords.contains(options.numberOfWords))
        precondition(options.wordListIdentifier == wordList.identifier)

        let numberInsertion = options.includeRandomNumber
            ? (randomSource.integer(in: 0...(options.numberOfWords - 1)), randomSource.integer(in: 0...9))
            : nil

        let specialCharacters = Array(options.validSpecialCharacters)
        let specialInsertion: (Int, Character)?
        if options.includeRandomSpecialCharacter, !specialCharacters.isEmpty {
            specialInsertion = (
                randomSource.integer(in: 0...(options.numberOfWords - 1)),
                specialCharacters[randomSource.integer(in: 0...(specialCharacters.count - 1))]
            )
        } else {
            specialInsertion = nil
        }

        return (0..<options.numberOfWords).map { index in
            var key = 0
            for _ in 0..<wordList.numberOfRollsPerWord {
                key = key * 10 + randomSource.integer(in: 1...6)
            }

            var word = wordList.word(for: key)
            if options.capitalizeWords {
                word = word.uppercasingFirstGrapheme()
            }
            if let numberInsertion, numberInsertion.0 == index {
                word += String(numberInsertion.1)
            }
            if let specialInsertion, specialInsertion.0 == index {
                word.append(specialInsertion.1)
            }
            return word
        }
        .joined(separator: options.wordSeparator)
    }
}

@MainActor
final class PassphraseGenerator: ObservableObject {
    @Published private(set) var passphrase = ""

    private let bundle: Bundle
    private let engine: PassphraseGeneratorEngine
    private let randomSource: any RandomIntegerSource
    private var loadedWordList: WordList?

    init(
        bundle: Bundle = .main,
        engine: PassphraseGeneratorEngine = PassphraseGeneratorEngine(),
        randomSource: any RandomIntegerSource = SystemRandomIntegerSource()
    ) {
        self.bundle = bundle
        self.engine = engine
        self.randomSource = randomSource
    }

    func generate(options: PassphraseGenerationOptions) {
        let wordList: WordList
        if let loadedWordList, loadedWordList.identifier == options.wordListIdentifier {
            wordList = loadedWordList
        } else {
            do {
                wordList = try WordListLoader.load(identifier: options.wordListIdentifier, bundle: bundle)
            } catch {
                preconditionFailure("Invalid bundled word-list resource: \(error)")
            }
            loadedWordList = wordList
        }

        passphrase = engine.generate(
            options: options,
            wordList: wordList,
            randomSource: randomSource
        )
    }
}
