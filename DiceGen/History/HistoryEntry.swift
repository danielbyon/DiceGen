//
//  HistoryEntry.swift
//  DiceGen
//

import Foundation

/// A copied passphrase and the time at which it was most recently copied.
struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let content: String
    let savedAt: Date
}

/// Non-secret configuration and PIN failure state for the history vault.
struct HistorySecurityMetadata: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var isConfigured = false
    var localAuthenticationEnabled = false
    var failedPINAttempts = 0
    var lockoutUntil: Date?
    var migrationNoticePending = false

    static let empty = HistorySecurityMetadata()
}

/// Errors raised when persisted history data cannot be trusted or used.
enum HistoryStoreError: Error, Equatable {
    case invalidPayload
    case unsupportedMetadataVersion(Int)
}

/// Persistence boundary for plaintext history and its non-secret security metadata.
protocol HistoryPersisting: Sendable {
    func loadEntries() async throws -> [HistoryEntry]
    func hasEntries() async throws -> Bool
    func replaceEntries(_ entries: [HistoryEntry]) async throws
    func recordCopiedPassphrase(_ content: String, at date: Date) async throws
    func deleteEntry(id: UUID) async throws
    func clearEntries() async throws
    func loadMetadata() async throws -> HistorySecurityMetadata
    func saveMetadata(_ metadata: HistorySecurityMetadata) async throws
    func resetAll() async throws
}
