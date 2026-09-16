//
//  HistoryVaultTests.swift
//  DiceGenTests
//

import Foundation
import XCTest
@testable import DiceGen

@MainActor
final class HistoryVaultTests: XCTestCase {
    func testFreshVaultStartsDisabled() async {
        let store = VaultStoreSpy()
        let credentials = VaultCredentialSpy()
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()

        XCTAssertEqual(vault.state, .disabled)
        XCTAssertTrue(vault.entries.isEmpty)
        XCTAssertFalse(vault.isConfigured)
    }

    func testDormantMigratedEntriesRequireSetupAndRemainUnpublished() async {
        let dormantEntry = HistoryEntry(id: UUID(), content: "dormant", savedAt: Date())
        let store = VaultStoreSpy(entries: [dormantEntry])
        let vault = makeVault(store: store, credentials: VaultCredentialSpy())

        vault.setSceneActive(true)
        await vault.initialize()

        XCTAssertEqual(vault.state, .setupRequired)
        XCTAssertTrue(vault.entries.isEmpty)
        XCTAssertFalse(vault.isConfigured)
    }

    func testConfiguredVaultWithCredentialStartsLockedWithoutPublishingEntries() async {
        var metadata = HistorySecurityMetadata.empty
        metadata.isConfigured = true
        let entry = HistoryEntry(id: UUID(), content: "secret", savedAt: Date())
        let store = VaultStoreSpy(entries: [entry], metadata: metadata)
        let credentials = VaultCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()

        XCTAssertEqual(vault.state, .locked)
        XCTAssertTrue(vault.entries.isEmpty)
        XCTAssertTrue(vault.isConfigured)
    }

    func testUnconfiguredCredentialMismatchFailsClosed() async {
        let store = VaultStoreSpy()
        let credentials = VaultCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()

        XCTAssertEqual(vault.state, .failed(.inconsistentSecurityState))
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testConfiguredWithoutCredentialMismatchFailsClosed() async {
        var metadata = HistorySecurityMetadata.empty
        metadata.isConfigured = true
        let vault = makeVault(store: VaultStoreSpy(metadata: metadata), credentials: VaultCredentialSpy())

        vault.setSceneActive(true)
        await vault.initialize()

        XCTAssertEqual(vault.state, .failed(.inconsistentSecurityState))
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testSuccessfulSetupPersistsCredentialAndMetadataAndUnlocks() async {
        let store = VaultStoreSpy()
        let credentials = VaultCredentialSpy()
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()
        let didConfigure = await vault.configureHistory(pin: validPIN)

        let credentialSnapshot = await credentials.snapshot()
        let metadata = await store.metadataSnapshot()
        XCTAssertTrue(didConfigure)
        XCTAssertEqual(credentialSnapshot.pin, validPIN)
        XCTAssertTrue(metadata.isConfigured)
        XCTAssertFalse(metadata.localAuthenticationEnabled)
        XCTAssertEqual(metadata.failedPINAttempts, 0)
        XCTAssertNil(metadata.lockoutUntil)
        XCTAssertEqual(vault.state, .unlocked)
    }

    func testSetupMetadataFailureDeletesNewCredentialAndRemainsUnconfigured() async {
        let store = VaultStoreSpy(saveMetadataError: .writeFailed)
        let credentials = VaultCredentialSpy()
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()
        let didConfigure = await vault.configureHistory(pin: validPIN)

        let credentialSnapshot = await credentials.snapshot()
        let metadata = await store.metadataSnapshot()
        XCTAssertFalse(didConfigure)
        XCTAssertNil(credentialSnapshot.pin)
        XCTAssertFalse(metadata.isConfigured)
        XCTAssertEqual(vault.state, .disabled)
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testInvalidPINDoesNotWriteCredentialOrMetadata() async {
        let store = VaultStoreSpy()
        let credentials = VaultCredentialSpy()
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()
        let didConfigure = await vault.configureHistory(pin: "12")

        let credentialSnapshot = await credentials.snapshot()
        let storeSnapshot = await store.snapshot()
        XCTAssertFalse(didConfigure)
        XCTAssertEqual(credentialSnapshot.setPINCalls, 0)
        XCTAssertEqual(storeSnapshot.saveMetadataCalls, 0)
        XCTAssertEqual(vault.state, .disabled)
    }

    func testPINLockoutUsesApprovedDurationsAndCapsAtOneHour() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        var metadata = configuredMetadata()
        let store = VaultStoreSpy(metadata: metadata)
        let credentials = VaultCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials, clock: clock)

        vault.setSceneActive(true)
        await vault.initialize()

        for attempt in 1...10 {
            let result = await vault.authenticateWithPIN(invalidPIN)
            if attempt < 5 {
                XCTAssertEqual(result, .incorrect)
            } else {
                let expectedDuration: TimeInterval = attempt == 5 ? 30 :
                    attempt == 6 ? 60 :
                    attempt == 7 ? 5 * 60 :
                    attempt == 8 ? 15 * 60 : 60 * 60
                guard case let .locked(until) = result else {
                    XCTFail("Attempt \(attempt) should start a lockout")
                    continue
                }
                XCTAssertEqual(until, clock.date.addingTimeInterval(expectedDuration))
                XCTAssertEqual(vault.lockoutUntil, until)
                clock.date = until.addingTimeInterval(1)
            }
        }

        metadata = await store.metadataSnapshot()
        XCTAssertEqual(metadata.failedPINAttempts, 10)
        XCTAssertEqual(metadata.lockoutUntil, clock.date.addingTimeInterval(-1))
    }

    func testActiveLockoutRejectsWithoutVerifyingOrIncrementing() async {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000))
        let store = VaultStoreSpy(metadata: configuredMetadata())
        let credentials = VaultCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials, clock: clock)

        vault.setSceneActive(true)
        await vault.initialize()
        for _ in 1...5 {
            let result = await vault.authenticateWithPIN(invalidPIN)
            if case let .locked(until) = result {
                clock.date = until.addingTimeInterval(-1)
            }
        }

        let before = await credentials.snapshot()
        let metadataBefore = await store.metadataSnapshot()
        let result = await vault.authenticateWithPIN(validPIN)
        let after = await credentials.snapshot()
        let metadataAfter = await store.metadataSnapshot()

        XCTAssertEqual(result, .locked(until: try XCTUnwrap(metadataBefore.lockoutUntil)))
        XCTAssertEqual(after.verifyPINCalls, before.verifyPINCalls)
        XCTAssertEqual(metadataAfter.failedPINAttempts, metadataBefore.failedPINAttempts)
        XCTAssertEqual(metadataAfter.lockoutUntil, metadataBefore.lockoutUntil)
    }

    func testLockoutMetadataSurvivesReconstructingVault() async {
        let clock = TestClock(Date(timeIntervalSince1970: 3_000))
        let store = VaultStoreSpy(metadata: configuredMetadata())
        let credentials = VaultCredentialSpy(pin: validPIN)
        let firstVault = makeVault(store: store, credentials: credentials, clock: clock)

        firstVault.setSceneActive(true)
        await firstVault.initialize()
        for _ in 1...5 {
            let result = await firstVault.authenticateWithPIN(invalidPIN)
            if case let .locked(until) = result {
                clock.date = until.addingTimeInterval(-1)
            }
        }

        let secondVault = makeVault(store: store, credentials: credentials, clock: clock)
        secondVault.setSceneActive(true)
        await secondVault.initialize()
        let metadata = await store.metadataSnapshot()

        XCTAssertEqual(secondVault.state, .locked)
        XCTAssertEqual(secondVault.lockoutUntil, metadata.lockoutUntil)
        let result = await secondVault.authenticateWithPIN(validPIN)
        XCTAssertEqual(result, .locked(until: try XCTUnwrap(metadata.lockoutUntil)))
    }

    func testSuccessfulPINClearsPersistedFailureStateBeforeUnlocking() async {
        let clock = TestClock(Date(timeIntervalSince1970: 4_000))
        var metadata = configuredMetadata()
        metadata.failedPINAttempts = 5
        metadata.lockoutUntil = clock.date.addingTimeInterval(-1)
        let store = VaultStoreSpy(metadata: metadata)
        let credentials = VaultCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials, clock: clock)

        vault.setSceneActive(true)
        await vault.initialize()
        let result = await vault.authenticateWithPIN(validPIN)

        let persisted = await store.metadataSnapshot()
        XCTAssertEqual(result, .success)
        XCTAssertEqual(persisted.failedPINAttempts, 0)
        XCTAssertNil(persisted.lockoutUntil)
        XCTAssertEqual(vault.state, .unlocked)
    }

    func testSuccessfulPINCompletionAfterBackgroundDoesNotPublishEntries() async {
        let store = VaultStoreSpy(entries: [historyEntry("hidden")], metadata: configuredMetadata())
        let credentials = SuspendingCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()
        let task = Task { await vault.authenticateWithPIN(validPIN) }
        await credentials.waitForVerification()

        vault.setSceneActive(false)
        await credentials.completeVerification(true)
        let result = await task.value

        XCTAssertEqual(result, .success)
        XCTAssertEqual(vault.state, .locked)
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testSetupCompletionAfterBackgroundRemainsConfiguredButLocked() async {
        let store = VaultStoreSpy(entries: [historyEntry("dormant")])
        let credentials = SuspendingCredentialSpy()
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()
        let task = Task { await vault.configureHistory(pin: validPIN) }
        await credentials.waitForSettingPIN()

        vault.setSceneActive(false)
        await credentials.completeSettingPIN()
        let didConfigure = await task.value

        XCTAssertTrue(didConfigure)
        XCTAssertTrue(vault.isConfigured)
        XCTAssertEqual(vault.state, .locked)
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testRecordingWhileLockedPersistsWithoutPublishingPlaintext() async {
        let store = VaultStoreSpy(metadata: configuredMetadata())
        let vault = makeVault(store: store, credentials: VaultCredentialSpy(pin: validPIN))

        vault.setSceneActive(true)
        await vault.initialize()
        await vault.recordCopiedPassphrase("copied while locked")

        let entries = await store.entriesSnapshot()
        XCTAssertEqual(entries.map(\.content), ["copied while locked"])
        XCTAssertEqual(vault.state, .locked)
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testDuplicateRecordingWhileUnlockedRefreshesRecency() async {
        let clock = TestClock(Date(timeIntervalSince1970: 100))
        let store = VaultStoreSpy(metadata: configuredMetadata())
        let vault = makeVault(
            store: store,
            credentials: VaultCredentialSpy(pin: validPIN),
            clock: clock
        )

        vault.setSceneActive(true)
        await vault.initialize()
        let firstUnlock = await vault.authenticateWithPIN(validPIN)
        XCTAssertEqual(firstUnlock, .success)
        await vault.recordCopiedPassphrase("duplicate")
        clock.date = Date(timeIntervalSince1970: 200)
        await vault.recordCopiedPassphrase("duplicate")

        XCTAssertEqual(vault.entries.count, 1)
        XCTAssertEqual(vault.entries[0].content, "duplicate")
        XCTAssertEqual(vault.entries[0].savedAt, clock.date)
    }

    func testRecordingBeforeSetupIsANoOp() async {
        let dormant = historyEntry("dormant")
        let setupRequiredStore = VaultStoreSpy(entries: [dormant])
        let setupRequiredVault = makeVault(store: setupRequiredStore, credentials: VaultCredentialSpy())
        setupRequiredVault.setSceneActive(true)
        await setupRequiredVault.initialize()
        await setupRequiredVault.recordCopiedPassphrase("not saved")

        let disabledStore = VaultStoreSpy()
        let disabledVault = makeVault(store: disabledStore, credentials: VaultCredentialSpy())
        disabledVault.setSceneActive(true)
        await disabledVault.initialize()
        await disabledVault.recordCopiedPassphrase("not saved")

        let setupRequiredEntries = await setupRequiredStore.entriesSnapshot()
        let disabledEntries = await disabledStore.entriesSnapshot()
        XCTAssertEqual(setupRequiredEntries.map(\.content), ["dormant"])
        XCTAssertTrue(disabledEntries.isEmpty)
    }

    func testRecordStorageFailureFailsClosed() async {
        let store = VaultStoreSpy(metadata: configuredMetadata(), recordEntriesError: .writeFailed)
        let vault = makeVault(store: store, credentials: VaultCredentialSpy(pin: validPIN))

        vault.setSceneActive(true)
        await vault.initialize()
        await vault.recordCopiedPassphrase("write failure")

        XCTAssertEqual(vault.state, .failed(.storage))
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testDeleteAndClearAreIgnoredWhileLockedAndWorkAfterPINUnlock() async {
        let first = historyEntry("first")
        let second = historyEntry("second")
        let store = VaultStoreSpy(entries: [first, second], metadata: configuredMetadata())
        let vault = makeVault(store: store, credentials: VaultCredentialSpy(pin: validPIN))

        vault.setSceneActive(true)
        await vault.initialize()
        await vault.deleteEntry(id: first.id)
        await vault.clearAll()
        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.deleteEntryCalls, 0)
        XCTAssertEqual(snapshot.clearEntriesCalls, 0)

        let unlockResult = await vault.authenticateWithPIN(validPIN)
        XCTAssertEqual(unlockResult, .success)
        await vault.deleteEntry(id: second.id)
        await vault.clearAll()
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.deleteEntryCalls, 1)
        XCTAssertEqual(snapshot.clearEntriesCalls, 1)
        XCTAssertTrue(vault.entries.isEmpty)
        XCTAssertTrue(vault.isConfigured)
    }

    func testLocalAuthenticationPreferenceRequiresUnlockedSession() async {
        let store = VaultStoreSpy(metadata: configuredMetadata())
        let vault = makeVault(store: store, credentials: VaultCredentialSpy(pin: validPIN))

        vault.setSceneActive(true)
        await vault.initialize()
        let lockedToggleResult = await vault.setLocalAuthenticationEnabled(true)
        XCTAssertFalse(lockedToggleResult)
        XCTAssertFalse(vault.localAuthenticationEnabled)
        let lockedSnapshot = await store.snapshot()
        XCTAssertEqual(lockedSnapshot.saveMetadataCalls, 0)

        let pinUnlockResult = await vault.authenticateWithPIN(validPIN)
        let unlockedToggleResult = await vault.setLocalAuthenticationEnabled(true)
        XCTAssertEqual(pinUnlockResult, .success)
        XCTAssertTrue(unlockedToggleResult)
        XCTAssertTrue(vault.localAuthenticationEnabled)
    }

    func testLocalAuthenticationPreferenceCompletionAfterBackgroundIsRejected() async {
        let store = VaultStoreSpy(metadata: configuredMetadata())
        let vault = makeVault(store: store, credentials: VaultCredentialSpy(pin: validPIN))

        vault.setSceneActive(true)
        await vault.initialize()
        let unlockResult = await vault.authenticateWithPIN(validPIN)
        XCTAssertEqual(unlockResult, .success)
        XCTAssertEqual(vault.state, .unlocked)

        await store.suspendNextMetadataSave()
        let task = Task { await vault.setLocalAuthenticationEnabled(true) }
        await store.waitForMetadataSave()

        vault.setSceneActive(false)
        await store.completeMetadataSave()
        let result = await task.value
        let persisted = await store.metadataSnapshot()

        XCTAssertFalse(result)
        XCTAssertFalse(vault.localAuthenticationEnabled)
        XCTAssertEqual(vault.state, .locked)
        XCTAssertTrue(vault.entries.isEmpty)
        XCTAssertFalse(persisted.localAuthenticationEnabled)
    }

    func testLocalAuthenticationPreferenceResetDuringPersistenceCannotReinstallMetadata() async {
        let store = VaultStoreSpy(metadata: configuredMetadata())
        let credentials = ControllableCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()
        let unlockResult = await vault.authenticateWithPIN(validPIN)
        XCTAssertEqual(unlockResult, .success)
        XCTAssertEqual(vault.state, .unlocked)

        await store.suspendNextMetadataSave()
        let preferenceTask = Task { await vault.setLocalAuthenticationEnabled(true) }
        await store.waitForMetadataSave()

        await vault.resetHistory()
        await store.completeMetadataSave()
        let result = await preferenceTask.value
        let persisted = await store.snapshot()
        let credentialSnapshot = await credentials.snapshot()

        XCTAssertFalse(result)
        XCTAssertEqual(persisted.metadata, .empty)
        XCTAssertNil(credentialSnapshot.pin)
        XCTAssertEqual(vault.state, .disabled)
        XCTAssertFalse(vault.isConfigured)
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testSystemAuthenticationDoesNotClearPINFailureState() async {
        var metadata = configuredMetadata()
        metadata.localAuthenticationEnabled = true
        metadata.failedPINAttempts = 4
        let store = VaultStoreSpy(entries: [historyEntry("private")], metadata: metadata)
        let authenticator = VaultAuthenticatorSpy(result: .success)
        let vault = HistoryVault(
            store: store,
            credentials: VaultCredentialSpy(pin: validPIN),
            authenticator: authenticator,
            migration: NoOpHistoryMigration()
        )

        vault.setSceneActive(true)
        await vault.initialize()
        let result = await vault.authenticateWithSystem()

        let persisted = await store.metadataSnapshot()
        XCTAssertEqual(result, .success)
        XCTAssertEqual(vault.state, .unlocked)
        XCTAssertEqual(persisted.failedPINAttempts, 4)
        XCTAssertNil(persisted.lockoutUntil)
    }

    func testSystemAuthenticationCancellationUnavailableAndFailureStayLocked() async {
        for result in [
            HistoryAuthenticationResult.cancelled,
            .unavailable,
            .failed
        ] {
            var metadata = configuredMetadata()
            metadata.localAuthenticationEnabled = true
            let vault = HistoryVault(
                store: VaultStoreSpy(metadata: metadata),
                credentials: VaultCredentialSpy(pin: validPIN),
                authenticator: VaultAuthenticatorSpy(result: result),
                migration: NoOpHistoryMigration()
            )
            vault.setSceneActive(true)
            await vault.initialize()

            let authenticationResult = await vault.authenticateWithSystem()
            XCTAssertEqual(authenticationResult, result)
            XCTAssertEqual(vault.state, .locked)
            XCTAssertTrue(vault.entries.isEmpty)
        }
    }

    func testSystemAuthenticationCompletionAfterBackgroundCannotUnlock() async {
        var metadata = configuredMetadata()
        metadata.localAuthenticationEnabled = true
        let store = VaultStoreSpy(entries: [historyEntry("system secret")], metadata: metadata)
        let authenticator = SuspendingAuthenticator()
        let vault = HistoryVault(
            store: store,
            credentials: VaultCredentialSpy(pin: validPIN),
            authenticator: authenticator,
            migration: NoOpHistoryMigration()
        )

        vault.setSceneActive(true)
        await vault.initialize()
        let task = Task { await vault.authenticateWithSystem() }
        await authenticator.waitForAuthentication()
        vault.setSceneActive(false)
        await authenticator.complete(.success)
        let result = await task.value

        XCTAssertEqual(result, .success)
        XCTAssertEqual(vault.state, .locked)
        XCTAssertTrue(vault.entries.isEmpty)
        vault.setSceneActive(true)
        XCTAssertEqual(vault.state, .locked)
    }

    func testChangePINRequiresCurrentPINEvenAfterSystemUnlock() async {
        var metadata = configuredMetadata()
        metadata.localAuthenticationEnabled = true
        let store = VaultStoreSpy(metadata: metadata)
        let credentials = VaultCredentialSpy(pin: validPIN)
        let vault = HistoryVault(
            store: store,
            credentials: credentials,
            authenticator: VaultAuthenticatorSpy(result: .success),
            migration: NoOpHistoryMigration()
        )
        let newPIN = String(repeating: "6", count: 4)

        vault.setSceneActive(true)
        await vault.initialize()
        let systemUnlockResult = await vault.authenticateWithSystem()
        XCTAssertEqual(systemUnlockResult, .success)
        let wrongCurrentResult = await vault.changePIN(currentPIN: invalidPIN, newPIN: newPIN)
        let correctCurrentResult = await vault.changePIN(currentPIN: validPIN, newPIN: newPIN)

        let credentialSnapshot = await credentials.snapshot()
        XCTAssertEqual(wrongCurrentResult, .incorrect)
        XCTAssertEqual(correctCurrentResult, .success)
        XCTAssertEqual(credentialSnapshot.pin, newPIN)
    }

    func testChangePINCompletionAfterBackgroundDoesNotInstallReplacementPIN() async {
        let store = VaultStoreSpy(
            entries: [historyEntry("private")],
            metadata: configuredMetadata()
        )
        let credentials = ControllableCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials)
        let newPIN = String(repeating: "6", count: 4)

        vault.setSceneActive(true)
        await vault.initialize()
        let unlockResult = await vault.authenticateWithPIN(validPIN)
        XCTAssertEqual(unlockResult, .success)
        XCTAssertEqual(vault.state, .unlocked)

        await credentials.suspendNextVerification()
        let task = Task { await vault.changePIN(currentPIN: validPIN, newPIN: newPIN) }
        await credentials.waitForVerification()

        vault.setSceneActive(false)
        await credentials.completeVerification(true)
        let result = await task.value
        let credentialSnapshot = await credentials.snapshot()

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(credentialSnapshot.pin, validPIN)
        XCTAssertEqual(credentialSnapshot.setPINCalls, 0)
        XCTAssertEqual(vault.state, .locked)
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testChangePINStaleDuringReplacementRestoresCurrentPIN() async {
        let store = VaultStoreSpy(
            entries: [historyEntry("private")],
            metadata: configuredMetadata()
        )
        let credentials = ControllableCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials)
        let newPIN = String(repeating: "6", count: 4)

        vault.setSceneActive(true)
        await vault.initialize()
        let unlockResult = await vault.authenticateWithPIN(validPIN)
        XCTAssertEqual(unlockResult, .success)
        XCTAssertEqual(vault.state, .unlocked)

        await credentials.suspendNextSetPIN()
        let task = Task { await vault.changePIN(currentPIN: validPIN, newPIN: newPIN) }
        await credentials.waitForSetPIN()

        vault.setSceneActive(false)
        await credentials.completeSetPIN()
        let result = await task.value
        let credentialSnapshot = await credentials.snapshot()

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(credentialSnapshot.pin, validPIN)
        XCTAssertEqual(credentialSnapshot.setPINCalls, 2)
        XCTAssertEqual(vault.state, .locked)
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testChangePINResetDuringReplacementCannotReinstallCredential() async {
        let store = VaultStoreSpy(
            entries: [historyEntry("private")],
            metadata: configuredMetadata()
        )
        let credentials = ControllableCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials)
        let newPIN = String(repeating: "6", count: 4)

        vault.setSceneActive(true)
        await vault.initialize()
        let unlockResult = await vault.authenticateWithPIN(validPIN)
        XCTAssertEqual(unlockResult, .success)
        XCTAssertEqual(vault.state, .unlocked)

        await credentials.suspendNextSetPIN()
        let changeTask = Task { await vault.changePIN(currentPIN: validPIN, newPIN: newPIN) }
        await credentials.waitForSetPIN()

        await vault.resetHistory()
        await credentials.completeSetPIN()
        let result = await changeTask.value
        let credentialSnapshot = await credentials.snapshot()

        XCTAssertEqual(result, .failed)
        XCTAssertNil(credentialSnapshot.pin)
        XCTAssertEqual(credentialSnapshot.setPINCalls, 1)
        XCTAssertEqual(vault.state, .disabled)
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testDisableRequiresUnlockedSessionAndResetWorksWithoutAuth() async {
        let store = VaultStoreSpy(metadata: configuredMetadata())
        let credentials = VaultCredentialSpy(pin: validPIN)
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()
        await vault.disableHistory()
        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.resetAllCalls, 0)
        XCTAssertEqual(vault.state, .locked)

        await vault.resetHistory()
        snapshot = await store.snapshot()
        let credentialSnapshot = await credentials.snapshot()
        XCTAssertEqual(snapshot.resetAllCalls, 1)
        XCTAssertEqual(credentialSnapshot.deleteCredentialCalls, 1)
        XCTAssertEqual(vault.state, .disabled)
        XCTAssertFalse(vault.isConfigured)
    }

    func testResetFailureLeavesVaultInInconsistentRecoveryState() async {
        let store = VaultStoreSpy(metadata: configuredMetadata(), resetAllError: .writeFailed)
        let credentials = VaultCredentialSpy(pin: validPIN, deleteCredentialError: .deleteFailed)
        let vault = makeVault(store: store, credentials: credentials)

        vault.setSceneActive(true)
        await vault.initialize()
        await vault.resetHistory()

        XCTAssertEqual(vault.state, .failed(.inconsistentSecurityState))
        XCTAssertTrue(vault.entries.isEmpty)
    }

    func testResetAfterFailedMigrationDeletesLegacyStateAndReturnsDisabled() async {
        let defaults = UserDefaults(suiteName: "DiceGenTests.HistoryVault.\(UUID().uuidString)")!
        defaults.set(
            [["content": "retained legacy history", "savedAt": Date(timeIntervalSince1970: 100)]],
            forKey: HistoryMigration.savedItemsKey
        )
        defaults.set(true, forKey: HistoryMigration.shouldSaveItemsKey)

        let store = VaultStoreSpy(
            entries: [historyEntry("new store history")],
            metadata: configuredMetadata(),
            replaceEntriesError: .writeFailed
        )
        let credentials = VaultCredentialSpy(pin: validPIN)
        let migration = HistoryMigration(defaults: defaults, store: store)
        let vault = HistoryVault(
            store: store,
            credentials: credentials,
            authenticator: VaultAuthenticatorSpy(result: .cancelled),
            migration: migration
        )

        vault.setSceneActive(true)
        await vault.initialize()

        XCTAssertEqual(vault.state, .failed(.storage))
        XCTAssertNotNil(defaults.object(forKey: HistoryMigration.savedItemsKey))
        XCTAssertTrue(defaults.bool(forKey: HistoryMigration.shouldSaveItemsKey))

        await vault.resetHistory()

        let storeSnapshot = await store.snapshot()
        let credentialSnapshot = await credentials.snapshot()
        XCTAssertTrue(storeSnapshot.entries.isEmpty)
        XCTAssertEqual(storeSnapshot.metadata, .empty)
        XCTAssertNil(defaults.object(forKey: HistoryMigration.savedItemsKey))
        XCTAssertNil(defaults.object(forKey: HistoryMigration.shouldSaveItemsKey))
        XCTAssertNil(credentialSnapshot.pin)
        XCTAssertEqual(vault.state, .disabled)
    }

    func testMigrationNoticeConsumptionPersists() async {
        var metadata = configuredMetadata()
        metadata.migrationNoticePending = true
        let store = VaultStoreSpy(metadata: metadata)
        let vault = makeVault(store: store, credentials: VaultCredentialSpy(pin: validPIN))

        vault.setSceneActive(true)
        await vault.initialize()
        await vault.consumeMigrationNotice()

        let persisted = await store.metadataSnapshot()
        XCTAssertFalse(vault.migrationNoticePending)
        XCTAssertFalse(persisted.migrationNoticePending)
    }

    private var validPIN: String { String(repeating: "7", count: 4) }

    private var invalidPIN: String { String(repeating: "8", count: 4) }

    private func configuredMetadata() -> HistorySecurityMetadata {
        var metadata = HistorySecurityMetadata.empty
        metadata.isConfigured = true
        return metadata
    }

    private func historyEntry(_ content: String) -> HistoryEntry {
        HistoryEntry(id: UUID(), content: content, savedAt: Date())
    }

    private func makeVault(
        store: VaultStoreSpy,
        credentials: any PINCredentialStoring,
        migration: NoOpHistoryMigration = NoOpHistoryMigration(),
        clock: TestClock = TestClock(Date(timeIntervalSince1970: 0))
    ) -> HistoryVault {
        HistoryVault(
            store: store,
            credentials: credentials,
            authenticator: VaultAuthenticatorSpy(result: .cancelled),
            migration: migration,
            now: { clock.date }
        )
    }
}

@MainActor
private struct NoOpHistoryMigration: HistoryMigrating {
    func migrateIfNeeded() async throws {}

    func discardLegacyHistory() {}
}

private final class TestClock: @unchecked Sendable {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

private actor VaultStoreSpy: HistoryPersisting {
    private var entries: [HistoryEntry]
    private var metadata: HistorySecurityMetadata
    private let saveMetadataError: VaultStoreError?
    private let loadEntriesError: VaultStoreError?
    private let replaceEntriesError: VaultStoreError?
    private let recordEntriesError: VaultStoreError?
    private let resetAllError: VaultStoreError?
    private var saveMetadataCalls = 0
    private var shouldSuspendNextMetadataSave = false
    private var metadataSaveContinuation: CheckedContinuation<Void, Never>?
    private var metadataSaveWaiter: CheckedContinuation<Void, Never>?
    private var metadataSaveStarted = false
    private var deleteEntryCalls = 0
    private var clearEntriesCalls = 0
    private var resetAllCalls = 0

    init(
        entries: [HistoryEntry] = [],
        metadata: HistorySecurityMetadata = .empty,
        saveMetadataError: VaultStoreError? = nil,
        loadEntriesError: VaultStoreError? = nil,
        replaceEntriesError: VaultStoreError? = nil,
        recordEntriesError: VaultStoreError? = nil,
        resetAllError: VaultStoreError? = nil
    ) {
        self.entries = entries
        self.metadata = metadata
        self.saveMetadataError = saveMetadataError
        self.loadEntriesError = loadEntriesError
        self.replaceEntriesError = replaceEntriesError
        self.recordEntriesError = recordEntriesError
        self.resetAllError = resetAllError
    }

    func loadEntries() async throws -> [HistoryEntry] {
        if let loadEntriesError { throw loadEntriesError }
        return entries
    }

    func hasEntries() async throws -> Bool {
        if let loadEntriesError { throw loadEntriesError }
        return !entries.isEmpty
    }

    func replaceEntries(_ entries: [HistoryEntry]) async throws {
        if let replaceEntriesError { throw replaceEntriesError }
        self.entries = entries
    }

    func recordCopiedPassphrase(_ content: String, at date: Date) async throws {
        if let recordEntriesError { throw recordEntriesError }
        entries.removeAll { $0.content == content }
        entries.insert(HistoryEntry(id: UUID(), content: content, savedAt: date), at: 0)
    }

    func deleteEntry(id: UUID) async throws {
        deleteEntryCalls += 1
        entries.removeAll { $0.id == id }
    }

    func clearEntries() async throws {
        clearEntriesCalls += 1
        entries.removeAll()
    }

    func loadMetadata() async throws -> HistorySecurityMetadata { metadata }

    func saveMetadata(_ metadata: HistorySecurityMetadata) async throws {
        saveMetadataCalls += 1
        if let saveMetadataError { throw saveMetadataError }
        if shouldSuspendNextMetadataSave {
            shouldSuspendNextMetadataSave = false
            metadataSaveStarted = true
            metadataSaveWaiter?.resume()
            metadataSaveWaiter = nil
            await withCheckedContinuation { continuation in
                metadataSaveContinuation = continuation
            }
        }
        self.metadata = metadata
    }

    func suspendNextMetadataSave() {
        shouldSuspendNextMetadataSave = true
        metadataSaveStarted = false
    }

    func waitForMetadataSave() async {
        guard !metadataSaveStarted else { return }
        await withCheckedContinuation { continuation in
            metadataSaveWaiter = continuation
        }
    }

    func completeMetadataSave() {
        metadataSaveContinuation?.resume()
        metadataSaveContinuation = nil
    }

    func resetAll() async throws {
        resetAllCalls += 1
        if let resetAllError { throw resetAllError }
        entries.removeAll()
        metadata = .empty
    }

    func metadataSnapshot() -> HistorySecurityMetadata { metadata }

    func snapshot() -> (
        entries: [HistoryEntry],
        metadata: HistorySecurityMetadata,
        saveMetadataCalls: Int,
        deleteEntryCalls: Int,
        clearEntriesCalls: Int,
        resetAllCalls: Int
    ) {
        (entries, metadata, saveMetadataCalls, deleteEntryCalls, clearEntriesCalls, resetAllCalls)
    }

    func entriesSnapshot() -> [HistoryEntry] { entries }
}

private actor VaultCredentialSpy: PINCredentialStoring {
    private var pin: String?
    private let deleteCredentialError: VaultCredentialError?
    private var setPINCalls = 0
    private var verifyPINCalls = 0
    private var deleteCredentialCalls = 0

    init(pin: String? = nil, deleteCredentialError: VaultCredentialError? = nil) {
        self.pin = pin
        self.deleteCredentialError = deleteCredentialError
    }

    func hasCredential() async throws -> Bool { pin != nil }

    func setPIN(_ pin: String) async throws {
        setPINCalls += 1
        self.pin = pin
    }

    func verifyPIN(_ pin: String) async throws -> Bool {
        verifyPINCalls += 1
        return self.pin == pin
    }

    func deleteCredential() async throws {
        deleteCredentialCalls += 1
        if let deleteCredentialError { throw deleteCredentialError }
        pin = nil
    }

    func snapshot() -> (pin: String?, setPINCalls: Int, verifyPINCalls: Int, deleteCredentialCalls: Int) {
        (pin, setPINCalls, verifyPINCalls, deleteCredentialCalls)
    }
}

private actor ControllableCredentialSpy: PINCredentialStoring {
    private var pin: String?
    private var shouldSuspendNextVerification = false
    private var shouldSuspendNextSetPIN = false
    private var verificationContinuation: CheckedContinuation<Bool, Never>?
    private var verificationWaiter: CheckedContinuation<Void, Never>?
    private var verificationStarted = false
    private var setPINContinuation: CheckedContinuation<Void, Never>?
    private var setPINWaiter: CheckedContinuation<Void, Never>?
    private var setPINStarted = false
    private var setPINCalls = 0

    init(pin: String? = nil) {
        self.pin = pin
    }

    func hasCredential() async throws -> Bool { pin != nil }

    func setPIN(_ pin: String) async throws {
        setPINCalls += 1
        if shouldSuspendNextSetPIN {
            shouldSuspendNextSetPIN = false
            setPINStarted = true
            setPINWaiter?.resume()
            setPINWaiter = nil
            await withCheckedContinuation { continuation in
                setPINContinuation = continuation
            }
        }
        self.pin = pin
    }

    func verifyPIN(_ pin: String) async throws -> Bool {
        guard shouldSuspendNextVerification else { return self.pin == pin }

        shouldSuspendNextVerification = false
        verificationStarted = true
        verificationWaiter?.resume()
        verificationWaiter = nil
        return await withCheckedContinuation { continuation in
            verificationContinuation = continuation
        }
    }

    func deleteCredential() async throws {
        pin = nil
    }

    func suspendNextVerification() {
        shouldSuspendNextVerification = true
        verificationStarted = false
    }

    func suspendNextSetPIN() {
        shouldSuspendNextSetPIN = true
        setPINStarted = false
    }

    func waitForVerification() async {
        guard !verificationStarted else { return }
        await withCheckedContinuation { continuation in
            verificationWaiter = continuation
        }
    }

    func completeVerification(_ result: Bool) {
        verificationContinuation?.resume(returning: result)
        verificationContinuation = nil
    }

    func waitForSetPIN() async {
        guard !setPINStarted else { return }
        await withCheckedContinuation { continuation in
            setPINWaiter = continuation
        }
    }

    func completeSetPIN() {
        setPINContinuation?.resume()
        setPINContinuation = nil
    }

    func snapshot() -> (pin: String?, setPINCalls: Int) {
        (pin, setPINCalls)
    }
}

private struct VaultAuthenticatorSpy: HistoryAuthenticating {
    let result: HistoryAuthenticationResult

    func authenticate(reason: String) async -> HistoryAuthenticationResult {
        result
    }
}

private actor SuspendingCredentialSpy: PINCredentialStoring {
    private var pin: String?
    private var verificationContinuation: CheckedContinuation<Bool, Never>?
    private var settingContinuation: CheckedContinuation<Void, Never>?
    private var verificationWaiter: CheckedContinuation<Void, Never>?
    private var settingWaiter: CheckedContinuation<Void, Never>?
    private var verificationStarted = false
    private var settingStarted = false

    init(pin: String? = nil) {
        self.pin = pin
    }

    func hasCredential() async throws -> Bool { pin != nil }

    func setPIN(_ pin: String) async throws {
        settingStarted = true
        settingWaiter?.resume()
        settingWaiter = nil
        await withCheckedContinuation { continuation in
            settingContinuation = continuation
        }
        self.pin = pin
    }

    func verifyPIN(_ pin: String) async throws -> Bool {
        verificationStarted = true
        verificationWaiter?.resume()
        verificationWaiter = nil
        return await withCheckedContinuation { continuation in
            verificationContinuation = continuation
        }
    }

    func deleteCredential() async throws {
        pin = nil
    }

    func waitForVerification() async {
        guard !verificationStarted else { return }
        await withCheckedContinuation { continuation in
            verificationWaiter = continuation
        }
    }

    func completeVerification(_ result: Bool) {
        verificationContinuation?.resume(returning: result)
        verificationContinuation = nil
    }

    func waitForSettingPIN() async {
        guard !settingStarted else { return }
        await withCheckedContinuation { continuation in
            settingWaiter = continuation
        }
    }

    func completeSettingPIN() {
        settingContinuation?.resume()
        settingContinuation = nil
    }
}

private actor SuspendingAuthenticator: HistoryAuthenticating {
    private var continuation: CheckedContinuation<HistoryAuthenticationResult, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var started = false

    func authenticate(reason: String) async -> HistoryAuthenticationResult {
        started = true
        waiter?.resume()
        waiter = nil
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitForAuthentication() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func complete(_ result: HistoryAuthenticationResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private enum VaultStoreError: Error, Equatable, Sendable {
    case writeFailed
}

private enum VaultCredentialError: Error, Equatable, Sendable {
    case deleteFailed
}
