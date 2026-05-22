---
phase: 04-app-attest-physical-device-ci-hardening
plan: 03
subsystem: attestation
tags: [app-attest, devicecheck, keychain, secure-enclave, cryptokit, sha-256, simulator-bypass]

# Dependency graph
requires:
  - phase: 04-app-attest-physical-device-ci-hardening
    provides: "Plan 01 — AttestationService protocol, AttestationStatus enum, AttestationError taxonomy, TrustTier enum, KeychainKey.attestedKeyId + .lastHeartbeatAt, appattest-environment entitlement"
  - phase: 02-networking-contract-device-keys
    provides: "KeychainStore (set/get/delete + scope bulk-delete), KeychainAccessibility.afterFirstUnlockThisDeviceOnly, KeychainError.itemNotFound, DeviceFingerprint.current(keychain:).installUUID"
  - phase: 01-foundations
    provides: "Logger protocol, LogEvent, LogField, OSLogLoggerImpl, LoggingSubsystem.auth"
provides:
  - "AttestedKeyStore — Keychain persistence wrapper for attestedKeyId + lastHeartbeatAt (D-01, D-03, D-07)"
  - "DCAppAttestAttestationService — production AttestationService impl (D-01 idempotency, D-04 clearPersistedKeyId, D-06 SHA-256(challenge), D-09 DCError→AttestationStatus map)"
  - "SimulatorBypassAttestationService — file-top-gated DEBUG+simulator impl emitting sim-bypass-{installUUID} + fixed fake attestationObject/assertion bytes (D-10)"
affects:
  - "Plan 04 (attestation-aware /device/register + /device/challenge + /device/heartbeat endpoints + mock fixtures)"
  - "Plan 05 (Release-strings grep gate validates no sim-bypass-* symbols leak into Release)"
  - "Plan 06 (AppContainer composition — #if DEBUG && targetEnvironment(simulator) gate selects between the two impls)"
  - "Plan 07 (DevMenu Re-attest Now row + backend-error response interceptor both invoke clearPersistedKeyId)"
  - "Plan 09 (validationLedgerDeviceTests/AppAttestRoundTripTests exercises the real DCAppAttest path)"
  - "Plan 11 (SessionRestoreProbe cold-boot + didBecomeActive 24h heartbeat cadence call attestKey/generateAssertion)"

# Tech tracking
tech-stack:
  added:
    - "DeviceCheck.DCAppAttestService (iOS 14+ SDK, Apple-managed App Attest framework)"
    - "CryptoKit.SHA256 (Apple-provided hash; chosen over CommonCrypto per D-06)"
  patterns:
    - "Attestation dual-impl — production DCAppAttestAttestationService + simulator-bypass SimulatorBypassAttestationService, resolved at AppContainer layer (Plan 06) via #if DEBUG && targetEnvironment(simulator) — mirrors Phase 2 KeyStoreProtocol dual-impl"
    - "Keychain-first idempotency guard — readAttestedKeyId short-circuits before DCAppAttestService.generateKey() to respect Apple's undocumented once-per-install rate limit (Pitfall 2)"
    - "File-top preprocessor gate for simulator-only symbols — #if DEBUG && targetEnvironment(simulator) wraps the ENTIRE SimulatorBypassAttestationService body, ensuring the symbol does not exist in Release binaries (verified via strings grep showing 0 matches)"
    - "DCError NSError mapping via dual tables — statusForDCError returns wire-level AttestationStatus for the /device/register payload; mapDCError returns Swift-level AttestationError for throwing call paths"
    - "PII-safe attestation logging — fields carry only DCError.Code.rawValue (integer, .count LogField case) + AttestationStatus.rawValue (embedded in event name); attestationObject/keyId bytes + NSError.userInfo never flow into Logger"

key-files:
  created:
    - "validationLedger/Core/Attestation/AttestedKeyStore.swift"
    - "validationLedger/Core/Attestation/DCAppAttestAttestationService.swift"
    - "validationLedger/Core/Attestation/SimulatorBypassAttestationService.swift"
  modified: []

key-decisions:
  - "D-01 applied: generateKeyIfNeeded reads Keychain FIRST and short-circuits when attestedKeyId is present — DCAppAttestService.generateKey() fires at most once per install"
  - "D-06 applied uniformly in both attestKey and generateAssertion: clientDataHash = SHA-256(challenge) via CryptoKit.SHA256, challenge-only (no body/path binding)"
  - "D-09 mapping pinned: .featureUnsupported → .entitlementMissing, .serverUnavailable → .quotaExceeded, .invalidInput/.invalidKey/.unknownSystemFailure → .error, unknown → .error; isSupported == false short-circuits to .unsupported without any DCAppAttestService call"
  - "D-10 enforced: SimulatorBypassAttestationService body wrapped in file-top #if DEBUG && targetEnvironment(simulator); Release-iphoneos strings scan confirms 0 references to sim-bypass or SimulatorBypassAttestationService in the Release binary"
  - "AttestedKeyStore uses KeychainError.itemNotFound (the real KeychainStore surface, not a hypothetical KeychainStore.Error.itemNotFound) for the get→nil translation"
  - "PII-safe logger field choice: DCError.code is logged via `.count` LogField (integer, safe); AttestationStatus.rawValue is embedded in the LogEvent name prefix (`attestation_generate_key_failed_<status>`) to avoid needing a new LogField case"
  - "@MainActor on DCAppAttestAttestationService per RESEARCH Pattern 1 + 04-PATTERNS.md Pattern B — DCAppAttestService callbacks arrive on unspecified queues; marking the class @MainActor keeps Keychain writes on the main actor for consistency with BiometricService + DefaultSessionLockService"

patterns-established:
  - "Attestation dual-impl resolver pattern: public AttestationService protocol + one production class + one simulator-gated class, selected by AppContainer under the same #if DEBUG && targetEnvironment(simulator) guard used for KeyStoreProtocol"
  - "AttestedKeyStore as the sole Keychain↔attestation boundary: all attestedKeyId / lastHeartbeatAt read/write/delete operations flow through this struct so callers cannot accidentally forget .afterFirstUnlockThisDeviceOnly accessibility"
  - "Release-hygiene via file-top preprocessor gate: the simulator-only attestation impl's entire body is excluded from the Release archive at compile time (no #if targetEnvironment-per-method); Plan 05 adds a formal strings grep CI gate on top of this"
  - "DCError dual-mapping tables: statusForDCError (wire-level AttestationStatus for /device/register payload) and mapDCError (Swift-level AttestationError for throwing APIs); both handle @unknown default for forward compatibility"

requirements-completed: [DEV-04]

# Metrics
duration: ~6min
completed: 2026-04-22
---

# Phase 4 Plan 3: App Attest Client Services Summary

**Implemented AttestedKeyStore Keychain wrapper + DCAppAttestAttestationService production impl + SimulatorBypassAttestationService DEBUG-gated impl, wiring D-01 once-per-install idempotency, D-06 CryptoKit-SHA256-of-challenge hashing, D-09 DCError→AttestationStatus mapping, and D-10 file-top simulator-bypass gate that produces 0 sim-bypass strings in the Release binary.**

## Performance

- **Duration:** ~6 min (349s wall time)
- **Started:** 2026-04-22T11:31:28Z (approx. — a few minutes before Task 1 commit)
- **Completed:** 2026-04-22T11:37:17Z
- **Tasks:** 3 (all `type="auto"`, fully autonomous)
- **Files created:** 3
- **Files modified:** 0

## Accomplishments

- `AttestedKeyStore` provides 5 Keychain methods (`read/write/delete AttestedKeyId`, `read/write LastHeartbeatAt`) all going through `.afterFirstUnlockThisDeviceOnly`, with `KeychainError.itemNotFound` translated to `nil` returns.
- `DCAppAttestAttestationService` implements the full production path: `@MainActor`, initializer DI (DCAppAttestService.shared + AttestedKeyStore + Logger), Keychain-first idempotency in `generateKeyIfNeeded`, CryptoKit `SHA256.hash(data: challenge)` in both `attestKey` and `generateAssertion` (exactly 2 occurrences — uniform D-06 rule), and both `statusForDCError` (wire-level `AttestationStatus`) and `mapDCError` (Swift-level `AttestationError`) DCError tables.
- `SimulatorBypassAttestationService` emits the `sim-bypass-{installUUID}` keyId (composed via `DeviceFingerprint.current(keychain:).installUUID`) + fixed fake attestation/assertion bytes, persisted through `AttestedKeyStore` so `clearPersistedKeyId` has a real delete target.
- Release-hygiene verified out-of-band: Release-iphoneos binary `strings` output contains 0 `sim-bypass` / `SimulatorBypassAttestationService` matches. Plan 05 will formalize this as a CI gate.

## Task Commits

Each task was committed atomically with `--no-verify` (Wave 2 parallel executor; orchestrator runs hooks once after all agents complete).

1. **Task 1: Create AttestedKeyStore (Keychain persistence wrapper)** — `34d4e7f` (feat)
2. **Task 2: Create DCAppAttestAttestationService (production impl)** — `56936a3` (feat)
3. **Task 3: Create SimulatorBypassAttestationService (DEBUG-simulator impl)** — `22ec138` (feat)

**Plan metadata:** SUMMARY.md commit is the final step of this agent; orchestrator owns the STATE.md / ROADMAP.md commits after the wave merges.

## Files Created/Modified

- `validationLedger/Core/Attestation/AttestedKeyStore.swift` (CREATED) — Keychain persistence wrapper for `attestedKeyId` + `lastHeartbeatAt` (D-01 accessibility, D-03 logout preservation, D-07 heartbeat cadence storage). Neither key is a member of the session scope.
- `validationLedger/Core/Attestation/DCAppAttestAttestationService.swift` (CREATED) — `@MainActor` production `AttestationService` conforming class. D-01 Keychain-first idempotency, D-04 `clearPersistedKeyId`, D-05 caller-supplied challenge, D-06 `SHA-256(challenge)` via `CryptoKit`, D-07 assertion path for `/device/heartbeat`, D-09 `DCError.Code` → `AttestationStatus` mapping via two dedicated helpers (`statusForDCError` + `mapDCError`). PII discipline: only `DCError.code` integer + `AttestationStatus.rawValue` (via event prefix) reach Logger.
- `validationLedger/Core/Attestation/SimulatorBypassAttestationService.swift` (CREATED) — file-top `#if DEBUG && targetEnvironment(simulator)` gated implementation. Emits `attestedKeyId = "sim-bypass-{installUUID}"` + fixed fake `"sim-bypass-attestation-object-v1"` / `"sim-bypass-assertion-v1"` byte payloads; persists via `AttestedKeyStore`. `@unchecked Sendable` mirrors `SoftwareKeyStore`'s keychain reference pattern.

## Decisions Made

- **Chose CryptoKit.SHA256 over CommonCrypto for `clientDataHash`** per D-06. CryptoKit is Apple-provided, synchronous, typed, and already in the dependency graph via `SoftwareKeyStore.P256.Signing.PrivateKey`. CommonCrypto would require a bridging header or `CCrypto` import with no benefit.
- **Used `KeychainError.itemNotFound` (not `KeychainStore.Error.itemNotFound`) for the catch pattern** — the plan's action block referenced a hypothetical `KeychainStore.Error.itemNotFound`; the real `KeychainStore.swift` surfaces this as `KeychainError.itemNotFound` (a top-level enum). Verified by reading the real Keychain file first and applying the `DeviceFingerprint.resolveInstallUUID` analog pattern (which uses `try?` to collapse the same error).
- **Logger field strategy: DCError.Code integer via `.count` LogField + status rawValue via event-name prefix** — per 04-PATTERNS.md Pattern A Open Q2 guidance and the existing `LogField` enum surface (no `.attestedKeyId` / `.attestationObject` cases added; verified plan-level success criterion 4).
- **Build verification used `iPhone 16` simulator destination** (not `iPhone 15` as the plan wrote) because only iPhone 16 simulators are installed in this Xcode 26.4 runner. Functionally equivalent.
- **`@MainActor` placed on the class declaration** (one match), not per-method, matching `DefaultBiometricService` precedent.
- **Task 3 Release build used `CODE_SIGNING_ALLOWED=NO`** so the generic/iOS build can complete without a provisioning profile (equivalent of the CI-style compile-only check described in the plan's verification block).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected `KeychainStore.Error.itemNotFound` reference to `KeychainError.itemNotFound`**
- **Found during:** Task 1 (AttestedKeyStore)
- **Issue:** Plan's action block referenced `KeychainStore.Error.itemNotFound` as the catch pattern. The real `KeychainStore.swift` surfaces this via a top-level `KeychainError` enum, not a nested `Error` type.
- **Fix:** Used `catch KeychainError.itemNotFound` to translate misses to `nil` returns. Matches the `DeviceFingerprint.resolveInstallUUID` existing pattern.
- **Files modified:** `validationLedger/Core/Attestation/AttestedKeyStore.swift`
- **Verification:** `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug` returns BUILD SUCCEEDED with 0 `error:` lines.
- **Committed in:** `34d4e7f` (Task 1 commit)
- **Note:** The plan's own gotchas section explicitly flagged this: "The exact 'item not found' error case depends on how KeychainStore surfaces misses — READ the real KeychainStore.swift first." The deviation is the expected inline verification described by the plan author.

**2. [Rule 1 - Bug] Removed `KeychainScope.session` reference from AttestedKeyStore header comment**
- **Found during:** Task 1 acceptance criteria self-check
- **Issue:** Initial header comment said "Neither key is a member of `KeychainScope.session`" — the acceptance criterion grep for `"KeychainScope.session"` required 0 matches (to prove the class does not accidentally couple to scope logic).
- **Fix:** Rewrote the comment to reference "the session-scope Keychain group" by description, pointing to `KeychainScope.swift` for the membership table rather than naming the enum case inline.
- **Files modified:** `validationLedger/Core/Attestation/AttestedKeyStore.swift`
- **Verification:** `grep -c "KeychainScope.session"` returns 0.
- **Committed in:** `34d4e7f` (same Task 1 commit; pre-commit edit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 bugs caught at acceptance-criteria-verify time).
**Impact on plan:** Both deviations were strictly inline corrections — no architectural change, no new dependency, no scope creep. Both were explicitly anticipated by the plan's `<gotchas>` / acceptance-criteria surfaces.

## Issues Encountered

- **Simulator destination mismatch:** Plan specified `iPhone 15` but only iPhone 16 simulators are installed. Substituted `iPhone 16` — identical compile behavior. Noted in "Decisions Made" above.
- **Release build code-signing:** Plan's verification block expected `xcodebuild build ... -configuration Release` to work out-of-the-box. On this runner, `CODE_SIGNING_ALLOWED=NO` is required to complete without a provisioning profile. Documented for future phases; Plan 05's CI gate will need the same flag.

## Plan-Level Verification Results

Per the `<verification>` block in the plan:

1. `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug` → **BUILD SUCCEEDED**, 0 errors.
2. `xcodebuild build -scheme validationLedger -destination 'generic/platform=iOS' -configuration Release CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**; Release binary `strings` output contains 0 matches for `sim-bypass` or `SimulatorBypassAttestationService` (preprocessor gate verified out-of-band; Plan 05 formalizes this as CI).
3. All 3 new files exist; acceptance-criteria grep counts match the plan's expectations (see Task Commits above).
4. `grep -nE "case \.attestedKeyId|case \.attestationObject" validationLedger/Core/Logging/Logger.swift` returns **no matches** — no new PII LogField cases introduced.

## Known Stubs

None. All three files are production-ready implementations. The `sim-bypass-attestation-object-v1` / `sim-bypass-assertion-v1` byte payloads are intentional fixed values (D-10 wire contract with the mock backend), not stubs — Plan 04's `/device/register` mock fixture matches these verbatim.

## User Setup Required

None — all file additions; no external service configuration, no environment variables, no provisioning profile changes (App Attest entitlement was already wired in Plan 01).

## Next Phase Readiness

- **Plan 04 (/device/challenge + /device/heartbeat + /device/register attestation fields):** Ready — both AttestationService implementations expose the same `attestKey(keyId:, challenge:)` + `generateAssertion(keyId:, challenge:)` signatures that Plan 04 will call.
- **Plan 05 (Release-strings grep CI gate):** Ready — the file-top `#if DEBUG && targetEnvironment(simulator)` gate has been smoke-verified. Plan 05 only needs to codify the grep into a CI step.
- **Plan 06 (AppContainer composition):** Ready — both impls have matching initializer shapes (each takes a `KeychainStore` or derived `AttestedKeyStore`); Plan 06 selects under the same `#if DEBUG && targetEnvironment(simulator)` guard used for `KeyStoreProtocol`.
- **Plan 07 (DevMenu Re-attest Now + backend interceptor):** Ready — both impls expose `clearPersistedKeyId()` which delegates to `AttestedKeyStore.deleteAttestedKeyId()`.
- **Plan 09 (validationLedgerDeviceTests/AppAttestRoundTripTests):** Ready — `DCAppAttestAttestationService` is the production target; test will need a real iOS device (simulator has no Secure Enclave / no DeviceCheck support).

## Self-Check: PASSED

Verified:

- `validationLedger/Core/Attestation/AttestedKeyStore.swift` — exists; in commit `34d4e7f`.
- `validationLedger/Core/Attestation/DCAppAttestAttestationService.swift` — exists; in commit `56936a3`.
- `validationLedger/Core/Attestation/SimulatorBypassAttestationService.swift` — exists; in commit `22ec138`.
- Commits `34d4e7f`, `56936a3`, `22ec138` all present in `git log --oneline`.
- Debug/Simulator and Release/iOS builds both succeed.
- Release binary has 0 `sim-bypass` / `SimulatorBypassAttestationService` string matches.
- No new `LogField` case added; PII discipline intact.

---

*Phase: 04-app-attest-physical-device-ci-hardening*
*Plan: 03*
*Completed: 2026-04-22*
