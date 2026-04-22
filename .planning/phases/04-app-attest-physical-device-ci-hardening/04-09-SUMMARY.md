---
phase: 04-app-attest-physical-device-ci-hardening
plan: 09
subsystem: testing
tags: [swift-testing, device-tests, app-attest, dcappattest, secure-enclave, biometric, keychain, logout, d-13, d-03, d-14]
wave: 4

# Dependency graph
requires:
  - phase: 04-app-attest-physical-device-ci-hardening
    provides: "AttestedKeyStore (Plan 03), DCAppAttestAttestationService (Plan 03), MockURLProtocol fixtures + device-challenge/register/heartbeat JSON (Plan 02), SeededBiometricService + SeededLAContext (Plan 02), AppContainer.biometricServiceOverride test seam (Plan 06), AttestationError/AttestationStatus/TrustTier (Plan 01)"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    provides: "DefaultLogoutService.logout(reason:) async, KeychainScope.session membership, AppContainer composition root"
  - phase: 02-networking-contract-device-keys
    provides: "KeychainStore, SecureEnclaveKeyStore, KeyStoreProtocol.generateDeviceIdentityKeys(), validationLedgerDeviceTests target (Phase 2 Plan 18) with SecureEnclaveKeyStoreTests analog shape"
  - phase: 01-foundational-conventions-scaffolding
    provides: "OSLogLoggerImpl + LoggingSubsystem.auth, Swift Testing harness, App Attest entitlement file wired into the signed binary"

provides:
  - "validationLedgerDeviceTests/AppAttestRoundTripTests.swift — D-13 (3) App Attest attestKey + generateAssertion real-hardware round-trip with MockURLProtocol-backed /device/challenge + /device/register + /device/heartbeat fixtures; accept-either-outcome for quotaExceeded (Pitfall 2)"
  - "validationLedgerDeviceTests/KeychainBiometricACLTests.swift — D-13 (2) + D-14 seeded-biometric ACL round-trip; SeededBiometricService injected via AppContainer(biometricServiceOverride:); accept-either-outcome for errSecAuthFailed on unattended CI"
  - "validationLedgerDeviceTests/LogoutClearsAuthorizationKeyTests.swift — D-13 (4) logout SE ACL clearing (SESS-04) + D-03 invariant pinned on device (attestedKeyId MUST survive logout)"
  - "Phase 3 HUMAN-UAT item #4 (logout wipes keys) retired into CI coverage per the Phase 4 D-13 contract (04-CONTEXT.md L79-82)"
  - "Every test defer-purges the Keychain keys it touches — cross-test state-leak discipline (T-APP-ATTEST-14 mitigation)"

affects:
  - 04-10 (CI YAML upgrades to run the full validationLedgerDeviceTests target on self-hosted iPhone runner — these three suites are what it executes)
  - 05-* (every future device-scoped regression test will follow the @Suite + purge-in-defer + accept-either-outcome pattern established here)

# Tech tracking
tech-stack:
  added:
    - "None — all frameworks (Testing, Foundation, Security, DeviceCheck, CryptoKit) already in Phase 1–3 stack"
  patterns:
    - "Accept-either-outcome for biometric/App-Attest device tests — two valid terminal states (.success OR errSecAuthFailed; .attested OR .quotaExceeded) encoded inline with documentation, so unattended CI + quota-pressured Apple servers do not cause red builds"
    - "purge-in-defer Keychain cleanup — each @Test starts from a known-empty state and leaves the device clean for the next test on the same physical iPhone"
    - "AppContainer(biometricServiceOverride: SeededBiometricService()) as the composition seam for tests that need real KeychainStore + real SecureEnclaveKeyStore + real LogoutService but MUST NOT prompt Face ID"
    - "Direct SE application-tag probe (SecItemCopyMatching with kSecAttrApplicationTag + kSecAttrKeyType) as the post-logout assertion surface — sidesteps SecureEnclaveKeyStore.publicKeyRepresentation's device-slot bias and lets the test observe authKey-slot deletion independently"
    - "Positive-contrast assertions in invariant tests — logoutPreservesAttestedKeyId also asserts sessionToken was wiped, so the test proves logout ran AND the D-03 carve-out held (not just that nothing happened)"

key-files:
  created:
    - "validationLedgerDeviceTests/AppAttestRoundTripTests.swift"
    - "validationLedgerDeviceTests/KeychainBiometricACLTests.swift"
    - "validationLedgerDeviceTests/LogoutClearsAuthorizationKeyTests.swift"
  modified: []

key-decisions:
  - "Used AppContainer(biometricServiceOverride: SeededBiometricService()) in LogoutClearsAuthorizationKeyTests rather than stitching KeychainStore + SecureEnclaveKeyStore + DefaultLogoutService by hand — the real composition root wires LogoutService's dependencies (401 interceptor, session reset, SecureEnclaveKeyStore auth-slot deletion) exactly the way production does, so the test validates the real logout teardown rather than a hand-rolled approximation. The plan's gotcha note about 'AppContainer init complexity' turned out not to apply — the init signature is 4 params, all defaulted except `env: Environment.current`."
  - "Directly queried the SE for the authKey application tag post-logout (SecItemCopyMatching with kSecAttrApplicationTag = 'com.maldin.validationLedger.authKey') rather than calling SecureEnclaveKeyStore.publicKeyRepresentation(). Rationale: publicKeyRepresentation targets the DEVICE slot, so it could return a stale device-slot key and mask auth-slot deletion. Direct tag probe asserts errSecItemNotFound = authorization key is truly gone from the SEP."
  - "Added a companion assertion in logoutClearsAuthorizationKey that the deviceKey SE entry SURVIVES logout (errSecSuccess). This pins D-16 STEP 3 (next OTP re-register uses the same deviceKey) the same way D-03 pins attestedKeyId preservation — device identity is not session-bound."
  - "Honest test names — the suite avoids any 'biometric_auth_roundtrip' naming (Pitfall 5); D-14 tests assert KEYCHAIN ACL STORAGE round-trip, the D-13-4 test asserts LOGOUT SE ACL CLEARING, the D-03 test asserts INVARIANT PRESERVATION. No test name overclaims end-to-end biometric authentication."

patterns-established:
  - "Pattern: device-test @Suite shape — `import Testing + Foundation + Security (+ DeviceCheck / CryptoKit as needed) + @testable import validationLedger`, struct conforming to `@Suite(name)`, purge helper + defer in every @Test, documentation header explaining target-membership rationale (SE absent on simulator) + accept-either-outcome rationale (Pitfall 2 / CI biometric) + D-traceability (D-13, D-14, D-03, SESS-04, D-16)"
  - "Pattern: @MainActor device test — when the SUT uses AppContainer (which is @MainActor for SceneDelegate's benefit), the test's helper AND each @Test carry @MainActor so the container can be constructed and its members read without hopping isolation domains"
  - "Pattern: sessionToken-as-control-variable — tests that assert attestedKeyId PRESERVATION also seed + assert sessionToken wiping, so the test proves both (a) logout actually executed and (b) it discriminated between session-scope and attestation-scope items"

requirements-completed: [DEV-04, CI-03]

# Metrics
duration: ~3h (split across two sessions: original executor Wave 4 start → Anthropic-quota pause → continuation session after quota reset)
completed: 2026-04-22
---

# Phase 4 Plan 9: Device Test Suite (D-13 + D-14 + D-03) Summary

**Three device-only Swift Testing suites (AppAttestRoundTripTests + KeychainBiometricACLTests + LogoutClearsAuthorizationKeyTests) that compile for `generic/platform=iOS` and exercise real SE + real App Attest + real Keychain ACL + real LogoutService on a physical iPhone — the CI-03 payload that Plan 10's self-hosted runner actually runs.**

## Performance

- **Duration:** ~3h wall clock (interrupted by Anthropic quota pause mid-Task-3; continuation session reviewed the drafted file, confirmed the AppContainer init call matches the real signature, ran the device build, and committed)
- **Started:** 2026-04-21 (Wave 4 parallel kickoff — see phase-04 Wave 4 pause note `a4052db`)
- **Completed:** 2026-04-22T16:47:00Z
- **Tasks:** 3 / 3
- **Files created:** 3 (all under `validationLedgerDeviceTests/`)
- **Files modified:** 0

## Accomplishments

- AppAttestRoundTripTests lands real-hardware attestKey + generateAssertion coverage with MockURLProtocol-backed challenge/register/heartbeat fixtures — the FIRST test in the repo that calls DCAppAttestService.shared on real SE hardware (D-13-3).
- KeychainBiometricACLTests lands `.biometryCurrentSet` ACL-bound Keychain item storage + retrieval behind `SeededBiometricService` so unattended CI does not prompt Face ID (D-13-2 + D-14).
- LogoutClearsAuthorizationKeyTests lands the SESS-04 logout teardown assertion (authorizationKey SE entry deleted + sessionToken wiped) alongside the D-03 invariant assertion (attestedKeyId PRESERVED across logout). The test also asserts deviceKey SURVIVES logout (D-16 STEP 3).
- Every test carries a defer-block Keychain purge — T-APP-ATTEST-14 state-leak threat mitigated at the test-discipline level.
- Phase 3 HUMAN-UAT item #4 ("logout wipes keys") is now retired into CI coverage.
- `xcodebuild build -scheme validationLedger -destination 'generic/platform=iOS' -configuration Debug -only-testing:validationLedgerDeviceTests` returns **BUILD SUCCEEDED** with **0 errors** — the acceptance criterion for this plan.
- No pbxproj edit needed — `validationLedgerDeviceTests` uses Xcode's `PBXFileSystemSynchronizedRootGroup`, so a file dropped on disk under that directory is auto-added to Compile Sources. Confirmed by inspecting `project.pbxproj` lines 27-31 and observing the two sibling test files (committed in Tasks 1 + 2) are also not individually listed.

## Task Commits

Parallel Wave 4 protocol — each task committed with `--no-verify` to avoid cross-wave hook interactions on the worktree branch.

1. **Task 1: AppAttestRoundTripTests.swift (D-13-3)** — `f02a9a4` (test)
2. **Task 2: KeychainBiometricACLTests.swift (D-13-2 + D-14)** — `d8cc981` (test)
3. **Task 3: LogoutClearsAuthorizationKeyTests.swift (D-13-4 + D-03)** — `02de890` (test)

**Plan metadata commit:** forthcoming after this SUMMARY lands (`docs(04-09): add SUMMARY after continuation`).

## Files Created/Modified

- `validationLedgerDeviceTests/AppAttestRoundTripTests.swift` — @Suite for real-device App Attest attestKey + generateAssertion with accept-either-outcome for quotaExceeded (Pitfall 2) and MockURLProtocol fixtures for /device/challenge + /device/register + /device/heartbeat.
- `validationLedgerDeviceTests/KeychainBiometricACLTests.swift` — @Suite using `AppContainer(biometricServiceOverride: SeededBiometricService())` to assert `.biometryCurrentSet` ACL items can be stored + retrieved without prompting Face ID in CI (D-14).
- `validationLedgerDeviceTests/LogoutClearsAuthorizationKeyTests.swift` — @Suite with two @Test methods: `logoutClearsAuthorizationKey` (SESS-04 teardown: session token wiped + authorizationKey SE entry deleted + deviceKey survives) and `logoutPreservesAttestedKeyId` (D-03 invariant: attestedKeyId survives logout while sessionToken is wiped).

## Decisions Made

- **AppContainer as the test seam (vs. hand-rolled composition)** — The plan's Task 3 action block flagged "AppContainer init complexity" and suggested a fallback to hand-stitched KeychainStore + SecureEnclaveKeyStore + LogoutService. The fallback was NOT needed: the real init has 4 parameters (3 defaulted), only `env: Environment.current` is required, and `biometricServiceOverride: SeededBiometricService()` neutralizes the only Face-ID-prompting surface inside the container. Using the real composition root validates the REAL logout teardown path (including 401 interceptor wiring, sessionLock observation, SecureEnclaveKeyStore.deleteKey(slot: .authorization)).
- **Direct SE application-tag probe for post-logout assertion** — `SecureEnclaveKeyStore.publicKeyRepresentation()` reads the device slot; using it to assert auth-slot deletion would be ambiguous at best and a false-positive at worst. The test queries `SecItemCopyMatching(kSecAttrApplicationTag = "com.maldin.validationLedger.authKey")` directly and asserts `errSecItemNotFound`. This is the SEP-level authoritative check.
- **Positive-contrast assertions in invariant tests** — `logoutPreservesAttestedKeyId` seeds both `attestedKeyId` and `sessionToken`, then after `logout(reason:)` asserts BOTH that sessionToken was wiped AND attestedKeyId survives. Proving the carve-out requires proving the teardown ran — otherwise a no-op logout would pass the "survives" assertion spuriously.
- **Honest test naming (Pitfall 5 enforced)** — No test name contains "biometric_auth_roundtrip" or similar end-to-end claims. The suite names are mechanistic: `LogoutClearsAuthorizationKeyTests`, and the @Test methods are `logoutClearsAuthorizationKey` + `logoutPreservesAttestedKeyId` (both of which honestly describe the single Keychain/SE operation under test).

## Deviations from Plan

### Process deviations

**1. Continuation across two sessions (Anthropic quota pause).**
- **Found during:** End of Task 2 execution on 2026-04-21 (phase-04 Wave 4 kickoff).
- **Issue:** Anthropic API quota bite during Wave 4 parallel execution paused the executor (see commit `a4052db` — "pause Wave 4 — executors hit Anthropic quota; worktrees preserved"). The executor had already landed Task 1 (`f02a9a4`) and Task 2 (`d8cc981`) as commits, and had drafted `validationLedgerDeviceTests/LogoutClearsAuthorizationKeyTests.swift` on disk (205 lines, fully formed @Suite with two @Test methods + purge helper + defer blocks + API-contract header) but had not yet added it to git, built it, or committed it.
- **Fix:** After quota reset, a continuation executor in the same worktree (`agent-a8a9f3ba`) reviewed the drafted file against Task 3's action block, confirmed that the real `AppContainer.init(env:networkConfig:isSecureEnclaveAvailable:biometricServiceOverride:)` signature matches the test's call exactly (no compile error), verified all six Task 3 acceptance-criteria greps pass, ran `xcodebuild build -scheme validationLedger -destination 'generic/platform=iOS' -configuration Debug -only-testing:validationLedgerDeviceTests` (BUILD SUCCEEDED, 0 errors), and committed the file in a single `test(04-09): ...` commit (`02de890`). No rewrite or rebase of the prior two commits occurred.
- **Files affected:** `validationLedgerDeviceTests/LogoutClearsAuthorizationKeyTests.swift` (single-commit add)
- **Verification:** (a) `git log --oneline 67485a0..HEAD` shows exactly three test commits (Tasks 1/2/3) on the worktree branch; (b) `xcodebuild build ... generic/platform=iOS -only-testing:validationLedgerDeviceTests` succeeds with `** BUILD SUCCEEDED **` and `grep -c "error:" → 0`; (c) all Task 3 acceptance-criteria greps pass their thresholds (see Self-Check below).
- **Committed in:** `02de890` (Task 3 commit)

### Plan-action-block deviations

**2. Skipped pbxproj edit — file-system-synchronized group auto-discovers the test file.**
- **Found during:** Step 2 of the continuation session (wire the test file into the Xcode project).
- **Issue:** The plan instructed "add `LogoutClearsAuthorizationKeyTests.swift` to the Xcode project (`validationLedger.xcodeproj/project.pbxproj`) under the `validationLedgerDeviceTests` target's Compile Sources." Inspecting the pbxproj, the `validationLedgerDeviceTests` target uses `isa = PBXFileSystemSynchronizedRootGroup` (Xcode 16+ file-system-sync feature) at lines 27-31 and references that group via `fileSystemSynchronizedGroups = ( A30000000000000000000009 /* validationLedgerDeviceTests */ )` at lines 175-177. No individual file references exist in the pbxproj for the two sibling test files (AppAttestRoundTripTests.swift, KeychainBiometricACLTests.swift) committed in Tasks 1 + 2 — they build because they are on disk under the synchronized root.
- **Fix:** No pbxproj edit performed. The file was added to git and built via the existing file-system-sync mechanism. `git status` at the end of Task 3 shows pbxproj UNTOUCHED.
- **Verification:** `xcodebuild build ... -only-testing:validationLedgerDeviceTests` compiles `LogoutClearsAuthorizationKeyTests.swift` into the `validationLedgerDeviceTests.xctest` bundle with zero errors, proving the file is picked up by the target.
- **Committed in:** N/A (no change required)

---

**Total deviations:** 2 (1 process — quota-induced session split; 1 plan-action-block correction — pbxproj edit obsoleted by Xcode 16's PBXFileSystemSynchronizedRootGroup). Both surfaced during execution, neither introduced scope creep, and both are documented for future planners.
**Impact on plan:** Zero. The 3 files delivered match the plan's `files_modified` frontmatter exactly; acceptance criteria for all three tasks pass.

## Issues Encountered

- **Anthropic API quota pause mid-Wave 4.** Handled by a continuation session in the same worktree after quota reset. Two pre-existing commits (Task 1 `f02a9a4`, Task 2 `d8cc981`) preserved; Task 3 draft reviewed and committed as `02de890`.

## Threat Flags

None. All files are test-only and run in the `validationLedgerDeviceTests` target (NOT shipped to App Store). The Plan's threat register (T-APP-ATTEST-01 / -13 / -14) is mitigated by this plan's artifacts rather than introduced.

## User Setup Required

None — these are CI-runtime tests. Plan 10's self-hosted iPhone runner is where they execute; that infrastructure setup is scoped to Plan 10 and Plan 10's USER-SETUP document.

## Next Phase Readiness

- Plan 10 (the CI YAML upgrade) can proceed. The `validationLedgerDeviceTests.xctest` bundle now contains 3 device-only suites covering the D-13 contract (SE round-trip from Phase 2 + Keychain-ACL + App-Attest + logout-clearing) plus the D-03 invariant on real hardware.
- Plan 10 should invoke `xcodebuild test -scheme validationLedger -destination 'platform=iOS,id=<self-hosted-device-UDID>' -only-testing:validationLedgerDeviceTests`. The build step already passes; the test execution surface is what the physical runner validates.
- The accept-either-outcome patterns in the two biometric/Attest tests mean Plan 10 does NOT need conditional CI logic to tolerate `errSecAuthFailed` or `quotaExceeded` — the tests absorb those states inline.
- No blockers carried into Plan 10 or Phase 5.

## Self-Check: PASSED

### Files exist
- `validationLedgerDeviceTests/AppAttestRoundTripTests.swift` — FOUND
- `validationLedgerDeviceTests/KeychainBiometricACLTests.swift` — FOUND
- `validationLedgerDeviceTests/LogoutClearsAuthorizationKeyTests.swift` — FOUND

### Commits exist
- `f02a9a4` (Task 1) — FOUND in `git log`
- `d8cc981` (Task 2) — FOUND in `git log`
- `02de890` (Task 3) — FOUND in `git log`

### Task 3 acceptance-criteria greps (plan lines 486-496)
- `grep -c "logoutClearsAuthorizationKey\|logoutPreservesAttestedKeyId"` → **2** (required: 2)
- `grep -c "logoutService.logout"` → **2** (required: 2)
- `grep -c "attestedKeyId"` → **18** (required: ≥3)
- `grep -c "keyid-survives-logout"` → **3** (required: ≥2)
- `grep -c "D-03"` → **8** (required: ≥1)

### Build verification
- `xcodebuild build -scheme validationLedger -destination 'generic/platform=iOS' -configuration Debug -only-testing:validationLedgerDeviceTests` → **BUILD SUCCEEDED**
- `grep -c "error:"` on build output → **0** (required: 0)

### Plan-level verification (04-09-PLAN.md lines 521-527)
1. 3 device-test files exist with @Suite/@Test structure — CONFIRMED
2. Every test has defer-block Keychain purge — CONFIRMED (grepped `defer { purge` in all 3 files)
3. AppAttestRoundTripTests tolerates quotaExceeded (Pitfall 2) — CONFIRMED (Task 1 file header + test body)
4. KeychainBiometricACLTests uses SeededBiometricService + biometricServiceOverride (D-14) — CONFIRMED (Task 2 file)
5. LogoutClearsAuthorizationKeyTests pins D-03 on device — CONFIRMED (`logoutPreservesAttestedKeyId` @Test asserts attestedKeyId survives logout)
6. All 3 files compile for device target — CONFIRMED (BUILD SUCCEEDED above)

## TDD Gate Compliance

This plan is `type: execute` (not `type: tdd`) — no RED/GREEN/REFACTOR gate sequence required. All three commits are `test(...)` commits that add test files; no implementation code was shipped in this plan (the SUT types — SecureEnclaveKeyStore, LogoutService, DCAppAttestAttestationService, AppContainer — were already implemented in Phase 2 and Phase 4 Plans 01-06). Gate-compliance evaluation: N/A.

---
*Phase: 04-app-attest-physical-device-ci-hardening*
*Completed: 2026-04-22*
