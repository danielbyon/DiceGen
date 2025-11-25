//
//  PassphraseGeneratorView.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/30/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI
import MobileCoreServices

struct PassphraseGeneratorView: View {

    @EnvironmentObject var historyStorage: HistoryStorage
    @EnvironmentObject var userSettings: UserSettings
    @ObservedObject var passphraseGenerator: PassphraseGenerator
    @State private var showingSettings = false

    private static let wordRange = 3...50

    var body: some View {
        Form {
            SecureContentInfoView(passphraseGenerator: passphraseGenerator)
            Section(header: SectionHeader("Options")) {
                Stepper(value: $userSettings.numberOfWords, in: Self.wordRange) {
                    Text("\(Int(userSettings.numberOfWords)) words")
                }
                Toggle(isOn: $userSettings.capitalizeWords) {
                    Text("Capitalize words")
                }
                Toggle(isOn: $userSettings.includeRandomNumber) {
                    Text("Include random number")
                }
                Toggle(isOn: $userSettings.includeRandomSpecialCharacter) {
                    Text("Include special character")
                }
                if userSettings.includeRandomSpecialCharacter {
                    NavigationLink(destination: SelectSpecialCharactersView()) {
                        Text("Special characters")
                    }
                }
                Picker("Word separator", selection: $userSettings.wordSeparator) {
                    Text("Space")
                        .tag(" ")
                    Text("Dot")
                        .tag(".")
                    Text("Dash")
                        .tag("-")
                }
                NavigationLink(destination: SelectWordListView(selectedIdentifier: $userSettings.defaultIdentifier)) {
                    HStack {
                        Text("Word List")
                        Spacer()
                        Text(userSettings.defaultIdentifier.title)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            if historyStorage.shouldSaveItems {
                Section {
                    NavigationLink(destination: PassphraseHistoryView()) {
                        Text("View Passphrase History")
                    }
                }
            }
        }
        .navigationBarTitle("DiceGen")
        .navigationBarItems(leading: Button(action: {
            self.showingSettings.toggle()
        }, label: {
            Image(systemName: "info.circle")
                .padding([.trailing, .vertical])
        }).sheet(isPresented: $showingSettings) {
            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .environmentObject(HistoryStorage())
            .environmentObject(UserSettings())
        })
    }

}

struct PassphraseGeneratorView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PassphraseGeneratorView(passphraseGenerator: .default)
                .environmentObject(HistoryStorage())
                .environmentObject(UserSettings())
        }
    }
}
