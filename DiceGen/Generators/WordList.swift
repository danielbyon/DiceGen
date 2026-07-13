//
//  WordList.swift
//  DiceGen
//

import Foundation

enum WordListValidationError: Error, CustomStringConvertible {
    case resourceCount(name: String, count: Int)
    case unreadableResource(name: String, reason: String)
    case invalidUTF8(resource: String)
    case malformedRow(resource: String, line: Int, reason: String)
    case invalidKey(resource: String, line: Int, value: String)
    case duplicateKey(resource: String, line: Int, key: Int)
    case unexpectedKeys(resource: String, keys: [Int])
    case missingKeys(resource: String, keys: [Int])
    case emptyWord(resource: String, line: Int, key: Int)

    var description: String {
        switch self {
        case let .resourceCount(name, count):
            return "Expected exactly one bundled WordLists/\(name).txt resource, found \(count)."
        case let .unreadableResource(name, reason):
            return "Could not read bundled word list \(name): \(reason)"
        case let .invalidUTF8(resource):
            return "Bundled word list \(resource) is not valid UTF-8."
        case let .malformedRow(resource, line, reason):
            return "Bundled word list \(resource) has a malformed row at line \(line): \(reason)"
        case let .invalidKey(resource, line, value):
            return "Bundled word list \(resource) has invalid key '\(value)' at line \(line)."
        case let .duplicateKey(resource, line, key):
            return "Bundled word list \(resource) repeats key \(key) at line \(line)."
        case let .unexpectedKeys(resource, keys):
            return "Bundled word list \(resource) has unexpected keys: \(Self.summarize(keys))."
        case let .missingKeys(resource, keys):
            return "Bundled word list \(resource) is missing keys: \(Self.summarize(keys))."
        case let .emptyWord(resource, line, key):
            return "Bundled word list \(resource) has an empty word for key \(key) at line \(line)."
        }
    }

    private static func summarize(_ keys: [Int]) -> String {
        let prefix = keys.prefix(10).map(String.init).joined(separator: ", ")
        return keys.count > 10 ? "\(prefix), … (\(keys.count) total)" : prefix
    }
}

struct DiceKeySpace {
    /// Diceware keys contain one digit per roll, and every digit must be in 1...6.
    static func keys(numberOfRolls: Int) -> Set<Int> {
        precondition(numberOfRolls > 0)
        var prefixes = [0]
        for _ in 0..<numberOfRolls {
            prefixes = prefixes.flatMap { prefix in
                (1...6).map { prefix * 10 + $0 }
            }
        }
        return Set(prefixes)
    }
}

struct WordList {
    let identifier: WordListIdentifier
    let numberOfRollsPerWord: Int

    /// Construction is restricted to the validating loader so every generated dice key is present.
    private let words: [Int: String]

    fileprivate init(identifier: WordListIdentifier, words: [Int: String]) {
        self.identifier = identifier
        self.numberOfRollsPerWord = identifier.numberOfRollsPerWord
        self.words = words
    }

    var keys: Set<Int> { Set(words.keys) }
    var count: Int { words.count }

    func word(for key: Int) -> String {
        guard let word = words[key] else {
            preconditionFailure("Validated word list \(identifier.rawValue) does not contain generated key \(key).")
        }
        return word
    }
}

struct WordListTextResource {
    let filename: String
    let data: Data
}

struct WordListResourceClassification: Equatable {
    let referencedSelectableResources: [String]
    let unreferencedDicewareResources: [String]
    let otherTextResources: [String]
}

enum WordListResourceClassifier {
    static func classify(
        resources: [WordListTextResource],
        selectableIdentifiers: [WordListIdentifier] = WordListIdentifier.allCases
    ) throws -> WordListResourceClassification {
        var referencedResources: [String] = []
        let referencedBaseNames = Set(selectableIdentifiers.map(\.filename))

        for identifier in selectableIdentifiers {
            let matches = resources.filter {
                URL(fileURLWithPath: $0.filename).deletingPathExtension().lastPathComponent == identifier.filename
            }
            guard matches.count == 1, let match = matches.first else {
                throw WordListValidationError.resourceCount(name: identifier.filename, count: matches.count)
            }
            _ = try WordListLoader.validate(
                data: match.data,
                numberOfRolls: identifier.numberOfRollsPerWord,
                resourceName: match.filename
            )
            referencedResources.append(match.filename)
        }

        var unreferencedDicewareResources: [String] = []
        var otherTextResources: [String] = []
        for resource in resources {
            let baseName = URL(fileURLWithPath: resource.filename).deletingPathExtension().lastPathComponent
            guard !referencedBaseNames.contains(baseName) else { continue }

            let isDicewareResource = [4, 5].contains { numberOfRolls in
                (try? WordListLoader.validate(
                    data: resource.data,
                    numberOfRolls: numberOfRolls,
                    resourceName: resource.filename
                )) != nil
            }
            if isDicewareResource {
                unreferencedDicewareResources.append(resource.filename)
            } else {
                otherTextResources.append(resource.filename)
            }
        }

        return WordListResourceClassification(
            referencedSelectableResources: referencedResources.sorted(),
            unreferencedDicewareResources: unreferencedDicewareResources.sorted(),
            otherTextResources: otherTextResources.sorted()
        )
    }

    static func classify(bundle: Bundle = .main) throws -> WordListResourceClassification {
        let resourceURLs = bundle.urls(forResourcesWithExtension: "txt", subdirectory: "WordLists") ?? []
        let resources = try resourceURLs.map { resourceURL in
            do {
                return WordListTextResource(
                    filename: resourceURL.lastPathComponent,
                    data: try Data(contentsOf: resourceURL)
                )
            } catch {
                throw WordListValidationError.unreadableResource(
                    name: resourceURL.lastPathComponent,
                    reason: error.localizedDescription
                )
            }
        }
        return try classify(resources: resources)
    }
}

enum WordListLoader {
    static func resourceURLs(for identifier: WordListIdentifier, bundle: Bundle = .main) -> [URL] {
        let expectedFilename = identifier.filename
        return (bundle.urls(forResourcesWithExtension: "txt", subdirectory: "WordLists") ?? [])
            .filter { $0.deletingPathExtension().lastPathComponent == expectedFilename }
    }

    static func load(identifier: WordListIdentifier, bundle: Bundle = .main) throws -> WordList {
        let matches = resourceURLs(for: identifier, bundle: bundle)
        guard matches.count == 1, let resourceURL = matches.first else {
            throw WordListValidationError.resourceCount(name: identifier.filename, count: matches.count)
        }

        let data: Data
        do {
            data = try Data(contentsOf: resourceURL)
        } catch {
            throw WordListValidationError.unreadableResource(
                name: resourceURL.lastPathComponent,
                reason: error.localizedDescription
            )
        }

        let words = try validate(
            data: data,
            numberOfRolls: identifier.numberOfRollsPerWord,
            resourceName: resourceURL.lastPathComponent
        )
        return WordList(identifier: identifier, words: words)
    }

    static func validate(
        data: Data,
        numberOfRolls: Int,
        resourceName: String
    ) throws -> [Int: String] {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw WordListValidationError.invalidUTF8(resource: resourceName)
        }

        var rows = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        rows = rows.map { row in
            row.last == "\r" ? String(row.dropLast()) : row
        }
        while rows.last?.allSatisfy({ $0 == " " || $0 == "\t" }) == true {
            rows.removeLast()
        }

        var words: [Int: String] = [:]
        for (offset, row) in rows.enumerated() {
            let lineNumber = offset + 1
            guard !row.allSatisfy({ $0 == " " || $0 == "\t" }) else {
                throw WordListValidationError.malformedRow(
                    resource: resourceName,
                    line: lineNumber,
                    reason: "blank rows are only allowed at the end of the resource"
                )
            }
            guard let separator = row.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                throw WordListValidationError.malformedRow(
                    resource: resourceName,
                    line: lineNumber,
                    reason: "expected a dice key followed by whitespace and a word"
                )
            }

            let keyText = String(row[..<separator])
            guard let key = Int(keyText) else {
                throw WordListValidationError.invalidKey(
                    resource: resourceName,
                    line: lineNumber,
                    value: keyText
                )
            }

            var wordStart = separator
            while wordStart < row.endIndex, row[wordStart] == " " || row[wordStart] == "\t" {
                wordStart = row.index(after: wordStart)
            }
            let word = String(row[wordStart...])
            guard !word.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw WordListValidationError.emptyWord(resource: resourceName, line: lineNumber, key: key)
            }
            guard words[key] == nil else {
                throw WordListValidationError.duplicateKey(
                    resource: resourceName,
                    line: lineNumber,
                    key: key
                )
            }
            words[key] = word
        }

        let expectedKeys = DiceKeySpace.keys(numberOfRolls: numberOfRolls)
        let actualKeys = Set(words.keys)
        let unexpectedKeys = actualKeys.subtracting(expectedKeys).sorted()
        guard unexpectedKeys.isEmpty else {
            throw WordListValidationError.unexpectedKeys(resource: resourceName, keys: unexpectedKeys)
        }
        let missingKeys = expectedKeys.subtracting(actualKeys).sorted()
        guard missingKeys.isEmpty else {
            throw WordListValidationError.missingKeys(resource: resourceName, keys: missingKeys)
        }

        return words
    }
}
