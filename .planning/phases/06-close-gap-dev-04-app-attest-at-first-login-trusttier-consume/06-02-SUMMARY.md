---
phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume
plan: 02
subsystem: onboarding-attestation
tags: [app-attest, dev-04, otp, device-register, trust-tier, first-login]
requires:
  - KeychainKey.trustTier + AttestedKeyStore.writeTrustTier (Plan 06-01)
  - AttestationService protocol (generateKeyIfNeeded / attestKey)
  - DeviceChallengeEndpoint / DeviceRegisterEndpoint (Phase 4)
  - AttestationErrorResponseInterceptor.extractErrorCode (Phase 4)
provides:
  - OTPViewModel STEP 5 first-login App Attest orchestration
  - OTPViewModel grown DI surface (attestationService parameter)
  - challengeExpired refetch-and-retry-once register path
  - trustTier Keychain persistence from the captured /device/register response
affects:
  - validationLedger/Features/Onboarding/Auth/OTPViewModel.swift
  - validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift
  - validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift
tech-stack:
  added: []
  patterns:
    - "Graceful-skip / degrade-and-continue: App Attest is never a login gate — a non-.attested status or a transient failure both still POST /device/register"
    - "challengeExpired refetch-and-retry-once: a self-contained STEP 5 catch arm reusing AttestationErrorResponseInterceptor.extractErrorCode for the body parse"
    - "PII-disciplined attestation logging: attestation_first_login_* events carry only the event name + AttestationStatus.rawValue"
    - ".serialized @Suite for tests sharing the global MockURLProtocol handler registry (Phase 2 WR-01)"
key-files:
  created: []
  modified:
    - validationLedger/Features/Onboarding/Auth/OTPViewModel.swift
    - validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift
    - validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift
decisions:
  - "OTPViewModel grows its DI by an attestationService parameter and constructs AttestedKeyStore(keychain:) internally — the SceneDelegate.performHeartbeatIfNeeded precedent (D6-01, Pattern D, initializer-DI only)"
  - "STEP 5 attestation work is extracted into a non-throwing buildAttestationFields() helper so the D6-04 graceful-skip / D6-05 degrade boundary is one place and the D6-06 retry can re-invoke it cleanly"
  - "OTPViewModelTests is .serialized — the STEP 5 behavioural fixtures drive the global MockURLProtocol registry; parallel @Test execution stomped sibling AttestBackend handlers (Phase 2 WR-01 pattern)"
  - "Verification simulator switched from plan-specified 'iPhone 16' (unavailable on this host) to 'iPhone 17' (Rule 3 — blocking issue)"
metrics:
  duration: 21min
  completed: 2026-05-18
requirements: [DEV-04]
---

# Phase 6 Plan 02: First-Login App Attest Orchestration Summary

Wires App Attest into `OTPViewModel.verify()` STEP 5 — the literal fix for the DEV-04 gap the v1.0 milestone audit found, where STEP 5 hardcoded `attestationStatus: .unsupported` and never called `AttestationService`. The first successful OTP verify now fires `generateKeyIfNeeded()` -> `GET /device/challenge` -> `attestKey()`, sends the real attestation payload to `POST /device/register`, handles the graceful-skip / degrade-and-continue / challengeExpired-retry-once postures, captures the previously-discarded register response, and persists `trustTier` to Keychain.

## What Was Built

- **Grown DI surface (D6-01).** `OTPViewModel.init` gains an `attestationService: any AttestationService` parameter and constructs `AttestedKeyStore(keychain:)` internally from the already-held `keychain` — the exact `SceneDelegate.performHeartbeatIfNeeded` precedent (Pattern D, initializer-DI, no service locator). The single construction site `AuthCoordinator.pushOTP` passes `container.attestationService`.
- **Rewritten STEP 5.** The stale "Plan 06 AppContainer wiring will replace this" comment block and the `_ = try await apiClient.request(...)` register-response discard are gone. The progress slot stays `state = .settingUp(progress: 4, total: 6)` — the attestation work folds into the existing STEP 5 slot, `total` is unchanged (06-RESEARCH Pitfall 4 / A3).
- **`buildAttestationFields()` — the non-throwing attestation boundary.** A private async helper that runs `generateKeyIfNeeded()`; on a non-`.attested`/`.simulatorBypass` status it returns the D6-04 graceful-skip tuple (nil `attestedKeyId`/`attestationObject` + the real status, no challenge fetched, `attestKey` not called); on a usable key it fetches `GET /device/challenge`, base64-decodes the challenge, and calls `attestKey()`; any throw (challenge fetch, base64-decode, or `attestKey`) degrades to the D6-05 tuple (nil fields + `status = .error`). It never throws — login is never blocked.
- **`postDeviceRegister(...)` — one register POST.** A thin helper that issues a single `DeviceRegisterEndpoint` request and surfaces the typed `NetworkError`, so the STEP 5 caller can pattern-match a `challengeExpired` body.
- **D6-06 challengeExpired refetch-and-retry-once.** STEP 5 wraps the register POST in a `catch let NetworkError.httpError(_, data) where AttestationErrorResponseInterceptor.extractErrorCode(from: data) == "challengeExpired"` arm that re-runs `buildAttestationFields()` (fresh challenge + re-attest) and retries the POST exactly once. A second consecutive `challengeExpired` (or any other failure on the retry) is NOT retried again — it surfaces as `state = .registerFailed`. The retry control flow is self-contained inside STEP 5.
- **D6-01 trustTier persistence.** On register success the captured `registerResponse.trustTier` is persisted via `try? attestedKeyStore.writeTrustTier(...)` — a Keychain write failure does not block login (degrades to the safe `.softwareOnly` default downstream; the role-shell `AppContainer` re-hydrates from this key in Plan 03).
- **D6-07 PII discipline.** The three new attestation log calls (`attestation_first_login_challenge_expired_retry`, `attestation_first_login_skipped_no_key`, `attestation_first_login_degraded`) carry only the event name + `AttestationStatus.rawValue` — never `String(describing: error)`, `.userInfo`, or `.localizedDescription`. The pre-existing non-attestation catches keep their `String(describing:)` idiom unchanged.
- **14-test behavioural suite.** `OTPViewModelTests` grew from 4 thin compile-shape tests to 14: the 4 originals plus 10 behavioural `@Test` cases driving the full `verify -> GET /device/challenge -> POST /device/register` sequence through MockURLProtocol fixtures + a scriptable `FakeAttestationService` — `.attested` happy path, D6-01 trustTier Keychain persistence, D6-04 graceful-skip (`.unsupported` / `.entitlementMissing`), D6-05 degrade (challenge fetch failure / `attestKey` throw), D6-06 retry-once + second-expiry-surfaces, `retryRegister` idempotency, and the D6-07 PII source-grep. A lock-guarded `AttestBackend` sequences per-call `/device/register` outcomes and captures the POST body.

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Wave 0 RED tests — STEP 5 attestation orchestration behaviour | `5c0db4c` | OTPViewModelTests.swift |
| 2 | Rewrite OTPViewModel STEP 5 + grow DI + update AuthCoordinator | `85b0846` | OTPViewModel.swift, AuthCoordinator.swift, OTPViewModelTests.swift |

## Verification

- `xcodebuild test -only-testing:validationLedgerTests/OTPViewModelTests` (iPhone 17 simulator) — **14 tests pass, 0 failures**.
- `xcodebuild test -only-testing:validationLedgerTests/OTPViewModelTests -only-testing:validationLedgerTests/Attestation` — combined run passes, 0 failures (no Attestation-suite regression).
- `xcodebuild test -only-testing:validationLedgerTests -parallel-testing-enabled NO` — **full simulator suite: 383 tests in 71 suites pass, 0 failures**. No MockURLProtocol fixture-leak class of failure (Phase 4 deferred-items #1 watched for).
- `grep 'Plan 06 AppContainer wiring' OTPViewModel.swift` — 0 matches (stale comment deleted).
- `grep '_ = try await apiClient.request' OTPViewModel.swift` — 0 matches (the STEP 5 register discard is gone; the register call assigns to a `let`).
- `grep 'attestationStatus: .unsupported' OTPViewModel.swift` — 0 matches (the hardcoded STEP 5 `.unsupported` is removed — the DEV-04 gap is closed).
- `grep 'settingUp(progress: 4, total: 6)' OTPViewModel.swift` — 1 match (`total` is still 6).
- `AuthCoordinator.pushOTP` passes `attestationService: container.attestationService`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] OTPViewModelTests must be `.serialized`**
- **Found during:** Task 2 GREEN verification.
- **Issue:** The first GREEN run failed 12 of 14 tests with symptoms of cross-test state corruption — `lastRegisterBody` was `nil` (register POST "never sent") and an `.entitlementMissing` test observed an `unsupported` payload from a different test's `AttestBackend`. Swift Testing runs `@Test`s in parallel by default; the STEP 5 behavioural tests each register an `AttestBackend` handler into the **global** `MockURLProtocol` handler registry, so concurrent tests stomped each other's fixtures.
- **Fix:** Added the `.serialized` suite trait to `@Suite(...)` on `OTPViewModelTests` — the established Phase 2 WR-01 pattern for suites that share `MockURLProtocol` global state. After serialization all 14 tests pass and the full suite is green.
- **Files modified:** `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift` (committed in Task 2's `85b0846`).
- **Commit:** `85b0846`.

**2. [Rule 3 - Blocking] Verification simulator destination unavailable**
- **Found during:** Task 1 / Task 2 verification.
- **Issue:** The plan's `<verify>` blocks specify `platform=iOS Simulator,name=iPhone 16`. That simulator is not installed on this host (per the executor environment note — available: iPhone 17 / 17 Pro / Air / 16e).
- **Fix:** Ran the build and test commands against `name=iPhone 17` instead. The destination is the only change; the scheme, test targets, and `-only-testing` filters are exactly as the plan specifies. (Wave 1 / Plan 06-01 made the identical substitution.)
- **Files modified:** None (verification-command-only change).
- **Commit:** N/A.

### Note — verification project path

The plan's `<verify>` blocks `cd` into the repo root and run `xcodebuild test -scheme validationLedger`. As a parallel worktree executor, all builds were run from the worktree with an explicit `-project validationLedger.xcodeproj` so the worktree's source (not the main checkout) was compiled. No behavioural difference — the project file is identical to the main checkout's.

## TDD Gate Compliance

Both tasks carry `tdd="true"` and the gate sequence is satisfied in git history:
1. **RED** — `test(06-02): ...` (`5c0db4c`) landed the 10 behavioural tests; the standalone run failed to compile against the not-yet-grown `OTPViewModel.init` (`error: extra argument 'attestationService' in call`). This is the expected RED state — the tests were written against the intended Task 2 signature, not stubbed green.
2. **GREEN** — `feat(06-02): ...` (`85b0846`) landed the STEP 5 rewrite + grown DI; all 14 `OTPViewModelTests` then pass.

No REFACTOR commit — the GREEN implementation needed no follow-up cleanup. `tdd_mode` is `false` in `config.json` and the orchestrator passed neither `MVP_MODE` nor `TDD_MODE`, so the MVP+TDD runtime gate does not apply.

## Self-Check: PASSED

- FOUND: validationLedger/Features/Onboarding/Auth/OTPViewModel.swift (modified)
- FOUND: validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift (modified)
- FOUND: validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift (modified)
- FOUND commit: 5c0db4c
- FOUND commit: 85b0846
