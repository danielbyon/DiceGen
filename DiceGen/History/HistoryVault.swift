//
//  HistoryVault.swift
//  DiceGen
//

import Combine
import Foundation

/// The published authorization state of the protected history feature.
enum HistoryVaultState: Equatable, Sendable {
    case initializing
    case disabled
    case setupRequired
    case locked
    case unlocked
    case failed(HistoryVaultFailure)
}

/// Fail-closed categories for history storage and credential failures.
enum HistoryVaultFailure: Equatable, Sendable {
    case storage
    case credential
    case inconsistentSecurityState
}

/// The result of an explicit DiceGen PIN operation.
enum HistoryPINResult: Equatable, Sendable {
    case success
    case incorrect
    case locked(until: Date)
    case failed
}

/// The scene phases that affect protected history authorization and privacy.
enum HistoryScenePhase: Equatable, Sendable {
    case active
    case inactive
    case background
}

/// Coordinates protected history persistence, authentication, lockout, and privacy state.
@MainActor
final class HistoryVault: ObservableObject {
    @Published private(set) var state: HistoryVaultState = .initializing
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var lockoutUntil: Date?
    /// Indicates that a lifecycle interruption invalidated system authentication and requires explicit PIN entry.
    @Published private(set) var systemAuthenticationRequiresPIN = false

    private let store: any HistoryPersisting
    private let credentials: any PINCredentialStoring
    private let authenticator: any HistoryAuthenticating
    private let migration: any HistoryMigrating
    private let now: @Sendable () -> Date

    @Published private var metadata: HistorySecurityMetadata = .empty
    @Published private(set) var sceneIsActive = false
    private var sessionGeneration: UInt = 0
    private var resetGeneration: UInt = 0
    private var systemAuthenticationInFlight = false
    private var systemAuthenticationGeneration: UInt = 0
    private var systemAuthenticationActivationWaiter: CheckedContinuation<Void, Never>?

    init(
        store: any HistoryPersisting,
        credentials: any PINCredentialStoring,
        authenticator: any HistoryAuthenticating,
        migration: any HistoryMigrating,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.credentials = credentials
        self.authenticator = authenticator
        self.migration = migration
        self.now = now
    }

    /// Builds an isolated preview vault so previews never touch production defaults or Keychain data.
    static func preview() -> HistoryVault {
        let identifier = UUID().uuidString
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiceGen-HistoryPreview-\(identifier)", isDirectory: true)
        let store = HistoryStore(rootURL: rootURL)
        let defaults = UserDefaults(suiteName: "DiceGen.HistoryPreview.\(identifier)")!
        let credentials = KeychainPINCredentialStore(service: "DiceGen.HistoryPreview.\(identifier)")
        let migration = HistoryMigration(defaults: defaults, store: store)
        return HistoryVault(
            store: store,
            credentials: credentials,
            authenticator: LocalHistoryAuthenticator(),
            migration: migration
        )
    }

    var isConfigured: Bool { metadata.isConfigured }

    var localAuthenticationEnabled: Bool { metadata.localAuthenticationEnabled }

    var migrationNoticePending: Bool { metadata.migrationNoticePending }

    /// Loads non-secret state without ever publishing stored plaintext before authorization.
    func initialize() async {
        sessionGeneration &+= 1
        systemAuthenticationGeneration &+= 1
        resumeSystemAuthenticationActivationWaiter()
        entries.removeAll()
        lockoutUntil = nil
        systemAuthenticationRequiresPIN = false
        state = .initializing

        do {
            try await migration.migrateIfNeeded()
        } catch {
            fail(.storage)
            return
        }

        let loadedMetadata: HistorySecurityMetadata
        do {
            loadedMetadata = try await store.loadMetadata()
        } catch {
            fail(.storage)
            return
        }

        let hasCredential: Bool
        do {
            hasCredential = try await credentials.hasCredential()
        } catch {
            fail(.credential)
            return
        }

        let hasEntries: Bool
        do {
            hasEntries = try await store.hasEntries()
        } catch {
            fail(.storage)
            return
        }

        metadata = loadedMetadata
        lockoutUntil = loadedMetadata.lockoutUntil

        if loadedMetadata.isConfigured != hasCredential {
            fail(.inconsistentSecurityState)
            return
        }

        if !loadedMetadata.isConfigured {
            guard !loadedMetadata.localAuthenticationEnabled,
                  loadedMetadata.failedPINAttempts == 0,
                  loadedMetadata.lockoutUntil == nil else {
                fail(.inconsistentSecurityState)
                return
            }
            state = hasEntries ? .setupRequired : .disabled
        } else {
            state = .locked
        }
    }

    /// Treats the legacy Boolean lifecycle call as a full background transition.
    func setSceneActive(_ active: Bool) {
        setScenePhase(active ? .active : .background)
    }

    /// Locks immediately outside the active scene and preserves only in-flight
    /// system authentication across the transient inactive phase.
    func setScenePhase(_ phase: HistoryScenePhase) {
        sceneIsActive = phase == .active
        guard phase != .active else {
            resumeSystemAuthenticationActivationWaiter()
            return
        }

        entries.removeAll()
        sessionGeneration &+= 1
        if metadata.isConfigured, !isFailed {
            state = .locked
        }

        guard phase == .background else { return }

        systemAuthenticationGeneration &+= 1
        if systemAuthenticationInFlight {
            systemAuthenticationRequiresPIN = true
        }
        resumeSystemAuthenticationActivationWaiter()
    }

    /// Creates the local PIN credential and commits configured history security metadata.
    func configureHistory(pin: String) async -> Bool {
        guard sceneIsActive,
              !metadata.isConfigured,
              !isFailed,
              state == .disabled || state == .setupRequired,
              HistoryPINPolicy.isValid(pin) else {
            return false
        }

        let operationGeneration = resetGeneration
        let operationSession = sessionGeneration
        let stateBeforeSetup = state

        do {
            try await credentials.setPIN(pin)
        } catch {
            fail(.credential)
            return false
        }

        guard operationGeneration == resetGeneration else {
            return await discardStaleSetup()
        }

        var configuredMetadata = metadata
        configuredMetadata.isConfigured = true
        configuredMetadata.localAuthenticationEnabled = false
        configuredMetadata.failedPINAttempts = 0
        configuredMetadata.lockoutUntil = nil

        do {
            try await store.saveMetadata(configuredMetadata)
        } catch {
            return await reconcileSetupFailure(
                stateBeforeSetup: stateBeforeSetup,
                operationGeneration: operationGeneration
            )
        }

        guard operationGeneration == resetGeneration else {
            return await discardStaleSetup()
        }

        metadata = configuredMetadata
        lockoutUntil = nil

        guard sceneIsActive else {
            entries.removeAll()
            state = .locked
            return true
        }

        do {
            let dormantEntries = try await store.loadEntries()
            guard operationGeneration == resetGeneration else {
                entries.removeAll()
                return await discardStaleSetup()
            }
            guard sceneIsActive, sessionGeneration == operationSession else {
                entries.removeAll()
                state = .locked
                return true
            }
            entries = dormantEntries
            state = .unlocked
            return true
        } catch {
            entries.removeAll()
            fail(.storage)
            return false
        }
    }

    /// Verifies the DiceGen PIN and applies the persistent failure schedule.
    func authenticateWithPIN(_ pin: String) async -> HistoryPINResult {
        guard metadata.isConfigured, sceneIsActive, state == .locked, !isFailed else {
            return .failed
        }

        let operationGeneration = resetGeneration
        let operationSession = sessionGeneration
        if let lockoutUntil = activeLockoutDeadline() {
            self.lockoutUntil = lockoutUntil
            return .locked(until: lockoutUntil)
        }
        if metadata.lockoutUntil != nil {
            metadata.lockoutUntil = nil
            lockoutUntil = nil
        }

        let verified: Bool
        if HistoryPINPolicy.isValid(pin) {
            do {
                verified = try await credentials.verifyPIN(pin)
            } catch {
                fail(.credential)
                return .failed
            }
        } else {
            verified = false
        }

        guard operationGeneration == resetGeneration, metadata.isConfigured else {
            return .failed
        }

        guard verified else {
            return await recordFailedPINAttempt()
        }

        var clearedMetadata = metadata
        clearedMetadata.failedPINAttempts = 0
        clearedMetadata.lockoutUntil = nil
        do {
            try await store.saveMetadata(clearedMetadata)
        } catch {
            fail(.storage)
            return .failed
        }

        guard operationGeneration == resetGeneration, metadata.isConfigured else {
            entries.removeAll()
            return .failed
        }

        metadata = clearedMetadata
        lockoutUntil = nil

        guard sceneIsActive, sessionGeneration == operationSession else {
            entries.removeAll()
            state = .locked
            return .success
        }

        do {
            entries = try await store.loadEntries()
            guard operationGeneration == resetGeneration,
                  sceneIsActive,
                  sessionGeneration == operationSession,
                  metadata.isConfigured else {
                entries.removeAll()
                if metadata.isConfigured, !isFailed { state = .locked }
                return .success
            }
            state = .unlocked
            systemAuthenticationRequiresPIN = false
            return .success
        } catch {
            entries.removeAll()
            fail(.storage)
            return .failed
        }
    }

    /// Attempts system authentication without changing PIN failure accounting.
    func authenticateWithSystem() async -> HistoryAuthenticationResult {
        guard metadata.isConfigured,
              metadata.localAuthenticationEnabled,
              sceneIsActive,
              state == .locked,
              !isFailed,
              !systemAuthenticationRequiresPIN,
              !systemAuthenticationInFlight else {
            return .failed
        }

        let operationGeneration = resetGeneration
        let operationAuthenticationGeneration = systemAuthenticationGeneration
        systemAuthenticationInFlight = true
        defer { systemAuthenticationInFlight = false }
        let result = await authenticator.authenticate(reason: "Unlock your private passphrase history.")

        guard isCurrentSystemAuthentication(
            operationGeneration: operationGeneration,
            operationAuthenticationGeneration: operationAuthenticationGeneration
        ) else {
            return staleSystemAuthenticationResult()
        }

        guard result == .success else { return result }

        await waitForSystemAuthenticationActivation()

        guard isCurrentSystemAuthentication(
                  operationGeneration: operationGeneration,
                  operationAuthenticationGeneration: operationAuthenticationGeneration
              ),
              sceneIsActive,
              state == .locked else {
            return staleSystemAuthenticationResult()
        }

        do {
            entries = try await store.loadEntries()
            guard isCurrentSystemAuthentication(
                      operationGeneration: operationGeneration,
                      operationAuthenticationGeneration: operationAuthenticationGeneration
                  ),
                  sceneIsActive,
                  state == .locked else {
                return staleSystemAuthenticationResult()
            }
            state = .unlocked
            return .success
        } catch {
            guard isCurrentSystemAuthentication(
                      operationGeneration: operationGeneration,
                      operationAuthenticationGeneration: operationAuthenticationGeneration
                  ),
                  sceneIsActive,
                  state == .locked else {
                return staleSystemAuthenticationResult()
            }
            entries.removeAll()
            fail(.storage)
            return .failed
        }
    }

    private func isCurrentSystemAuthentication(
        operationGeneration: UInt,
        operationAuthenticationGeneration: UInt
    ) -> Bool {
        operationGeneration == resetGeneration
            && operationAuthenticationGeneration == systemAuthenticationGeneration
            && metadata.isConfigured
            && !isFailed
            && !Task.isCancelled
    }

    private func waitForSystemAuthenticationActivation() async {
        guard !sceneIsActive else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if sceneIsActive {
                continuation.resume()
            } else {
                systemAuthenticationActivationWaiter = continuation
            }
        }
    }

    private func resumeSystemAuthenticationActivationWaiter() {
        systemAuthenticationActivationWaiter?.resume()
        systemAuthenticationActivationWaiter = nil
    }

    private func staleSystemAuthenticationResult() -> HistoryAuthenticationResult {
        return .stale
    }

    /// Records a successful generated-passphrase copy without requiring the history list to be unlocked.
    func recordCopiedPassphrase(_ content: String) async {
        guard metadata.isConfigured,
              sceneIsActive,
              (state == .locked || state == .unlocked),
              !content.isEmpty,
              !isFailed else {
            return
        }

        let operationGeneration = resetGeneration
        let operationSession = sessionGeneration
        do {
            try await store.recordCopiedPassphrase(content, at: now())
        } catch {
            entries.removeAll()
            fail(.storage)
            return
        }

        guard operationGeneration == resetGeneration else {
            entries.removeAll()
            return
        }

        guard state == .unlocked, sceneIsActive, sessionGeneration == operationSession else {
            entries.removeAll()
            if metadata.isConfigured, !isFailed { state = .locked }
            return
        }

        do {
            entries = try await store.loadEntries()
        } catch {
            entries.removeAll()
            fail(.storage)
        }
    }

    /// Deletes one history entry only from an active unlocked session.
    func deleteEntry(id: UUID) async {
        guard state == .unlocked, sceneIsActive, !isFailed else { return }
        let operationGeneration = resetGeneration
        let operationSession = sessionGeneration
        do {
            try await store.deleteEntry(id: id)
            let updatedEntries = try await store.loadEntries()
            guard operationGeneration == resetGeneration,
                  sceneIsActive,
                  sessionGeneration == operationSession,
                  metadata.isConfigured else {
                entries.removeAll()
                if metadata.isConfigured, !isFailed { state = .locked }
                return
            }
            entries = updatedEntries
        } catch {
            entries.removeAll()
            fail(.storage)
        }
    }

    /// Clears all history while leaving the configured PIN and authentication preference intact.
    func clearAll() async {
        guard state == .unlocked, sceneIsActive, !isFailed else { return }
        let operationGeneration = resetGeneration
        let operationSession = sessionGeneration
        do {
            try await store.clearEntries()
            guard operationGeneration == resetGeneration,
                  sceneIsActive,
                  sessionGeneration == operationSession,
                  metadata.isConfigured else {
                entries.removeAll()
                if metadata.isConfigured, !isFailed { state = .locked }
                return
            }
            entries.removeAll()
        } catch {
            entries.removeAll()
            fail(.storage)
        }
    }

    /// Changes the optional system-authentication preference from an unlocked session.
    func setLocalAuthenticationEnabled(_ enabled: Bool) async -> Bool {
        guard state == .unlocked, sceneIsActive, metadata.isConfigured, !isFailed else { return false }
        let operationGeneration = resetGeneration
        let operationSession = sessionGeneration
        let previousMetadata = metadata
        var updatedMetadata = previousMetadata
        updatedMetadata.localAuthenticationEnabled = enabled
        do {
            try await store.saveMetadata(updatedMetadata)
        } catch {
            fail(.storage)
            return false
        }
        guard operationGeneration == resetGeneration, metadata.isConfigured else {
            // A destructive reset invalidated this operation; remove any late preference
            // write so it cannot recreate security metadata after reset completed.
            do {
                try await store.resetAll()
            } catch {
                fail(.inconsistentSecurityState)
            }
            return false
        }
        guard sceneIsActive, sessionGeneration == operationSession else {
            // A suspended persistence call may have written after backgrounding; restore the
            // pre-operation preference before rejecting the stale authenticated mutation.
            do {
                try await store.saveMetadata(previousMetadata)
            } catch {
                fail(.inconsistentSecurityState)
                return false
            }
            entries.removeAll()
            state = .locked
            return false
        }
        metadata = updatedMetadata
        return true
    }

    /// Re-authenticates with the current PIN before replacing it with a new PIN.
    func changePIN(currentPIN: String, newPIN: String) async -> HistoryPINResult {
        guard state == .unlocked, sceneIsActive, metadata.isConfigured, !isFailed else { return .failed }

        let operationGeneration = resetGeneration
        let operationSession = sessionGeneration
        if let lockoutUntil = activeLockoutDeadline() {
            return .locked(until: lockoutUntil)
        }
        if metadata.lockoutUntil != nil {
            metadata.lockoutUntil = nil
            lockoutUntil = nil
        }

        let verified: Bool
        if HistoryPINPolicy.isValid(currentPIN) {
            do {
                verified = try await credentials.verifyPIN(currentPIN)
            } catch {
                fail(.credential)
                return .failed
            }
        } else {
            verified = false
        }

        guard operationGeneration == resetGeneration, metadata.isConfigured else { return .failed }
        guard verified else {
            let result = await recordFailedPINAttempt()
            if case .locked = result {
                entries.removeAll()
                state = .locked
            }
            return result
        }

        guard sceneIsActive, sessionGeneration == operationSession else {
            entries.removeAll()
            state = .locked
            return .failed
        }

        var clearedMetadata = metadata
        clearedMetadata.failedPINAttempts = 0
        clearedMetadata.lockoutUntil = nil
        do {
            try await store.saveMetadata(clearedMetadata)
        } catch {
            fail(.storage)
            return .failed
        }

        guard operationGeneration == resetGeneration, metadata.isConfigured else { return .failed }
        guard sceneIsActive, sessionGeneration == operationSession else {
            entries.removeAll()
            state = .locked
            return .failed
        }
        metadata = clearedMetadata
        lockoutUntil = nil

        guard HistoryPINPolicy.isValid(newPIN) else { return .failed }

        guard sceneIsActive, sessionGeneration == operationSession else {
            entries.removeAll()
            state = .locked
            return .failed
        }

        do {
            try await credentials.setPIN(newPIN)
        } catch {
            fail(.credential)
            return .failed
        }

        guard operationGeneration == resetGeneration, metadata.isConfigured else {
            // A destructive reset invalidated this operation; remove any late replacement
            // instead of allowing it to recreate a credential after reset completed.
            do {
                try await credentials.deleteCredential()
            } catch {
                fail(.inconsistentSecurityState)
            }
            return .failed
        }
        guard sceneIsActive, sessionGeneration == operationSession else {
            // Restore the verified PIN if backgrounding races the credential replacement.
            do {
                try await credentials.setPIN(currentPIN)
            } catch {
                fail(.inconsistentSecurityState)
                return .failed
            }
            entries.removeAll()
            state = .locked
            return .failed
        }
        return .success
    }

    /// Disables history only after the current unlocked session has authorized the destructive reset.
    func disableHistory() async {
        guard state == .unlocked, sceneIsActive, metadata.isConfigured, !isFailed else { return }
        await resetHistory()
    }

    /// Destroys history, the PIN credential, and all persisted security metadata.
    func resetHistory() async {
        resetGeneration &+= 1
        sessionGeneration &+= 1
        systemAuthenticationGeneration &+= 1
        resumeSystemAuthenticationActivationWaiter()
        entries.removeAll()
        lockoutUntil = nil
        systemAuthenticationRequiresPIN = false
        migration.discardLegacyHistory()

        let cleared = await clearPersistedState()
        guard cleared else {
            metadata = .empty
            state = .failed(.inconsistentSecurityState)
            return
        }

        metadata = .empty
        state = .disabled
    }

    /// Marks the one-time migration notice consumed after persistence succeeds.
    func consumeMigrationNotice() async {
        guard metadata.migrationNoticePending, !isFailed else { return }
        let operationGeneration = resetGeneration
        var updatedMetadata = metadata
        updatedMetadata.migrationNoticePending = false
        do {
            try await store.saveMetadata(updatedMetadata)
        } catch {
            fail(.storage)
            return
        }
        guard operationGeneration == resetGeneration else { return }
        metadata = updatedMetadata
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func activeLockoutDeadline() -> Date? {
        guard let lockoutUntil = metadata.lockoutUntil, lockoutUntil > now() else { return nil }
        return lockoutUntil
    }

    private func recordFailedPINAttempt() async -> HistoryPINResult {
        let failedAttempts = metadata.failedPINAttempts == Int.max
            ? Int.max
            : metadata.failedPINAttempts + 1
        var updatedMetadata = metadata
        updatedMetadata.failedPINAttempts = failedAttempts
        updatedMetadata.lockoutUntil = lockoutDuration(afterFailedAttempts: failedAttempts).map {
            now().addingTimeInterval($0)
        }

        do {
            try await store.saveMetadata(updatedMetadata)
        } catch {
            fail(.storage)
            return .failed
        }

        metadata = updatedMetadata
        lockoutUntil = updatedMetadata.lockoutUntil
        if let lockoutUntil = updatedMetadata.lockoutUntil {
            return .locked(until: lockoutUntil)
        }
        return .incorrect
    }

    private func lockoutDuration(afterFailedAttempts count: Int) -> TimeInterval? {
        switch count {
        case ...4:
            return nil
        case 5:
            return 30
        case 6:
            return 60
        case 7:
            return 5 * 60
        case 8:
            return 15 * 60
        default:
            return 60 * 60
        }
    }

    private func reconcileSetupFailure(
        stateBeforeSetup: HistoryVaultState,
        operationGeneration: UInt
    ) async -> Bool {
        guard operationGeneration == resetGeneration else { return await discardStaleSetup() }

        do {
            let persistedMetadata = try await store.loadMetadata()
            guard operationGeneration == resetGeneration else { return await discardStaleSetup() }
            if !persistedMetadata.isConfigured {
                do {
                    try await credentials.deleteCredential()
                } catch {
                    fail(.inconsistentSecurityState)
                    return false
                }
                metadata = persistedMetadata
                lockoutUntil = persistedMetadata.lockoutUntil
                entries.removeAll()
                state = stateBeforeSetup == .setupRequired ? .setupRequired : .disabled
                return false
            }

            metadata = persistedMetadata
            lockoutUntil = persistedMetadata.lockoutUntil
            entries.removeAll()
            state = .failed(.inconsistentSecurityState)
            return false
        } catch {
            fail(.inconsistentSecurityState)
            return false
        }
    }

    private func discardStaleSetup() async -> Bool {
        let cleared = await clearPersistedState()
        metadata = .empty
        lockoutUntil = nil
        entries.removeAll()
        if cleared {
            state = .disabled
        } else {
            state = .failed(.inconsistentSecurityState)
        }
        return false
    }

    private func clearPersistedState() async -> Bool {
        var storeCleared = true
        do {
            try await store.resetAll()
        } catch {
            storeCleared = false
        }

        var credentialsCleared = true
        do {
            try await credentials.deleteCredential()
        } catch {
            credentialsCleared = false
        }
        return storeCleared && credentialsCleared
    }

    private func fail(_ failure: HistoryVaultFailure) {
        systemAuthenticationGeneration &+= 1
        resumeSystemAuthenticationActivationWaiter()
        entries.removeAll()
        state = .failed(failure)
    }
}
