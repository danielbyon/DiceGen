//
//  WordList.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/30/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation

struct WordList {

    let identifier: WordListIdentifier
    let numberOfRollsPerWord: Int
    let words: [Int: String]

    private static let separator = " "

    private static var cache: [WordListIdentifier: [Int: String]] = [:]

    init(identifier: WordListIdentifier) {
        self.identifier = identifier
        self.numberOfRollsPerWord = identifier.numberOfRollsPerWord

        if let existingWords = Self.cache[identifier] {
            self.words = existingWords
        } else {
            guard let fileURL = Bundle.main.url(forResource: identifier.filename, withExtension: "txt", subdirectory: "WordLists"),
                let file = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    fatalError()
            }
            var words: [Int: String] = [:]
            let lines = file.components(separatedBy: .newlines)
            for line in lines {
                let components = line.components(separatedBy: Self.separator)
                assert(components.count >= 2)
                guard let key = Int(components[0]) else {
                    fatalError()
                }
                let word = components.dropFirst().joined(separator: Self.separator)
                words[key] = word
            }
            self.words = words

            Self.cache[identifier] = words
        }
    }

}
