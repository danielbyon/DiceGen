//
//  PassphraseGeneratorView.swift
//  DiceGen
//

import SwiftUI

struct PassphraseGeneratorView: View {
    @EnvironmentObject private var passphraseGenerator: PassphraseGenerator
    @EnvironmentObject private var userSettings: UserSettings
    @State private var showingSettings = false

    let reviewRequester: InAppReviewRequester

    var body: some View {
        Form {
            SecureContentInfoView(reviewRequester: reviewRequester)
            Section(header: SectionHeader("Options")) {
                Stepper(value: $userSettings.numberOfWords, in: PassphraseConstraints.numberOfWords) {
                    Text("\(userSettings.numberOfWords) words")
                }
                Toggle("Capitalize words", isOn: $userSettings.capitalizeWords)
                Toggle("Include random number", isOn: $userSettings.includeRandomNumber)
                Toggle("Include special character", isOn: $userSettings.includeRandomSpecialCharacter)
                if userSettings.includeRandomSpecialCharacter {
                    NavigationLink("Special characters") {
                        SelectSpecialCharactersView()
                    }
                }
                Picker("Word separator", selection: $userSettings.wordSeparator) {
                    Text("Space").tag(" ")
                    Text("Dot").tag(".")
                    Text("Dash").tag("-")
                }
                NavigationLink {
                    SelectWordListView(selectedIdentifier: $userSettings.defaultIdentifier)
                } label: {
                    HStack {
                        Text("Word List")
                        Spacer()
                        Text(userSettings.defaultIdentifier.title)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .navigationTitle("DiceGen")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .task(id: userSettings.generationOptions) {
            passphraseGenerator.generate(options: userSettings.generationOptions)
        }
    }
}

struct PassphraseGeneratorView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PassphraseGeneratorView(reviewRequester: InAppReviewRequester())
        }
        .environmentObject(UserSettings())
        .environmentObject(PassphraseGenerator())
        .environmentObject(TipStore(client: StoreKitClient(), startTransactionListener: false))
    }
}
