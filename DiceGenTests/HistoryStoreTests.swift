//
//  HistoryStoreTests.swift
//  DiceGenTests
//

import Foundation
import XCTest
@testable import DiceGen

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testEmptyStoreLoadsNoEntriesAndEmptyMetadata() async throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let store = HistoryStore(rootURL: root)

        let entries = try await store.loadEntries()
        let metadata = try await store.loadMetadata()
        XCTAssertEqual(entries, [])
        XCTAssertEqual(metadata, .empty)
    }

    func testDuplicateCopyMovesEntryToFrontWithFreshTimestamp() async throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let store = HistoryStore(rootURL: root)
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        let third = Date(timeIntervalSince1970: 300)

        try await store.recordCopiedPassphrase("alpha", at: first)
        try await store.recordCopiedPassphrase("beta", at: second)
        try await store.recordCopiedPassphrase("alpha", at: third)

        let entries = try await store.loadEntries()
        XCTAssertEqual(entries.map(\.content), ["alpha", "beta"])
        XCTAssertEqual(entries.map(\.savedAt), [third, second])
    }

    func testConcurrentCopiesPreserveBothEntries() async throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let store = HistoryStore(rootURL: root)

        async let firstCopy: Void = store.recordCopiedPassphrase(
            "first",
            at: Date(timeIntervalSince1970: 100)
        )
        async let secondCopy: Void = store.recordCopiedPassphrase(
            "second",
            at: Date(timeIntervalSince1970: 200)
        )
        _ = try await (firstCopy, secondCopy)

        let entries = try await store.loadEntries()
        XCTAssertEqual(entries.map(\.content), ["second", "first"])
    }

    func testHistoryRetainsMoreThanOneHundredEntries() async throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let store = HistoryStore(rootURL: root)

        for index in 0..<150 {
            try await store.recordCopiedPassphrase("entry-\(index)", at: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        let entries = try await store.loadEntries()
        XCTAssertEqual(entries.count, 150)
    }

    func testDeleteAndClearAllRemoveEntries() async throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let store = HistoryStore(rootURL: root)

        try await store.recordCopiedPassphrase("alpha", at: Date(timeIntervalSince1970: 100))
        try await store.recordCopiedPassphrase("beta", at: Date(timeIntervalSince1970: 200))
        let entries = try await store.loadEntries()
        let alphaID = try XCTUnwrap(entries.first(where: { $0.content == "alpha" })).id
        try await store.deleteEntry(id: alphaID)

        let remaining = try await store.loadEntries()
        XCTAssertEqual(remaining.map(\.content), ["beta"])

        try await store.clearEntries()
        let cleared = try await store.loadEntries()
        XCTAssertEqual(cleared, [])
    }

    func testMetadataRoundTrips() async throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let store = HistoryStore(rootURL: root)
        var metadata = HistorySecurityMetadata.empty
        metadata.isConfigured = true
        metadata.localAuthenticationEnabled = true
        metadata.failedPINAttempts = 8
        metadata.lockoutUntil = Date(timeIntervalSince1970: 500)
        metadata.migrationNoticePending = true

        try await store.saveMetadata(metadata)

        let loaded = try await store.loadMetadata()
        XCTAssertEqual(loaded, metadata)
    }

    func testMalformedHistoryPayloadThrowsInsteadOfPartiallyDecoding() async throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let store = HistoryStore(rootURL: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("[{\"content\":\"visible\"},".utf8).write(to: store.historyFileURL)

        do {
            _ = try await store.loadEntries()
            XCTFail("Malformed history should fail closed")
        } catch {
            XCTAssertEqual(error as? HistoryStoreError, .invalidPayload)
        }
    }

    func testResetRemovesHistoryDirectory() async throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let store = HistoryStore(rootURL: root)
        try await store.recordCopiedPassphrase("alpha", at: .now)
        try await store.saveMetadata(.empty)

        try await store.resetAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testHistoryAndMetadataWritesExcludeDirectoryAndFilesFromBackup() async throws {
        let root = temporaryRoot()
        defer { removeTemporaryRoot(root) }
        let store = HistoryStore(rootURL: root)
        try await store.recordCopiedPassphrase("alpha", at: .now)
        try await store.saveMetadata(.empty)

        for url in [root, store.historyFileURL, store.securityFileURL] {
            let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            XCTAssertEqual(values.isExcludedFromBackup, true, url.path)
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DiceGenHistoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func removeTemporaryRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}
