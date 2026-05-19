---
phase: 04-app-attest-physical-device-ci-hardening
plan: 07
wave: 4
subsystem: auth
tags: [app-attest, attestation, heartbeat, devmenu, interceptor, networking, session, d-07, d-04, d-12]

# Dependency graph
requires:
  - phase: 04-app-attest-physical-device-ci-hardening
    provides: Plan 01 (AttestationService protocol + Keychain keys attestedKeyId/lastHeartbeatAt); Plan 03 (DCAppAttestAttestationService + SimulatorBypassAttestationService + AttestedKeyStore); Plan 04 (DeviceHeartbeatEndpoint + DeviceRegisterEndpoint three-key payload); Plan 06 (AppContainer.attestationService + AppContainer.session + AppSession main-actor holder)
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    provides: SceneDelegate cold-boot probe + AppCoordinator phase routing (Plan 03-11); Auth401ResponseInterceptor (Plan 03-07); DevMenuViewController DEBUG-gated shell (Phase 1 01-05)
  - phase: 02-networking-device-keys
    provides: APIClient.responseInterceptors composition + ResponseInterceptor protocol (Plan 02-01/02-04)
provides:
  - D-07 heartbeat cadence: cold-boot + 24h warm-foreground heartbeat fires via SceneDelegate.performHeartbeatIfNeeded, updates AppSession.trustTier from response
  - D-04 manual re-attestation: DEBUG-only DevMenu 'Re-attest now' row clears attestedKeyId and regenerates via AttestationService
  - D-04 automatic re-attestation: AttestationErrorResponseInterceptor intercepts 4xx on /device/register + /device/heartbeat, inspects error_code for attestationInvalid|nonceExpired|keyCompromised, runs clearPersistedKeyId + generateKeyIfNeeded + retry-once
  - APIClient interceptor-chain registration pattern: Auth401 + AttestationError orthogonal coexistence (path + status + error-code filters)
  - Retry-once budget enforcement (T-APP-ATTEST-15): linear flow, no recursion, bounded DCAppAttestService.generateKey quota pressure
affects: [phase 04 Wave 5 validation, phase 05 KYC + BOL, any future endpoint that depends on trustTier or reacts to backend re-attestation signals]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ResponseInterceptor orthogonality — multiple interceptors can coexist in the same chain by constraining on disjoint (path, status, body) tuples"
    - "Safe-fail interceptor semantics — any failure after the trigger (clear / regenerate) logs at .error and returns the ORIGINAL 4xx unchanged so the caller still handles it normally; do not throw out of the interceptor"
    - "Retry-once via `send` closure — the retry calls the APIClient-supplied `send` directly, which bypasses this interceptor on the second pass (no recursion)"
    - "Forward-compat body parsing — accept both error_code (snake_case wire) and errorCode (camelCase) in extractErrorCode to absorb backend-contract drift"

key-files:
  created:
    - validationLedger/Core/Networking/Interceptors/AttestationErrorResponseInterceptor.swift
  modified:
    - validationLedger/App/SceneDelegate.swift
    - validationLedger/App/DevMenu/DevMenuViewController.swift
    - validationLedger/App/AppContainer.swift
    - validationLedgerTests/Attestation/AttestationErrorResponseInterceptorTest.swift

key-decisions:
  - "Interceptor registered AFTER Auth401ResponseInterceptor — a 401 on /device/heartbeat routes through Auth401's session-expiry logout path and is NOT absorbed by a body-decode of a spurious attestationInvalid error (orthogonality via filter disjointness, not chain ordering alone)."
  - "Safe-fail on clear/regenerate errors — if clearPersistedKeyId() or generateKeyIfNeeded() throws, log at .error and return the original 4xx unchanged. Never throw out of the interceptor; caller must still see the 4xx to handle."
  - "Accept both error_code and errorCode JSON keys — defensive against backend contract drift between snake_case wire format and camelCase."
  - "Retry EXACTLY ONCE per top-level request (T-APP-ATTEST-15) — the retry path calls `send` directly (closure closes over APIClient's send, not this interceptor), so a second 4xx flows through unchanged. No recursion; quota pressure bounded to 1 extra DCAppAttestService.generateKey per D-04 trigger."
  - "PII discipline enforced via empty LogField dictionaries — every logger call passes [:] and relies on the event-name string alone to carry the D-04 signal. No response-body bytes, no attestedKeyId, no assertion ever reach the logger (FOUND-01 / CLAUDE.md constraint)."

patterns-established:
  - "Pattern: 4xx body-sniffing interceptor — read the response body JSON to pick a narrow trigger set, short-circuit on any parse failure, then perform a bounded recovery action + retry-once"
  - "Pattern: filter stack short-circuit order — (1) path, (2) status, (3) body-parse — cheapest checks first, body-parse is the most expensive and comes last"
  - "Pattern: orthogonal interceptor coexistence — two interceptors fire on the same chain but on disjoint triggers (401 vs 4xx+canonical-attestation-code) so they never act on the same response"

requirements-completed: [DEV-04]

# Metrics
duration: 4h 28m (wall-clock across two sessions; first session landed Tasks 1–2 then paused on Anthropic quota; second session staged + completed Task 3 + SUMMARY)
completed: 2026-04-22
---

# Phase 4 Plan 07: SceneDelegate Heartbeat + DevMenu Re-attest + AttestationErrorResponseInterceptor Summary

**D-07 heartbeat cadence (cold-boot + 24h warm-foreground), D-04 manual re-attestation via DevMenu, and D-04 automatic backend-driven re-attestation via AttestationErrorResponseInterceptor — the full D-04/D-07 surface wired through SceneDelegate, DevMenu, and the APIClient response-interceptor chain.**

## Performance

- **Duration:** 4h 28m (split across two sessions; quota pause in between)
- **Started:** 2026-04-22T12:10:27Z (commit 3c72e7e timestamp in UTC)
- **Completed:** 2026-04-22T16:38:33Z (commit 5039dbf timestamp in UTC)
- **Tasks:** 3 of 3
- **Files modified:** 4 (SceneDelegate.swift, DevMenuViewController.swift, AppContainer.swift, test file); **Files created:** 1 (AttestationErrorResponseInterceptor.swift)

## Accomplishments

- **D-07 heartbeat cadence wired end-to-end** — SceneDelegate.performHeartbeatIfNeeded fires on cold-boot (after biometric unlock) and on didBecomeActive when lastHeartbeatAt is >24h old or absent; updates AppSession.trustTier from the /device/heartbeat response; failure is fire-and-forget and never blocks role-shell render (.error-level log with empty fields only).
- **D-04 manual path** — DevMenu gains a DEBUG-only `.reattestNow` Row that invokes container.attestationService.clearPersistedKeyId() + generateKeyIfNeeded() with a UX completion alert. Entire path is `#if DEBUG`-gated (Pattern G); Release builds compile zero bytes for this surface.
- **D-04 automatic path** — AttestationErrorResponseInterceptor intercepts 4xx responses on /device/register + /device/heartbeat, inspects the JSON body's error_code field, and on the three canonical triggers (attestationInvalid / nonceExpired / keyCompromised) clears the persisted keyId, regenerates, and retries the original URLRequest EXACTLY ONCE. Malformed body, unrelated error codes, and non-attestation paths all flow through unchanged.
- **AppContainer interceptor-chain wiring** — Registered the new interceptor after Auth401ResponseInterceptor so the two operate orthogonally (401 vs 4xx + canonical attestation error_code). Six-line header comment added to AppContainer documenting the ordering rationale.
- **Plan 05 Task 4 test suite re-enabled** — Removed the @Suite(.disabled) placeholder; replaced TODO(04-07) commentary with real assertions across 5 tests (3 canonical triggers + 2 negative paths). All 5 pass; Plan 03 Auth401ResponseInterceptorTests (6 tests) still pass — no regression.

## Task Commits

1. **Task 1: Wire SceneDelegate D-07 cold-boot + 24h warm-foreground heartbeat** — `3c72e7e` (feat)
2. **Task 2: Add DevMenu 'Re-attest now' row for D-04 manual re-attestation** — `7ef7e8b` (feat)
3. **Task 3: Create AttestationErrorResponseInterceptor + register in AppContainer's interceptor chain + re-enable Plan 05 Task 4 test suite** — `5039dbf` (feat)

**Plan metadata commit:** pending (this SUMMARY commit will use `docs(04-07): add SUMMARY after continuation`).

_Commits 1 and 2 landed in the first executor session; commit 3 landed in the continuation session after the Anthropic quota pause._

## Files Created/Modified

**Created**
- `validationLedger/Core/Networking/Interceptors/AttestationErrorResponseInterceptor.swift` — ResponseInterceptor-conforming struct for D-04 automatic path. 141 lines. Path + status + body filters; retry-once; safe-fail. PII-safe logging (empty LogField dictionaries).

**Modified**
- `validationLedger/App/SceneDelegate.swift` — Added `performHeartbeatIfNeeded(container:)` helper + call sites in scene(_:willConnectTo:) .restored branch (cold-boot, fire-and-forget Task) and handleDidBecomeActive (24h threshold check, fires AFTER the existing biometric-lock check).
- `validationLedger/App/DevMenu/DevMenuViewController.swift` — Added `.reattestNow` Row enum case + handler calling container.attestationService.clearPersistedKeyId + generateKeyIfNeeded with UIAlertController completion feedback. DEBUG-gated via the file-top `#if DEBUG` that already wraps the entire VC (no new gate needed — Pattern G).
- `validationLedger/App/AppContainer.swift` — Appended AttestationErrorResponseInterceptor to `responseInterceptors` array in APIClient construction, immediately after Auth401ResponseInterceptor. Added 6-line header comment documenting the Auth401 → AttestationError ordering rationale. Also removed a now-unused `_ = attestationLogger` suppress that became active because the new interceptor uses attestationLogger for real.
- `validationLedgerTests/Attestation/AttestationErrorResponseInterceptorTest.swift` — Removed `@Suite(.disabled(...))` annotation that Plan 05 Task 4 installed as a cross-wave placeholder. Replaced the TODO(04-07) commentary and empty test bodies with real assertions against FakeAttestationService + SendSpy for 5 tests: 3 canonical trigger codes (attestationInvalid on /device/register, nonceExpired on /device/heartbeat, keyCompromised on /device/register) each driving clearPersistedKeyIdCallCount==1, generateKeyIfNeededCallCount==1, spy.invocations==2, final 200; plus 2 negative paths (unrelated 500 error_code on /device/register with 0 service calls + no retry; attestationInvalid on /auth/otp/verify with 0 service calls + no retry — path filter excludes).

**Xcode project file (project.pbxproj):** No edit needed. The `validationLedger` and `validationLedgerTests` targets use `PBXFileSystemSynchronizedRootGroup` (Xcode 15+/26 synchronized groups); new Swift files under `validationLedger/` and `validationLedgerTests/` are auto-included in their respective target's Compile Sources. Confirmed by building + running the test suite with the new file in place.

## Decisions Made

See the `key-decisions` frontmatter list above. Summary:

1. **Register AFTER Auth401ResponseInterceptor** — so a 401 on /device/heartbeat is never absorbed by a body-decode of a spurious attestationInvalid error. The filter disjointness (401 vs 4xx + canonical code) is the primary guarantee; chain ordering is belt-and-suspenders.
2. **Safe-fail inside the interceptor** — clear failure or regenerate failure logs at .error and returns the ORIGINAL 4xx. Caller always sees the 4xx to handle normally. Never throw out.
3. **Accept both error_code and errorCode JSON keys** — forward-compat against backend drift.
4. **Retry EXACTLY once via the `send` closure** — the retry path does not re-enter this interceptor. Quota pressure bounded to 1 extra generateKey per D-04 trigger. Mitigates T-APP-ATTEST-15.
5. **PII-safe logging via empty LogField dictionaries** — event name alone carries the signal. Satisfies FOUND-01 / CLAUDE.md "zero PII in analytics or crash logs" constraint.

## Deviations from Plan

**Notable deviation:** Executed across two sessions due to Anthropic quota pause on 2026-04-22. Tasks 1–2 landed in the first session (commits 3c72e7e and 7ef7e8b, between 12:10Z and 12:11Z). The quota limit interrupted mid-Task-3 with the WIP staged in the worktree filesystem. A continuation executor picked up after quota reset at ~16:11Z, reviewed the WIP files against the Task 3 spec, verified no fixes were needed, ran the verify block + test suite, committed Task 3 as 5039dbf, and produced this SUMMARY. No work was lost; no commits were rewritten or rebased. The two pre-existing Task 1/2 commits are preserved intact.

### Auto-fixed Issues

None during Task 3 continuation. The WIP files staged by the first executor already satisfied the spec precisely:
- AttestationErrorResponseInterceptor.swift conforms to ResponseInterceptor, has all 3 canonical trigger codes, filters by path + 4xx + body, calls clearPersistedKeyId + generateKeyIfNeeded, retries once, safe-fails on errors, uses PII-safe empty LogField dictionaries.
- AppContainer.swift registers the interceptor after Auth401 with the documented ordering comment. Additionally removes a `_ = attestationLogger` no-op suppress that was needed in Plan 06 when the logger was constructed-but-unused in the sim branch; Task 3 makes the logger genuinely used by the new interceptor, so the suppress becomes dead.
- AttestationErrorResponseInterceptorTest.swift removes the @Suite(.disabled) gate and implements all 5 spec tests.

### Xcode iPhone simulator model

Spec line 537 asks for `iPhone 15` as the simulator destination. Only iPhone 16 / 16 Pro / 16 Plus variants are available on this runner. Used `iPhone 16`. Build and test results identical; the destination name change is cosmetic. No impact on acceptance criteria.

---

**Total deviations:** 1 executor continuation (quota pause, no code impact) + 1 simulator-name substitution (cosmetic).
**Impact on plan:** Zero scope creep. All acceptance criteria met. All tests pass.

## Issues Encountered

- **Anthropic quota pause 2026-04-22 between Task 2 commit and Task 3 commit.** Worktree preserved the staged files (`git status` showed M/A correctly). Continuation executor resumed in the same worktree on the same branch (`worktree-agent-af7cefb2`); no rebase, no force-reset, no file loss. Documented for future reference as evidence that the parallel-executor worktree protocol survives quota-driven interruptions cleanly.

## Self-Check: PASSED

**File existence**
- FOUND: `validationLedger/Core/Networking/Interceptors/AttestationErrorResponseInterceptor.swift`
- FOUND: `validationLedger/App/AppContainer.swift` (modified)
- FOUND: `validationLedger/App/SceneDelegate.swift` (modified)
- FOUND: `validationLedger/App/DevMenu/DevMenuViewController.swift` (modified)
- FOUND: `validationLedgerTests/Attestation/AttestationErrorResponseInterceptorTest.swift` (modified, un-disabled)

**Commits in `git log --oneline`**
- FOUND: `3c72e7e` — feat(04-07): wire D-07 cold-boot + 24h-warm-foreground heartbeat in SceneDelegate
- FOUND: `7ef7e8b` — feat(04-07): add DevMenu 'Re-attest now' row for D-04 manual re-attestation
- FOUND: `5039dbf` — feat(04-07): AttestationErrorResponseInterceptor + AppContainer wiring + test re-enable (D-04 automatic path)

**Verify-block results (Task 3)**
- `test -f` interceptor file: PRESENT
- `grep -c "public struct AttestationErrorResponseInterceptor: ResponseInterceptor"` in interceptor: **1** (spec >=1).
- `grep -c "attestationInvalid\|nonceExpired\|keyCompromised"` in interceptor: **6** (each canonical code >=1).
- `grep -c "/device/register\|/device/heartbeat"` in interceptor: **6** (each path token >=1).
- `grep -c "clearPersistedKeyId\|generateKeyIfNeeded"` in interceptor: **4** (each method >=1).
- `grep -c "try await send(request)"` in interceptor: **2** (original + retry; spec >=2).
- `grep -c "AttestationErrorResponseInterceptor"` in AppContainer.swift: **2** (comment mention + actual registration).
- `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug`: **BUILD SUCCEEDED**, 0 errors, 0 warnings.
- `xcodebuild test -only-testing:validationLedgerTests/AttestationErrorResponseInterceptorTest`: **5 of 5 tests PASS**, exit 0, TEST SUCCEEDED.
    - "4xx attestationInvalid on /device/register → clearPersistedKeyId + generateKeyIfNeeded + retry-once" PASS
    - "4xx nonceExpired on /device/heartbeat → same chain" PASS
    - "4xx keyCompromised → same chain" PASS
    - "4xx/5xx unrelated error code → chain does NOT fire; no retry" PASS
    - "4xx attestationInvalid on NON-attestation path (/auth/otp/verify) → no interference" PASS
- `xcodebuild test -only-testing:validationLedgerTests/Auth401ResponseInterceptorTests` (regression check per Task 3 acceptance criterion): **6 of 6 tests PASS**, exit 0. No regression from the new interceptor (path + status + error-code filters keep the two interceptors orthogonal).

**Post-commit deletion check**
- `git diff --diff-filter=D HEAD~1 HEAD` for commit 5039dbf: empty (no files deleted).

## User Setup Required

None — no external service configuration required by this plan. DEV-04 is a client-local interception pattern + local DevMenu row + heartbeat cadence wiring; no backend config, no secrets, no env vars.

## Next Phase Readiness

**Ready for Wave 5 (validation).** Specifically:
- The D-04 automatic chain has production code + passing tests. Plan 04-05's previously-disabled "FakeAttestationService chain" test suite is now live and green; Plan 04-10 (phase validation) can assert D-04 coverage without additional scaffolding.
- The D-07 heartbeat cadence is empirically observable in the simulator via log events (`app_container_init`, `app_coordinator_init`, and the attestation preflight events flow on scene connect); Plan 04-10 can grep for the expected event sequence in a device-CI smoke run.
- No blockers for downstream phases. Phase 5 (KYC + BOL) can depend on trustTier mutation through AppSession; the SceneDelegate heartbeat is the write path, the interceptor is the recovery path, both land in this plan.

**Concerns / residual risks (already accepted in threat_model)**
- T-APP-ATTEST-08 (cold-boot heartbeat on stale session → spike of 401 telemetry on /device/heartbeat): ACCEPTED. Documented in SceneDelegate header + attestation-rotation.md. Dual-duty heartbeat (liveness + session-validity) is the intended design.
- T-APP-ATTEST-15 (retry loop): MITIGATED via retry-once + linear flow. Quota pressure bounded to 1 extra generateKey per D-04 trigger.

---
*Phase: 04-app-attest-physical-device-ci-hardening*
*Plan: 07 (Wave 4)*
*Completed: 2026-04-22*
