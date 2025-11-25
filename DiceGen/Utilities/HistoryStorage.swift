//
//  HistoryStorage.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/31/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation
import Combine

class HistoryStorage: ObservableObject {

    let objectWillChange = PassthroughSubject<Void, Never>()

    var savedItems: [SavedItem] {
        get { storedSavedItems.compactMap { SavedItem(dictionary: $0) } }
        set { storedSavedItems = newValue.map { $0.toDictionary() } }
    }

    @UserDefault(key: "savedItems", defaultValue: [])
    private var storedSavedItems: [NSDictionary] {
        willSet {
            objectWillChange.send()
        }
    }

    @UserDefault(key: "shouldSaveItems", defaultValue: true)
    var shouldSaveItems: Bool {
        willSet {
            if !newValue { // Clear history when disabling
                storedSavedItems.removeAll()
            }
            objectWillChange.send()
        }
    }

    var isEmpty: Bool { storedSavedItems.isEmpty }

    func saveItem(_ item: String) {
        guard shouldSaveItems,
            !savedItems.contains(where: { $0.content == item }) else { return }
        savedItems.insert(SavedItem(content: item), at: 0)
    }

}
