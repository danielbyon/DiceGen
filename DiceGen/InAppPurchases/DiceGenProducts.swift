//
//  DiceGenProducts.swift
//  DiceGen
//

import Foundation

enum DiceGenProduct {
    static let smallTip = "smallTip"
    static let mediumTip = "mediumTip"
    static let largeTip = "largeTip"

    static let allIdentifiers: Set<String> = [smallTip, mediumTip, largeTip]

    static func emojiSuffix(for productIdentifier: String) -> String {
        switch productIdentifier {
        case smallTip: return " 🍫"
        case mediumTip: return " ☕️"
        case largeTip: return " 🍕"
        default: return ""
        }
    }
}
