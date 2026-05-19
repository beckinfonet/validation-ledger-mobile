---
phase: 02-networking-contract-device-keys
plan: 06
subsystem: security
tags: [ios, secure-enclave, keystore, device-identity, ecdsa-p256, biometrics, keychain, m1]

# Dependency graph
requires:
  - phase: 01-foundational-conventions-scaffolding
    provides: KeyStoreProtocol stub, SoftwareKeyStore baseline, SecureEnclaveKeyStore fatalError stub, KeychainStore, KeychainKey, KeychainAccessibility, validationLedgerDeviceTests target with SecureEnclaveSmokeTests precedent
provides:
  - Extended KeyStoreProtocol with generateDeviceIdentityKeys() + signWithAuthorization(_:)
  - KeyStoreError.keyGenerationFailed(CFError?) typed failure case
  - SoftwareKeyStore two-slot parity (devicePrivateKey + authPrivateKey) for simulator
  - SecureEnclaveKeyStore full implementation (SecKeyCreateRandomKey + SecAccessControlCreateWithFlags two-key ACL pattern)
  - DeviceFingerprint (model via utsname, iosVersion via UIDevice, Keychain-persisted installUUID)
  - ADR 0004 documenting the two-key + .biometryCurrentSet decision
  - Simulator test coverage: SoftwareKeyStoreExtendedTests (4 @Tests) + DeviceFingerprintTests (4 @Tests)
  - Device test scaffolding: SecureEnclaveKeyStoreTests (6 @Tests in validationLedgerDeviceTests/, device-CI pending HUMAN-UAT)
affects:
  - 02-07 (AppContainer DEV-03 refactor — will consume the extended protocol surface)
  - 03-* Phase 3 onboarding (OTP verify triggers generateDeviceIdentityKeys; /device/register consumes DeviceFingerprint)
  - SESS-03 session re-bind flow (catches errSecAuthFailed on authorizationKey after biometric re-enrollment)

# Tech tracking
tech-stack:
  added:
    - Security.framework (SecKeyCreateRandomKey, SecAccessControlCreateWithFlags, SecKeyCreateSignature)
    - UIKit (utsname-based hardware identifier via UIDevice extension)
  patterns:
    - "Two-key ACL split: deviceKey (.devicePasscode) for identity, authorizationKey (.biometryCurrentSet) for sensitive ops"
    - "Keyslot enum carries (applicationTag, accessControlFlags) — eliminates stringly-typed tag construction at call sites"
    - "loadPrivateKey guards SecKey force-cast with CFGetTypeID(key) == SecKeyGetTypeID()"
    - "Keychain upsert-on-read pattern for install UUID (try? get → generate + set → return)"
    - "Test-only Keychain service string for per-suite isolation (com.maldin.validationLedger.tests.*)"

key-files:
  created:
    - validationLedger/Core/Identity/DeviceFingerprint.swift
    - validationLedgerTests/KeyStore/SoftwareKeyStoreExtendedTests.swift
    - validationLedgerTests/Identity/DeviceFingerprintTests.swift
    - validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift
    - docs/adr/0004-secure-enclave-two-key-pattern.md
  modified:
    - validationLedger/Core/KeyStore/KeyStoreProtocol.swift
    - validationLedger/Core/KeyStore/SoftwareKeyStore.swift
    - validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift

key-decisions:
  - "Two-key pattern with .devicePasscode for deviceKey and .biometryCurrentSet for authorizationKey (ADR 0004)"
  - "Use Security framework (SecKeyCreateRandomKey) NOT CryptoKit's SecureEnclave.P256.Signing.PrivateKey — CryptoKit wrapper lacks .biometryCurrentSet ACL support"
  - ".biometryCurrentSet invalidation-on-re-enrollment is the intended security property; SESS-03 re-bind flow (Phase 3) handles it — no workaround"
  - "CryptoKit P-256 publicKey.rawRepresentation is 64 bytes (32 X + 32 Y); SecKeyCopyExternalRepresentation is 65 bytes (0x04 prefix + X + Y). Simulator tests assert 64; device tests assert 65."
  - "installUUID persisted in Keychain (not UserDefaults) with .afterFirstUnlockThisDeviceOnly accessibility"
  - "Test isolation via dedicated service string rather than real production Keychain namespace"
  - "AppContainer left untouched — Plan 07 owns DEV-03 composition refactor"

patterns-established:
  - "Two-key SE pattern: deviceKey (passcode-only) + authorizationKey (biometric, invalidation-sensitive)"
  - "Keyslot enum encapsulates per-slot configuration (applicationTag, flags) — avoids parallel switch statements at every call site"
  - "DeviceFingerprint factory with injected KeychainStore (initializer-DI convention, no singletons)"
  - "Device-only test suite convention: validationLedgerDeviceTests/ target membership + purge-in-defer cleanup"

requirements-completed: [DEV-01, DEV-02, DEV-03, DEV-05]

# Metrics
duration: 12min
completed: 2026-04-21
---

# Phase 2 Plan 06: Device Keys & Identity Surface Summary

**Secure-Enclave two-key (deviceKey `.devicePasscode` + authorizationKey `.biometryCurrentSet`) P-256 signing via `SecKeyCreateRandomKey`, plus `DeviceFingerprint` with Keychain-persisted installUUID for `/device/register` — all simulator tests green; device suite committed pending HUMAN-UAT on physical iPhone.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-04-21T19:47Z
- **Completed:** 2026-04-21T19:59Z
- **Tasks:** 7 of 8 (Task 7 HUMAN-UAT checkpoint deferred per executor checkpoint_protocol)
- **Files created:** 5
- **Files modified:** 3
- **Commits:** 6 task commits (2 feat, 3 test, 1 docs)

## Accomplishments

- **DEV-01 + DEV-02:** `SecureEnclaveKeyStore.swift` now generates two EC P-256 keypairs in the Secure Enclave via `SecKeyCreateRandomKey` with `kSecAttrTokenID = kSecAttrTokenIDSecureEnclave`. `Keyslot` enum carries per-slot `applicationTag` + `accessControlFlags` so call sites never assemble strings. Persistent keys (`kSecAttrIsPermanent: true`) survive relaunch via `kSecAttrApplicationTag`.
- **DEV-02 ACL split:** `deviceKey` uses `[.privateKeyUsage, .devicePasscode]`; `authorizationKey` uses `[.privateKeyUsage, .biometryCurrentSet]`. The `.biometryCurrentSet` invalidation-on-re-enrollment semantic is documented (ADR 0004) and NOT worked around — Phase 3's SESS-03 re-bind flow depends on it.
- **DEV-03 surface:** `KeyStoreProtocol` now has 4 methods: `sign(_:)`, `publicKeyRepresentation()`, `generateDeviceIdentityKeys()`, `signWithAuthorization(_:)`. `SoftwareKeyStore` matches the shape with two `P256.Signing.PrivateKey` instances so simulator path never branches on store type. `AppContainer`'s `#if DEBUG && targetEnvironment(simulator)` gate is UNCHANGED (Plan 07 owns the forced-stub composition refactor).
- **DEV-05:** `Core/Identity/DeviceFingerprint.swift` (new module) assembles `{ model, iosVersion, installUUID }`. Model comes from `utsname()` (`iPhone15,2` on device, `arm64` on simulator — acceptable per plan). installUUID is a UUIDv4 persisted at `KeychainKey("device.install_uuid")` with `.afterFirstUnlockThisDeviceOnly`.
- **ADR 0004:** Records the two-key + `.biometryCurrentSet` decision, rejects `.biometryAny` and CryptoKit's `SecureEnclave.P256.Signing.PrivateKey` wrapper, cross-references Research Pattern 7 + Pitfall 1 + DEV-02.
- **Simulator tests:** 8 @Tests (4 SoftwareKeyStoreExtendedTests + 4 DeviceFingerprintTests) all pass on iPhone 17 Pro / iOS 26.4.
- **Device tests:** 6 @Tests committed to `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift`; `xcodebuild build-for-testing -destination 'generic/platform=iOS'` succeeds. Physical-device execution pending HUMAN-UAT on paired iPhone 15 Pro Max (UDID 48F5B3CC-0E06-50CE-BFD4-8A0A136E144D per Phase 1 VERIFICATION) — self-hosted runner activation remains the Phase 1 HUMAN-UAT #7 open item.

## Task Commits

Each task was committed atomically:

1. **Tasks 1 + 2 combined (must ship together to preserve build):** `23086a8` (feat)
   - Task 1: Extended `KeyStoreProtocol` + `SoftwareKeyStore` — DEV-01/02 protocol surface
   - Task 2: Filled `SecureEnclaveKeyStore` with `SecKeyCreateRandomKey` + two-key ACL
2. **Task 3: `SoftwareKeyStoreExtendedTests`** — `6c258d7` (test) — 4 @Tests, all pass
3. **Task 4: `DeviceFingerprint.swift`** — `ff5544d` (feat) — new `Core/Identity/` module, DEV-05
4. **Task 5: `DeviceFingerprintTests`** — `bf51178` (test) — 4 @Tests, all pass
5. **Task 6: `SecureEnclaveKeyStoreTests`** — `55e339c` (test) — 6 @Tests, device-target, build-for-testing green
6. **Task 7: HUMAN-UAT checkpoint** — deferred per executor checkpoint_protocol; device CI gated on Phase 1 HUMAN-UAT #7
7. **Task 8: ADR 0004** — `4a358ad` (docs)

Plan metadata commit follows this SUMMARY.md.

## Files Created/Modified

- `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` — extended protocol (4 methods) + `KeyStoreError.keyGenerationFailed(CFError?)`
- `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` — two `P256.Signing.PrivateKey` slots (device + auth)
- `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` — full SE implementation via Security framework (no `fatalError`)
- `validationLedger/Core/Identity/DeviceFingerprint.swift` — new file; `DeviceFingerprint.current(keychain:)` factory; `UIDevice.modelIdentifier()` extension
- `validationLedgerTests/KeyStore/SoftwareKeyStoreExtendedTests.swift` — 4 simulator @Tests
- `validationLedgerTests/Identity/DeviceFingerprintTests.swift` — 4 simulator @Tests
- `validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift` — 6 device-target @Tests (HUMAN-UAT gated)
- `docs/adr/0004-secure-enclave-two-key-pattern.md` — ADR for two-key + `.biometryCurrentSet` decision
- `.planning/phases/02-networking-contract-device-keys/deferred-items.md` — logged pre-existing Plan 03 failing test (out of scope)

## Decisions Made

- **Keep `import CryptoKit` in `SecureEnclaveKeyStore.swift`** even though key generation uses Security framework directly — retained for `SecureEnclave.isAvailable` availability checks that AppContainer's gate relies on (per plan note).
- **Simulator test asserts 64-byte public key size, device test asserts 65-byte** — CryptoKit's `P256.Signing.PublicKey.rawRepresentation` (used by `SoftwareKeyStore`) is 64 bytes (32 X + 32 Y); Security's `SecKeyCopyExternalRepresentation` (used by `SecureEnclaveKeyStore`) is 65 bytes (0x04 prefix + 32 X + 32 Y). Tests assert their respective format. Documented inline.
- **`modelIdentifier()` on simulator returns `"arm64"` or `"x86_64"`**, not a device identifier like `"iPhone15,2"`. This is the documented behavior of `utsname()` on iOS Simulator. DEV-05 wire-format tests (Phase 3) must treat simulator-origin fingerprints accordingly — NOT a plan deviation, just a known simulator quirk.
- **Test commits separate from implementation commits** per the executor TDD convention (`test(...)` commit gate before/after `feat(...)` gate). For SoftwareKeyStore, tests follow impl because the impl already existed as a Phase 1 stub being extended (no true RED phase possible without tearing down existing behavior).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Simulator test expected 65-byte public key; CryptoKit returns 64 bytes**

- **Found during:** Task 3 (SoftwareKeyStoreExtendedTests authoring)
- **Issue:** The plan's test template asserted `devicePub.count == 65` citing "EC P-256 uncompressed public key must be 65 bytes (0x04 + 32 X + 32 Y)". That format is correct for `SecKeyCopyExternalRepresentation` (Security framework), but `P256.Signing.PublicKey.rawRepresentation` (CryptoKit — what `SoftwareKeyStore` uses) omits the leading `0x04` prefix and returns 64 bytes.
- **Fix:** Changed assertion to `devicePub.count == 64` in `SoftwareKeyStoreExtendedTests` with an inline comment explaining the two formats. Kept the plan's 65-byte assertion in the device-target `SecureEnclaveKeyStoreTests` (which uses Security framework, so 65 IS correct). Updated the `@Test` name string from "65-byte" to "64-byte" for the simulator test.
- **Files modified:** `validationLedgerTests/KeyStore/SoftwareKeyStoreExtendedTests.swift`
- **Verification:** All 4 @Tests pass on iPhone 17 Pro / iOS 26.4.
- **Committed in:** `6c258d7` (Task 3 commit)

### Deferred / Out-of-scope

**Pre-existing failing test in `validationLedgerTests/Networking/APIClientEndpointTests.swift`** — introduced in commit `526e29b` (Plan 02-03). NOT caused by Plan 06 changes. Logged to `.planning/phases/02-networking-contract-device-keys/deferred-items.md` for Plan 03/04 re-visit.

---

**Total deviations:** 1 auto-fixed (1 bug — test size assertion mismatch)
**Impact on plan:** Auto-fix was essential for green simulator tests; no scope creep. Both CryptoKit and Security key formats are documented inline in the test files.

## Issues Encountered

- `xcodebuild test` with `-only-testing` selector across the full suite surfaced the pre-existing `OTPRequestEndpoint` fixture test failure (Plan 02-03 regression). Targeted Plan 06 selector (`-only-testing:validationLedgerTests/SoftwareKeyStoreExtendedTests -only-testing:validationLedgerTests/DeviceFingerprintTests`) confirmed all new tests pass; the unrelated failure is logged in `deferred-items.md`.

## User Setup Required

None - no external service configuration required. Physical-device execution of `SecureEnclaveKeyStoreTests` is a HUMAN-UAT gate that requires the Phase 1 self-hosted runner to come online (Phase 1 HUMAN-UAT #7 cross-reference).

## Next Phase Readiness

- **Plan 07 (Wave 3, DEV-03):** can now consume `generateDeviceIdentityKeys()` / `signWithAuthorization(_:)` on both sim (`SoftwareKeyStore`) and device (`SecureEnclaveKeyStore`) paths without branching. AppContainer composition refactor + forced-stub test for "refuse to launch on production device without SE" is Plan 07's owned surface.
- **Phase 3 onboarding (OTP verify → key generation):** `AuthRepository.confirmOTP(...)` can call `keyStore.generateDeviceIdentityKeys()` unconditionally; the two-key pattern is uniform across environments.
- **Phase 3 `/device/register` payload assembly:** `DeviceFingerprint.current(keychain:)` is ready to consume; payload projection (wire-format `Encodable`) lives in Plan 03-style endpoint file (`DeviceRegisterEndpoint.DeviceFingerprintPayload`).
- **HUMAN-UAT cross-reference:** Phase 1 HUMAN-UAT #7 (self-hosted device runner activation) continues to gate device-CI execution of `SecureEnclaveKeyStoreTests` + (future) `RefuseLaunchWithoutSecureEnclaveTests`. Phase 2 VERIFICATION will note this cross-reference at phase close.

## Threat Model Coverage (from Plan 06 `<threat_model>`)

All six threat IDs (T-02-23 through T-02-28) are mitigated or intentionally accepted:

- **T-02-23 (Spoofing — stolen device):** mitigated via `.biometryCurrentSet` on authorizationKey (re-enrollment invalidates). Verified: `SecureEnclaveKeyStore.Keyslot.authorization.accessControlFlags == [.privateKeyUsage, .biometryCurrentSet]`.
- **T-02-24 (Information Disclosure — private key material):** mitigated via `kSecAttrTokenIDSecureEnclave`. Verified by grep: 1 occurrence in `SecureEnclaveKeyStore.swift`.
- **T-02-25 (DoS — simulator false-pass):** mitigated by test membership. `SecureEnclaveKeyStoreTests` lives only in `validationLedgerDeviceTests/`.
- **T-02-26 (Elevation — wrong ACL flag combination):** mitigated by exact-literal flag sets (no `.or`/`.and` composition). Verified by grep: `.devicePasscode` (2 occurrences), `.biometryCurrentSet` (3 occurrences).
- **T-02-27 (Information Disclosure — installUUID):** accepted per plan (UUIDv4, app-scoped, not IDFA-like, Keychain-only storage).
- **T-02-28 (Tampering — Keychain state pollution):** mitigated via `purgeAllKeys` defer in device tests + dedicated test service string in simulator tests.

## Self-Check: PASSED

All 10 claimed file paths exist. All 6 task commits verified in `git log --oneline --all`:

- `23086a8` feat(02-06): Secure Enclave two-key pattern + SoftwareKeyStore parity
- `6c258d7` test(02-06): SoftwareKeyStoreExtendedTests — two-key simulator parity
- `ff5544d` feat(02-06): DeviceFingerprint with installUUID persistence
- `bf51178` test(02-06): DeviceFingerprintTests — installUUID persistence
- `55e339c` test(02-06): SecureEnclaveKeyStoreTests — device-target DEV-01/02 round-trip
- `4a358ad` docs(02-06): ADR 0004 — Secure Enclave two-key pattern rationale

---
*Phase: 02-networking-contract-device-keys*
*Plan: 06*
*Completed: 2026-04-21*
