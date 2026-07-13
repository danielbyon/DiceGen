//
//  SelectWordListView.swift
//  DiceGen
//

import SwiftUI

struct SelectWordListView: View {
    @Binding var selectedIdentifier: WordListIdentifier

    var body: some View {
        List {
            Section(header: SectionHeader("English")) {
                ForEach(WordListIdentifier.allEnglish, id: \.self) { identifier in
                    WordListRow(selectedIdentifier: $selectedIdentifier, identifier: identifier)
                }
            }
            Section(header: SectionHeader("Other languages")) {
                ForEach(WordListIdentifier.allOtherLanguages, id: \.self) { identifier in
                    WordListRow(selectedIdentifier: $selectedIdentifier, identifier: identifier)
                }
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Select Word List")
    }
}

struct WordListRow: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIdentifier: WordListIdentifier
    let identifier: WordListIdentifier

    var body: some View {
        Button {
            selectedIdentifier = identifier
            dismiss()
        } label: {
            HStack {
                Text(identifier.title)
                if identifier == selectedIdentifier {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
            .foregroundStyle(.primary)
        }
    }
}

struct SelectWordListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SelectWordListView(selectedIdentifier: .constant(.english))
        }
    }
}
