//
//  SpecialCharacter.swift
//  DiceGen
//
//  Created by Daniel Byon on 4/5/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation

// ~ ! # $ % ^ & * ( ) - = + [ ] \ { } : ; " ' < > ? /
enum SpecialCharacter: String, CaseIterable {

    case tilde
    case exclamationPoint
    case at
    case poundSign
    case currency
    case percent
    case caret
    case ampersand
    case asterisk
    case openParentheses
    case closeParentheses
    case minusSign
    case equalSign
    case plusSign
    case openSquareBracket
    case closeSquareBracket
    case backslash
    case openBrace
    case closeBrace
    case colon
    case semicolon
    case quotationMark
    case apostrophe
    case openArrowBracket
    case closeArrowBracket
    case questionMark
    case slash

    var symbol: String {
        switch self {
        case .tilde: return "~"
        case .exclamationPoint: return "!"
        case .at: return "@"
        case .poundSign: return "#"
        case .currency: return "$"
        case .percent: return "%"
        case .caret: return "^"
        case .ampersand: return "&"
        case .asterisk: return "*"
        case .openParentheses: return "("
        case .closeParentheses: return ")"
        case .minusSign: return "-"
        case .equalSign: return "="
        case .plusSign: return "+"
        case .openSquareBracket: return "["
        case .closeSquareBracket: return "]"
        case .backslash: return "\""
        case .openBrace: return "{"
        case .closeBrace: return "}"
        case .colon: return ":"
        case .semicolon: return ";"
        case .quotationMark: return "\""
        case .apostrophe: return "'"
        case .openArrowBracket: return "<"
        case .closeArrowBracket: return ">"
        case .questionMark: return "?"
        case .slash: return "/"
        }
    }

    static var allCharacters: String { validCharacters(from: allCases) }

    static func validCharacters(from specialCharacters: [SpecialCharacter]) -> String {
        specialCharacters.map { $0.symbol }.joined(separator: "")
    }

}
