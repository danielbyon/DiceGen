# History Privacy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore copied-passphrase history as an opt-in local-only feature protected by a DiceGen PIN, optional LocalAuthentication, persistent brute-force throttling, lifecycle relocking, app-switcher privacy protection, backup exclusion, and loss-aware migration of legacy history.

**Architecture:** Add a focused `History` subsystem: an actor-backed file store owns plaintext history and backup-excluded security metadata; an actor-backed Keychain credential store owns the salted PIN verifier; a LocalAuthentication adapter owns system authentication; a one-time migrator owns legacy `UserDefaults` keys; and a `@MainActor` `HistoryVault` coordinates state without exposing plaintext entries before authorization. SwiftUI consumes only the vault’s published state, while `ContentView` owns scene lifecycle relocking/privacy-cover behavior and existing copy flows record history only after a successful clipboard copy.

**Tech Stack:** Swift, SwiftUI, Foundation, Security, CryptoKit, LocalAuthentication, XCTest/XCUITest, Xcode project file membership.

**Spec:** `docs/superpowers/specs/2026-09-14-history-privacy-design.md`

## Global Constraints

1. History is off by default; no new copied passphrase is persisted until PIN setup completes successfully.
2. Persist history as plaintext under Application Support; do not add history encryption, SwiftData, Core Data, cloud sync, analytics, accounts, or server dependencies.
3. Mark the History directory, `history.json`, and `security.json` with `URLResourceValues.isExcludedFromBackup = true`; reapply the attribute after every atomic file replacement.
4. History has no count or age limit. Duplicate content is represented once; copying it again moves it to the front with a fresh timestamp.
5. The DiceGen PIN accepts ASCII digits only and is 4-12 digits inclusive.
6. PIN verifier v1 is PBKDF2-HMAC-SHA256, 600,000 iterations, 16 random salt bytes, 32 verifier bytes. Store verifier metadata and bytes in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; never store the plaintext PIN.
7. PIN derivation/verification must not synchronously block the main actor.
8. Changing the PIN always requires the current DiceGen PIN even when the current session was unlocked through LocalAuthentication.
9. Forgotten PIN recovery is destructive only: reset history and all security configuration; do not preserve history through LocalAuthentication.
10. Persist PIN failure state and lockout deadline in backup-excluded security metadata. Failures 1-4 have no delay; failure 5 = 30s; failure 6 = 1m; failure 7 = 5m; failure 8 = 15m; failure 9+ = 1h. Submissions during an active lockout do not verify and do not increment the failure count. Only successful DiceGen PIN verification clears accumulated PIN failures.
11. Optional LocalAuthentication uses `LAPolicy.deviceOwnerAuthentication`; system auth success never clears PIN failure state. User cancellation leaves the PIN route available.
12. Unlock state and plaintext UI entries exist only in memory. Any scene state other than `.active` immediately locks the vault, clears published entries, invalidates stale auth completions, and presents an opaque privacy cover. Returning active never auto-unlocks.
13. Disabling History deletes entries, Keychain verifier, LocalAuthentication preference, lockout state, and all persisted history-security configuration. Re-enabling requires full PIN setup.
14. Legacy `savedItems` / `shouldSaveItems` are owned exclusively by migration. Persist migrated entries and notice state successfully before deleting legacy keys; on failure preserve the legacy keys for retry.
15. Migrated entries remain dormant and inaccessible until PIN setup. A one-time notice explains that History now requires setup.
16. A history write failure must not make a successful clipboard copy appear to have failed; instead the History subsystem enters fail-closed recovery state.
17. Current deployment/project settings and Mac Catalyst support must be preserved. Do not lower deployment targets or remove Catalyst support.
18. Use the existing local-only clipboard behavior and in-app-review copy accounting for both generator copies and history copies.
19. Examples below use `-destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro'`. If that simulator name is not installed, substitute an available iPhone simulator without changing the test selection or assertions.

## File Structure

Create focused production files:

- `DiceGen/History/HistoryEntry.swift` — persisted entry model plus backup-excluded security metadata model.
- `DiceGen/History/HistoryStore.swift` — atomic JSON persistence, backup exclusion, duplicate recency behavior, and reset.
- `DiceGen/History/PINCredentialStore.swift` — PIN policy, PBKDF2-HMAC-SHA256, constant-time verifier comparison, Keychain CRUD.
- `DiceGen/History/HistoryAuthenticator.swift` — LocalAuthentication protocol/result and production `LAContext` adapter.
- `DiceGen/History/HistoryMigration.swift` — one-time ownership of legacy history defaults, validation, deduplication, import, notice state, cleanup.
- `DiceGen/History/HistoryVault.swift` — main-actor state machine coordinating setup, PIN auth, lockout, system auth, entries, lifecycle, settings mutations, and reset.
- `DiceGen/Views/History/HistoryUnlockView.swift` — system-auth-first gate with explicit DiceGen PIN path, lockout UI, and Forgot PIN reset.
- `DiceGen/Views/History/PassphraseHistoryView.swift` — authorized list, copy, recency refresh, swipe delete, and Clear All.
- `DiceGen/Views/History/HistorySetupView.swift` — 4-12 digit PIN entry/confirmation and setup commit.
- `DiceGen/Views/History/HistorySettingsView.swift` — protected history settings, LocalAuthentication toggle, disable/reset behavior.
- `DiceGen/Views/History/ChangeHistoryPINView.swift` — current/new/confirm PIN flow that always verifies the current DiceGen PIN.

Create focused tests rather than expanding the existing large test file:

- `DiceGenTests/HistoryStoreTests.swift`
- `DiceGenTests/PINCredentialStoreTests.swift`
- `DiceGenTests/HistoryAuthenticatorTests.swift`
- `DiceGenTests/HistoryMigrationTests.swift`
- `DiceGenTests/HistoryVaultTests.swift`
- `DiceGenUITests/HistoryUITests.swift`

Modify existing integration points only where needed:

- `DiceGen/DiceGenApp.swift`
- `DiceGen/Utilities/UserSettings.swift`
- `DiceGen/Views/ContentView.swift`
- `DiceGen/Views/SecureContentInfoView.swift`
- `DiceGen/Views/PassphraseGeneratorView.swift`
- `DiceGen/Views/SettingsView.swift`
- `DiceGen/Info.plist`
- `DiceGen.xcodeproj/project.pbxproj`
- `DiceGenTests/DiceGenTests.swift`
- `DiceGenUITests/DiceGenUITests.swift`

Keep Xcode groups aligned with the filesystem: add a `History` group under the app group and a nested `History` group under `Views`; add every new Swift source to the correct app/test Sources phase as it is introduced.

---

### Task 1: Add backup-excluded history persistence

**Files:**
- Create: `DiceGen/History/HistoryEntry.swift`
- Create: `DiceGen/History/HistoryStore.swift`
- Create: `DiceGenTests/HistoryStoreTests.swift`
- Modify: `DiceGen.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Foundation filesystem APIs only.
- Produces `HistoryEntry`, `HistorySecurityMetadata`, `HistoryPersisting`, and `HistoryStore`.

- [ ] **Step 1: Write persistence tests first**

Create `HistoryStoreTests.swift` with isolated temporary directories. Cover: empty load; newest-first order; duplicate recopy refreshes timestamp/order; 150 unique entries survive to prove no retention cap; individual delete; Clear All; metadata round-trip; malformed JSON throws rather than partially decoding; reset removes the History directory; backup attributes are true on directory, entry file, and security file after writes.

Representative test:

```swift
func testDuplicateCopyMovesEntryToFrontWithFreshTimestamp() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
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
```

Backup test:

```swift
try await store.recordCopiedPassphrase("alpha", at: .now)
try await store.saveMetadata(.empty)
for url in [root, store.historyFileURL, store.securityFileURL] {
    let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(values.isExcludedFromBackup, true)
}
```

- [ ] **Step 2: Run focused tests and verify missing history types fail compilation**

```bash
xcodebuild test -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' -only-testing:DiceGenTests/HistoryStoreTests
```

- [ ] **Step 3: Implement persisted models and protocol**

`HistoryEntry.swift`:

```swift
import Foundation

struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let content: String
    let savedAt: Date
}

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

enum HistoryStoreError: Error, Equatable {
    case invalidPayload
    case unsupportedMetadataVersion(Int)
}

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
```

- [ ] **Step 4: Implement `HistoryStore` actor**

Use exact filenames `history.json` and `security.json`. `loadEntries()` decodes the entire array, rejects empty content, duplicate IDs, or duplicate content as invalid payload, then returns timestamp-descending order. `replaceEntries` validates/sorts, creates root, writes with `.atomic`, then reapplies backup exclusion to the resulting file and root. `recordCopiedPassphrase` removes identical content, inserts a new UUID/timestamp at index 0, and saves. `loadMetadata` returns `.empty` when missing and rejects unsupported schema versions. `resetAll` removes the entire History root.

Core file-writing helper:

```swift
private func excludeFromBackup(_ url: URL) throws {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutableURL = url
    try mutableURL.setResourceValues(values)
}
```

- [ ] **Step 5: Add files to Xcode project and pass focused tests**

Create app `History` PBXGroup; add production files to app Sources and `HistoryStoreTests.swift` to unit-test Sources.

- [ ] **Step 6: Commit**

```bash
git add DiceGen/History/HistoryEntry.swift DiceGen/History/HistoryStore.swift DiceGenTests/HistoryStoreTests.swift DiceGen.xcodeproj/project.pbxproj
git commit -m "Add local history persistence"
```

---

### Task 2: Add PIN policy, PBKDF2 verifier, and Keychain storage

**Files:**
- Create: `DiceGen/History/PINCredentialStore.swift`
- Create: `DiceGenTests/PINCredentialStoreTests.swift`
- Modify: `DiceGen.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces `HistoryPINPolicy.isValid(_:)`, `PINVerifierParameters.v1`, `PINCredentialStoring`, `KeychainPINCredentialStore`.

- [ ] **Step 1: Write policy, derivation, and Keychain tests**

Generate valid/invalid PIN inputs from repeated single digits rather than hard-coded credential-like strings:

```swift
XCTAssertFalse(HistoryPINPolicy.isValid(String(repeating: "7", count: 3)))
XCTAssertTrue(HistoryPINPolicy.isValid(String(repeating: "7", count: 4)))
XCTAssertTrue(HistoryPINPolicy.isValid(String(repeating: "7", count: 12)))
XCTAssertFalse(HistoryPINPolicy.isValid(String(repeating: "7", count: 13)))
XCTAssertFalse(HistoryPINPolicy.isValid("12a4"))
XCTAssertFalse(HistoryPINPolicy.isValid("１２３４"))
XCTAssertEqual(PINVerifierParameters.v1.iterations, 600_000)
XCTAssertEqual(PINVerifierParameters.v1.saltByteCount, 16)
XCTAssertEqual(PINVerifierParameters.v1.verifierByteCount, 32)
```

Verify PBKDF2-HMAC-SHA256 against standard vectors. Represent standard input and expected digest as byte arrays in the test file so no credential-looking literal is persisted in source comments or strings. For Keychain integration, use a unique test service and a low test-only iteration count; verify correct/incorrect PIN outcomes and inspect the raw Keychain record to ensure entered PIN bytes are absent.

- [ ] **Step 2: Run focused tests and verify missing types fail**

```bash
xcodebuild test -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' -only-testing:DiceGenTests/PINCredentialStoreTests
```

- [ ] **Step 3: Implement policy, parameters, record, and PBKDF2**

```swift
import CryptoKit
import Foundation
import Security

enum HistoryPINPolicy {
    static func isValid(_ pin: String) -> Bool {
        guard (4...12).contains(pin.count) else { return false }
        return pin.unicodeScalars.allSatisfy { (48...57).contains(Int($0.value)) }
    }
}

struct PINVerifierParameters: Codable, Equatable, Sendable {
    let version: Int
    let iterations: Int
    let saltByteCount: Int
    let verifierByteCount: Int
    static let v1 = PINVerifierParameters(version: 1, iterations: 600_000, saltByteCount: 16, verifierByteCount: 32)
}

struct PINVerifierRecord: Codable, Equatable, Sendable {
    let version: Int
    let iterations: Int
    let salt: Data
    let verifier: Data
}
```

Implement PBKDF2-HMAC-SHA256 with CryptoKit HMAC. Because v1 output is exactly 32 bytes, support one SHA-256 output block only; append big-endian block index 1 to salt, compute U1, iterate U2...Uc, XOR into output, and return prefix outputByteCount. Reject non-positive iterations and output sizes outside 1...32.

- [ ] **Step 4: Implement async credential protocol + Keychain actor**

```swift
protocol PINCredentialStoring: Sendable {
    func hasCredential() async throws -> Bool
    func setPIN(_ pin: String) async throws
    func verifyPIN(_ pin: String) async throws -> Bool
    func deleteCredential() async throws
}
```

`KeychainPINCredentialStore` actor requirements:

1. `setPIN` validates PIN, gets 16 bytes from `SecRandomCopyBytes`, derives verifier using configured parameters, JSON-encodes `PINVerifierRecord`, then upserts generic-password data.
2. Keychain item has exact service/account, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`.
3. `verifyPIN` rejects invalid format as false, decodes record, rejects unsupported version, derives candidate using record salt/iterations, then constant-time compares.
4. `deleteCredential` treats `errSecItemNotFound` as success.
5. CPU derivation occurs on this actor, never on `HistoryVault` main actor.

Constant-time helper:

```swift
private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).reduce(UInt8(0)) { result, pair in result | (pair.0 ^ pair.1) } == 0
}
```

- [ ] **Step 5: Add project membership and pass focused tests**

- [ ] **Step 6: Commit**

```bash
git add DiceGen/History/PINCredentialStore.swift DiceGenTests/PINCredentialStoreTests.swift DiceGen.xcodeproj/project.pbxproj
git commit -m "Add protected history PIN credentials"
```

---

### Task 3: Add LocalAuthentication adapter

**Files:**
- Create: `DiceGen/History/HistoryAuthenticator.swift`
- Create: `DiceGenTests/HistoryAuthenticatorTests.swift`
- Modify: `DiceGen.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
enum HistoryAuthenticationResult: Equatable, Sendable { case success, cancelled, unavailable, failed }
protocol HistoryAuthenticating: Sendable { func authenticate(reason: String) async -> HistoryAuthenticationResult }
```

- [ ] **Step 1: Write evaluator-driven tests**

Use an injected evaluator fake to verify production passes exactly `.deviceOwnerAuthentication`; success maps to `.success`; user/app/system cancel and user fallback map to `.cancelled`; inability to evaluate maps to `.unavailable`; generic auth failure maps to `.failed`. No test may invoke real biometrics/passcode UI.

- [ ] **Step 2: Run focused tests and verify missing types fail**

```bash
xcodebuild test -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' -only-testing:DiceGenTests/HistoryAuthenticatorTests
```

- [ ] **Step 3: Implement auth boundary**

```swift
import LocalAuthentication

enum HistoryAuthenticationResult: Equatable, Sendable {
    case success, cancelled, unavailable, failed
}

protocol HistoryAuthenticating: Sendable {
    func authenticate(reason: String) async -> HistoryAuthenticationResult
}

protocol LocalAuthenticationEvaluating: Sendable {
    func canEvaluate(_ policy: LAPolicy) async -> Bool
    func evaluate(_ policy: LAPolicy, reason: String) async throws -> Bool
}
```

`LocalHistoryAuthenticator` hard-codes `.deviceOwnerAuthentication`, maps LAError codes as described above, and delegates through `LAContextEvaluator`. `LAContextEvaluator` creates a fresh LAContext per evaluation and bridges callback APIs with checked continuation if needed; do not retain a context across sessions.

- [ ] **Step 4: Add project membership and pass tests**

- [ ] **Step 5: Commit**

```bash
git add DiceGen/History/HistoryAuthenticator.swift DiceGenTests/HistoryAuthenticatorTests.swift DiceGen.xcodeproj/project.pbxproj
git commit -m "Add history system authentication"
```

---

### Task 4: Migrate legacy history before deleting old defaults

**Files:**
- Create: `DiceGen/History/HistoryMigration.swift`
- Create: `DiceGenTests/HistoryMigrationTests.swift`
- Modify: `DiceGen/Utilities/UserSettings.swift:9-46`
- Modify: `DiceGenTests/DiceGenTests.swift:261-270`
- Modify: `DiceGen.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
@MainActor protocol HistoryMigrating { func migrateIfNeeded() async throws }
```

- [ ] **Step 1: Reverse old UserSettings cleanup test**

Replace current deletion expectation with a test proving `UserSettings` leaves both legacy keys untouched for `HistoryMigration`.

```swift
func testUserSettingsLeavesLegacyHistoryForHistoryMigration() {
    withIsolatedDefaults { defaults in
        defaults.set([["content": "old-value", "savedAt": Date(timeIntervalSince1970: 100)]], forKey: "savedItems")
        defaults.set(true, forKey: "shouldSaveItems")
        _ = UserSettings(defaults: defaults)
        XCTAssertNotNil(defaults.object(forKey: "savedItems"))
        XCTAssertNotNil(defaults.object(forKey: "shouldSaveItems"))
    }
}
```

- [ ] **Step 2: Write migration tests**

Cover valid/malformed dictionaries, newest duplicate retention, retry idempotence when new store already contains imported content, prior-enabled with zero entries still sets migration notice, successful migration deletes both old keys, and any required new-store write failure preserves both keys.

- [ ] **Step 3: Run focused tests and verify expected failure**

```bash
xcodebuild test -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' -only-testing:DiceGenTests/HistoryMigrationTests -only-testing:DiceGenTests/DiceGenTests/testUserSettingsLeavesLegacyHistoryForHistoryMigration
```

- [ ] **Step 4: Remove legacy key ownership from `UserSettings`**

Delete both legacy key constants and both `removeObject` calls. Do not add history state to UserSettings.

- [ ] **Step 5: Implement loss-aware migration**

```swift
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
        if !merged.isEmpty || !existing.isEmpty { try await store.replaceEntries(merged) }

        var metadata = try await store.loadMetadata()
        if oldEnabled || !legacy.isEmpty {
            metadata.migrationNoticePending = true
            try await store.saveMetadata(metadata)
        }

        defaults.removeObject(forKey: Self.savedItemsKey)
        defaults.removeObject(forKey: Self.shouldSaveItemsKey)
    }
}
```

Accept only non-empty String content + Date timestamp. Sort combined entries newest-first and retain first content occurrence. Delete old keys only after all required new-store writes succeed.

- [ ] **Step 6: Add project membership and pass focused tests**

- [ ] **Step 7: Commit**

```bash
git add DiceGen/History/HistoryMigration.swift DiceGen/Utilities/UserSettings.swift DiceGenTests/HistoryMigrationTests.swift DiceGenTests/DiceGenTests.swift DiceGen.xcodeproj/project.pbxproj
git commit -m "Migrate legacy passphrase history"
```

---

### Task 5: Implement HistoryVault initialization, setup, PIN auth, and persistent lockout

**Files:**
- Create: `DiceGen/History/HistoryVault.swift`
- Create: `DiceGenTests/HistoryVaultTests.swift`
- Modify: `DiceGen.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
enum HistoryVaultState: Equatable {
    case initializing, disabled, setupRequired, locked, unlocked
    case failed(HistoryVaultFailure)
}

enum HistoryVaultFailure: Equatable { case storage, credential, inconsistentSecurityState }
enum HistoryPINResult: Equatable { case success, incorrect, locked(until: Date), failed }
```

Published/read-only surface:

```swift
@Published private(set) var state: HistoryVaultState
@Published private(set) var entries: [HistoryEntry]
@Published private(set) var lockoutUntil: Date?
var isConfigured: Bool { get }
var localAuthenticationEnabled: Bool { get }
var migrationNoticePending: Bool { get }
```

Methods in this task:

```swift
func initialize() async
func setSceneActive(_ active: Bool)
func configureHistory(pin: String) async -> Bool
func authenticateWithPIN(_ pin: String) async -> HistoryPINResult
```

- [ ] **Step 1: Write initialization/setup tests with actor fakes**

Verify: fresh -> disabled; dormant migrated entries -> setupRequired with published entries empty; configured metadata+credential -> locked; mismatched credential/config -> fail closed; successful setup writes credential then metadata; metadata failure rolls back newly created credential; invalid PIN writes nothing.

Generate test PIN values using `String(repeating: "7", count: 4)` so tests do not commit literal credential examples. In every setup/PIN-auth test, call `vault.setSceneActive(true)` before invoking methods that can unlock; tests that exercise background races then deliberately switch it back to false while the credential operation is suspended.

- [ ] **Step 2: Write deterministic lockout tests with injected clock**

Verify exact penalties for failure counts 5, 6, 7, 8, and 9+; active lockout rejects without invoking credential verifier and without incrementing; state survives reconstructing a second vault against same store metadata; successful PIN clears count/deadline only after metadata persistence succeeds; successful system auth is not part of this path. Add controllable credential-store tests where `verifyPIN` or `setPIN` suspends, call `setSceneActive(false)` while PBKDF2/credential work is in flight, then complete successfully and assert the vault does not publish `.unlocked` or plaintext entries. A successful setup that finishes after background may remain configured, but it must finish in `.locked` state with `entries` empty.

- [ ] **Step 3: Run focused tests and verify missing vault types fail**

```bash
xcodebuild test -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' -only-testing:DiceGenTests/HistoryVaultTests
```

- [ ] **Step 4: Implement vault shell and initialization**

```swift
@MainActor
final class HistoryVault: ObservableObject {
    @Published private(set) var state: HistoryVaultState = .initializing
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var lockoutUntil: Date?

    private let store: any HistoryPersisting
    private let credentials: any PINCredentialStoring
    private let authenticator: any HistoryAuthenticating
    private let migration: any HistoryMigrating
    private let now: () -> Date
    private var metadata: HistorySecurityMetadata = .empty
    private var sceneIsActive = false
    private var sessionGeneration: UInt = 0

    var isConfigured: Bool { metadata.isConfigured }
    var localAuthenticationEnabled: Bool { metadata.localAuthenticationEnabled }
    var migrationNoticePending: Bool { metadata.migrationNoticePending }
}
```

`initialize()` runs migration first, then reads metadata, credential existence, and hasEntries without loading plaintext into published entries. State table: unconfigured/no credential/no entries -> disabled; unconfigured/no credential/entries -> setupRequired; configured+credential -> locked; config/credential mismatch -> failed inconsistent; store error -> failed storage; credential query error -> failed credential.

Implement `setSceneActive(_:)` in this task because setup and PIN verification already depend on its generation guard. Setting inactive synchronously clears `entries`, increments `sessionGeneration`, and moves a configured non-failed vault to `.locked`; setting active changes only `sceneIsActive` and never unlocks. This minimal lifecycle behavior is expanded with LocalAuthentication coverage in Task 6.

- [ ] **Step 5: Implement transactional setup**

Setup is allowed only in disabled/setupRequired and only while the scene is active. Capture `sessionGeneration` before awaiting credential work. Validate PIN, create credential, persist configured metadata with LocalAuthentication false/failures reset, then load dormant entries only if the scene is still active and the generation is unchanged. If setup succeeds after the app became inactive, keep the persisted configuration but finish `.locked` with `entries` empty; never publish a stale unlocked session. If metadata save fails, reconcile the actual persisted metadata and credential instead of assuming the write was absent: if configuration did not commit, delete the newly created credential and remain unconfigured; if configuration committed but backup/persistence post-processing failed, preserve fail-closed consistency and enter recovery state. If rollback/reconciliation itself fails, enter `.failed(.inconsistentSecurityState)`. If dormant history is corrupt after setup, fail closed rather than exposing partial entries.

- [ ] **Step 6: Implement persistent PIN auth**

```swift
private func lockoutDuration(afterFailedAttempts count: Int) -> TimeInterval? {
    switch count {
    case ...4: nil
    case 5: 30
    case 6: 60
    case 7: 5 * 60
    case 8: 15 * 60
    default: 60 * 60
    }
}
```

Active deadline returns locked without verifier call/increment. Before awaiting `credentials.verifyPIN`, capture `sessionGeneration`; an incorrect PIN still updates/persists failure state even if the scene changes, because brute-force accounting must survive backgrounding. A correct PIN clears count/deadline and persists that first, but it may load/publish entries and set `.unlocked` only when the scene is active and the captured generation is unchanged. If correct verification completes after backgrounding, keep the cleared PIN-failure metadata but finish `.locked` with `entries` empty. Keychain/store errors fail closed.

- [ ] **Step 7: Add project membership and pass focused tests**

- [ ] **Step 8: Commit**

```bash
git add DiceGen/History/HistoryVault.swift DiceGenTests/HistoryVaultTests.swift DiceGen.xcodeproj/project.pbxproj
git commit -m "Add protected history vault state"
```

---

### Task 6: Complete vault lifecycle, LocalAuthentication, content mutations, PIN change, and reset

**Files:**
- Modify: `DiceGen/History/HistoryVault.swift`
- Modify: `DiceGenTests/HistoryVaultTests.swift`

**Interfaces added:**

```swift
func authenticateWithSystem() async -> HistoryAuthenticationResult
func recordCopiedPassphrase(_ content: String) async
func deleteEntry(id: UUID) async
func clearAll() async
func setLocalAuthenticationEnabled(_ enabled: Bool) async -> Bool
func changePIN(currentPIN: String, newPIN: String) async -> HistoryPINResult
func disableHistory() async
func resetHistory() async
func consumeMigrationNotice() async
```

- [ ] **Step 1: Add lifecycle/stale-auth tests**

Use controllable authenticator: begin auth, mark scene inactive, complete success, assert vault remains locked and entries empty. Verify returning active does not unlock.

- [ ] **Step 2: Add content/security mutation tests**

Cover record while locked; duplicate recency while unlocked; no-op record while disabled/setupRequired; storage error after record -> fail closed; delete/Clear All only while unlocked; LocalAuthentication preference only while unlocked; system auth success without clearing PIN failures; system cancel/unavailable/failure stay locked; Change PIN always verifies current PIN and uses lockout; Disable History requires unlocked; reset works without auth; reset clears store+credential; migration notice consumption persists.

- [ ] **Step 3: Run vault tests and observe missing-method failures**

- [ ] **Step 4: Extend the existing scene-generation guard to system auth**

Keep the `setSceneActive(_:)` behavior introduced in Task 5 unchanged. System auth requires configured+opted-in+active, captures `sessionGeneration` before await, and after success requires the same generation plus active scene before loading entries. Never mutate PIN failure count/deadline. The new lifecycle tests in this task specifically prove the existing scene guard also invalidates an in-flight LocalAuthentication completion.

- [ ] **Step 5: Implement content mutations**

`recordCopiedPassphrase` is allowed while configured and locked; use injected `now()`. If unlocked, reload after save for recency. If unconfigured, no-op. Storage errors clear entries/fail closed. Delete/Clear All guard unlocked and persist before updating published state.

- [ ] **Step 6: Implement security mutations and reset**

LocalAuthentication toggle saves metadata only from unlocked state. Change PIN verifies current PIN with same lockout rules, persists cleared failure state, validates new PIN, then replaces credential. Reset immediately clears entries/increments generation, attempts `store.resetAll()` and `credentials.deleteCredential()`, returns disabled only if both succeed, otherwise inconsistent failure. Disable guards unlocked then calls reset; reset itself deliberately has no auth guard.

- [ ] **Step 7: Run all unit tests**

```bash
xcodebuild test -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' -only-testing:DiceGenTests
```

- [ ] **Step 8: Commit**

```bash
git add DiceGen/History/HistoryVault.swift DiceGenTests/HistoryVaultTests.swift
git commit -m "Complete history vault protection"
```

---

### Task 7: Wire vault startup, clipboard recording, and scene privacy

**Files:**
- Modify: `DiceGen/DiceGenApp.swift:10-69`
- Modify: `DiceGen/Views/ContentView.swift:9-30`
- Modify: `DiceGen/Views/SecureContentInfoView.swift:7-48`
- Modify: directly affected previews.

- [ ] **Step 1: Extend runtime configuration with history dependencies**

Add `historyRootURL`, `historyCredentialStore`, `historyAuthenticator`. Production uses default HistoryStore root, bundle-scoped Keychain service, LocalHistoryAuthenticator.

For `--ui-testing`, clear a deterministic temp History directory and use private fakes:

```swift
private actor UITestPINCredentialStore: PINCredentialStoring {
    private var pin: String?
    func hasCredential() async throws -> Bool { pin != nil }
    func setPIN(_ pin: String) async throws { self.pin = pin }
    func verifyPIN(_ pin: String) async throws -> Bool { self.pin == pin }
    func deleteCredential() async throws { pin = nil }
}

private struct UITestHistoryAuthenticator: HistoryAuthenticating {
    let result: HistoryAuthenticationResult
    func authenticate(reason: String) async -> HistoryAuthenticationResult { result }
}
```

Default UI-test auth result is cancelled; launch argument `--ui-testing-local-auth-success` selects success.

- [ ] **Step 2: Create/inject one app-level vault**

Construct HistoryStore + HistoryMigration + HistoryVault in DiceGenApp init; store as StateObject and inject as environment object. Never create child vault instances.

- [ ] **Step 3: Initialize/relock in `ContentView` + privacy cover**

Add scenePhase/vault environment. Wrap navigation in ZStack and overlay opaque system background whenever scenePhase != active. Initial task calls `setSceneActive(scenePhase == .active)` then `await initialize()` while preserving existing one-time review launch accounting. Scene changes call setSceneActive.

- [ ] **Step 4: Record only after successful generator copy**

Keep `guard copyAction.copy(passphrase) else { return }` first; update copy feedback; then `Task { await historyVault.recordCopiedPassphrase(passphrase) }`. Never record Generate actions.

- [ ] **Step 5: Add safe preview factory**

`HistoryVault.preview()` uses unique temp root, unique UserDefaults suite, unique Keychain service. Update previews requiring history environment; preview migration must never use standard defaults.

- [ ] **Step 6: Run unit tests**

```bash
xcodebuild test -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' -only-testing:DiceGenTests
```

- [ ] **Step 7: Commit**

```bash
git add DiceGen/DiceGenApp.swift DiceGen/History/HistoryVault.swift DiceGen/Views/ContentView.swift DiceGen/Views/SecureContentInfoView.swift DiceGen/Views/PassphraseGeneratorView.swift
git commit -m "Wire protected history into app lifecycle"
```

---

### Task 8: Add authenticated history list and unlock UI

**Files:**
- Create: `DiceGen/Views/History/HistoryUnlockView.swift`
- Create: `DiceGen/Views/History/PassphraseHistoryView.swift`
- Modify: `DiceGen/Views/PassphraseGeneratorView.swift:13-55`
- Modify: `DiceGen.xcodeproj/project.pbxproj`

- [ ] **Step 1: Implement system-auth-first unlock UI**

Auto-attempt system auth once per appearance when preference enabled; otherwise show SecureField label `History PIN`. Always offer `Use DiceGen PIN` while system auth is enabled. `Unlock` calls vault PIN auth. Wrong PIN clears typed input. Lockout countdown uses TimelineView periodic once per second; timer does not mutate attempts. `Forgot PIN?` shows destructive confirmation that reset permanently deletes history, then calls reset with an onReset closure.

- [ ] **Step 2: Implement state-driven history view**

Initializing -> progress; locked -> HistoryUnlockView; unlocked -> list; failed -> reset-only recovery; disabled/setupRequired -> no plaintext + unavailable content.

Unlocked list:

```swift
List {
    ForEach(historyVault.entries) { entry in
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.content).textSelection(.enabled)
            Text(entry.savedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contextMenu { Button("Copy") { copy(entry) } }
        .swipeActions {
            Button("Delete", role: .destructive) {
                Task { await historyVault.deleteEntry(id: entry.id) }
            }
        }
    }
}
```

When unlocked/empty render `ContentUnavailableView("No History Yet", systemImage: "clock")`. Copy uses existing PassphraseCopyAction; after successful copy call vault record again to refresh recency. Toolbar `Clear All` confirms with button `Clear History`; it only clears entries.

- [ ] **Step 3: Add generator entry point only when configured**

NavigationLink label exactly `View Passphrase History`; destination gets existing review requester. Dormant migrated setupRequired state does not show row.

- [ ] **Step 4: Add nested `Views/History` group + app Sources membership**

- [ ] **Step 5: Build/run unit tests**

- [ ] **Step 6: Commit**

```bash
git add DiceGen/Views/History/HistoryUnlockView.swift DiceGen/Views/History/PassphraseHistoryView.swift DiceGen/Views/PassphraseGeneratorView.swift DiceGen.xcodeproj/project.pbxproj
git commit -m "Restore protected passphrase history UI"
```

---

### Task 9: Add History settings, setup/change PIN, migration notice, and Face ID copy

**Files:**
- Create: `DiceGen/Views/History/HistorySetupView.swift`
- Create: `DiceGen/Views/History/HistorySettingsView.swift`
- Create: `DiceGen/Views/History/ChangeHistoryPINView.swift`
- Modify: `DiceGen/Views/SettingsView.swift:29-56`
- Modify: `DiceGen/Views/PassphraseGeneratorView.swift`
- Modify: `DiceGen/Info.plist:6-40`
- Modify: `DiceGen.xcodeproj/project.pbxproj`

- [ ] **Step 1: Implement first-time setup**

HistorySetupView secure fields labels: `PIN`, `Confirm PIN`; numeric keyboard; `Enable History` button enabled only for valid matching PINs. Footer: `Use 4-12 digits. DiceGen cannot recover this PIN without deleting history.` Successful configure clears local typed state and dismisses. Do not automatically enable system auth.

- [ ] **Step 2: Implement Change PIN**

Fields: `Current PIN`, `New PIN`, `Confirm New PIN`; button `Change PIN`. Call vault change method. Incorrect/locked/failed are displayed without content exposure; success clears state/dismisses. No system-auth-only PIN replacement path.

- [ ] **Step 3: Implement `HistorySettingsView` state machine**

Initializing -> progress. Disabled/setupRequired -> explanation + `Enable History` link; setupRequired mentions migrated history becomes accessible after setup. Locked -> HistoryUnlockView. Unlocked -> toggle `Use Face ID / Touch ID / Device Passcode`, Change PIN link, destructive `Disable History`. Failed -> reset-only recovery.

Disable confirmation action text: `Delete History and Disable`; message states saved history and protection settings are permanently removed.

- [ ] **Step 4: Add top-level Settings History row**

NavigationLink label `History`; trailing status one of `Off`, `Setup Required`, `On`, `Needs Reset`. Never show entry count/content while locked.

- [ ] **Step 5: Add one-time migration notice**

Alert title `History now requires a PIN`. Message: `Existing history was moved to private local storage. Set a PIN in Settings > History to access it and resume saving copied passphrases.` `OK` calls consumeMigrationNotice; dismissal never deletes dormant entries.

- [ ] **Step 6: Add Face ID plist description**

```xml
<key>NSFaceIDUsageDescription</key>
<string>Use Face ID to unlock your private passphrase history.</string>
```

- [ ] **Step 7: Add project membership and run unit tests**

```bash
xcodebuild test -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' -only-testing:DiceGenTests
```

- [ ] **Step 8: Commit**

```bash
git add DiceGen/Views/History/HistorySetupView.swift DiceGen/Views/History/HistorySettingsView.swift DiceGen/Views/History/ChangeHistoryPINView.swift DiceGen/Views/SettingsView.swift DiceGen/Views/PassphraseGeneratorView.swift DiceGen/Info.plist DiceGen.xcodeproj/project.pbxproj
git commit -m "Add history privacy settings"
```

---

### Task 10: Add deterministic UI coverage and final validation

**Files:**
- Create: `DiceGenUITests/HistoryUITests.swift`
- Modify: `DiceGenUITests/DiceGenUITests.swift:11-37`
- Modify: `DiceGen/DiceGenApp.swift` only if accessibility/runtime seams require correction.
- Modify: `DiceGen.xcodeproj/project.pbxproj`

- [ ] **Step 1: Update existing smoke test**

Keep generator History row absent on fresh launch. In Settings assert `History` exists while legacy `Save copied passphrases/passwords` and `Clear passphrase/password history` controls remain absent.

- [ ] **Step 2: Add setup/copy/relock/PIN-unlock/Clear All UI test**

Use `let testPIN = String(repeating: "7", count: 4)` inside the test. Launch with `--ui-testing`, open Settings > History > Enable History, type testPIN into `PIN` and `Confirm PIN`, submit, return generator. Trigger Generate without copying, open History, assert `No History Yet`; return and copy, reopen History, assert nonempty. Press Home and reactivate, assert `History PIN` field appears; enter testPIN and tap `Unlock`; assert `Passphrase History` visible. Tap `Clear All`, confirm `Clear History`, assert `No History Yet`.

- [ ] **Step 3: Add destructive-disable UI test**

Set up with generated test PIN. While History settings unlocked, tap `Disable History`, confirm `Delete History and Disable`; return generator and assert history row absent. Reopen Settings > History and assert `Enable History`, proving full reset rather than pause.

- [ ] **Step 4: Add deterministic LocalAuthentication success UI test**

Launch with `--ui-testing-local-auth-success`, set up with generated test PIN, enable system-auth toggle, copy a passphrase, open History, background/reactivate. Assert history list returns without PIN entry and `History PIN` field is absent. This exercises injected system authentication rather than simulator biometric configuration.

- [ ] **Step 5: Add `HistoryUITests.swift` to UI-test Sources and run it**

```bash
xcodebuild test -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' -only-testing:DiceGenUITests/HistoryUITests
```

- [ ] **Step 6: Run complete iOS suite**

```bash
xcodebuild test -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro'
```

- [ ] **Step 7: Build Mac Catalyst**

```bash
xcodebuild build -project DiceGen.xcodeproj -scheme DiceGen -destination 'platform=macOS,variant=Mac Catalyst'
```

- [ ] **Step 8: Validate the approved PBKDF2 work factor on hardware if available**

On the oldest supported physical iPhone available to the developer, run a Release build and time one PIN setup plus one correct and one incorrect PIN verification. Record the observed latency in the implementation review notes. If hardware is unavailable, keep the approved 600,000-iteration work factor unchanged; do not tune security parameters from simulator timing. If physical-device latency is unacceptable, stop and revisit the design rather than silently lowering the iteration count.

- [ ] **Step 9: Inspect final privacy invariants before commit**

Verify: legacy keys appear only in migration/tests; no history in normal UserDefaults; no plaintext PIN persistence/logging; Face ID usage key exists; backup exclusion reapplied after both file writes; system auth never clears PIN failures; inactive scene clears entries synchronously; reset removes files+credential; clipboard success is independent of history write; every new source is exactly once in correct Sources phase.

- [ ] **Step 10: Commit**

```bash
git add DiceGen DiceGenTests DiceGenUITests DiceGen.xcodeproj/project.pbxproj
git commit -m "Cover protected history flows"
```

## Completion Criteria

1. Fresh install has no generator History row and records no copies before PIN setup.
2. Configured history stores only copied values, newest first, without retention cap; duplicate copies refresh timestamp/order.
3. History/security files are under Application Support and excluded from backup after replacement.
4. Keychain stores only versioned salted PBKDF2 verifier state with approved v1 parameters and device-only accessibility.
5. PIN lockout schedule persists across vault reconstruction/relaunch and cannot be bypassed by active-lockout submissions or LocalAuthentication.
6. `.deviceOwnerAuthentication` can unlock when opted in, while current DiceGen PIN remains mandatory for PIN change.
7. Every non-active scene transition clears plaintext UI entries, locks, invalidates stale auth completion, and covers the full UI; foreground never auto-unlocks.
8. Forgot PIN/reset and Disable History destroy entries plus security configuration; re-enable requires setup.
9. Legacy valid history migrates before old defaults are deleted, stays dormant until setup, and triggers one dismissible notice; migration failure preserves old defaults.
10. Corrupt/inconsistent state fails closed with destructive reset only.
11. Existing clipboard locality, review accounting, generator behavior, settings links, IAP behavior, deployment settings, and Catalyst support remain intact.
12. Full iOS unit/UI tests and Mac Catalyst build pass.
