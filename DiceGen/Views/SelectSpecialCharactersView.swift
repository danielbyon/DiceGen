//
//  SelectSpecialCharactersView.swift
//  DiceGen
//

import SwiftUI

struct SelectSpecialCharactersView: View {
    @EnvironmentObject private var userSettings: UserSettings

    private var specialCharacters: [SpecialCharacter] {
        SpecialCharacter.allCases.sorted { $0.rawValue < $1.rawValue }
    }

    private var allCharactersSelected: Bool {
        CharacterSet(charactersIn: userSettings.validSpecialCharacters)
            == CharacterSet(charactersIn: SpecialCharacter.allCharacters)
    }

    var body: some View {
        Form {
            ForEach(specialCharacters, id: \.self) { specialCharacter in
                Toggle(isOn: binding(for: specialCharacter)) {
                    Text(specialCharacter.symbol)
                }
                .animation(.default, value: userSettings.validSpecialCharacters)
            }
        }
        .navigationTitle("Special Characters")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(allCharactersSelected ? "Select None" : "Select All") {
                    userSettings.validSpecialCharacters = allCharactersSelected
                        ? ""
                        : SpecialCharacter.allCharacters
                }
            }
        }
    }

    private func binding(for specialCharacter: SpecialCharacter) -> Binding<Bool> {
        Binding(
            get: { userSettings.validSpecialCharacters.contains(specialCharacter.symbol) },
            set: { include in
                let symbol = specialCharacter.symbol
                if include {
                    if !userSettings.validSpecialCharacters.contains(symbol) {
                        userSettings.validSpecialCharacters += symbol
                    }
                } else {
                    userSettings.validSpecialCharacters = userSettings.validSpecialCharacters
                        .replacingOccurrences(of: symbol, with: "")
                }
            }
        )
    }
}

struct SelectSpecialCharactersView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SelectSpecialCharactersView()
        }
        .environmentObject(UserSettings())
    }
}
