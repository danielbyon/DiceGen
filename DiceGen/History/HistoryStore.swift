//
//  HistoryStore.swift
//  DiceGen
//

import Foundation

/// Actor-isolated JSON storage for local, backup-excluded passphrase history.
actor HistoryStore: HistoryPersisting {
    nonisolated let rootURL: URL
    nonisolated let historyFileURL: URL
    nonisolated let securityFileURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL, encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.rootURL = rootURL
        historyFileURL = rootURL.appendingPathComponent("history.json", isDirectory: false)
        securityFileURL = rootURL.appendingPathComponent("security.json", isDirectory: false)
        self.encoder = encoder
        self.decoder = decoder
    }

    /// Returns the production storage directory under Application Support.
    static func defaultRootURL(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleDirectory = bundleIdentifier ?? "DiceGen"
        return applicationSupport
            .appendingPathComponent(bundleDirectory, isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    func loadEntries() async throws -> [HistoryEntry] {
        try loadEntriesFromDisk()
    }

    func hasEntries() async throws -> Bool {
        try !loadEntriesFromDisk().isEmpty
    }

    func replaceEntries(_ entries: [HistoryEntry]) async throws {
        try replaceEntriesOnDisk(entries)
    }

    func recordCopiedPassphrase(_ content: String, at date: Date) async throws {
        guard !content.isEmpty else { throw HistoryStoreError.invalidPayload }

        // Keep the read-modify-write sequence synchronous within the actor so
        // concurrent copy operations cannot overwrite one another's entries.
        var entries = try loadEntriesFromDisk()
        entries.removeAll { $0.content == content }
        entries.insert(HistoryEntry(id: UUID(), content: content, savedAt: date), at: 0)
        try replaceEntriesOnDisk(entries)
    }

    func deleteEntry(id: UUID) async throws {
        var entries = try loadEntriesFromDisk()
        entries.removeAll { $0.id == id }
        try replaceEntriesOnDisk(entries)
    }

    func clearEntries() async throws {
        try replaceEntriesOnDisk([])
    }

    private func loadEntriesFromDisk() throws -> [HistoryEntry] {
        guard let data = try dataIfPresent(at: historyFileURL) else { return [] }

        do {
            let entries = try decoder.decode([HistoryEntry].self, from: data)
            try validate(entries)
            return sortNewestFirst(entries)
        } catch let error as HistoryStoreError {
            throw error
        } catch {
            throw HistoryStoreError.invalidPayload
        }
    }

    private func replaceEntriesOnDisk(_ entries: [HistoryEntry]) throws {
        try validate(entries)
        try write(sortNewestFirst(entries), to: historyFileURL)
    }

    func loadMetadata() async throws -> HistorySecurityMetadata {
        guard let data = try dataIfPresent(at: securityFileURL) else { return .empty }

        do {
            let metadata = try decoder.decode(HistorySecurityMetadata.self, from: data)
            guard metadata.schemaVersion == HistorySecurityMetadata.currentSchemaVersion else {
                throw HistoryStoreError.unsupportedMetadataVersion(metadata.schemaVersion)
            }
            guard metadata.failedPINAttempts >= 0 else {
                throw HistoryStoreError.invalidPayload
            }
            return metadata
        } catch let error as HistoryStoreError {
            throw error
        } catch {
            throw HistoryStoreError.invalidPayload
        }
    }

    func saveMetadata(_ metadata: HistorySecurityMetadata) async throws {
        guard metadata.schemaVersion == HistorySecurityMetadata.currentSchemaVersion,
              metadata.failedPINAttempts >= 0 else {
            throw HistoryStoreError.invalidPayload
        }
        try write(metadata, to: securityFileURL)
    }

    func resetAll() async throws {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        try FileManager.default.removeItem(at: rootURL)
    }

    private func dataIfPresent(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func validate(_ entries: [HistoryEntry]) throws {
        var identifiers = Set<UUID>()
        var contents = Set<String>()
        for entry in entries {
            guard !entry.content.isEmpty,
                  identifiers.insert(entry.id).inserted,
                  contents.insert(entry.content).inserted else {
                throw HistoryStoreError.invalidPayload
            }
        }
    }

    private func sortNewestFirst(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.sorted {
            if $0.savedAt == $1.savedAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.savedAt > $1.savedAt
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try excludeFromBackup(rootURL)
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        try excludeFromBackup(url)
        try excludeFromBackup(rootURL)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
