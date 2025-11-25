//
//  SavedItem.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/31/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation

struct SavedItem {

    let content: String
    let savedAt: Date

    init(content: String, savedAt: Date) {
        self.content = content
        self.savedAt = savedAt
    }

    init(content: String) {
        self.init(content: content, savedAt: Date())
    }

    init?(dictionary: NSDictionary) {
        guard let content = dictionary.value(forKey: "content") as? String,
            let savedAt = dictionary.value(forKey: "savedAt") as? Date else { return nil }
        self.init(content: content, savedAt: savedAt)
    }

    func toDictionary() -> NSDictionary {
        [
            "content": content,
            "savedAt": savedAt
            ] as NSDictionary
    }

}

extension SavedItem: Identifiable {

    var id: String { "\(content) \(savedAt)" }

}
