# History Privacy Design

**Date:** 2026-09-14

## Summary

DiceGen will restore passphrase history as an opt-in, local-only feature. History records only passphrases the user explicitly copies. History data is stored as plaintext because the threat model is limited to preventing unauthorized access through DiceGen's UI, not defending against filesystem extraction or device compromise.

History remains inaccessible until the user configures a DiceGen PIN. The PIN is always the baseline credential. Users may optionally enable LocalAuthentication as a convenience unlock path. When LocalAuthentication is enabled, DiceGen uses `LAPolicy.deviceOwnerAuthentication`, allowing Face ID or Touch ID with the system device passcode as Apple's fallback. The DiceGen PIN remains independently available from the auth UI.

History storage must be excluded from iCloud/device backup using `URLResourceValues.isExcludedFromBackup`. DiceGen will reapply the exclusion after writes because file operations can reset URL resource attributes. This is the strongest backup-exclusion mechanism provided by iOS; it is guidance to the backup subsystem rather than cryptographic prevention.

## Goals

1. Restore useful copied-passphrase history without returning to the previous unprotected `UserDefaults` implementation.
2. Require an app-specific PIN before history is recorded or viewed.
3. Optionally allow system owner authentication through LocalAuthentication.
4. Re-lock protected history whenever DiceGen leaves the foreground.
5. Prevent history content from appearing in app-switcher snapshots.
6. Keep all history data local and excluded from backup.
7. Preserve valid legacy history from older versions without exposing it before new protection is configured.
8. Keep the implementation proportional to DiceGen: a small isolated subsystem, not a database or generalized security framework.

## Non-goals

1. History-at-rest encryption.
2. Protection from a compromised device, filesystem extraction, debugger access, or an attacker with access outside DiceGen's UI.
3. Cloud sync or multi-device history.
4. PIN recovery that preserves history.
5. A server dependency or remote recovery credential.
6. SwiftData/Core Data persistence.
7. A retention limit or automatic age-based deletion.
8. Recording passphrases merely because they were generated.

## Security and Privacy Invariants

These invariants are authoritative and should be preserved even if implementation details change:

1. **No new history recording before protection setup.** New history recording is disabled until the user has configured a valid DiceGen PIN. Legacy entries may already exist in the migrated local store, but they remain inaccessible and are not published into UI state before successful setup and unlock.
2. **PIN is the baseline credential.** LocalAuthentication is optional and never replaces the configured DiceGen PIN.
3. **No plaintext PIN.** DiceGen stores only a salted, versioned PIN verifier in Keychain.
4. **No PIN recovery preserving history.** Changing the PIN always requires the current DiceGen PIN. A forgotten PIN can only be handled by resetting protection, which destroys history.
5. **History is plaintext by design.** The application-level authorization boundary is intentional; storage encryption is outside the threat model.
6. **History is local-only.** History data is excluded from backup and is not synced.
7. **Unlock state is ephemeral.** An unlocked history session exists only in memory and never survives the app leaving the active foreground state.
8. **No sensitive snapshot.** History content must be covered before app-switcher snapshots can expose it.
9. **Fail closed.** Corrupt storage, missing credentials, inconsistent security state, or authentication subsystem failures must never expose history without successful authorization.
10. **Migration is loss-aware.** Legacy data is deleted only after its replacement has been persisted successfully.
11. **Disabling history is destructive.** Disabling removes history data and all protection configuration, requiring full setup to enable history again.

## Prior Behavior Being Restored

The pre-modernization implementation stored history in `UserDefaults` under `savedItems` and `shouldSaveItems`. It:

- saved only copied passphrases;
- stored content and a timestamp;
- deduplicated by passphrase content;
- showed `View Passphrase History` on the generator screen when saving was enabled;
- exposed save-history and clear-history controls in Settings;
- deleted history when history saving was disabled.

The restored feature keeps the useful product semantics while replacing the unprotected persistence and access model.

## Chosen Architecture

Use a small `HistoryVault` subsystem with focused collaborators.

### `HistoryVault`

A main-actor observable controller owns the feature's user-facing state and coordinates storage and authentication. Its state should make invalid combinations difficult to represent. Conceptually, it covers:

- feature disabled/unconfigured with no retained history;
- setup required with dormant migrated history that cannot yet be viewed;
- feature enabled but locked;
- feature enabled and unlocked;
- PIN lockout with a deadline;
- unrecoverable/corrupt state requiring destructive reset.

It owns session-level state only; persistence and platform APIs live behind dedicated collaborators.

### `HistoryStore`

Owns plaintext history persistence in Application Support. Responsibilities:

- load and validate history;
- save atomically;
- apply/reapply backup exclusion;
- insert/update copied passphrases;
- delete one entry;
- clear all entries;
- import legacy entries.

### `PINCredentialStore`

Owns the PIN verifier in Keychain and the verifier format/version. It must never expose or persist the PIN itself.

The Keychain item should use an accessibility class equivalent to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so the credential does not migrate to another device independently of the local-only history.

### `HistoryAuthenticator`

Wraps LocalAuthentication behind an injectable interface. Production uses `LAContext`; tests use deterministic fakes. When enabled, authentication evaluates `deviceOwnerAuthentication`.

### `HistoryMigration`

Runs before current `UserSettings` initialization can remove legacy history keys. It is responsible only for the one-time migration contract and should not become a general migration framework.

### Why this architecture

A single giant history object would mix filesystem, Keychain, LocalAuthentication, migration, UI session state, and backup behavior, making security invariants harder to test. Conversely, a fully abstract coordinator/service graph is unnecessary for DiceGen. The chosen split creates direct test seams around the risky boundaries without over-engineering the app.

## Persistence Model

### Location

Persist history under a dedicated Application Support path, for example:

`Library/Application Support/<bundle-id>/History/history.json`

Backup-excluded history security metadata lives beside the entry payload under the same History directory. The exact leaf naming is an implementation detail, but neither the history payload nor its device-local security state should live in normal backed-up `UserDefaults`.

### Backup exclusion

The history directory and history file are marked with `isExcludedFromBackup = true`.

The store must reapply the exclusion after creating or replacing the file. Tests should verify the URL resource value where the platform permits it.

This requirement means "excluded using the platform-supported backup exclusion mechanism," not a claim that an app can cryptographically prevent every possible external backup mechanism.

### Entry model

Each entry contains:

- stable identifier;
- passphrase content;
- saved timestamp.

Entries are ordered newest first.

### Duplicate behavior

History contains at most one entry for identical passphrase content. Copying a passphrase already in history removes the prior entry and reinserts it at the top with a fresh timestamp. This intentionally differs from the old implementation, which left the original timestamp unchanged; the new model represents recency of use.

### Retention

There is no count or time limit. Entries remain until individually deleted, cleared, history is disabled/reset, or the app is removed.

### Atomicity and corruption

Writes must be atomic enough that interruption cannot intentionally expose a partially written payload. On read, invalid/corrupt payloads must not be partially decoded into visible history. The feature enters a fail-closed state and offers a destructive `Reset History` action.

## PIN Model

### Format

The DiceGen PIN is numeric and 4-12 digits inclusive.

PIN setup requires entry and confirmation before credentials are committed.

### Verifier storage

Version 1 uses PBKDF2-HMAC-SHA256 with 600,000 iterations, a cryptographically random 16-byte salt, and a 32-byte derived verifier. The Keychain record stores the verifier format version, salt, iteration count, and derived verifier so a future version can raise the work factor or change algorithms without ambiguity. Verification compares derived bytes without an early-exit string comparison.

PBKDF2 derivation must not synchronously block the main actor; the credential boundary should expose asynchronous verification/setup while preserving serialized state transitions in `HistoryVault`.

If profiling on the minimum supported hardware shows this work factor creates unacceptable interactive latency, implementation must revisit the design rather than silently weakening the cost.

Do not store the PIN in plaintext in Keychain, `UserDefaults`, files, logs, analytics, or crash metadata.

### Changing the PIN

Changing the PIN always requires the current DiceGen PIN, even if the current history session was unlocked through LocalAuthentication. This preserves the invariant that LocalAuthentication cannot become an implicit PIN-recovery mechanism.

After the current PIN verifies, the user enters and confirms the replacement PIN. A successful change replaces the stored verifier.

### Forgotten PIN

The PIN cannot be recovered. `Forgot PIN` explains that resetting protection permanently deletes history. After destructive confirmation, it performs the same full reset as disabling history.

Because this path only destroys protected data and configuration, it does not require successful PIN or LocalAuthentication first; otherwise a genuinely forgotten PIN could make the app unrecoverable. LocalAuthentication must not preserve history through this reset path.

## PIN Brute-force Protection

Failed PIN state survives process termination so force-quitting cannot reset the defense.

Persist the following in backup-excluded, device-local history security metadata rather than normal backed-up `UserDefaults`:

- accumulated failed-attempt state needed to determine the next penalty;
- current lockout-until timestamp when applicable;
- whether History is configured/enabled;
- whether LocalAuthentication is enabled.

This metadata is separate from the plaintext entry payload but is deleted by the same full reset. The Keychain verifier remains the authority for PIN verification.

The selected schedule is:

- failures 1-4: no delay;
- failure 5: 30 seconds;
- next failure after the delay: 1 minute;
- next: 5 minutes;
- next: 15 minutes;
- next: 1 hour;
- subsequent failures: remain capped at 1 hour.

While a lockout deadline is active, PIN submissions are rejected without running verification and without advancing the failure count. Escalation occurs only when an incorrect PIN is submitted after the current lockout has expired.

A successful DiceGen PIN verification clears the accumulated failure state and lockout deadline.

LocalAuthentication success does not count as PIN success for resetting the PIN-failure counter; otherwise a user could bypass accumulated PIN defenses without proving knowledge of the PIN. The implementation plan should preserve this distinction explicitly.

The lockout UI must communicate the remaining lockout state without revealing sensitive history.

## LocalAuthentication

LocalAuthentication is explicit opt-in after PIN setup. It is never enabled implicitly.

When enabled:

1. Opening protected history first offers system authentication.
2. Production evaluates `LAPolicy.deviceOwnerAuthentication`.
3. Face ID or Touch ID is used when available; the system may fall back to the device passcode according to platform behavior.
4. The auth UI always provides a route to `Use DiceGen PIN` instead.
5. Canceling system authentication is not treated as a feature failure; the user remains at the auth gate and can choose PIN.

Because Face ID may be used, the app must provide `NSFaceIDUsageDescription` with copy specific to unlocking DiceGen history.

On Mac Catalyst, the implementation should use the same LocalAuthentication policy and accept the platform-appropriate owner-authentication UI rather than inventing a separate desktop credential flow.

## Unlock Session and Lifecycle

Unlock authorization is an in-memory session property only. Plaintext entries should be loaded into observable/UI-facing state only after successful authorization.

Any scene transition away from `.active` must immediately:

1. mark history locked;
2. clear observable/UI-facing history entries and other sensitive presentation state;
3. cover sensitive history UI with an opaque privacy presentation suitable for app-switcher snapshots;
4. invalidate in-progress sensitive interactions where doing so does not break the platform authentication flow.

A LocalAuthentication completion may grant an unlocked session only while the scene is active; stale completions from a prior inactive/backgrounded state must be ignored.

Returning to `.active` never restores prior authorization. The next protected-history access requires authentication again.

The privacy cover should be driven high enough in the view hierarchy that sensitive history cannot remain visible merely because a child screen forgot to react to lifecycle changes.

## Feature Enablement and Settings Flow

History is off by default.

### Enabling

`Settings -> History` starts setup:

1. enter a 4-12 digit numeric PIN;
2. confirm the PIN;
3. commit the PIN verifier;
4. persist configured/enabled history security metadata;
5. enable history recording;
6. offer an explicit option to enable LocalAuthentication.

The required setup steps are transactional from the user's perspective: if credential or configuration persistence fails, DiceGen cleans up any partial setup it created and remains disabled. No newly copied passphrase is saved before setup completes successfully.

### Enabled settings

When history is enabled, History settings expose:

- LocalAuthentication preference;
- Change PIN;
- Disable History.

Access to sensitive history settings requires an unlocked history session first.

### Disabling

Disabling History requires authentication and destructive confirmation. It removes:

- the history payload;
- the Keychain PIN verifier;
- the LocalAuthentication preference;
- PIN failure/lockout state;
- other persisted history-security state that would allow the feature to remain configured.

Re-enabling later requires full PIN setup again.

## Generator Integration

The main generator screen shows `View Passphrase History` only when history is enabled.

History recording occurs only after a successful user copy action. Generating, regenerating, changing options, or merely displaying a passphrase never saves it.

The existing clipboard behavior remains local-only on iOS. History recording should be attached to the successful copy flow without regressing in-app-review accounting.

A failed history write must not make an otherwise successful clipboard copy appear to have failed. The copy action and history persistence are related product events but should not be coupled so tightly that storage corruption blocks copying. The application should surface history-specific failure state separately and keep history fail-closed for viewing.

## History Screen

After successful authorization, `Passphrase History` displays newest-first entries with timestamps.

Supported actions:

- copy an entry;
- swipe to delete an individual entry;
- Clear All.

Copying from History uses the same local-only clipboard abstraction and the same in-app-review copy accounting as copying the generated passphrase.

`Clear All` is destructive and should require an explicit confirmation appropriate to the current UI conventions. It clears entries but leaves History enabled and leaves the PIN/authentication configuration intact.

## Legacy Migration

### Inputs

Older versions may contain:

- `savedItems` containing dictionaries with `content` and `savedAt`;
- `shouldSaveItems` indicating prior recording preference.

Current `UserSettings` deliberately deletes these keys. Startup ordering must therefore change so migration gets first access.

### Migration ordering

On launch, before `UserSettings` performs legacy cleanup:

1. inspect the legacy values;
2. validate records individually;
3. discard malformed records rather than making them visible;
4. deduplicate valid records by passphrase content, retaining the newest occurrence;
5. write the resulting records to the new backup-excluded local store;
6. verify the new-store write succeeded;
7. only then delete the legacy `savedItems` and `shouldSaveItems` values.

If persistence fails, the legacy values remain so migration can retry on a future launch. Data preservation takes precedence over prematurely cleaning old keys.

### Post-migration state

Migrated history remains inaccessible until the user configures a new PIN. New copy recording also remains disabled until setup.

If legacy history existed or old history saving had been enabled, show a one-time dismissible notice explaining that History now requires a PIN and setup is needed to resume recording/access. Persist the notice-consumed state independently from the legacy keys so deleting those keys does not cause repeated prompts.

This avoids forcing setup during upgrade while making the behavior discoverable.

### Backup rationale

Legacy records are moved out of `UserDefaults` immediately rather than being left there pending PIN setup, because leaving them in the old storage would conflict with the new backup-exclusion requirement.

## Failure Behavior

### Corrupt/unreadable history file

Fail closed. Do not expose partially decoded entries. Keep protected history unavailable and offer destructive Reset History.

### Missing/inconsistent PIN credential

Fail closed. Do not silently turn authentication off. Offer a reset path that destroys inaccessible history and returns the feature to disabled/unconfigured state.

### Keychain error

Do not enable history unless credential setup completed successfully. During an existing configuration, authentication-impacting Keychain failures must not fall through to unlocked state.

### LocalAuthentication unavailable or error

If LocalAuthentication cannot be evaluated, keep the auth gate present and allow the DiceGen PIN path. User cancellation is normal control flow, not an error alert.

### History-write failure after copy

The copied passphrase remains copied; do not report clipboard failure. Mark/surface the history subsystem failure without exposing existing history. Subsequent history access follows fail-closed behavior if persistence integrity cannot be trusted.

### Reset History

The destructive reset path clears history and security configuration together and returns the feature to its default disabled state. It is the recovery route for forgotten PINs or unrecoverable storage/security inconsistency.

## Testing Strategy

### Persistence tests

- starts empty;
- newest-first ordering;
- duplicate content moves to front with a fresh timestamp;
- individual deletion;
- Clear All;
- unlimited retention semantics;
- save/reload round trip;
- malformed payload fails closed;
- backup exclusion is applied on creation and reapplied after writes;
- migration import ordering and deduplication.

### PIN/security tests

- PIN accepts only numeric 4-12 digit values;
- confirmation must match;
- persisted credential contains no plaintext PIN;
- credential is versioned and salted;
- current PIN is required for Change PIN even after LocalAuthentication unlock;
- Forgot PIN destroys history/security state;
- disabling History destroys history/security state;
- Keychain failures fail closed.

### Lockout tests

- attempts 1-4 have no delay;
- selected 30s / 1m / 5m / 15m / 1h schedule is enforced;
- penalty remains capped at 1h;
- failure state survives a reconstructed vault/process model;
- successful PIN verification clears failure state;
- LocalAuthentication unlock does not clear PIN failure state.

### LocalAuthentication tests

- disabled preference goes directly to PIN gate;
- enabled preference attempts system auth first;
- policy is `deviceOwnerAuthentication`;
- system auth success unlocks the in-memory session;
- cancellation leaves user at auth gate;
- PIN remains available as an alternative;
- unavailable LocalAuthentication does not expose content.

### Lifecycle/privacy tests

- unlocked session locks on every scene state other than active;
- returning active does not restore unlock;
- sensitive UI is replaced by the privacy cover while inactive;
- auth dialogs/interactions cannot leave history content exposed in the background.

### Migration tests

- valid legacy items migrate;
- malformed items are rejected;
- duplicate content keeps newest legacy occurrence;
- new store is persisted before legacy keys are deleted;
- migration failure preserves old keys for retry;
- migrated records remain inaccessible before PIN setup;
- new recording remains disabled before setup;
- one-time setup notice appears only for relevant upgrades.

### Integration/UI tests

- History is absent by default;
- PIN setup enables History;
- generator History row appears only when enabled;
- copied passphrase is recorded; generated-only passphrase is not;
- authentication gates the list;
- copied-history action uses normal clipboard/review path;
- swipe delete and Clear All work;
- disabling History removes the row and requires full setup if re-enabled;
- UI-test configuration uses injected authentication behavior rather than real biometrics.

## Expected Integration Areas

Implementation is expected to touch or add focused files around:

- `DiceGenApp.swift` for app-level vault ownership, startup ordering, and lifecycle/privacy integration;
- `SecureContentInfoView.swift` / clipboard action integration for recording successful copies;
- `PassphraseGeneratorView.swift` for the History entry point;
- `SettingsView.swift` for setup/security controls;
- `UserSettings.swift` to stop preempting the new migration path while retaining safe legacy cleanup responsibility as appropriate;
- `Info.plist` for Face ID usage description;
- new history model/store/auth/PIN/migration/view files;
- Xcode project file membership;
- unit tests and UI tests.

These are starting points, not permission to perform unrelated refactoring.

## Rejected Alternatives

### History enabled by default

Rejected because sensitive passphrases should not begin accumulating before the user knowingly configures protection.

### LocalAuthentication without a DiceGen PIN

Rejected because the chosen product model requires an app-specific fallback credential and a deterministic forgotten-credential reset policy.

### Device authentication as PIN recovery

Rejected because it would contradict the no-recovery-preserving-history invariant. LocalAuthentication may unlock history, but only knowledge of the current DiceGen PIN authorizes a PIN change.

### Memory-only PIN lockout

Rejected because force-quitting the app would bypass brute-force throttling.

### Keep history when disabling

Rejected because the old product semantics treated disabling as destructive, and retaining sensitive plaintext after the user disables history is surprising.

### Keep PIN/security configuration when disabling

Rejected. Disabling is a full reset; re-enabling requires explicit setup again.

### Leave legacy history in UserDefaults until setup

Rejected because it could remain subject to normal backup behavior and violate the new storage contract during the waiting period.

### Import legacy history only after PIN setup

Rejected for the same backup reason. Migration happens promptly, but access remains locked until setup.

### SwiftData/Core Data

Rejected because the data model is a small ordered collection, and multi-file database persistence complicates backup-exclusion guarantees without providing meaningful product value.

### Encrypted history storage

Explicitly out of scope. The threat model is unauthorized in-app access, not at-rest compromise.

## Implementation Boundary

This design authorizes a focused restoration of passphrase history with the privacy model above. It does not authorize unrelated architecture modernization, broad settings refactors, new cloud capabilities, analytics, account systems, or generalized credential infrastructure.

The next step after this spec is reviewed and approved is to produce a detailed implementation plan before touching product code.
