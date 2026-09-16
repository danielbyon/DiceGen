//
//  HistoryMigration.swift
//  DiceGen
//

import Foundation

/// Moves legacy plaintext history into the protected-history store exactly once.
@MainActor
protocol HistoryMigrating {
    func migrateIfNeeded() async throws
    func discardLegacyHistory()
}

/// Performs the one-way migration while retaining legacy defaults until persistence succeeds.
@MainActor
struct HistoryMigration: HistoryMigrating {
    static let savedItemsKey = "savedItems"
    static let shouldSaveItemsKey = "shouldSaveItems"

    let defaults: UserDefaults
    let store: any HistoryPersisting

    func migrateIfNeeded() async throws {
        let hasItems = defaults.object(forKey: Self.savedItemsKey) != nil
        let hasEnabled = defaults.object(forKey: Self.shouldSaveItemsKey) != nil
        guard hasItems || hasEnabled else { return }

        let oldEnabled = defaults.object(forKey: Self.shouldSaveItemsKey) as? Bool ?? false
        let legacy = validatedLegacyEntries()
        let existing = try await store.loadEntries()
        let merged = deduplicatedNewestFirst(existing + legacy)

        if !merged.isEmpty || !existing.isEmpty {
            try await store.replaceEntries(merged)
        }

        var metadata = try await store.loadMetadata()
        if oldEnabled || !legacy.isEmpty {
            metadata.migrationNoticePending = true
            try await store.saveMetadata(metadata)
        }

        discardLegacyHistory()
    }

    /// Removes legacy history after an explicit destructive reset has been chosen.
    func discardLegacyHistory() {
        defaults.removeObject(forKey: Self.savedItemsKey)
        defaults.removeObject(forKey: Self.shouldSaveItemsKey)
    }

    private func validatedLegacyEntries() -> [HistoryEntry] {
        guard let rawItems = defaults.object(forKey: Self.savedItemsKey) as? [Any] else {
            return []
        }

        return rawItems.compactMap { rawItem in
            guard let dictionary = rawItem as? [String: Any],
                  let content = dictionary["content"] as? String,
                  !content.isEmpty,
                  let savedAt = dictionary["savedAt"] as? Date else {
                return nil
            }
            return HistoryEntry(id: UUID(), content: content, savedAt: savedAt)
        }
    }

    private func deduplicatedNewestFirst(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        let sorted = entries.sorted {
            if $0.savedAt == $1.savedAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.savedAt > $1.savedAt
        }

        var seenContent = Set<String>()
        return sorted.filter { seenContent.insert($0.content).inserted }
    }
}
