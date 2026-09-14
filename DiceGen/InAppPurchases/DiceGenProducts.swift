//
//  DiceGenProducts.swift
//  DiceGen
//

import Foundation

enum DiceGenProduct {
    static let smallTip = "com.danielbyon.DiceGen.iap.tipjarsmall"
    static let mediumTip = "com.danielbyon.DiceGen.iap.tipjarmedium"
    static let largeTip = "com.danielbyon.DiceGen.iap.tipjarlarge"

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
