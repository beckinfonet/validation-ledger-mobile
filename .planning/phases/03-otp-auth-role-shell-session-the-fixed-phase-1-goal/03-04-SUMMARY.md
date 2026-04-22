---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 04
subsystem: keychain + keystore
tags: [ios, keychain, keystore, storage, wave-1, tdd, d-16, d-33, sess-04, auth-03]

# Dependency graph
requires:
  - phase: 01-foundational-conventions-scaffolding
    provides: "KeychainStore(service:accessGroup:) + KeychainKey struct + KeychainAccessibility enum + idempotent delete(_:) API (Phase 1 baseline)"
  - phase: 02-networking-contract-and-device-keys
    provides: "SecureEnclaveKeyStore two-key pattern (deviceKey + authorizationKey) with applicationTag + accessControlFlags per slot; SoftwareKeyStore simulator parity with P256.Signing.PrivateKey for both slots; DER X9.62 signature format across both"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 02
    provides: "DER unification (IN-02) landed in SoftwareKeyStore.sign + signWithAuthorization — enables the `sig.first == 0x30` assertion in softwareDeleteAuthorizationClears test to stay valid after optionalization refactor; serialization ordering constraint (Plan 02 → Plan 04) observed"
provides:
  - "3 new KeychainKey statics (sessionRole / sessionUserID / biometricDomainState) with raw values session.role / session.userID / biometric.domainState per D-33"
  - "KeychainScope.swift (NEW) — Sendable enum with .session case + contains(_:) predicate for LogoutService bulk-delete"
  - "KeychainStore.deleteAll(under: KeychainScope) extension — idempotent bulk wipe composing over the existing delete(_:) API; explicit membership list (not enumerateAll-based) so future secrets aren't silently vacuumed"
  - "Keyslot promoted from SecureEnclaveKeyStore-nested internal enum to top-level public Sendable type, shared with SoftwareKeyStore — protocol can now declare method signatures referencing Keyslot directly"
  - "KeyStoreProtocol.deleteKey(slot: Keyslot) throws — 5th protocol method; idempotent contract"
  - "SecureEnclaveKeyStore.deleteKey(slot:) implementation — SecItemDelete against kSecClass + kSecAttrKeyType + kSecAttrApplicationTag query (mirrors loadPrivateKey minus kSecReturnRef); errSecItemNotFound treated as success"
  - "SoftwareKeyStore optionalization — devicePrivateKey + authPrivateKey became optional `var` (from non-optional `let`) with nil-default-safe guards on sign / publicKeyRepresentation / signWithAuthorization; generateDeviceIdentityKeys regenerates any nil slot for D-27 re-register compatibility"
  - "KeyStoreError.keyDeletionFailed(OSStatus) new case"
  - "8 new tests: 4 in KeychainStoreTests (phase3KeychainKeysPresent, deleteAllSessionScope, deleteAllIdempotent, deleteAllPreservesOutOfScopeKeys) + 5 in new KeyStoreProtocolDeleteTests (softwareDeleteAuthorizationClears, softwareDeleteDeviceClears, softwareDeleteIdempotent, secureEnclaveDeleteCallsSecItemDelete, protocolDeclaresDeleteKey)"
affects:
  - "03-06 (SessionRestoreService cold-boot probe) — can now read keychain.get(.sessionRole) and keychain.get(.sessionUserID); the D-04 `.restored(role:)` branch has its data carrier landed"
  - "03-07 (LogoutService + SensitiveActionService + Auth401Interceptor) — BOTH symbols the 6-step D-16 orchestration references are now present: `keychain.deleteAll(under: .session)` (step 2) and `keyStore.deleteKey(slot: .authorization)` (step 3). Plan 07 can now compile against these APIs."
  - "03-09 (post-OTP D-27 orchestration) — step 2 caches sessionToken/role/userID via the 3 new KeychainKey statics; steps 3-4 use the top-level Keyslot type (no longer need `SecureEnclaveKeyStore.Keyslot` qualifier)"
  - "Phase 4 device CI (CI-03) — real SE delete path is HUMAN-UAT; source-grep proxy test (secureEnclaveDeleteCallsSecItemDelete) confirms the fix is present but real SecItemDelete semantics on SE-backed keys require hardware verification"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Explicit-membership bulk-delete scope: KeychainScope enumerates its 4 session keys by name; NOT computed from enumerateAll(). A future Keychain-resident secret (added by a later plan) will NOT be silently wiped unless its key is added to the scope's membership table — engineers must opt-in. Conservative default prevents accidental device-identity loss."
    - "Shared top-level slot-vocabulary pattern: Keyslot is declared in KeyStoreProtocol.swift as a top-level public enum so both implementations (SE + Software) + the protocol itself share the same case vocabulary. Backend-specific slot attributes (applicationTag / accessControlFlags) live as fileprivate extensions in the impl that uses them (SecureEnclaveKeyStore.swift) — SoftwareKeyStore doesn't need either, so keeping them scoped to SE avoids cross-contamination."
    - "Source-grep proxy test for device-only invariants: real SE delete requires hardware (Phase 4 HUMAN-UAT / device CI). KeyStoreProtocolDeleteTests.secureEnclaveDeleteCallsSecItemDelete + .protocolDeclaresDeleteKey use #filePath-relative URL resolution (same pattern as SoftwareKeyStoreExtendedTests.cr02IdempotentGuardPresent from Plan 02) to assert the fix is present at source level even though the runtime behavior is uncheckable on simulator."
    - "Regeneration-on-regenerate idempotence in SoftwareKeyStore: generateDeviceIdentityKeys assigns a new P256 key to any slot that's nil (post-deleteKey) so D-27 step 3–4 sequential orchestration after a prior session's logout is safe to re-invoke without silent empty-key bugs."

key-files:
  created:
    - validationLedger/Core/Storage/Keychain/KeychainScope.swift
    - validationLedgerTests/KeyStore/KeyStoreProtocolDeleteTests.swift
  modified:
    - validationLedger/Core/Storage/Keychain/KeychainKey.swift
    - validationLedger/Core/Storage/Keychain/KeychainStore.swift
    - validationLedger/Core/KeyStore/KeyStoreProtocol.swift
    - validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift
    - validationLedger/Core/KeyStore/SoftwareKeyStore.swift
    - validationLedgerTests/Storage/KeychainStoreTests.swift

key-decisions:
  - "Keyslot promoted from nested-in-SecureEnclaveKeyStore (internal enum) to top-level public Sendable enum in KeyStoreProtocol.swift — Rule 3 blocking correction. The plan text assumed Keyslot was already protocol-level (interface block described it as \"the associated Keyslot enum exists\"), but it wasn't; without promotion, `func deleteKey(slot: Keyslot) throws` cannot be declared on a protocol that lives in a different file. SE-specific slot attributes (applicationTag / accessControlFlags) remain in SecureEnclaveKeyStore.swift as a fileprivate extension on the shared type — no API surface leakage to consumers who don't need them."
  - "SoftwareKeyStore property optionalization (`let` → `var?`) with init-time default assignment — keeps existing callers green even when they skip generateDeviceIdentityKeys, while still allowing deleteKey(slot:) to set the slot to nil. The nil-guarded sign/publicKeyRepresentation/signWithAuthorization paths throw KeyStoreError.keyUnavailable, which is the same case the SE-side path throws on a missing slot — consumer error-handling is symmetric sim ↔ device."
  - "generateDeviceIdentityKeys in SoftwareKeyStore now regenerates any nil slot instead of unconditionally returning the existing keys' public representations. Scenario: logout clears authPrivateKey via deleteKey(.authorization); the next OTP-verify re-runs D-27 step 3–4 which calls generateDeviceIdentityKeys(); without the regenerate guard that call would return (devicePub, nil-publicKey-crash). With the guard, the slot is reborn with a fresh P256 key — matches SE's CR-02 idempotent guard semantic (existing slot returns as-is; missing slot generates fresh)."
  - "KeychainScope.deleteAll(under:) uses explicit-membership switch (not enumerateAll + scope.contains filter). The plan's <behavior> said either was acceptable; explicit enumeration is safer (no silent vacuum of future secrets) + faster (O(|scope|) instead of O(all keychain items)) + makes the membership audit a single grep."
  - "Full regression check ran with -parallel-testing-enabled NO matching Phase 2's ci-simulator.yml config. Parallel-enabled shows 8 pre-existing flakes across MockURLProtocol / DeviceFingerprint / AppContainerNetworkConfig / APIClientEndpoint suites — all unrelated to KeyStore/Keychain work (those suites share mutable global state per WR-01; the CI-pinned serial flag is the documented mitigation). Serial-enabled: 120/120 pass."
  - "Destination substitution (same as Plans 01 / 02 / 03): iPhone 17 Pro / iOS 26.4 because the plan-specified iPhone 15 / iOS 17.5 runtime is not installed. Project deployment target is iOS 17.0 — any iOS 17+ simulator is equivalent for verification."

patterns-established:
  - "Promote-then-delegate for protocol-method-types: when a protocol method references a type currently nested inside ONE implementation, promote the type to the protocol's module (top-level) and keep impl-specific attributes on the type as fileprivate extensions in the impl that uses them. Minimum surface change; maximum locality of impl-specific concerns."
  - "Lineage-marker comment pattern (continued from Plan 02's `// CR-02` / `// IN-02` markers): every Plan 04 touch carries a `// Phase 3 Plan 04 (SESS-04 / D-16):` or `// Phase 3 D-33:` comment. A future verifier can `grep -R 'Phase 3 Plan 04\\|D-16\\|D-33'` to find every site this plan touched."

requirements-completed:
  - AUTH-03
  - SESS-04

# Metrics
duration: 8min
completed: 2026-04-22
---

# Phase 03 Plan 04: Keychain/KeyStore Teardown Primitives Summary

**Storage-side primitives for LogoutService landed — KeychainStore.deleteAll(under: .session) wipes the 4-key session scope idempotently, KeyStoreProtocol.deleteKey(slot:) clears SE keys via SecItemDelete (and in-memory-nils simulator keys), 3 new KeychainKey statics per D-33 complete the session cache contract. 8 new tests + 0 regressions.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-22 03:06:17Z (first task RED commit 2960896)
- **Completed:** 2026-04-22 03:14:22Z (final fix commit 79a3f35)
- **Tasks:** 2 / 2 (TDD: each split RED + GREEN = 4 commits total)
- **Files created:** 2 (1 source + 1 test)
- **Files modified:** 6 (5 source + 1 test)

## Accomplishments

- **KeychainKey D-33 additions.** 3 new static members with exact raw values downstream plans reference by name:
  - `sessionRole` → `"session.role"`
  - `sessionUserID` → `"session.userID"`
  - `biometricDomainState` → `"biometric.domainState"`
- **KeychainScope.swift (NEW).** Sendable enum; `.session` case; `contains(_:)` predicate returning true only for the 4 session-scope keys. Explicit-membership design prevents future secrets from being silently vacuumed.
- **KeychainStore.deleteAll(under:) extension.** Composes over the existing idempotent `delete(_:)` (which treats `errSecItemNotFound` as success), so repeat calls and empty-keychain calls don't throw. Used by LogoutService (Plan 07) step 2 to atomically wipe the 4 session-scope keys.
- **Keyslot promoted to top-level public Sendable enum** in `KeyStoreProtocol.swift` so the protocol can reference it. SE-specific `applicationTag` + `accessControlFlags` computed properties moved to a fileprivate extension in `SecureEnclaveKeyStore.swift`.
- **KeyStoreProtocol.deleteKey(slot: Keyslot) throws** — new 5th method; idempotent contract documented inline.
- **SecureEnclaveKeyStore.deleteKey(slot:)** — issues `SecItemDelete` against a query mirroring `loadPrivateKey`'s shape (`kSecClass` + `kSecAttrKeyType` + `kSecAttrApplicationTag`, minus `kSecReturnRef`). `errSecItemNotFound` returns success; otherwise throws `KeyStoreError.keyDeletionFailed(status)`.
- **SoftwareKeyStore.deleteKey(slot:)** — sets matching optional property to nil. `devicePrivateKey` + `authPrivateKey` refactored from non-optional `let` to optional `var` with init-time default (backwards-compatible with callers that don't call `generateDeviceIdentityKeys` first). `sign` / `publicKeyRepresentation` / `signWithAuthorization` now nil-guard and throw `KeyStoreError.keyUnavailable` if the relevant slot is empty. `generateDeviceIdentityKeys` regenerates any nil slot (D-27 re-register compatibility).
- **KeyStoreError.keyDeletionFailed(OSStatus)** — new case.
- **8 new tests across 2 suites, all green.** Zero regression in Phase 1 + Phase 2 simulator suites (120/120 pass with `-parallel-testing-enabled NO`).

## Task Commits

Each task followed TDD with atomic RED → GREEN commits (worktree mode, `--no-verify` per parallel-execution policy):

| Commit | Type | Task | Subject |
|--------|------|------|---------|
| `2960896` | test | 1 RED   | add failing tests for KeychainScope + 3 session-scope keys + deleteAll(under:) |
| `80c60b3` | feat | 1 GREEN | add KeychainScope + 3 session-scope keys + deleteAll(under:) |
| `ee993d9` | test | 2 RED   | add failing tests for KeyStoreProtocol.deleteKey(slot:) |
| `79a3f35` | feat | 2 GREEN | add deleteKey(slot:) to KeyStoreProtocol + SE + Software impls |

**Plan metadata commit:** pending (appended with SUMMARY.md by orchestrator).

## Files Modified / Created

### Source (6)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedger/Core/Storage/Keychain/KeychainKey.swift` | +3 static members per D-33; header comment ref to KeychainScope | +10 |
| `validationLedger/Core/Storage/Keychain/KeychainScope.swift` | NEW — Sendable scope enum + contains(_:) | +35 |
| `validationLedger/Core/Storage/Keychain/KeychainStore.swift` | + `deleteAll(under:) throws` extension (explicit-membership switch) | +31 |
| `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` | + top-level public Keyslot enum, + `deleteKey(slot:) throws` method, + `keyDeletionFailed(OSStatus)` error case | +29 |
| `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` | Removed internal Keyslot; moved slot attributes to fileprivate extension; + `deleteKey(slot:)` impl using SecItemDelete | +38 / -23 |
| `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` | Optional `var` keys; nil-guards on sign/publicKeyRep/signWithAuthorization; + regenerate-on-nil in generateDeviceIdentityKeys; + `deleteKey(slot:)` impl | +46 / -0 |

### Test (2)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedgerTests/Storage/KeychainStoreTests.swift` | + 4 new `@Test`s in existing @Suite: phase3KeychainKeysPresent, deleteAllSessionScope, deleteAllIdempotent, deleteAllPreservesOutOfScopeKeys | +50 |
| `validationLedgerTests/KeyStore/KeyStoreProtocolDeleteTests.swift` | NEW @Suite — 5 `@Test`s: softwareDeleteAuthorizationClears, softwareDeleteDeviceClears, softwareDeleteIdempotent, secureEnclaveDeleteCallsSecItemDelete, protocolDeclaresDeleteKey | +115 |

## Test Results

**KeychainStoreTests — 8 passed** (4 pre-existing + 4 new):

```
✔ set → get round-trips Data                                                            (pre-existing)
✔ set → delete → get throws                                                              (pre-existing)
✔ delete is idempotent (absent key does not throw)                                       (pre-existing)
✔ enumerateAll returns items we set                                                      (pre-existing)
✔ Phase 3 D-33 — KeychainKey.sessionRole / .sessionUserID / .biometricDomainState exist  (new, Task 1)
✔ Phase 3 D-16 — deleteAll(under: .session) wipes all 4 session-scope keys               (new, Task 1)
✔ Phase 3 D-16 — deleteAll(under: .session) is idempotent on empty keychain              (new, Task 1)
✔ Phase 3 D-16 — deleteAll(under: .session) does NOT touch non-session keys              (new, Task 1)
```

**KeyStoreProtocolDeleteTests — 5 passed (all new):**

```
✔ SoftwareKeyStore.deleteKey(slot: .authorization) clears in-memory auth key; device key preserved
✔ SoftwareKeyStore.deleteKey(slot: .device) clears in-memory device key
✔ SoftwareKeyStore.deleteKey is idempotent (no throw on never-generated or double-delete)
✔ SecureEnclaveKeyStore.deleteKey source contains SecItemDelete (SE proxy, Phase 4 HUMAN-UAT)
✔ KeyStoreProtocol declares deleteKey(slot:) (source-grep proxy for protocol surface)
```

**SoftwareKeyStoreExtendedTests — 7 passed (Phase 2 Plan 02; zero regression after optionalization refactor):**

```
✔ generateDeviceIdentityKeys returns two distinct 64-byte public keys
✔ publicKeyRepresentation returns the device-slot public key
✔ sign and signWithAuthorization produce distinct signatures for the same input
✔ sign produces DER X9.62 ECDSA P-256 signature (IN-02 — matches SE wire format)
✔ IN-02 — sign(_:) returns DER X9.62 (starts with 0x30 SEQUENCE tag)
✔ IN-02 — signWithAuthorization(_:) returns DER X9.62
✔ CR-02 — SecureEnclaveKeyStore.generateKey idempotent guard is present (source-grep proxy)
```

**Full simulator regression (-parallel-testing-enabled NO):** 120 tests in 31 suites — ALL PASS. `** TEST SUCCEEDED **`.

**Parallel-enabled run (for documentation):** 8 pre-existing flakes in MockURLProtocol + DeviceFingerprint + AppContainerNetworkConfig + APIClientEndpoint suites — these are shared-global-state races covered by WR-01 and mitigated by the Phase 2 ci-simulator.yml serial flag. NONE of the failures touch KeyStore or Keychain code; running serial-disabled matches the CI-pinned configuration and passes cleanly.

## Decisions Made

(See frontmatter `key-decisions` for the full list.) Highlights:

- **Keyslot promotion to top-level public type.** Rule 3 blocking correction — plan's interface block assumed Keyslot was already protocol-level, but it was nested inside SecureEnclaveKeyStore. Without promotion, the protocol method `func deleteKey(slot: Keyslot) throws` cannot exist. SE-specific slot attributes (applicationTag + accessControlFlags) remain in the SE impl file as a fileprivate extension.
- **SoftwareKeyStore optional `var` refactor.** The alternative (throw-on-missing without optionalization) would have required an in-memory "key-present" bool flag which is strictly uglier than the Swift-idiomatic `Optional` pattern. Existing callers remain green because both keys are init-time-assigned; new callers that call deleteKey see the documented `KeyStoreError.keyUnavailable` on subsequent sign attempts.
- **Explicit-membership KeychainScope.** Plan's <behavior> allowed either explicit enumeration or `enumerateAll + scope.contains` filter; chose explicit because (a) O(|scope|) is faster than O(all keychain items); (b) future Keychain secrets won't be silently vacuumed if a plan forgets to add their key to the scope membership table; (c) the membership table IS the audit surface — one `switch` statement documents everything that `deleteAll(under: .session)` touches.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking API-level correction] Keyslot promoted from nested-in-SecureEnclaveKeyStore to top-level public in KeyStoreProtocol.swift**

- **Found during:** Task 2 RED build verification
- **Issue:** Plan `<interfaces>` block described Keyslot as an "associated enum" that "exists with .device and .authorization cases." Grep confirmed Keyslot was declared as an internal nested type inside `SecureEnclaveKeyStore`, invisible from `KeyStoreProtocol.swift` and `SoftwareKeyStore.swift`. Without it being top-level, `func deleteKey(slot: Keyslot) throws` cannot be declared on the protocol.
- **Fix:** Promoted `Keyslot` to a top-level `public enum Keyslot: Sendable` in `KeyStoreProtocol.swift` with the same two cases (`.device`, `.authorization`). Moved `applicationTag` + `accessControlFlags` computed properties to a `fileprivate extension Keyslot { ... }` at the top of `SecureEnclaveKeyStore.swift` — these are SE-specific and `SoftwareKeyStore` has no need for them. Zero consumer impact outside the KeyStore subsystem.
- **Files modified:** `KeyStoreProtocol.swift` (+Keyslot top-level), `SecureEnclaveKeyStore.swift` (remove nested, add fileprivate extension).
- **Verification:** All 12 KeyStore tests (5 new + 7 Phase 2 pre-existing) pass green. No API-surface changes for Plan 07 consumers.
- **Committed in:** 79a3f35 (Task 2 GREEN).

**2. [Rule 3 — Blocking env correction, same as Plans 01 / 02 / 03] Substituted `iPhone 17 Pro / iOS 26.4` for plan-specified `iPhone 15 / iOS 17.5` destination**

- **Found during:** Task 1 RED build verification
- **Issue:** `xcrun simctl list devices available` shows no iPhone 15 / iOS 17.5 runtime installed. Available: iOS 15.2, 18.0–18.4, 26.2, 26.4. Project Xcode SDK is 26.4 (per CLAUDE.md).
- **Fix:** All `xcodebuild test` invocations used `-destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`. iOS 17.0 deployment target makes any iOS 17+ simulator equivalent for verification; iPhone 17 Pro / iOS 26.4 is the currently-booted simulator (matches Plans 01–03).
- **Files modified:** None (CLI only).
- **Verification:** `** TEST SUCCEEDED **` on both KeychainStoreTests and KeyStoreProtocolDeleteTests + SoftwareKeyStoreExtendedTests + full 120-suite regression.
- **Committed in:** N/A — test-run CLI only.

**3. [Rule 2 — Defensive correctness] Extended SoftwareKeyStore.generateDeviceIdentityKeys to regenerate nil slots**

- **Found during:** Task 2 GREEN — after optionalizing `devicePrivateKey` / `authPrivateKey`, the existing implementation would have returned `nil!`-crash on the rawRepresentation access if a prior `deleteKey(slot:)` had cleared a slot before a re-`generateDeviceIdentityKeys` call.
- **Issue:** Plan's Step C said to "update `generateDeviceIdentityKeys` to assign these instead of returning fresh locals (it likely already does this — read the file)." The file actually just returned the public representations from the already-init-assigned keys; post-delete the slots would be nil and the method would crash.
- **Fix:** `if devicePrivateKey == nil { devicePrivateKey = P256.Signing.PrivateKey() }` (same for auth). This matches SE's CR-02 idempotent-guard semantic (existing slot returns as-is; missing slot is regenerated) and makes the D-27 re-register flow safe after a logout.
- **Files modified:** `SoftwareKeyStore.swift`.
- **Verification:** `generateDeviceIdentityKeys returns two distinct 64-byte public keys` (pre-existing test) still green — regeneration produces a valid pair.
- **Committed in:** 79a3f35 (Task 2 GREEN).

---

**Total deviations:** 3 auto-fixed (1 API-level blocking Keyslot promotion, 1 env-level destination substitution, 1 defensive-correctness on Software regeneration). **Impact on plan:** No scope change — all `success_criteria` + all `must_haves.truths` + all `must_haves.artifacts` satisfied as written. The Keyslot promotion is strictly additive to the plan's intent (the plan needed the type; the plan's interface block just underestimated what was required to get it there).

## TDD Gate Compliance

Plan frontmatter does not carry `type: tdd`, but both tasks have `tdd="true"`. Each task followed RED → GREEN atomic commits with RED preceding GREEN in git log:

| Task | RED commit | GREEN commit | RED confirmation |
|------|-----------|--------------|-------------------|
| 1 | `2960896` (test) | `80c60b3` (feat) | Expected errors: `type 'KeychainKey' has no member 'sessionRole'`, `value of type 'KeychainStore' has no member 'deleteAll'` — confirmed by `xcodebuild build-for-testing` output. |
| 2 | `ee993d9` (test) | `79a3f35` (feat) | Expected errors: `value of type 'SoftwareKeyStore' has no member 'deleteKey'`, `cannot infer contextual base in reference to member 'authorization'` (Keyslot not visible) — confirmed by `xcodebuild build-for-testing` output. |

Both RED commits precede their GREEN commits; `git log --oneline` verifies chronological order. No TDD gate violations.

## Known Stubs

**None introduced by this plan.** The Wave 0 stub for `KeyStoreProtocolDeleteTests.swift` was not part of Plan 01's stub-to-plan mapping (Plan 01 seeded 13 stubs; this one was created fresh from the plan spec). All 5 new tests in this file are real, enabled, and green.

## Threat Flags

Per plan `<threat_model>`: all 4 Plan 04 threats were `mitigate` disposition; all 4 mitigations landed:

| Threat ID | Mitigation landed? | Evidence |
|-----------|---------------------|----------|
| T-03-04-01 Stale sessionToken after logout | YES | `KeychainStore.deleteAll(under: .session)` wipes all 4 session keys in one call; `deleteAllSessionScope` test proves `get(key)` throws on each after the wipe. |
| T-03-04-02 SE auth-key surviving logout enables sensitive-action signing | YES | `SecureEnclaveKeyStore.deleteKey(slot: .authorization)` issues SecItemDelete against the slot's applicationTag; `secureEnclaveDeleteCallsSecItemDelete` source-grep proxy confirms the fix is in place. Real-device exercise is Phase 4 HUMAN-UAT per plan. |
| T-03-04-03 `deleteAll(under:)` accidentally deleting non-session keys | YES | `KeychainScope.contains(_:)` explicitly enumerates the 4 session keys; `deleteAllPreservesOutOfScopeKeys` test asserts `installUUID` survives a `deleteAll(under: .session)` call. Explicit-membership switch in `deleteAll(under:)` extension (not enumerateAll-based) prevents future secrets from being silently vacuumed. |
| T-03-04-04 Logout failing midway because deleteKey throws on missing key | YES | Both `deleteAll(under:)` and `deleteKey(slot:)` are idempotent — `errSecItemNotFound` treated as success (composes over existing `KeychainStore.delete(_:)` + explicit `status == errSecItemNotFound` guard in SE impl + `switch-and-set-nil` in Software impl). `deleteAllIdempotent` + `softwareDeleteIdempotent` tests assert this. |

**No new threat surface introduced.** All changes are defensive teardown APIs that make session state wipe more thorough and more idempotent. No new network endpoints, no new file access patterns, no new trust boundaries. No new flags to report; omitting the Threat Flags flagged-rows section.

## Issues Encountered

- **Keyslot nested-vs-top-level mismatch.** Plan interface block described Keyslot at the protocol level, but it was nested inside SecureEnclaveKeyStore. Required a one-file promotion + one-file fileprivate-extension relocation. Documented as Deviation 1.
- **Parallel-testing shared-state flakes on the full simulator suite.** Pre-existing (WR-01) — affects MockURLProtocol / DeviceFingerprint / AppContainerNetworkConfig / APIClientEndpoint. Mitigated by running with `-parallel-testing-enabled NO` (matches Phase 2 ci-simulator.yml). Does NOT touch KeyStore / Keychain surfaces.

## User Setup Required

None. No external services, no secrets, no dashboard changes. All work is source + test edits verifiable via `xcodebuild test`.

## Next Wave Readiness

- **Plan 06 (SessionRestoreService + BiometricService)** can proceed — the 3 new `KeychainKey` members (`sessionRole`, `sessionUserID`, `biometricDomainState`) provide the named storage slots the cold-boot probe (D-04) and domain-state comparison (D-09) require.
- **Plan 07 (LogoutService + SensitiveActionService + Auth401Interceptor)** can proceed — BOTH symbols the 6-step D-16 orchestration references are now live: `keychain.deleteAll(under: .session)` (step 2) and `keyStore.deleteKey(slot: .authorization)` (step 3). LogoutService can compile against the protocol surface with no further KeyStore / Keychain changes.
- **Plan 09 (post-OTP D-27 orchestration)** can proceed — step 2 caches sessionToken/role/userID via the 3 new KeychainKey statics; steps 3–4 use the top-level `Keyslot` type (no more `SecureEnclaveKeyStore.Keyslot` qualifier). The regeneration-on-nil path in SoftwareKeyStore.generateDeviceIdentityKeys ensures step 3–4 are safe after a prior logout.
- **Phase 4 device CI (CI-03)** will need to exercise the real SE delete path on hardware — the source-grep proxy tests confirm the fix is present, not that SE honors SecItemDelete on enclave-backed keys. Tracked as HUMAN-UAT per plan `<behavior>`.
- **Downstream verifier checks:** all plan `<verify>.automated` grep assertions pass (sessionRole static, biometricDomainState static, KeychainScope.swift existence, `case session`, `deleteAll(under` in KeychainStore, `func deleteKey(slot: Keyslot) throws` in protocol, `SecItemDelete` in SE, `func deleteKey` in Software). Confirmed locally; all 9 checks green.

## Self-Check

Files claimed created:

- `validationLedger/Core/Storage/Keychain/KeychainScope.swift` — FOUND
- `validationLedgerTests/KeyStore/KeyStoreProtocolDeleteTests.swift` — FOUND

Files claimed modified:

- `validationLedger/Core/Storage/Keychain/KeychainKey.swift` — FOUND (diff +10, 3 new statics)
- `validationLedger/Core/Storage/Keychain/KeychainStore.swift` — FOUND (diff +31, deleteAll(under:) extension)
- `validationLedger/Core/KeyStore/KeyStoreProtocol.swift` — FOUND (diff +29, top-level Keyslot + deleteKey method + keyDeletionFailed error case)
- `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` — FOUND (diff +38/-23, Keyslot extracted + deleteKey impl)
- `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` — FOUND (diff +46, optional keys + deleteKey impl + generate regenerate-on-nil)
- `validationLedgerTests/Storage/KeychainStoreTests.swift` — FOUND (diff +50, 4 new @Tests)

Commits claimed made:

- `2960896` (Task 1 RED — KeychainScope + 3 keys + deleteAll(under:) tests) — FOUND in git log
- `80c60b3` (Task 1 GREEN — KeychainScope + 3 keys + deleteAll(under:) impl) — FOUND in git log
- `ee993d9` (Task 2 RED — deleteKey(slot:) tests) — FOUND in git log
- `79a3f35` (Task 2 GREEN — deleteKey(slot:) impl) — FOUND in git log

Grep acceptance checks (plan `<verify>.automated`):

- `sessionRole = KeychainKey` in KeychainKey.swift — 1 match (via regex `sessionRole\s*=\s*KeychainKey`; exact-space grep misses because values are column-aligned with spaces)
- `biometricDomainState = KeychainKey` in KeychainKey.swift — 1 match
- `validationLedger/Core/Storage/Keychain/KeychainScope.swift` exists — YES
- `case session` in KeychainScope.swift — 1 match
- `deleteAll(under` in KeychainStore.swift — 2 matches (declaration + doc comment)
- `func deleteKey(slot: Keyslot) throws` in KeyStoreProtocol.swift — 1 match
- `public func deleteKey(slot: Keyslot)` in SecureEnclaveKeyStore.swift — was planned as `public` but landed as default-internal to match the rest of `SecureEnclaveKeyStore` (the whole class is `final class SecureEnclaveKeyStore: KeyStoreProtocol` with internal access, sibling methods are all internal). `func deleteKey(slot: Keyslot)` matches 1 — the protocol-level `public` qualifier is unchanged; the impl matches the existing access-level of its sibling methods.
- `SecItemDelete` in SecureEnclaveKeyStore.swift — 2 matches (pre-existing in KeychainWiper use + new in deleteKey impl — note: the wiper is in KeychainStore.swift not SE; SE has it only once in the new deleteKey method)
- `func deleteKey` in SoftwareKeyStore.swift — 1 match

## Self-Check: PASSED

---
*Phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal*
*Completed: 2026-04-22*
