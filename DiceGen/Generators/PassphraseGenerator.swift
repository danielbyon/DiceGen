//
//  PassphraseGenerator.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/29/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation

// MARK: - PassphraseGenerator
final class PassphraseGenerator: ObservableObject {

    @Published private(set) var passphrase = ""

    private let wordGenerator: WordGenerator
    private let numberOfWords: Int
    private let capitalizeWords: Bool
    private let includeRandomNumber: Bool
    private let includeRandomSpecialCharacter: Bool
    private let validSpecialCharacters: String
    private let wordSeparator: String

    init(
        wordListIdentifier: WordListIdentifier,
        numberOfWords: Int,
        capitalizeWords: Bool,
        includeRandomNumber: Bool,
        includeRandomSpecialCharacter: Bool,
        validSpecialCharacters: String,
        wordSeparator: String) {
        self.wordGenerator = WordGenerator(identifier: wordListIdentifier)
        self.numberOfWords = numberOfWords
        self.capitalizeWords = capitalizeWords
        self.includeRandomNumber = includeRandomNumber
        self.includeRandomSpecialCharacter = includeRandomSpecialCharacter
        self.validSpecialCharacters = validSpecialCharacters
        self.wordSeparator = wordSeparator
        generatePassphrase()
    }

    func generatePassphrase() {
        let randomNumber = generateRandomNumber()
        let randomSpecialCharacter = generateRandomSpecialCharacter()

        passphrase = (0..<numberOfWords)
            .map { i in
                var word = wordGenerator.generateWord()
                if capitalizeWords {
                    word = word.capitalized
                }
                if let randomNumber = randomNumber, randomNumber.index == i {
                    word += "\(randomNumber.number)"
                }
                if let randomSpecialCharacter = randomSpecialCharacter, randomSpecialCharacter.index == i {
                    word += randomSpecialCharacter.character
                }
                return word
            }
            .joined(separator: wordSeparator)
        debugPrint("Generated passphrase: \(passphrase)")
    }

    private func generateRandomNumber() -> (index: Int, number: Int)? {
        guard includeRandomNumber else { return nil}
        let index = Int.random(in: 0..<numberOfWords)
        let number = Int.random(in: 0...9)
        return (index, number)
    }

    private func generateRandomSpecialCharacter() -> (index: Int, character: String)? {
        guard includeRandomSpecialCharacter, !validSpecialCharacters.isEmpty else { return nil }
        let index = Int.random(in: 0..<numberOfWords)
        guard let character = validSpecialCharacters.randomElement() else { return nil }
        return (index, String(character))
    }

}

// MARK: - Debug
extension PassphraseGenerator {

    static let `default` = PassphraseGenerator(
        wordListIdentifier: .english,
        numberOfWords: 5,
        capitalizeWords: false,
        includeRandomNumber: false,
        includeRandomSpecialCharacter: false,
        validSpecialCharacters: "", wordSeparator: " ")

}

// MARK: - WordGenerator
private struct WordGenerator {

    private let wordList: WordList

    init(identifier: WordListIdentifier) {
        self.wordList = WordList(identifier: identifier)
    }

    func generateWord() -> String {
        var key = 0
        for _ in 0..<wordList.numberOfRollsPerWord {
            key *= 10
            key += Int.random(in: 1...6)
        }
        return wordList.words[key]!
    }

}
