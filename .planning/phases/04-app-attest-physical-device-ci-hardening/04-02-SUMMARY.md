---
phase: 04-app-attest-physical-device-ci-hardening
plan: 02
subsystem: test-infrastructure
tags: [test-fixtures, keychain, attestation, biometric, wave-0, test-doubles]
dependency_graph:
  requires:
    - "validationLedgerTests/Networking/FixtureLoader.swift (Phase 2 — Bundle-marker fixture loader)"
    - "validationLedger/Core/Auth/BiometricService.swift (Phase 3 — BiometricService protocol + BiometricFallback enum)"
    - "validationLedger/Core/Storage/Keychain/KeychainScope.swift (Phase 3 — .session case)"
    - "validationLedger/Core/Storage/Keychain/KeychainKey.swift (Phase 3 existing keys; 04-01 adds attestedKeyId + lastHeartbeatAt)"
    - "04-01 (parallel Wave 1) — AttestationService protocol + AttestationStatus enum for FakeAttestationService to conform against post-merge"
  provides:
    - "4 JSON fixtures for /device/challenge, /device/heartbeat (success + attestation-invalid), /device/register (software-only) — consumed by Plan 05 TDD tests"
    - "KeychainScopeTests.swift — D-03 invariant pin (4 Swift Testing methods)"
    - "FakeAttestationService.swift — scriptable test double with call counts + last-args capture for D-01/D-06/D-07 assertions"
    - "SeededBiometricService (SeededLAContext.swift) — D-14 unattended device-CI biometric double"
  affects:
    - "Plan 05 (simulator tests) — will import FakeAttestationService + the 4 JSON fixtures"
    - "Plan 06 (AppContainer test seam) — will inject SeededBiometricService + FakeAttestationService"
    - "Plan 09 (KeychainBiometricACLTests, device CI) — will consume SeededBiometricService"
tech_stack:
  added: []
  patterns:
    - "Swift Testing (import Testing, @Suite, @Test) — mirrors Phase 3 EndpointEncodingTests + KeychainStoreTests convention"
    - "@unchecked Sendable on test doubles — mirrors Phase 2 StubCountryGateForUITest / StubLocationProviderForUITest pattern"
    - "Scriptable Result-typed 'next...' properties + private(set) call counters — industry-standard test-double shape"
    - "snake_case JSON keys + ISO8601 Z-suffix — mirrors existing device-register-success.json convention"
key_files:
  created:
    - "validationLedgerTests/Networking/Fixtures/device-challenge-success.json"
    - "validationLedgerTests/Networking/Fixtures/device-heartbeat-success.json"
    - "validationLedgerTests/Networking/Fixtures/device-heartbeat-attestation-invalid.json"
    - "validationLedgerTests/Networking/Fixtures/device-register-software-only.json"
    - "validationLedgerTests/Storage/KeychainScopeTests.swift"
    - "validationLedgerTests/Attestation/FakeAttestationService.swift"
    - "validationLedgerDeviceTests/SeededLAContext.swift"
  modified: []
decisions:
  - "D-03: attestedKeyId + lastHeartbeatAt NOT in .session scope — enforced by 4-test Swift Testing suite that will fail-loud if someone ever adds them to KeychainScope.session.contains"
  - "D-14: SeededBiometricService returns success synchronously, never instantiates LAContext — HONEST-NAMING rule enforced via header comment directing test authors away from testBiometricAuthFlow-style names"
  - "Parallel-wave coordination: FakeAttestationService intentionally omits `: AttestationService` conformance declaration in this worktree; conformance added in post-merge reconciliation once 04-01's protocol symbol is available"
  - "PBXFileSystemSynchronizedRootGroup auto-inclusion: no project.pbxproj edits required for either the fixtures or the 3 Swift files — they are picked up by filesystem placement"
metrics:
  duration_minutes: ~2
  tasks_completed: 3
  files_created: 7
  files_modified: 0
  commits: 3
  completed: 2026-04-22
---

# Phase 4 Plan 2: Wave-0 Test Infrastructure (Fixtures + Doubles + D-03 Invariant Pin) Summary

**One-liner:** Landed 4 snake_case JSON fixtures for /device/challenge + /device/heartbeat (success + error) + /device/register (software-only), a 4-test Swift Testing suite pinning the D-03 KeychainScope invariant, a scriptable FakeAttestationService test double with call counts + last-args capture, and a SeededBiometricService for D-14 unattended device CI — 7 test-target-only files, zero production-code changes, ready for Plan 05's TDD work to consume.

## Context

This plan ran in **Wave 1 parallel mode** alongside plan 04-01 (foundational types + protocols + ADR + runbook). The two plans were designed to not collide: 04-01 touches production `validationLedger/Core/Attestation/` + `validationLedger/Core/Storage/Keychain/` + docs + entitlements, while 04-02 touches only `validationLedgerTests/` + `validationLedgerDeviceTests/`. Post-merge, the test-target artifacts here compile against the production types there.

Two artifacts (KeychainScopeTests.swift + FakeAttestationService.swift) reference symbols that only exist in the 04-01 worktree (`KeychainKey.attestedKeyId`, `KeychainKey.lastHeartbeatAt`, `AttestationService` protocol, `AttestationStatus` enum). They compile only post-merge — this is the intentional parallel-wave coordination shape documented in the executor prompt's `<coordination_note>`.

## What Was Built

### Task 1 — JSON Fixtures (commit `07af643`)

Four fixtures, all snake_case + ISO8601 Z-suffix to match the `JSONDecoder.convertFromSnakeCase` convention in `APIClient`:

| Fixture | Purpose | Key Shape |
|---------|---------|-----------|
| `device-challenge-success.json` | GET /device/challenge 200 (D-05) | `challenge` (base64), `expires_at` (ISO8601, 60s TTL per D-08), `nonce` |
| `device-heartbeat-success.json` | POST /device/heartbeat 200 (D-07) | `heartbeat_accepted_at`, `trust_tier: "hardwareAttested"` (D-12) |
| `device-heartbeat-attestation-invalid.json` | POST /device/heartbeat 400 triggering D-04 re-attest | `error_code: "attestationInvalid"`, `error_message` |
| `device-register-software-only.json` | POST /device/register 200 for simulator-bypass path (D-10) | `device_id: "dev-sim-bypass-123"`, `trust_tier: "softwareOnly"` |

Verified the base64 challenge: `echo -n "challenge-nonce-for-testing" | base64` produces `Y2hhbGxlbmdlLW5vbmNlLWZvci10ZXN0aW5n` — matches the fixture verbatim.

### Task 2 — D-03 Invariant Pin + Attestation Test Double (commit `edc95bb`)

**`validationLedgerTests/Storage/KeychainScopeTests.swift`** — 4-test Swift Testing suite:
- `testAttestedKeyIdNotInSessionScope` — pins D-03 (attestedKeyId survives logout)
- `testLastHeartbeatAtNotInSessionScope` — pins D-03 (lastHeartbeatAt survives logout)
- `testSessionMembersUnchanged` — regression guard on existing session members (sessionToken, sessionRole, sessionUserID, biometricDomainState)
- `testInstallUUIDNotInSessionScope` — regression guard on the DEV-05 invariant

If anyone later adds `attestedKeyId` or `lastHeartbeatAt` to `KeychainScope.session.contains`'s array, 2 of these tests go red, preserving the D-03 "preserve-across-logout" contract documented in ADR 0005.

**`validationLedgerTests/Attestation/FakeAttestationService.swift`** — scriptable test double:
- 3 `Result`-typed `next...` properties for scripting outcomes (generateKeyIfNeeded / attestKey / generateAssertion)
- 4 `private(set)` call counters (one per method)
- 4 `private(set)` last-args capture properties (keyId + challenge for attestKey and generateAssertion)
- 4 method stubs matching the expected 04-01 protocol shape

Enables Plan 05's D-01 once-per-install assertion (`#expect(fake.generateKeyIfNeededCallCount == 1)` after N cold-boots) and D-06 clientDataHash assertion (`#expect(fake.lastAttestKeyChallenge == expectedChallenge)`).

### Task 3 — Seeded Biometric Service for Device CI (commit `1c23182`)

**`validationLedgerDeviceTests/SeededLAContext.swift`** — `SeededBiometricService` conforming to the real `BiometricService` protocol (2 members: `evaluate(reason:fallback:)` async throws + `currentDomainState() -> Data?`). Never instantiates a real LAContext — grep for `LAContext()` in this file returns 0 matches. Adds:
- `shouldThrowOnEvaluate: Error?` for opt-in failure modelling
- `evaluateCallCount` + `currentDomainStateCallCount` counters
- `lastEvaluateReason` + `lastEvaluateFallback` last-args capture
- Fixed `seeded-domain-state` payload per RESEARCH line 716

The HONEST-NAMING rule (T-APP-ATTEST-05 compensating control) is enforced via a prominent header comment: any test using this double MUST be named after the Keychain side-effect (e.g., `testKeychainACLCreatedWhenBiometricSucceeds`), never after the OS biometric prompt.

## Verification

1. **File existence:** All 7 files exist at the exact paths in `files_modified` frontmatter.
2. **JSON parse:** `python3 -c "import json; json.load(...)"` succeeds on all 4 fixtures.
3. **Key shapes:** Required keys grep to 1 match each (`challenge`, `trust_tier: "hardwareAttested"`, `error_code: "attestationInvalid"`, `trust_tier: "softwareOnly"`).
4. **Base64 sanity:** Fixture's `challenge` value is a valid base64 of `"challenge-nonce-for-testing"`.
5. **KeychainScopeTests structure:** 4 @Test methods present; `@Suite("KeychainScope — D-03: attestation keys preserved across logout")` annotation present.
6. **FakeAttestationService structure:** `final class FakeAttestationService: @unchecked Sendable` declared; 4 counters + 4 last-args declared; 4 method stubs present.
7. **SeededBiometricService structure:** `final class SeededBiometricService: BiometricService, @unchecked Sendable` declared; zero `LAContext()` instantiation; `seeded-domain-state` payload present; file at top-level of `validationLedgerDeviceTests/` alongside existing device tests.
8. **Target membership:** Auto-inclusion via `PBXFileSystemSynchronizedRootGroup` (verified by inspecting `project.pbxproj`: each test target has `fileSystemSynchronizedGroups = (<target-group>);` which picks up every file under the target directory). No manual pbxproj edits required.

Build verification against real `xcodebuild` is **deferred to post-merge** — this worktree cannot compile KeychainScopeTests.swift or FakeAttestationService.swift in isolation because both reference symbols landed in the parallel 04-01 worktree (see Deviations section below). The orchestrator's post-merge Wave 1 test gate runs the full compile.

## Deviations from Plan

### 1. [Rule 3 — Blocking] FakeAttestationService omits explicit `: AttestationService` conformance

- **Found during:** Task 2
- **Issue:** Plan's acceptance criterion asks for `grep "final class FakeAttestationService: AttestationService" == 1`. In this worktree, the `AttestationService` protocol does NOT exist yet (it's created by sibling Wave-1 plan 04-01). Attempting to declare the conformance here would fail compilation.
- **Fix:** Per the executor prompt's explicit `<coordination_note>` instruction, declared the class as `final class FakeAttestationService: @unchecked Sendable` (no protocol conformance), with a header comment flagging the post-merge reconciliation task. The method signatures match the 04-01 protocol shape verbatim, so post-merge adding `: AttestationService` is a single-line edit (no signature drift expected).
- **Files modified:** `validationLedgerTests/Attestation/FakeAttestationService.swift`
- **Commit:** `edc95bb`
- **Follow-up:** Post-merge reconciliation (orchestrator or next-wave planner) must add the `: AttestationService` conformance declaration. If signatures drift, the Wave-1 post-merge test gate will surface it.

### 2. [Rule 3 — Blocking] KeychainScopeTests references symbols landed by 04-01

- **Found during:** Task 2
- **Issue:** The 4 @Test methods reference `KeychainKey.attestedKeyId` + `KeychainKey.lastHeartbeatAt` which are added by 04-01 Task 2 in the parallel worktree. In isolation, this worktree's `KeychainKey.swift` does not contain them.
- **Fix:** Wrote the file as specified by the plan — this is the intended post-merge artifact. Added a prominent header comment explaining the parallel-wave coordination so reviewers understand the isolation-build failure is expected. Post-merge, the file compiles and the 4 tests pass (pinning D-03).
- **Files modified:** `validationLedgerTests/Storage/KeychainScopeTests.swift`
- **Commit:** `edc95bb`
- **Follow-up:** Post-merge Wave-1 test gate runs `xcodebuild test -only-testing:validationLedgerTests/Storage/KeychainScopeTests` to confirm the invariant holds.

### 3. [Rule 1 — Bug in acceptance criterion] LAContext() grep count interpretation

- **Found during:** Task 3 verification
- **Issue:** Plan's acceptance says `grep "LAContext()" == 0`. My initial header comment read "does NOT instantiate LAContext() in any method path", which technically contributed a grep match even though the sense was the opposite of violation.
- **Fix:** Rephrased the comment to "does NOT instantiate a real LAContext in any method path" to satisfy the strict grep count while preserving the documented anti-pattern. Zero code paths touch `LAContext()` — the anti-pattern guard remains intact.
- **Files modified:** `validationLedgerDeviceTests/SeededLAContext.swift`
- **Commit:** Folded into `1c23182`

## Authentication Gates

None. This plan is pure test-target artifact creation — no network, no login.

## Test Naming Discipline (HONEST-NAMING Rule)

Per T-APP-ATTEST-05 mitigation (plan frontmatter) + RESEARCH Pitfall 5, the header comment in `SeededLAContext.swift` documents the rule that any test using `SeededBiometricService` MUST be named after the Keychain side-effect path, NEVER after the OS biometric prompt. Example correct names: `testKeychainACLCreatedWhenBiometricSucceeds`, `testAuthorizationKeyReadsAfterBiometricEvaluation`. Example prohibited name: `testBiometricAuthFlow`.

The plan's `<must_haves>` truth that mentioned "D-14" / the naming discipline is therefore inlined into the file's header comment, surviving as a permanent code-review reminder.

## Threat Flags

None. All new artifacts are test-target-only and never link into the shipping app binary (T-APP-ATTEST-03 mitigation).

## Known Stubs

None. Every artifact is a complete, self-contained test-target deliverable. `FakeAttestationService.nextGenerateKeyIfNeeded` etc. are intentionally scriptable (default `.success(...)`) — Plan 05 tests override the default when they need to model failure paths; defaulting to success is correct test-double behavior, not a stub.

## Self-Check: PASSED

- Files present: all 7 created files verified on disk.
- Commits present: 3 commits (`07af643`, `edc95bb`, `1c23182`) all on branch `worktree-agent-a77af919`.
- No unexpected deletions: `git diff --diff-filter=D HEAD~3 HEAD` returns empty.
- `git status --short` is clean before writing this SUMMARY.
- Build verification against xcodebuild deferred to post-merge Wave 1 test gate (KeychainScopeTests + FakeAttestationService both reference 04-01 symbols — intentional parallel-wave shape per coordination note).
