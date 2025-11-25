//
//  WordListIdentifier.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/30/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation

enum WordListIdentifier: String, CaseIterable {

    case catalan
    case chinesePinyin
    case chineseWubi
    case czech
    case danish
    case dutch
    case effLong
    case effShort
    case effShort2
    case english
    case englishBeale
    case englishCombined
    case englishImproved
    case esperanto
    case finnish
    case french
    case german
    case hungarian
    case italian
    case japanese
    case latin
    case maori
    case norwegian
    case portuguese
    case romanian
    case slovak
    case spanish
    case swedish

}

extension WordListIdentifier: Comparable {

    static func < (lhs: WordListIdentifier, rhs: WordListIdentifier) -> Bool {
        lhs.title < rhs.title
    }

}

extension WordListIdentifier: Equatable {

    static func == (lhs: WordListIdentifier, rhs: WordListIdentifier) -> Bool {
        lhs.title == rhs.title
    }

}

extension WordListIdentifier {

    var filename: String { rawValue }

    var title: String {
        switch self {
        case .catalan,
             .czech,
             .danish,
             .dutch,
             .english,
             .esperanto,
             .finnish,
             .french,
             .german,
             .hungarian,
             .italian,
             .japanese,
             .latin,
             .maori,
             .norwegian,
             .portuguese,
             .romanian,
             .slovak,
             .spanish,
             .swedish:
            return rawValue.capitalized
        case .chinesePinyin:
            return "Chinese Pinyin"
        case .chineseWubi:
            return "Chinese Wubi"
        case .effLong:
            return "EFF Long Words"
        case .effShort:
            return "EFF Short Words"
        case .effShort2:
            return "EFF Short Words (Unique 3-letter prefixes)"
        case .englishBeale:
            return "English Beale version"
        case .englishCombined:
            return "English Combined version"
        case .englishImproved:
            return "English Improved version"
        }
    }

    var numberOfRollsPerWord: Int {
        switch self {
        case .effShort,
            .effShort2:
            return 4
        default:
            return 5
        }
    }

    static var allEnglish: [WordListIdentifier] {
        allCases.filter { $0.isEnglish }.sorted()
    }

    static var allOtherLanguages: [WordListIdentifier] {
        allCases.filter { !$0.isEnglish }.sorted()
    }

    var isEnglish: Bool {
        switch self {
        case .effLong,
             .effShort,
             .effShort2,
             .english,
             .englishBeale,
             .englishCombined,
             .englishImproved:
            return true
        default:
            return false
        }
    }

}
