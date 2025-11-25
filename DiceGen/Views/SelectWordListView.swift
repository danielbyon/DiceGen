//
//  SelectWordListView.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/31/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import SwiftUI

struct SelectWordListView: View {

    @Environment(\.presentationMode) var presentation
    @Binding var selectedIdentifier: WordListIdentifier

    var body: some View {
        List {
            Section(header: SectionHeader("English")) {
                ForEach(WordListIdentifier.allEnglish, id: \.self) { identifier in
                    WordListRow(selectedIdentifier: self.$selectedIdentifier, identifier: identifier)
                }
            }
            Section(header: SectionHeader("Other languages")) {
                ForEach(WordListIdentifier.allOtherLanguages, id: \.self) { identifier in
                    WordListRow(selectedIdentifier: self.$selectedIdentifier, identifier: identifier)
                }
            }
        }
        .listStyle(GroupedListStyle())
        .navigationBarTitle(Text("Select Word List"))
    }

}

struct SelectWordListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SelectWordListView(selectedIdentifier: .constant(.english))
        }
    }
}

struct WordListRow: View {

    @Environment(\.presentationMode) var presentation
    @Binding var selectedIdentifier: WordListIdentifier

    let identifier: WordListIdentifier

    var body: some View {
        Button(action: {
            self.selectedIdentifier = self.identifier
            self.presentation.wrappedValue.dismiss()
        }) {
            HStack {
                Text(identifier.title)
                if identifier == self.selectedIdentifier {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
            .foregroundColor(.primary)
        }
    }
}
