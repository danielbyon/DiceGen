//
//  PassphraseHistoryView.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/31/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI

struct PassphraseHistoryView: View {

    @Environment(\.presentationMode) var presentation
    @EnvironmentObject var historyStorage: HistoryStorage
    @EnvironmentObject var userSettings: UserSettings

    private var prompt: String {
        #if targetEnvironment(macCatalyst)
        return "Right click to copy.\n\nGenerated passphrases that are copied to the clipboard will be saved here. This can be disabled in settings."
        #else
        return "Tap and hold to copy.\n\nGenerated passphrases that are copied to the clipboard will be saved here. This can be disabled in settings."
        #endif
    }

    var body: some View {
        List {
            Section(footer: Text(prompt).minimumScaleFactor(0.9)) {
                ForEach(historyStorage.savedItems) { item in
                    VStack(alignment: .leading) {
                        Text(item.content)
                            .padding(.bottom, 4.0)
                        Text(dateFormatter.string(from: item.savedAt))
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                    .contextMenu(menuItems: {
                        Button(action: {
                            UIPasteboard.general.string = item.content
                            InAppReviewManager.recordPassphraseCopied()
                        }) {
                            HStack {
                                Text("Copy")
                                Image(systemName: "doc.on.doc")
                            }
                        }
                    })
                }
            }
        }
        .listStyle(GroupedListStyle())
        .navigationBarTitle("Passphrase History")
        .navigationBarItems(trailing: Button(action: {
            self.historyStorage.savedItems = []
            self.presentation.wrappedValue.dismiss()
        }, label: {
            Text("Clear")
        })
            .disabled(historyStorage.isEmpty))
    }

}

struct PassphraseHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        PassphraseHistoryView()
            .environmentObject(HistoryStorage())
            .environmentObject(UserSettings())
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()
