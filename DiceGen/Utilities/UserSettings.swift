//
//  UserSettings.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/30/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation
import Combine

final class UserSettings: ObservableObject {

    let objectWillChange = PassthroughSubject<Void, Never>()

    var defaultIdentifier: WordListIdentifier {
        get { WordListIdentifier(rawValue: storedDefaultIdentifier) ?? .english }
        set { storedDefaultIdentifier = newValue.rawValue }
    }

    @UserDefault(key: "wordListIdentifier", defaultValue: WordListIdentifier.english.rawValue)
    private var storedDefaultIdentifier: String {
        willSet {
            objectWillChange.send()
        }
    }

    @UserDefault(key: "numberOfWords", defaultValue: 5)
    var numberOfWords: Int {
        willSet {
            objectWillChange.send()
        }
    }

    @UserDefault(key: "capitalizeWords", defaultValue: false)
    var capitalizeWords: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @UserDefault(key: "includeRandomNumber", defaultValue: false)
    var includeRandomNumber: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @UserDefault(key: "includeRandomSpecialCharacter", defaultValue: false)
    var includeRandomSpecialCharacter: Bool {
        willSet {
            objectWillChange.send()
        }
    }

    @UserDefault(key: "validSpecialCharacters", defaultValue: SpecialCharacter.allCharacters)
    var validSpecialCharacters: String {
        willSet {
            objectWillChange.send()
        }
    }

    @UserDefault(key: "wordSeparator", defaultValue: " ")
    var wordSeparator: String {
        willSet {
            objectWillChange.send()
        }
    }

}
