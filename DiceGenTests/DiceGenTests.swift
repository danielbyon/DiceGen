//
//  DiceGenTests.swift
//  DiceGenTests
//
//  Created by Daniel Byon on 3/29/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import XCTest
@testable import DiceGen

class DiceGenTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testPassphraseGenerationPerformance_DefaultSettings() throws {
        let passphraseGenerator = PassphraseGenerator(
            wordListIdentifier: .english,
            numberOfWords: 5,
            capitalizeWords: false,
            includeRandomNumber: false,
            includeRandomSpecialCharacter: false,
            validSpecialCharacters: "",
            wordSeparator: " ")
        measure {
            for _ in 1...1000 {
                passphraseGenerator.generatePassphrase()
            }
        }
    }

    func testPassphraseGenerationPerformance_MinComplexity() throws {
        let passphraseGenerator = PassphraseGenerator(
            wordListIdentifier: .english,
            numberOfWords: 3,
            capitalizeWords: false,
            includeRandomNumber: false,
            includeRandomSpecialCharacter: false,
            validSpecialCharacters: "",
            wordSeparator: " ")
        measure {
            for _ in 1...1000 {
                passphraseGenerator.generatePassphrase()
            }
        }
    }

    func testPassphraseGenerationPerformance_MaxComplexity() throws {
        let passphraseGenerator = PassphraseGenerator(
            wordListIdentifier: .english,
            numberOfWords: 50,
            capitalizeWords: true,
            includeRandomNumber: true,
            includeRandomSpecialCharacter: true,
            validSpecialCharacters: SpecialCharacter.allCharacters,
            wordSeparator: " ")
        measure {
            for _ in 1...1000 {
                passphraseGenerator.generatePassphrase()
            }
        }
    }

}
