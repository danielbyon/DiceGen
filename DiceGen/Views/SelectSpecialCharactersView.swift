//
//  SelectSpecialCharactersView.swift
//  DiceGen
//
//  Created by Daniel Byon on 4/4/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI

struct SelectSpecialCharactersView: View {

    @EnvironmentObject var userSettings: UserSettings

    private var specialCharacters: [SpecialCharacter] {
        SpecialCharacter.allCases.sorted { $0.rawValue < $1.rawValue }
    }

    private var allCharactersSelected: Bool {
        CharacterSet(charactersIn: userSettings.validSpecialCharacters) == CharacterSet(charactersIn: SpecialCharacter.allCharacters)
    }

    var body: some View {
        Form {
            ForEach(0..<specialCharacters.count, id: \.self) { i in
                Toggle(isOn: Binding<Bool>(get: {
                    self.userSettings.validSpecialCharacters.contains(self.specialCharacters[i].symbol)
                }, set: { include in
                    let currentCharacters = self.userSettings.validSpecialCharacters
                    if include {
                        if !currentCharacters.contains(self.specialCharacters[i].symbol) {
                            self.userSettings.validSpecialCharacters = currentCharacters + self.specialCharacters[i].symbol
                        }
                    } else {
                        if currentCharacters.contains(self.specialCharacters[i].symbol) {
                            self.userSettings.validSpecialCharacters = currentCharacters.replacingOccurrences(of: self.specialCharacters[i].symbol, with: "")
                        }
                    }
                })) {
                    Text(self.specialCharacters[i].symbol)
                }
                .animation(.default)
            }
        }
        .navigationBarTitle("Special Characters")
        .navigationBarItems(trailing: Button(action: {
            if self.allCharactersSelected {
                self.userSettings.validSpecialCharacters = ""
            } else {
                self.userSettings.validSpecialCharacters = SpecialCharacter.allCharacters
            }
        }) {
            Text(allCharactersSelected ? "Select None" : "Select All")
                .padding([.leading, .vertical])
        })
    }

}

struct SelectSpecialCharactersView_Previews: PreviewProvider {
    static var previews: some View {
        SelectSpecialCharactersView()
            .environmentObject(UserSettings())
    }
}
