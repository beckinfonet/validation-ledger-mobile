---
phase: 05-kyc-capture-upload-pipeline
plan: 07
subsystem: infra
tags: [kyc, app-wiring, bgtaskscheduler, background-tasks, coordinator, keychain, cold-boot-routing, session-restore]

# Dependency graph
requires:
  - phase: 05-kyc-capture-upload-pipeline
    plan: 01
    provides: OTPVerifyEndpoint.Response.kycStatus optional field, BGTask Info.plist registration, RED BackgroundUploadSchedulingTests scaffold
  - phase: 05-kyc-capture-upload-pipeline
    plan: 02
    provides: KYCSessionStore (loadSession pending-upload check), ArtifactUploadState.committed
  - phase: 05-kyc-capture-upload-pipeline
    plan: 04
    provides: KYCUploader actor — resumeAllPendingUploads() BGTask-handler entry point
  - phase: 05-kyc-capture-upload-pipeline
    plan: 05
    provides: KYCCoordinator type + onKYCSubmitted/onSignOut callback surface
  - phase: 03-otp-auth-role-shell-session
    provides: AppPhase/AppCoordinator/SceneDelegate .auth wiring, SessionRestoreService probe, OTPViewModel D-27 orchestration, LogoutService
provides:
  - .kyc(Role) AppPhase — the D-12 KYC hard gate; role shell unreachable until KYC submitted
  - KeychainKey.kycStatus + KeychainScope.session membership — D-13 cached KYC status
  - SessionRestoreResult.needsKYC(role:) — cold-boot routing on the cached kycStatus
  - AppCoordinator KYCCoordinator retention + onKYCSubmitted/onSignOut wiring
  - OTPViewModel.onKYCRequired — post-OTP routing of a non-verified user into the KYC gate
  - KYCUploadScheduler — BGProcessingTaskRequest scheduling + launch handler (UPL-05)
  - BGTaskScheduling protocol seam — simulator-testable scheduling decision logic
affects: [05-08-kyc-human-uat]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "AppPhase hard-gate: a non-verified kycStatus routes to .kyc(Role); the role shell is only constructed for .role — the gate is enforced at AppCoordinator.makeRoot routing (T-05-07-01)"
    - "Optimistic cold-boot routing: SessionRestoreService reads the cached kycStatus with no round-trip; absent/non-verified fails CLOSED to the KYC gate (T-05-07-02)"
    - "BGTaskScheduling protocol seam — an injectable wrapper over BGTaskScheduler so the scheduling decision is simulator-testable; DefaultBGTaskScheduling in prod, a fake in tests"
    - "AppDelegate-owned single scheduler: the BGTask handler registered once at launch; its live-uploader slot is filled by SceneDelegate so the handler captures the scene AppContainer's kycUploader, never a fresh container (T-05-07-06)"
    - "Coordinator retention by AppCoordinator — kycCoordinator strong property mirrors authCoordinator exactly (RESEARCH Pitfall 6)"

key-files:
  created:
    - validationLedger/Core/Identity/KYC/KYCUploadScheduler.swift
  modified:
    - validationLedger/Core/Storage/Keychain/KeychainKey.swift
    - validationLedger/Core/Storage/Keychain/KeychainScope.swift
    - validationLedger/Core/Auth/SessionRestoreService.swift
    - validationLedger/App/SceneDelegate.swift
    - validationLedger/App/AppCoordinator.swift
    - validationLedger/App/AppDelegate.swift
    - validationLedger/App/AppContainer.swift
    - validationLedger/Features/Onboarding/Auth/OTPViewModel.swift
    - validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift
    - validationLedgerTests/Auth/SessionRestoreServiceTests.swift
    - validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift
    - validationLedgerTests/KYC/BackgroundUploadSchedulingTests.swift

key-decisions:
  - "SessionRestoreResult gains a third case .needsKYC(role:) rather than a kycVerified Bool payload on .restored — the case keeps the SceneDelegate cold-boot switch exhaustive and self-documenting, and carries the role so the KYC gate's verified-Continue CTA routes on to the role shell"
  - "KYCUploadScheduler is owned by AppDelegate (single instance, BGTask handler registered once at launch) and INJECTED into every AppContainer SceneDelegate builds — AppContainer.init takes an optional kycUploadScheduler param, falling back to a fresh stand-alone scheduler when nil (existing tests / non-app callers) so the container is always fully formed"
  - "The BGTask handler resolves the uploader via a lock-guarded live-uploader slot the SceneDelegate fills with the scene AppContainer's kycUploader — the handler never constructs an AppContainer, so exactly one KYCSessionStore touches the on-disk store (T-05-07-06)"
  - "KYCCoordinator.onSignOut runs LogoutService.logout(.userInitiated) directly (D-14) — wiping the session-scope Keychain incl. kycStatus and posting .sessionDidInvalidate — rather than the bare onLogout→presentRoot(.auth) path, so the cached KYC status is properly wiped while the on-disk KYCSessionStore blob survives (D-02)"

patterns-established:
  - "AppPhase hard-gate pattern: a routing-decision enum case (.kyc(Role)) whose target VC tree (KYCCoordinator) is the only reachable surface until a gate condition (KYC submitted) is met"
  - "BGTaskScheduling seam: a Sendable protocol over BGTaskScheduler whose decision logic (submit-iff-pending) is exercised against a recording fake on simulator CI"

requirements-completed: [KYC-01, UPL-05]

# Metrics
duration: 15min
completed: 2026-05-17
---

# Phase 5 Plan 07: KYC Gate + Background-Upload Wiring Summary

**The `.kyc(Role)` `AppPhase` hard gate (D-12) — a non-verified user post-OTP or on cold boot is routed into `KYCCoordinator` and the role shell is unreachable until KYC is submitted — plus `KeychainKey.kycStatus` cold-boot routing (D-13), `KYCCoordinator` retention, the `KYCUploadScheduler` `BGProcessingTaskRequest` upload-continuation wiring (UPL-05), and the D-14 KYC sign-out path.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-05-17T06:56:20Z
- **Completed:** 2026-05-17T07:11:35Z
- **Tasks:** 2
- **Files:** 13 (1 created, 12 modified)

## Accomplishments

- **Task 1 — the `.kyc` hard gate + cold-boot routing.** Added `KeychainKey.kycStatus` (`session.kycStatus`) as a member of `KeychainScope.session` (the cached status string IS wiped on logout, like `sessionRole` — the on-disk `KYCSessionStore` blob is a separate store that survives, D-02). Added `case kyc(Role)` to `AppPhase`. Extended `SessionRestoreResult` with `case needsKYC(role:)` — `DefaultSessionRestoreService.probe()` reads the cached `kycStatus` optimistically (no round-trip) and routes a non-"verified" value to the KYC gate, failing CLOSED (T-05-07-02). `SceneDelegate.scene(_:willConnectTo:)`'s cold-boot switch routes `.needsKYC` → `presentRoot(.kyc)`. `AppCoordinator` constructs `KYCCoordinator` for `.kyc`, retains it in a `kycCoordinator` strong property (mirrors `authCoordinator` — RESEARCH Pitfall 6), and wires `onKYCSubmitted` → role shell and `onSignOut` → `LogoutService` (D-14). `OTPViewModel` persists the OTP-verify response's `kycStatus` to Keychain and routes via a new `onKYCRequired` callback (threaded through `AuthCoordinator` → `AppCoordinator` → `SceneDelegate`) when not verified.
- **Task 2 — `KYCUploadScheduler` + `BGProcessingTaskRequest` (UPL-05).** New `KYCUploadScheduler` in `Core/Identity/KYC/` implementing the RATIFIED foreground-loop-plus-BGTask model: a `BGProcessingTaskRequest` (under `com.maldin.validationLedger.kyc-upload`, matching the plan-01 Info.plist) granting runtime when the app backgrounds mid-upload — NOT a file-based background `URLSession`. A `BGTaskScheduling` protocol seam makes the scheduling decision simulator-testable. `AppDelegate` owns the single scheduler and registers its handler at launch (before `didFinishLaunchingWithOptions` returns — RESEARCH Pattern 6). `SceneDelegate` passes that scheduler into every `AppContainer`, fills its live-uploader slot with the scene container's `kycUploader`, and adds `sceneDidEnterBackground` which submits a `BGProcessingTaskRequest` when a non-committed artifact is on disk. The handler resumes the scene container's `KYCUploader.resumeAllPendingUploads()` — it never constructs a new `AppContainer` (T-05-07-06). `AppContainer` gains a `kycUploadScheduler` `let` property.

## Task Commits

Each task was committed atomically:

1. **Task 1: KeychainKey.kycStatus + .kyc AppPhase + cold-boot routing** — `4c582e9` (feat)
2. **Task 2: KYCUploadScheduler + BGProcessingTaskRequest wiring** — `b1d83d5` (feat)

**Plan metadata:** see final docs commit.

## Files Created/Modified

- `validationLedger/Core/Identity/KYC/KYCUploadScheduler.swift` — NEW. UPL-05 background upload-continuation: `BGProcessingTaskRequest` scheduling, BGTask launch handler, the `BGTaskScheduling` protocol seam + `DefaultBGTaskScheduling`, the lock-guarded live-uploader slot
- `validationLedger/Core/Storage/Keychain/KeychainKey.swift` — added `KeychainKey.kycStatus` (D-13)
- `validationLedger/Core/Storage/Keychain/KeychainScope.swift` — added `kycStatus` to `KeychainScope.session.contains(_:)` + doc comment
- `validationLedger/Core/Auth/SessionRestoreService.swift` — added `SessionRestoreResult.needsKYC(role:)`; `probe()` reads the cached `kycStatus`
- `validationLedger/App/SceneDelegate.swift` — added `case kyc(Role)` to `AppPhase`; cold-boot `.needsKYC` route; `presentRoot` injects the scheduler + fills the live-uploader slot; new `sceneDidEnterBackground` (UPL-05)
- `validationLedger/App/AppCoordinator.swift` — `kycCoordinator` retention property; `.kyc` init-switch branch; `onKYCSubmitted`/`onSignOut` wiring; `onKYCRequired` callback; `.kyc` in `phaseDescription`
- `validationLedger/App/AppDelegate.swift` — `kycUploadScheduler` property; `registerHandler()` at launch
- `validationLedger/App/AppContainer.swift` — `kycUploadScheduler` `let` property + optional `kycUploadScheduler` init param
- `validationLedger/Features/Onboarding/Auth/OTPViewModel.swift` — persists `kycStatus` to Keychain (D-27 step 2); `onKYCRequired` callback; D-12 routing on verified status
- `validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift` — `onKYCRequired` callback forwarding `OTPViewModel.onKYCRequired`
- `validationLedgerTests/Auth/SessionRestoreServiceTests.swift` — RED scaffold extended: verified → role result, absent/non-verified → KYC-gate result (3 new/updated tests)
- `validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift` — `SessionRestoreResult` switch made exhaustive for `.needsKYC` (Deviation 1)
- `validationLedgerTests/KYC/BackgroundUploadSchedulingTests.swift` — RED Wave-0 scaffold replaced with 4 GREEN tests over the `BGTaskScheduling` fake

## Decisions Made

- **`SessionRestoreResult` gains a `.needsKYC(role:)` case** rather than a `kycVerified: Bool` payload on `.restored`. The dedicated case keeps the SceneDelegate cold-boot `switch` exhaustive and self-documenting, and carries the role so the KYC gate's verified-"Continue" CTA can route on to the role shell.
- **`KYCUploadScheduler` is AppDelegate-owned and injected into `AppContainer`.** `AppDelegate` constructs the single scheduler (its BGTask handler is registered once per process at launch). `AppContainer.init` takes an optional `kycUploadScheduler` parameter; `SceneDelegate` passes the AppDelegate instance, so the BGTask handler's live-uploader slot, the slot `sceneDidEnterBackground` fills, and the scheduling decision all act on one scheduler. When `nil` (existing tests / non-app callers) `init` constructs a fresh stand-alone scheduler so the container is still fully formed.
- **The BGTask handler resolves the uploader via a lock-guarded live-uploader slot** the SceneDelegate fills with the scene `AppContainer`'s `kycUploader`. The handler never constructs an `AppContainer`, so exactly one `KYCSessionStore` instance touches the on-disk store (T-05-07-06).
- **`KYCCoordinator.onSignOut` runs `LogoutService.logout(.userInitiated)` directly** (D-14), not the bare `onLogout → presentRoot(.auth)` path — so the session-scope Keychain (incl. the cached `kycStatus`) is wiped and `.sessionDidInvalidate` posts (SceneDelegate's observer root-swaps to phone-entry). The on-disk `KYCSessionStore` blob is NOT in LogoutService teardown (D-02) — the partial KYC resumes on next login.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Pre-existing `SessionRestoreResult` switch made non-exhaustive by the new case**
- **Found during:** Task 1 (test build)
- **Issue:** Adding `case needsKYC(role:)` to `SessionRestoreResult` made the pre-existing `switch result` in `AppCoordinatorPhase3RoutingTests.sessionRestoreProbeRuns()` non-exhaustive — `error: switch must be exhaustive`. The test target would not build.
- **Fix:** Added `.needsKYC` to that switch's `case` list (it accepts any probe outcome — the test only asserts non-crash). A directly-caused blocking compile error from the current task's enum extension.
- **Files modified:** `validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift`
- **Verification:** `SessionRestoreServiceTests` builds + 6 tests GREEN.
- **Committed in:** `4c582e9` (Task 1 commit)

**2. [Rule 3 - Blocking] Simulator destination `iPhone 16` unavailable — substituted `iPhone 16e`**
- **Found during:** Task 1 (build + test verification)
- **Issue:** The plan's `<verify><automated>` commands target `platform=iOS Simulator,name=iPhone 16`, but this environment's installed simulators are `iPhone 16e`, `iPhone 17`, `iPhone 17 Pro`, `iPhone 17 Pro Max`, `iPhone Air` — no plain `iPhone 16` (the same environment limitation recorded in the 05-01..05 SUMMARYs).
- **Fix:** Ran all build/test verifications against `iPhone 16e`. Source/test code is destination-agnostic; only the verification destination changed.
- **Files modified:** None (verification command only).
- **Verification:** Build succeeds, both plan-07 suites GREEN on `iPhone 16e`.
- **Committed in:** N/A (no code change).

**3. [Rule 3 - Blocking] `xcodebuild test` must pass `-parallel-testing-enabled NO`**
- **Found during:** Task 1 (test run)
- **Issue:** The plan's `<verify><automated>` command does not pass `-parallel-testing-enabled NO`. The project's `.serialized` Swift Testing suites mutate the global `MockURLProtocol` registry and contaminate each other when run in parallel — a known project constraint (`ci-simulator.yml` already propagates the flag; documented in the Phase 2 and 05-04 SUMMARYs).
- **Fix:** Ran all `xcodebuild test` verifications with `-parallel-testing-enabled NO`, matching the project CI.
- **Files modified:** None (verification command only).
- **Verification:** Both plan-07 suites pass deterministically.
- **Committed in:** N/A (no code change).

**4. [Rule 3 - Blocking] `grep` gates tripped on negation doc comments — comments reworded**
- **Found during:** Task 2 (acceptance-criteria grep gates)
- **Issue:** Three grep gates must return 0: `background(withIdentifier` in `KYCUploadScheduler.swift`, and `AppContainer()` in both `KYCUploadScheduler.swift` and `AppDelegate.swift`. The file header comments explained the RATIFIED constraint by NAMING the forbidden things ("does NOT build a file-based background `URLSession`", "never constructs a new `AppContainer`") — the literal substrings tripped the gates even though the statements are negations and there is no actual usage. (Same grep-gate phrasing class as the 05-02 Deviation 4 and 05-04 Deviation 3.)
- **Fix:** Reworded the three doc comments to say "file-based background-mode session" and "composition root" instead of the literal API/type names. Same documentation intent; the gates now return 0. No behavioural change.
- **Files modified:** `validationLedger/Core/Identity/KYC/KYCUploadScheduler.swift`, `validationLedger/App/AppDelegate.swift` (comments only).
- **Verification:** All three gates return 0; build still succeeds; both suites still GREEN.
- **Committed in:** `b1d83d5` (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (all Rule 3 - blocking). Deviation 1 is a directly-caused compile error from the current task's enum extension. Deviations 2 and 3 are environment/verification-command substitutions for an unavailable simulator and a required CI flag — the delivered artifacts are unchanged. Deviation 4 is a grep-gate phrasing fix with no behavioural change.
**Impact on plan:** No scope creep. All planned artifacts delivered; all acceptance-criteria grep gates pass and both plan-07 suites are GREEN.

## Grep-Gate Literal-Target Notes

One acceptance-criteria grep gate exceeds its stated count for a benign reason; the gate intent holds:

- **`grep -c "kycStatus" KeychainKey.swift` returns 2, not 1.** `kycStatus` appears in the `public static let kycStatus` declaration (added exactly once, as required) and once in its explanatory doc comment. The key is declared exactly once; the second hit is the comment. The gate's intent — the key is added — is satisfied.

## Verification Results

- **`SessionRestoreServiceTests` — 6 tests GREEN** on `iPhone 16e`, `-parallel-testing-enabled NO`: verified `kycStatus` → `.restored(role:)`; absent `kycStatus` → `.needsKYC(role:)`; `kycStatus != "verified"` → `.needsKYC(role:)`; plus the 3 pre-existing `.needsAuth` tests.
- **`BackgroundUploadSchedulingTests` — 4 tests GREEN**: a pending upload submits exactly one `BGProcessingTaskRequest` under `com.maldin.validationLedger.kyc-upload`; the request has `requiresNetworkConnectivity == true` / `requiresExternalPower == false`; no pending upload submits nothing; `registerHandler` registers under the kyc-upload identifier.
- **Grep gates (all pass):** `kycStatus` in `KeychainKey.swift` = 2 (declaration + comment), in `KeychainScope.swift` = 4 (≥1); `case kyc` in `SceneDelegate.swift` = 1 (≥1); `kycCoordinator` in `AppCoordinator.swift` = 4 (≥2); `case .kyc` in `AppCoordinator.swift` = 3 (≥2); `kycStatus` (ci) in `OTPViewModel.swift` = 9 (≥1); `BGProcessingTaskRequest` in `KYCUploadScheduler.swift` = 4 (≥1); `com.maldin.validationLedger.kyc-upload` in `KYCUploadScheduler.swift` = 1 (≥1); `BGTaskScheduler` in `AppDelegate.swift` = 2 (≥1); `sceneDidEnterBackground` in `SceneDelegate.swift` = 1; `kycUploader|kycSessionStore` in `AppContainer.swift` = 8 (≥2); `background(withIdentifier` in `KYCUploadScheduler.swift` = 0; `AppContainer()` in `AppDelegate.swift` = 0; `AppContainer()` in `KYCUploadScheduler.swift` = 0.
- **Full simulator suite:** 316 tests, 314 pass. The 2 remaining failures are the plan-01 Wave-0 RED `#expect(Bool(false))` scaffolds owned by plan 05-06 — `KYCReviewViewModelTests` + `KYCStatusViewModelTests`, each with the literal placeholder `"RED: ... implemented in plan 05-06"`. They were RED before plan 05-07 and are out of scope here — no regression.
- The simulator scheme builds clean with the wired-in KYC subsystem.

## Threat Surface

The four `mitigate`-disposition threats in the plan's threat register are addressed:

- **T-05-07-01** (KYC gate bypassed to reach the role shell) — the `.kyc(Role)` hard gate is enforced at `AppCoordinator`'s init-switch routing: a non-verified `kycStatus` routes to `.kyc` and the `KYCCoordinator` is the only constructed VC tree; the role shell (`roleCoordinator`) is built only for `.role`. `GET /kyc/status` (the plan-06 status screen) re-confirms after routing.
- **T-05-07-02** (tampered/absent cached `kycStatus` grants role-shell access) — `SessionRestoreService.probe()` and `OTPViewModel`'s post-verify routing both check `kycStatus == "verified"` explicitly; any other value (including `nil`) routes to `.kyc`, never `.role` — fails CLOSED.
- **T-05-07-03** (`kycStatus` Keychain entry surviving logout) — `KeychainKey.kycStatus` is a member of `KeychainScope.session`, wiped by `deleteAll(under: .session)` on logout exactly like `sessionRole`; the separate on-disk `KYCSessionStore` blob deliberately survives (D-02).
- **T-05-07-06** (a second `KYCSessionStore` instance racing the scene store) — the BGTask handler captures the scene `AppContainer`'s `kycUploader` via the scheduler's lock-guarded live-uploader slot; it never constructs an `AppContainer`. The `grep` gates assert zero `AppContainer()` in `AppDelegate.swift` and `KYCUploadScheduler.swift`, so exactly one `KYCSessionStore` touches the on-disk store.

T-05-07-04 (sign-out loses in-progress KYC — `accept`) and T-05-07-05 / T-05-07-SC (`accept`) need no implementation; D-14's `LogoutService` path leaves the on-disk session untouched, as designed. No new security surface beyond the plan's threat model was introduced.

## Issues Encountered

- The full simulator run shows 2 failing tests — `KYCReviewViewModelTests` + `KYCStatusViewModelTests`. Both are explicit plan-01 Wave-0 RED scaffolds (`#expect(Bool(false), "RED: ... implemented in plan 05-06")`) owned by plan 05-06, which has not yet executed. They were RED before plan 05-07 and are out of scope — not a regression, and already documented upstream (05-01 SUMMARY "Known Stubs", 05-04 SUMMARY "Verification Results"). No deferred item created.

## Known Stubs

None introduced by this plan. `KYCCoordinator.pushReview()` remains a stub (a plan-05 known item that plan 06 fills in) — this plan does not touch it. The `.kyc` gate, cold-boot routing, BGTask scheduling, and the D-14 sign-out path are all fully wired and tested.

## User Setup Required

None — no external service configuration required. Phase 5 installs zero packages (threat T-05-07-SC, RESEARCH Package Legitimacy Audit); `BackgroundTasks` is a first-party iOS 17 SDK framework.

## Next Phase Readiness

- The Phase 5 KYC subsystem is now fully wired into the app: cold boot and post-OTP both route a non-verified user into `KYCCoordinator` via the `.kyc` hard gate; the BGTask continuation is registered and scheduled; the D-14 sign-out path runs `LogoutService` while leaving the on-disk session intact.
- **Plan 05-06** (KYC review/status) fills the `KYCCoordinator.pushReview()` stub and turns the two remaining RED scaffolds (`KYCReviewViewModelTests`, `KYCStatusViewModelTests`) GREEN. Once the review screen calls `onKYCSubmitted`, the `.kyc → .role` transition this plan wired completes end-to-end.
- **Plan 05-08** consolidates the physical-device HUMAN-UAT — including a live verification of the `.kyc` gate (cold-boot routing on a real `kycStatus`), the BGTask continuation across a real background transition, and the D-14 sign-out path.
- No existing test regressed; the plan-01 RED `BackgroundUploadSchedulingTests` scaffold for this plan is now GREEN.

## Self-Check: PASSED

All created/modified files verified on disk (`KYCUploadScheduler.swift`, `KeychainKey.swift`, `SessionRestoreService.swift`, `AppCoordinator.swift`, `BackgroundUploadSchedulingTests.swift`). Both task commits verified in `git log` (`4c582e9`, `b1d83d5`). `SessionRestoreServiceTests` (6) + `BackgroundUploadSchedulingTests` (4) GREEN; all grep gates pass; simulator scheme builds clean.

---
*Phase: 05-kyc-capture-upload-pipeline*
*Completed: 2026-05-17*
