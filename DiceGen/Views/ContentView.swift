//
//  ContentView.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/29/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var userSettings: UserSettings

    var body: some View {
        NavigationView {
            PassphraseGeneratorView(
                passphraseGenerator: PassphraseGenerator(
                    wordListIdentifier: userSettings.defaultIdentifier,
                    numberOfWords: userSettings.numberOfWords,
                    capitalizeWords: userSettings.capitalizeWords,
                    includeRandomNumber: userSettings.includeRandomNumber,
                    includeRandomSpecialCharacter: userSettings.includeRandomSpecialCharacter,
                    validSpecialCharacters: userSettings.validSpecialCharacters,
                    wordSeparator: userSettings.wordSeparator))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(HistoryStorage())
            .environmentObject(UserSettings())
    }
}
