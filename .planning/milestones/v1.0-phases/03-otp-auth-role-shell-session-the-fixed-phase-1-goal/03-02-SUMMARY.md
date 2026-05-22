---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 02
subsystem: keystore + networking
tags: [ios, phase-2-followup, keystore, networking, carryover-fixes, wave-1, tdd]

# Dependency graph
requires:
  - phase: 02-networking-contract-and-device-keys
    provides: "SecureEnclaveKeyStore two-key pattern + SoftwareKeyStore sim parity + 4 acronym-tail endpoint RequestBodies (CR-02/IN-01/IN-02/IN-05 all Phase 2 carryovers)"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 01
    provides: "EndpointEncodingTests.swift Wave 0 stub with @Test(.disabled) placeholder — filled in this plan"
provides:
  - "Idempotent SecureEnclaveKeyStore.generateKey(slot:) — second call returns existing pubkey (CR-02 closed)"
  - "Unified DER X9.62 signature wire format across SoftwareKeyStore (sim) + SecureEnclaveKeyStore (device) (IN-02 closed)"
  - "Explicit CodingKeys on 4 acronym-tail RequestBodies: OTPVerify, DeviceRegister.DeviceFingerprint, KYCUploadChunk, KYCUploadCommit (IN-01/IN-05 closed)"
  - "7 new tests: 3 in SoftwareKeyStoreExtendedTests (signReturnsDER, signWithAuthorizationReturnsDER, cr02IdempotentGuardPresent) + 4 in EndpointEncodingTests (one per fixed endpoint)"
  - "1 existing test updated (SoftwareKeyStoreExtendedTests.signSize) — was asserting 64-byte raw format, now asserts 70–72 byte DER"
affects:
  - "03-09 (post-OTP D-27 7-step orchestration) — step 3+4 generateDeviceIdentityKeys is now safe to invoke twice without duplicate-key risk; step 5 POST /device/register emits install_uuid not install_u_u_i_d"
  - "03-05 (APIClient 429 Retry-After) — OTPVerifyEndpoint.RequestBody now has explicit CodingKeys that will be exercised by the 429 path fixture replay"
  - "Phase 5 KYC upload pipeline — KYCUploadChunkEndpoint + KYCUploadCommitEndpoint RequestBody wire format is now locked"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wire-contract pinning: explicit `private enum CodingKeys: String, CodingKey` on Encodable structs with acronym-tail properties (ID/UUID) paired with JSONEncoder.keyEncodingStrategy = .convertToSnakeCase. Defensive even when the current toolchain handles acronyms correctly — locks the contract against future Swift stdlib changes."
    - "Source-grep proxy tests for device-only invariants: `#filePath`-relative URL resolution in the test file reads the source file + asserts a marker string is present. Used here for CR-02 where real Secure Enclave behavior is HUMAN-UAT / Phase 4 device CI."
    - "DER X9.62 as the canonical ECDSA signature wire format across sim + device — P256.Signing.ECDSASignature.derRepresentation matches SecKeyCreateSignature's .ecdsaSignatureMessageX962SHA256 output byte-for-byte."

key-files:
  created: []
  modified:
    - validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift
    - validationLedger/Core/KeyStore/SoftwareKeyStore.swift
    - validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift
    - validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift
    - validationLedger/Core/Networking/Endpoints/KYCUploadChunkEndpoint.swift
    - validationLedger/Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift
    - validationLedgerTests/KeyStore/SoftwareKeyStoreExtendedTests.swift
    - validationLedgerTests/Networking/EndpointEncodingTests.swift

key-decisions:
  - "Extended existing SoftwareKeyStoreExtendedTests.swift rather than creating SoftwareKeyStoreTests.swift — the plan's stated path did not exist; the Extended file is the single Swift Testing @Suite for this keystore and adding the 3 new tests there is the plan's literal 'extend, don't replace' guidance."
  - "CR-02 verification uses a source-grep proxy test — real SE behavior is device-only (HUMAN-UAT / Phase 4). The test resolves the source file via #filePath-relative URL resolution rather than relying on xcodebuild's working directory, which is not guaranteed to be the repo root."
  - "Plan premise re: IN-01/IN-05 was partially incorrect on the current toolchain: Swift 5.9+/Xcode 26.4 JSONEncoder.convertToSnakeCase DOES correctly map otpSessionID → otp_session_id (not otp_session_i_d). Tests passed on first run before source fix (Rule 4-adjacent discovery). Explicit CodingKeys were still added per the plan's stated must_haves artifacts + as defensive wire-contract pinning against future toolchain drift."
  - "Destination substitution: iPhone 17 Pro / iOS 26.4 (currently-booted simulator) instead of plan-specified iPhone 15 / iOS 17.5 (runtime not installed) — same Rule 3 blocking env correction as Plan 01; iOS 17.0 deployment target makes either destination equivalent for verification."
  - "Rewrote existing signSize test as part of Task 1 RED phase — it was asserting `sig.count == 64` (raw format) which breaks once IN-02 flips to DER. New form asserts DER shape (0x30 tag + 70–72 bytes). Documented as a planned test update, not a deviation."

patterns-established:
  - "Carryover-fix lineage marker pattern: `// CR-02 (Phase 2 carryover, closed Phase 3 Plan 02): ...` comment preceding every fix block. Future verifier + engineers can `grep -R 'CR-02\\|IN-01\\|IN-02\\|IN-05'` to find every Phase 2 carryover resolution site."
  - "RED→GREEN atomic commit pattern per TDD: test commit precedes source fix commit; source fix commit message references the preceding RED commit's test names. Four commits total: RED Task 1 + GREEN Task 1 + RED Task 2 + GREEN Task 2."

requirements-completed:
  - AUTH-03
  - SESS-04

# Metrics
duration: 8min
completed: 2026-04-21
---

# Phase 03 Plan 02: Pre-Phase-3 Carryover Fixes Summary

**All 4 Pre-Phase-3 carryover fixes (CR-02 idempotent SE key generate, IN-01/IN-05 explicit CodingKeys on 4 endpoint RequestBodies, IN-02 DER X9.62 signature unification) landed with 7 new + 1 rewritten tests all green; zero regression on Phase 2's 14 APIClientEndpointTests.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-21 (first task commit 5280566)
- **Completed:** 2026-04-21 (final fix commit 1225ab7)
- **Tasks:** 2 / 2 (TDD: each split into RED test commit + GREEN fix commit = 4 commits total)
- **Files modified:** 8 (6 source + 2 test)
- **Files created:** 0

## Accomplishments

- **CR-02 closed.** `SecureEnclaveKeyStore.generateKey(slot:)` now returns the existing slot's public key via `try? loadPublicKey(slot: slot)` guard if one is already present, instead of inserting a second SecKey alongside the old. Downstream impact: Plan 09's D-27 steps 3+4 (`generateDeviceIdentityKeys`) are safe to invoke twice without duplicate-key risk breaking pub/priv pairing.
- **IN-02 closed.** `SoftwareKeyStore.sign(_:)` and `signWithAuthorization(_:)` now return `signature.derRepresentation` (DER X9.62, 70–72 bytes) instead of `rawRepresentation` (64-byte compact). This matches `SecureEnclaveKeyStore`'s `.ecdsaSignatureMessageX962SHA256` native output — backend sees identical signature bytes regardless of sim vs device build target.
- **IN-01 closed.** `OTPVerifyEndpoint.RequestBody` now has `private enum CodingKeys` with `case otpSessionID = "otpSessionId"`.
- **IN-05 closed (3 sites).** `DeviceRegisterEndpoint.DeviceFingerprintPayload.installUUID = "installUuid"`, `KYCUploadChunkEndpoint.RequestBody.uploadID = "uploadId"`, `KYCUploadCommitEndpoint.RequestBody.uploadID = "uploadId"` — all four RequestBody structs now have explicit CodingKeys that pin the wire contract.
- **7 new assertions + 1 rewritten:** `SoftwareKeyStoreExtendedTests` gains `signReturnsDER`, `signWithAuthorizationReturnsDER`, `cr02IdempotentGuardPresent`; the existing `signSize` was rewritten from raw to DER shape. `EndpointEncodingTests` was filled from a Wave 0 `@Test(.disabled(...))` stub to 4 real assertions (one per fixed endpoint). All pass green.
- **Zero Phase 2 regression.** `APIClientEndpointTests` (14 encode/decode fixture round-trips) still all green — the CodingKeys additions are additive on the Encodable side; the Decodable side already had its CodingKeys for these acronym fields per Phase 2's IN-01 partial fix on Response.

## Task Commits

Each task was committed atomically following TDD (RED commit → GREEN commit). Worktree mode uses `--no-verify` per parallel-execution policy.

| Commit | Type | Subject |
|--------|------|---------|
| `5280566` | test | Task 1 RED — add failing tests for CR-02 idempotent SE guard + IN-02 DER unification |
| `4d448a9` | fix  | Task 1 GREEN — CR-02 idempotent SE key generate + IN-02 DER unification |
| `27127f6` | test | Task 2 RED — acronym-tail CodingKeys regression tests for IN-01/IN-05 |
| `1225ab7` | fix  | Task 2 GREEN — IN-01 + IN-05 explicit CodingKeys on 4 endpoint RequestBodies |

**Plan metadata commit:** pending (appended with SUMMARY.md via orchestrator).

## Files Modified

### Source (6)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` | CR-02 idempotent guard at top of `generateKey(slot:)` + marker comment | +8 |
| `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` | IN-02 `sign` + `signWithAuthorization` → `signature.derRepresentation` + marker comments | +10 / -2 |
| `validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift` | IN-01 `private enum CodingKeys` on RequestBody: `case otpSessionID = "otpSessionId"` + `case code` | +12 |
| `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` | IN-05 `private enum CodingKeys` on DeviceFingerprintPayload: `case installUUID = "installUuid"` (+ model, iosVersion) | +10 |
| `validationLedger/Core/Networking/Endpoints/KYCUploadChunkEndpoint.swift` | IN-05 `private enum CodingKeys` on RequestBody: `case uploadID = "uploadId"` (+ chunkIndex, chunkData, chunkSha256) | +11 |
| `validationLedger/Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift` | IN-05 `private enum CodingKeys` on RequestBody: `case uploadID = "uploadId"` | +8 |

### Test (2)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedgerTests/KeyStore/SoftwareKeyStoreExtendedTests.swift` | +3 new `@Test`s (IN-02 sign, IN-02 signWithAuthorization, CR-02 source-grep proxy); +1 rewritten existing test (signSize raw→DER) | +61 / -2 |
| `validationLedgerTests/Networking/EndpointEncodingTests.swift` | Filled Wave 0 stub: +4 new `@Test`s (one per fixed endpoint) + shared `snakeEncoder` helper | +61 / -4 |

## Test Results

**SoftwareKeyStoreExtendedTests — 7 passed** (4 pre-existing + 3 new):

```
✔ generateDeviceIdentityKeys returns two distinct 64-byte public keys          (pre-existing)
✔ publicKeyRepresentation returns the device-slot public key                   (pre-existing)
✔ sign and signWithAuthorization produce distinct signatures for the same input (pre-existing)
✔ sign produces DER X9.62 ECDSA P-256 signature (IN-02 — matches SE wire format) (rewritten)
✔ IN-02 — sign(_:) returns DER X9.62 (starts with 0x30 SEQUENCE tag)           (new)
✔ IN-02 — signWithAuthorization(_:) returns DER X9.62                          (new)
✔ CR-02 — SecureEnclaveKeyStore.generateKey idempotent guard is present (source-grep proxy) (new)
```

**EndpointEncodingTests — 4 passed (all new, filled from Wave 0 stub):**

```
✔ IN-01 — OTPVerifyEndpoint.RequestBody encodes otpSessionID → otp_session_id
✔ IN-05 — DeviceRegisterEndpoint.DeviceFingerprintPayload encodes installUUID → install_uuid
✔ IN-05 — KYCUploadChunkEndpoint.RequestBody encodes uploadID → upload_id
✔ IN-05 — KYCUploadCommitEndpoint.RequestBody encodes uploadID → upload_id
```

**APIClientEndpointTests — 14 passed (no Phase 2 regression):**

All 14 encode/decode fixture round-trips across OTPRequest, OTPVerify, DeviceRegister, KYCUploadInit, KYCUploadChunk, KYCUploadCommit, KYCStatus green.

**Total:** 25 tests in 3 suites, `** TEST SUCCEEDED **` (full combined run in commit 1225ab7).

## Decisions Made

- **Destination substitution** (same as Plan 01): used `iPhone 17 Pro / iOS 26.4` because the plan-specified `iPhone 15 / iOS 17.5` runtime is not installed in this environment. Project deployment target is iOS 17.0 — any iOS 17+ simulator is equivalent for verification.
- **Test file location correction:** plan referenced `validationLedgerTests/KeyStore/SoftwareKeyStoreTests.swift` but the actual file is `SoftwareKeyStoreExtendedTests.swift`. Extended that file per the plan's literal "extend, don't replace" guidance. No new file created.
- **CR-02 via source-grep proxy:** real SE behavior is HUMAN-UAT / Phase 4 device CI. The simulator test reads the source via `#filePath`-relative URL resolution and asserts the `try? loadPublicKey(slot: slot)` guard + `CR-02` marker comment are present. This is the plan's prescribed "acceptable test variant."
- **Tests passed BEFORE source fix for Task 2 (unexpected GREEN in RED phase):** the plan assumed Swift's `JSONEncoder.convertToSnakeCase` mangles `otpSessionID` → `otp_session_i_d`. A standalone `swift /tmp/snake_test.swift` check confirmed the current Swift 5.9+/Xcode 26.4 toolchain correctly emits `otp_session_id`/`install_uuid`/`upload_id` without explicit CodingKeys. Applied Rule 2 (defensive correctness): still added the CodingKeys per plan must_haves, treating them as wire-contract pinning against future toolchain drift. Tests serve as regression locks.
- **Existing `signSize` test rewritten** as part of Task 1 RED: it previously asserted `sig.count == 64` (raw format). The IN-02 fix flips to DER which is 70–72 bytes — the old assertion would have broken. Rewrote in the RED commit to assert the DER shape so GREEN leaves the test green. Documented in the Task 1 test commit body.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking Env Correction] Substituted `iPhone 17 Pro / iOS 26.4` for plan-specified `iPhone 15 / iOS 17.5` destination**
- **Found during:** Task 1 RED build verification
- **Issue:** `xcrun simctl list devices available` shows no iPhone 15 / iOS 17.5 runtime. Installed: iOS 15.2, 18.0–18.4, 26.2, 26.4. Project Xcode SDK is 26.4 (per `CLAUDE.md`).
- **Fix:** Ran `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'` for all verification. iOS 17.0 deployment target makes any iOS 17+ destination equivalent.
- **Files modified:** None (CLI only).
- **Verification:** `** TEST SUCCEEDED **` on all three suites.
- **Committed in:** N/A — test-run CLI only, no file changes.

**2. [Rule 3 — File path correction] Plan-specified `SoftwareKeyStoreTests.swift` does not exist; extended `SoftwareKeyStoreExtendedTests.swift` instead**
- **Found during:** Task 1 RED file-read step
- **Issue:** `validationLedgerTests/KeyStore/` contains only `SoftwareKeyStoreExtendedTests.swift` (the single Swift Testing @Suite for this keystore). Plan frontmatter + must_haves referenced the non-existent file.
- **Fix:** Added the 3 new tests + rewrote the existing `signSize` test inside `SoftwareKeyStoreExtendedTests.swift`. Matches the plan's literal "extend the existing `@Suite`" directive; only the filename differs from the plan text.
- **Files modified:** `validationLedgerTests/KeyStore/SoftwareKeyStoreExtendedTests.swift` (instead of `...Tests.swift`).
- **Verification:** All 7 tests pass green.
- **Committed in:** 5280566 (RED), 4d448a9 (GREEN).

**3. [Rule 2-adjacent — Defensive correctness despite unreproducible premise] Toolchain does not exhibit the acronym-mangle bug IN-01/IN-05 describes, but explicit CodingKeys still applied as defensive wire-contract pinning**
- **Found during:** Task 2 RED run — tests passed on the first try before source fix (expected RED, got GREEN)
- **Issue:** Plan states `.convertToSnakeCase` produces `otp_session_i_d` / `install_u_u_i_d` / `upload_i_d` on acronym-tail properties. Standalone `swift /tmp/snake_test.swift` check against the current Swift 5.9+/Xcode 26.4 toolchain produced `otp_session_id` / `install_uuid` / `upload_id` correctly. Swift's acronym handling has evidently improved since the bug was originally identified in Phase 2 review.
- **Fix:** Still added all 4 explicit `CodingKeys` enums per plan `must_haves.artifacts` and `must_haves.truths`. They pin the wire contract regardless of future toolchain changes, and the plan's downstream verifier explicitly checks for their presence (`grep -c 'case otpSessionID = "otpSessionId"' ...` etc.). The tests serve as regression locks.
- **Files modified:** 4 endpoint files + 1 test file (as planned).
- **Verification:** All 4 EndpointEncodingTests pass green (both before AND after source fix — before proves the current toolchain doesn't regress; after proves the explicit contract matches the toolchain's current output).
- **Committed in:** 27127f6 (tests), 1225ab7 (source).

**4. [Planned test update] Existing `signSize` test rewritten from raw (64-byte) to DER (70–72 byte) shape assertion**
- **Found during:** Task 1 RED authoring
- **Issue:** The existing `signSize` test in `SoftwareKeyStoreExtendedTests` asserted `sig.count == 64` (raw format). The IN-02 fix flips sign output to DER (70–72 bytes) — the old assertion would break in GREEN.
- **Fix:** Rewrote the assertion to match DER shape (`sig.first == 0x30` + `sig.count >= 70 && <= 72`). This IS a test update, not a bug fix. Kept the same `func signSize` name since call-site references (if any) would otherwise break; renamed the `@Test` display name to reflect new semantics ("sign produces DER X9.62 ECDSA P-256 signature (IN-02 — matches SE wire format)").
- **Files modified:** `validationLedgerTests/KeyStore/SoftwareKeyStoreExtendedTests.swift`.
- **Verification:** All 7 tests pass green.
- **Committed in:** 5280566 (RED, with the rewrite), 4d448a9 (GREEN confirms).

---

**Total deviations:** 4 auto-fixed (2 blocking env/path corrections, 1 defensive-correctness under unreproducible premise, 1 planned test rewrite).
**Impact on plan:** No scope change. All plan `success_criteria` checkboxes, all `must_haves.truths`, and all `must_haves.artifacts` paths + `contains` patterns satisfied as written.

## TDD Gate Compliance

Plan frontmatter does not have `type: tdd`, but individual tasks had `tdd="true"`. Each task followed RED → GREEN atomic commits:

| Task | RED commit | GREEN commit | Notes |
|------|-----------|--------------|-------|
| 1 (CR-02 + IN-02) | 5280566 (test) | 4d448a9 (fix) | RED confirmed failing: 7 issues across 4 assertions (existing signSize + 3 new). GREEN all 7 tests pass. |
| 2 (IN-01 + IN-05) | 27127f6 (test) | 1225ab7 (fix) | RED unexpectedly passed — toolchain doesn't reproduce the mangle bug. GREEN adds defensive CodingKeys per plan must_haves; tests continue to pass. Rule 2 applied (see Deviation 3). |

Both RED commits precede their GREEN commits; `git log --oneline` verifies chronological order. No TDD gate violations.

## Known Stubs

**None introduced by this plan.** Plan 01's Wave 0 stub `EndpointEncodingTests.swift` is now filled with 4 real assertions — removed from the pending-stub ledger. The 12 other Wave 0 stubs remain intact and traceable to their owning plans per the Plan 01 Stub-to-Plan Mapping.

## Threat Flags

Per plan `<threat_model>`: Phase 3 Plan 02 threats were all `mitigate` disposition, and all four mitigations landed:

| Threat ID | Mitigation landed? | Evidence |
|-----------|---------------------|----------|
| T-03-02-01 Duplicate SE key insertion | YES | `if let existingPub = try? loadPublicKey(slot: slot) { return existingPub }` at top of `generateKey(slot:)` + `cr02IdempotentGuardPresent` test |
| T-03-02-02 Sim/device signature format divergence | YES | Both `sign` + `signWithAuthorization` return `derRepresentation`; 0 remaining `signature.rawRepresentation` refs + 2 DER-shape tests |
| T-03-02-03 Acronym-tail property wire-format mangle | YES | All 4 RequestBody structs have `private enum CodingKeys` with camelCase raw values + 4 snake_case round-trip assertion tests |
| T-03-02-04 Wrong key signs payload after duplicate insertion | YES (transitive) | Same mitigation as T-03-02-01 — prevents the root cause |

**No new threat surface introduced.** All changes add defensive explicit contracts or fix identified Phase 2 carryovers. No new network endpoints, no new file access, no new trust boundaries. Omitting the "Threat Flags" flagged-rows section (no new flags to report).

## Issues Encountered

- **Plan premise re: IN-01/IN-05 did not reproduce on the current toolchain.** The plan describes `.convertToSnakeCase` producing `otp_session_i_d` etc. on acronym-tail properties. Quick standalone `swift <file>` check with a fresh `Encodable` struct proved the current toolchain produces the correct `otp_session_id` etc. without explicit CodingKeys. Applied Rule 2 (defensive correctness) — CodingKeys still landed as wire-contract pinning. Documented in Deviation 3; plan must_haves still satisfied.
- **Test file name drift.** Plan referenced `SoftwareKeyStoreTests.swift`; actual file is `SoftwareKeyStoreExtendedTests.swift`. Extended the existing file per the plan's "extend, don't replace" directive. Documented in Deviation 2.

## User Setup Required

None. No external services, no secrets, no dashboard changes. All work is source + test edits verifiable via `xcodebuild test`.

## Next Phase Readiness

- **Plan 03 (`PlatformPayloadField`)** can proceed — test stub `PlatformPayloadFieldTests.swift` from Plan 01 is still pending. Plan 02 has no cross-impact on that plan.
- **Plan 05 (`APIClientRateLimit`)** now has both the fixture (`otp-verify-rate-limited.json` from Plan 01) AND the OTPVerifyEndpoint's explicit RequestBody CodingKeys wire-format-locked for the 429 replay path.
- **Plan 09 (post-OTP D-27 7-step orchestration)** is now safe to author: step 3 + 4 (`generateDeviceIdentityKeys`) can be invoked idempotently without duplicate-SE-key risk; step 5 `POST /device/register` will emit `install_uuid` correctly; `OTPVerifyEndpoint` wire format is locked for the preceding step 1.
- **Phase 4 device CI (CI-03)** will need to exercise the real CR-02 idempotent path on hardware — the source-grep proxy test here only confirms the fix is present, not that SE honors the behavior. Tracked as HUMAN-UAT per Plan `behavior` section.
- **Downstream verifier should check:** all 6 grep assertions in the plan's `<verify>` section pass (`try? loadPublicKey(slot: slot)` count, `signature.derRepresentation` count, `signature.rawRepresentation` count = 0, and the 4 `case X = "Y"` patterns in the 4 endpoint files). Confirmed locally; all 6 checks green.

## Self-Check

Files claimed modified:

- `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift` — FOUND (diff +8 lines, CR-02 guard + marker)
- `validationLedger/Core/KeyStore/SoftwareKeyStore.swift` — FOUND (diff +10/-2, IN-02 derRepresentation x2)
- `validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift` — FOUND (diff +12, IN-01 CodingKeys)
- `validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift` — FOUND (diff +10, IN-05 CodingKeys on DeviceFingerprintPayload)
- `validationLedger/Core/Networking/Endpoints/KYCUploadChunkEndpoint.swift` — FOUND (diff +11, IN-05 CodingKeys)
- `validationLedger/Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift` — FOUND (diff +8, IN-05 CodingKeys)
- `validationLedgerTests/KeyStore/SoftwareKeyStoreExtendedTests.swift` — FOUND (diff +61/-2, 3 new + 1 rewritten tests)
- `validationLedgerTests/Networking/EndpointEncodingTests.swift` — FOUND (diff +61/-4, 4 real tests from Wave 0 stub)

Commits claimed made:

- `5280566` (Task 1 RED) — FOUND
- `4d448a9` (Task 1 GREEN) — FOUND
- `27127f6` (Task 2 RED) — FOUND
- `1225ab7` (Task 2 GREEN) — FOUND

Grep acceptance checks:

- `try? loadPublicKey(slot: slot)` in `SecureEnclaveKeyStore.swift` — 1 (expected >= 1)
- `CR-02` marker in `SecureEnclaveKeyStore.swift` — 1 (expected >= 1)
- `signature.derRepresentation` in `SoftwareKeyStore.swift` — 2 (expected >= 2; sign + signWithAuthorization)
- `signature.rawRepresentation` in `SoftwareKeyStore.swift` — 0 (expected 0)
- `case otpSessionID = "otpSessionId"` in `OTPVerifyEndpoint.swift` — 1 (expected 1)
- `case installUUID = "installUuid"` in `DeviceRegisterEndpoint.swift` — 1 (expected 1)
- `case uploadID = "uploadId"` in `KYCUploadChunkEndpoint.swift` — 1 (expected 1)
- `case uploadID = "uploadId"` in `KYCUploadCommitEndpoint.swift` — 1 (expected 1)

## Self-Check: PASSED

---
*Phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal*
*Completed: 2026-04-21*
