//
//  HistoryMigrationTests.swift
//  DiceGenTests
//

import Foundation
import XCTest
@testable import DiceGen

@MainActor
final class HistoryMigrationTests: XCTestCase {
    func testMalformedLegacyEntriesAreIgnoredAndLegacyKeysAreRemovedAfterMigration() async throws {
        let defaults = isolatedDefaults()
        defaults.set([
            ["content": "valid", "savedAt": Date(timeIntervalSince1970: 100)],
            ["content": "", "savedAt": Date(timeIntervalSince1970: 200)],
            ["content": "missing-date"],
            ["content": 42, "savedAt": Date(timeIntervalSince1970: 300)],
            "not-a-dictionary"
        ], forKey: HistoryMigration.savedItemsKey)
        defaults.set("not-a-bool", forKey: HistoryMigration.shouldSaveItemsKey)
        let store = MigrationStoreSpy()

        try await HistoryMigration(defaults: defaults, store: store).migrateIfNeeded()
        let snapshot = await store.snapshot()

        XCTAssertEqual(snapshot.entries.map(\.content), ["valid"])
        XCTAssertTrue(snapshot.metadata.migrationNoticePending)
        XCTAssertNil(defaults.object(forKey: HistoryMigration.savedItemsKey))
        XCTAssertNil(defaults.object(forKey: HistoryMigration.shouldSaveItemsKey))
    }

    func testMigrationRetainsNewestOccurrenceOfDuplicateContent() async throws {
        let defaults = isolatedDefaults()
        defaults.set([
            ["content": "duplicate", "savedAt": Date(timeIntervalSince1970: 100)],
            ["content": "duplicate", "savedAt": Date(timeIntervalSince1970: 200)],
            ["content": "other", "savedAt": Date(timeIntervalSince1970: 150)]
        ], forKey: HistoryMigration.savedItemsKey)
        let store = MigrationStoreSpy()

        try await HistoryMigration(defaults: defaults, store: store).migrateIfNeeded()
        let entries = await store.entriesSnapshot()

        XCTAssertEqual(entries.map(\.content), ["duplicate", "other"])
        XCTAssertEqual(entries[0].savedAt, Date(timeIntervalSince1970: 200))
    }

    func testMigrationIsIdempotentWhenStoreAlreadyContainsImportedContent() async throws {
        let defaults = isolatedDefaults()
        let importedDate = Date(timeIntervalSince1970: 100)
        defaults.set([["content": "already-imported", "savedAt": importedDate]], forKey: HistoryMigration.savedItemsKey)
        let store = MigrationStoreSpy()

        try await HistoryMigration(defaults: defaults, store: store).migrateIfNeeded()

        defaults.set([["content": "already-imported", "savedAt": importedDate]], forKey: HistoryMigration.savedItemsKey)
        try await HistoryMigration(defaults: defaults, store: store).migrateIfNeeded()

        let entries = await store.entriesSnapshot()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].content, "already-imported")
    }

    func testPreviouslyEnabledHistoryWithNoEntriesStillSetsMigrationNotice() async throws {
        let defaults = isolatedDefaults()
        defaults.set([], forKey: HistoryMigration.savedItemsKey)
        defaults.set(true, forKey: HistoryMigration.shouldSaveItemsKey)
        let store = MigrationStoreSpy()

        try await HistoryMigration(defaults: defaults, store: store).migrateIfNeeded()

        let metadata = await store.metadataSnapshot()
        let replaceEntriesCallCount = await store.replaceEntriesCallCount()
        XCTAssertTrue(metadata.migrationNoticePending)
        XCTAssertEqual(replaceEntriesCallCount, 0)
        XCTAssertNil(defaults.object(forKey: HistoryMigration.savedItemsKey))
        XCTAssertNil(defaults.object(forKey: HistoryMigration.shouldSaveItemsKey))
    }

    func testNewStoreWriteFailurePreservesBothLegacyKeys() async {
        let defaults = isolatedDefaults()
        defaults.set([["content": "must-survive", "savedAt": Date(timeIntervalSince1970: 100)]], forKey: HistoryMigration.savedItemsKey)
        defaults.set(true, forKey: HistoryMigration.shouldSaveItemsKey)
        let store = MigrationStoreSpy(replaceEntriesError: .writeFailed)

        do {
            try await HistoryMigration(defaults: defaults, store: store).migrateIfNeeded()
            XCTFail("A failed history write must abort migration")
        } catch let error as MigrationStoreError {
            XCTAssertEqual(error, .writeFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNotNil(defaults.object(forKey: HistoryMigration.savedItemsKey))
        XCTAssertNotNil(defaults.object(forKey: HistoryMigration.shouldSaveItemsKey))
    }

    func testMetadataWriteFailureAlsoPreservesBothLegacyKeys() async {
        let defaults = isolatedDefaults()
        defaults.set([], forKey: HistoryMigration.savedItemsKey)
        defaults.set(true, forKey: HistoryMigration.shouldSaveItemsKey)
        let store = MigrationStoreSpy(saveMetadataError: .writeFailed)

        do {
            try await HistoryMigration(defaults: defaults, store: store).migrateIfNeeded()
            XCTFail("A failed metadata write must abort migration")
        } catch let error as MigrationStoreError {
            XCTAssertEqual(error, .writeFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNotNil(defaults.object(forKey: HistoryMigration.savedItemsKey))
        XCTAssertNotNil(defaults.object(forKey: HistoryMigration.shouldSaveItemsKey))
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "DiceGenTests.HistoryMigration.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}

private actor MigrationStoreSpy: HistoryPersisting {
    private var entries: [HistoryEntry]
    private var metadata: HistorySecurityMetadata
    private let replaceEntriesError: MigrationStoreError?
    private let saveMetadataError: MigrationStoreError?
    private var replaceEntriesCalls = 0

    init(
        entries: [HistoryEntry] = [],
        metadata: HistorySecurityMetadata = .empty,
        replaceEntriesError: MigrationStoreError? = nil,
        saveMetadataError: MigrationStoreError? = nil
    ) {
        self.entries = entries
        self.metadata = metadata
        self.replaceEntriesError = replaceEntriesError
        self.saveMetadataError = saveMetadataError
    }

    func loadEntries() async throws -> [HistoryEntry] { entries }

    func hasEntries() async throws -> Bool { !entries.isEmpty }

    func replaceEntries(_ entries: [HistoryEntry]) async throws {
        replaceEntriesCalls += 1
        if let replaceEntriesError { throw replaceEntriesError }
        self.entries = entries
    }

    func recordCopiedPassphrase(_ content: String, at date: Date) async throws {
        entries.append(HistoryEntry(id: UUID(), content: content, savedAt: date))
    }

    func deleteEntry(id: UUID) async throws {
        entries.removeAll { $0.id == id }
    }

    func clearEntries() async throws {
        entries.removeAll()
    }

    func loadMetadata() async throws -> HistorySecurityMetadata { metadata }

    func saveMetadata(_ metadata: HistorySecurityMetadata) async throws {
        if let saveMetadataError { throw saveMetadataError }
        self.metadata = metadata
    }

    func resetAll() async throws {
        entries.removeAll()
        metadata = .empty
    }

    func snapshot() -> (entries: [HistoryEntry], metadata: HistorySecurityMetadata) {
        (entries, metadata)
    }

    func entriesSnapshot() -> [HistoryEntry] { entries }

    func metadataSnapshot() -> HistorySecurityMetadata { metadata }

    func replaceEntriesCallCount() -> Int { replaceEntriesCalls }
}

private enum MigrationStoreError: Error, Equatable, Sendable {
    case writeFailed
}
