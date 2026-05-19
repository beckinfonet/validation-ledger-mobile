---
phase: 05-kyc-capture-upload-pipeline
verified: 2026-05-18T20:00:00Z
status: human_needed
score: 5/5
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 5/5
  gaps_closed:
    - "SC-2 force-quit mid-upload resume — now automated by KYCForceQuitResumeUITests on the device CI lane (plan 05-12/05-13)"
    - "D-08 Profile entry to KYC status screen — now automated by KYCProfileEntryUITests on the device CI lane (plan 05-12/05-13)"
    - "D-12 hard gate (non-verified cannot reach role shell) — now automated by KYCHardGateUITests on the device CI lane (plan 05-12/05-13)"
    - "Test-10 background/foreground capture-session resilience — now automated by KYCCaptureLifecycleUITests on the device CI lane (plan 05-12/05-13)"
  gaps_remaining: []
  regressions: []
gaps: []
human_verification:
  - test: "SC-4 — background-upload completion under real OS suspension via BGProcessingTaskRequest"
    expected: "With an artifact mid-upload, backgrounding the app (Home / swipe up but do NOT kill) allows the upload to continue and complete. Re-opening the app shows the artifact as committed."
    why_human: "iOS grants BGProcessingTaskRequest runtime on its own schedule — not reproducible in CI or simulator, and no XCUITest can force the OS to grant background runtime on demand. BackgroundUploadSchedulingTests proves the scheduling decision logic; end-to-end completion under real suspension is human-only."
  - test: "Test 10 — deliberate AVCaptureSessionRuntimeError injection on device (recoverable-cue / shutter re-arm)"
    expected: "When a genuine AVCaptureSessionRuntimeError occurs (a real camera-hardware fault), the capture screen shows a recoverable 'The camera needs a moment. Try the photo again.' cue within ~5s with the shutter button ENABLED — not a permanent dead shutter — and tapping the shutter fires another capture attempt."
    why_human: "A genuine AVCaptureSessionRuntimeError is a real camera-hardware fault that cannot be forced on demand by any XCUITest — the live AVFoundation runtimeErrorNotification only fires on a real device under a real fault. CameraSessionLifecycleTests proves the VM-layer shutter re-arm in the simulator; the runtime-error rebuild path is hardware-only. (The background/foreground portion of Test 10 is now automated by KYCCaptureLifecycleUITests on the device CI lane.)"
---

# Phase 5: KYC Capture + Upload Pipeline — Verification Report (Re-verification 3)

**Phase Goal:** Build `KYCCoordinator` + capture flow (face → DL front/back → vehicle/trailer/plate) with GPS metadata attached at capture time via `AVCapturePhoto.fileDataRepresentation()` → `CGImageDestination` GPS injection (never through `UIImage`), and the resumable chunked upload pipeline (idempotency-keyed, jittered backoff, foreground `URLSession` chunk loop + `BGProcessingTaskRequest` continuation). KYC status UI renders Pending/Under Review/Verified/Rejected with rejection-reason copy.

**Verified:** 2026-05-18T20:00:00Z
**Status:** human_needed
**Re-verification:** Yes — third pass; gap-closure plans 05-11 (DEBUG launch-argument test seams), 05-12 (four device XCUITest files), and 05-13 (device CI lane wiring). 4 of the 5 prior human-UAT items are now automated as device XCUITests on the `ci-device.yml` lane. 2 human-UAT items remain (SC-4 and the Test-10 deliberate AVCaptureSessionRuntimeError injection).

---

## Re-verification Summary

The prior VERIFICATION.md (2026-05-18T07:00:00Z) scored 5/5 with `status: human_needed`. That pass closed UAT Test 9 (status screen error on device) and UAT Test 10 (force-quit camera shutter wedge) at the code level, leaving 5 physical-device human-UAT items.

This re-verification pass focuses on the device-UAT automation gap-closure plans:

- **Plan 05-11** — added the `#if DEBUG`-gated `-KYCTestSeedForUITest` launch-argument seam (three modes: `nonVerified`, `underReview`, `midUpload`) to `SceneDelegate`, `AppContainer`, and `KYCSessionStore`. Seam suppresses cold-boot biometric lock under the seam. Commits: `0c673b7`, `bb95a13`, `c128f1e`, `ffd8569` (biometric-lock fix).
- **Plan 05-12** — created four device XCUITest files: `KYCForceQuitResumeUITests` (SC-2), `KYCProfileEntryUITests` (D-08), `KYCHardGateUITests` (D-12), `KYCCaptureLifecycleUITests` (Test-10 background/foreground). Commits: `7596d78`, `09e3e7b`, `c1ce155`, `bdbcd3b` (hittable-guard fix).
- **Plan 05-13** — wired the four XCUITest classes into `ci-device.yml` device lane (class-scoped `-only-testing` flags, not the whole target), raised `timeout-minutes` 25→35, updated `05-HUMAN-UAT.md` and `05-VERIFICATION.md`, updated `docs/ci.md`. Commits: `af63146`, `3de4b11`, `0f97ee3` (scope fix), `fa72922` (MockOTP fixture fix).

Device run result (orchestrator-provided): `Beck Maldin 16` (iPhone 16) — 4/4 tests passed, zero retries:

| XCUITest | Requirement | Result |
|----------|-------------|--------|
| `KYCForceQuitResumeUITests` | SC-2 | passed 13.1s |
| `KYCProfileEntryUITests` | D-08 | passed 9.5s |
| `KYCHardGateUITests` | D-12 | passed 3.8s |
| `KYCCaptureLifecycleUITests` | Test-10 bg/fg | passed 29.3s |

Simulator suite: 367 unit tests, 0 failures (carried forward from prior).

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A user in any role can complete the full KYC capture flow, each captured artifact has EXIF GPS metadata from a fresh (<30s, <100m) CLLocation | VERIFIED | `KYCGPSUploadPayloadIntegrationTests` (commit `300a976`): injects CLLocation 41.8781/-87.6298 → `GPSMetadataInjector.injectGPS` → `KYCSessionStore` → `KYCUploader.upload(.face)` via `MockURLProtocol` → reassembles chunk_data bodies → asserts byte-identical GPS-tagged JPEG + lat/lon recovery within epsilon 0.0001. Test GREEN. |
| 2 | Killing the app mid-upload and relaunching resumes from the last committed chunk | VERIFIED (automated device lane) | `KYCForceQuitResumeUITests` (commit `09e3e7b`) performs a real `XCUIApplication().terminate()` + relaunch under the `midUpload` seed and asserts non-error resumed state — device-verified passing 13.1s. `KYCUploaderResumeTests` (chunksAcked==2 resume, no re-init) and `KYCForceQuitResumeDeviceTests` (339 lines, asserts first chunk after resume = index 5) cover the pipeline/persistence layer. |
| 3 | The KYC status screen renders Pending / Under Review / Verified / Rejected with backend rejection-reason copy — driven through mock fixtures | VERIFIED | `KYCStatusViewModelTests`: 2 tests drive all 4 fixtures. `RejectionReasonCode` enum finalized. `MockDefaultFixtures.dispatchHandler` has a `(GET, /kyc/status)` case returning `kycStatusResponseJSON()`. `Gap (Test 9)` regression test GREEN. `KYCProfileEntryUITests` device-verifies `KYCStatusViewController` opens from Profile (passed 9.5s on device). |
| 4 | Uploads continue in the background via BGProcessingTaskRequest | VERIFIED (scheduling logic) / HUMAN-UAT (UX) | `BackgroundUploadSchedulingTests` GREEN. `SceneDelegate.sceneDidEnterBackground` wired to `scheduleUploadContinuation`. `AppDelegate.kycUploadScheduler.registerHandler()` called before launch returns. `Info.plist`: `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: processing`. Real OS completion is HUMAN-UAT (SC-4). |
| 5 | Exponential backoff with jitter caps retries at 5 attempts; idempotency keys prevent duplicate chunk commits | VERIFIED | `KYCUploaderRetryTests`: explicitly asserts `recorder.attempts(forChunk: 0) == 5`. `KYCUploaderIdempotencyTests` (3 tests): stable key reuse, no duplicate ack, key stable across resume. |

**Score:** 5/5 — all automated success criteria verified. Status is `human_needed` because 2 physical-device items remain that cannot be verified in CI or the simulator.

---

### Device-UAT Automation (Plans 05-11 / 05-12 / 05-13)

The device-UAT burden has been reduced from 5 items to 2. Plans 05-11, 05-12, and 05-13 automate four of the five device-UAT items as XCUITests that run on the self-hosted device CI lane on every merge to `main`:

| Former human item | Now automated by | Device CI lane |
|-------------------|------------------|----------------|
| SC-2 — force-quit mid-upload resume | `KYCForceQuitResumeUITests` (real `terminate()` + relaunch) | `ci-device.yml` class-scoped `-only-testing` |
| D-08 — Profile entry to KYC status screen | `KYCProfileEntryUITests` (live `nav-avatar` → `profile-kyc-status` tap-through) | `ci-device.yml` class-scoped `-only-testing` |
| D-12 — hard gate (non-verified cannot reach role shell) | `KYCHardGateUITests` (seeded `nonVerified`, asserts no role tab bar) | `ci-device.yml` class-scoped `-only-testing` |
| Test 10 — background/foreground capture-session resilience | `KYCCaptureLifecycleUITests` (`press(.home)` + `activate()`, shutter `isHittable`) | `ci-device.yml` class-scoped `-only-testing` |

The device lane uses class-scoped `-only-testing` flags (not `-only-testing:validationLedgerUITests`) because the whole target also holds `RoleShellSmokeTests` and `LimitedTrustBannerTests`, which are simulator-tuned and fail on real hardware.

Only 2 human-UAT items remain — SC-4 (`BGProcessingTaskRequest` background-upload completion) and the Test-10 deliberate `AVCaptureSessionRuntimeError` injection — both irreducibly human because neither the OS background-runtime grant nor a real camera-hardware fault can be forced on demand by an XCUITest.

---

### Required Artifacts (Gap-Closure 05-11 / 05-12 / 05-13)

All artifacts from prior verification carry forward as VERIFIED. Additions from plans 05-11, 05-12, 05-13:

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `validationLedger/App/SceneDelegate.swift` | `#if DEBUG` `-KYCTestSeedForUITest` parsing block; falls through to `SessionRestoreProbe` switch; suppresses cold-boot biometric lock under seam | VERIFIED | Lines 232, 486: seam parses 3 modes, sets `AppContainer.kycTestSeed` + `.mock` networkConfig, does NOT early-return; `presentBiometricLockIfNeeded` early-returns on seam presence. 12 commits confirmed in git. |
| `validationLedger/App/AppContainer.swift` | `#if DEBUG` `enum KYCUITestSeed` (3 cases) + `static var kycTestSeed: KYCUITestSeed?` + init-time `#if DEBUG` consumption block seeding Keychain state | VERIFIED | Lines 93, 107, 524: enum declared; static declared; consumption block writes `sessionToken`, `sessionRole`, `kycStatus` via `KeychainStore` keys; `.midUpload` calls `seedMidUploadStateForUITest()`. |
| `validationLedger/Core/Storage/KYCSessionStore.swift` | `#if DEBUG` `seedMidUploadStateForUITest()` using `withSession` API; `chunksAcked==5`, `totalChunks==12`, `committed==false` | VERIFIED | Line 271: method exists; `#if DEBUG` confirmed; body calls `withSession`. |
| `validationLedgerUITests/KYCForceQuitResumeUITests.swift` | SC-2: `terminate()` + relaunch under `midUpload` seed; asserts non-error resumed state | VERIFIED | File exists (8211 bytes); `grep -c 'terminate()'` returns 7; `grep -c 'KYCTestSeedForUITest'` returns 3. Device: passed 13.1s. |
| `validationLedgerUITests/KYCProfileEntryUITests.swift` | D-08: `nav-avatar` tap → `profile-kyc-status` tap → `kyc-status-heading` appears | VERIFIED | File exists (5220 bytes); `grep -c 'profile-kyc-status'` returns 3. Device: passed 9.5s. |
| `validationLedgerUITests/KYCHardGateUITests.swift` | D-12: `nonVerified` seed → `kyc-start-heading` exists → no role tab bar | VERIFIED | File exists (4342 bytes); `grep -c 'kyc-start-heading'` returns 3. Device: passed 3.8s. |
| `validationLedgerUITests/KYCCaptureLifecycleUITests.swift` | Test-10 bg/fg: `press(.home)` + `activate()` → `kyc-face-shutter` `isHittable` | VERIFIED | File exists (6061 bytes); `grep -c 'XCUIDevice.shared.press'` returns 2; `grep -c 'kyc-face-shutter'` returns 3. Device: passed 29.3s. |
| `.github/workflows/ci-device.yml` | Class-scoped `-only-testing` for 4 KYC XCUITest classes; `changes` PATTERN includes `validationLedgerUITests/`; `timeout-minutes: 35` | VERIFIED | Lines 55, 77, 123-126: 4 class-scoped flags confirmed; path filter includes `validationLedgerUITests/`; timeout is 35. |
| `validationLedger.xcodeproj/xcshareddata/xcschemes/validationLedger.xcscheme` | `validationLedgerUITests` TestableReference present and not `skipped` | VERIFIED | `skipped = "NO"` confirmed at line 43 of the scheme file. |
| `docs/ci.md` | Subsection describing the device XCUITest lane and naming the four files | VERIFIED | Lines 140-164: subsection present, names all four files, documents class-scoped scope decision. |
| `.planning/phases/05-kyc-capture-upload-pipeline/05-HUMAN-UAT.md` | 4 items marked AUTOMATED; 2 items remain open; dated 2026-05-18 note | VERIFIED | Items 1 (SC-2), 3 (D-08), 4 (D-12), 5 bg/fg portion marked `[x] AUTOMATED`; items 2 (SC-4) and 5 runtime-error injection are `[ ] REMAINS HUMAN-UAT`. Dated note at file top confirmed. |

---

### Key Link Verification (Gap-Closure 05-11 / 05-12 / 05-13)

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `validationLedgerUITests/*.swift` | `validationLedger/App/SceneDelegate.swift` | `launchArguments = ["-KYCTestSeedForUITest", <mode>]` | WIRED | All four XCUITest files set launch arguments; SceneDelegate parses at line 232. |
| `SceneDelegate` `-KYCTestSeedForUITest` block | `AppContainer.kycTestSeed` | Static set before throwaway container construction | WIRED | SceneDelegate:245 sets static; AppContainer:524 reads it in `#if DEBUG` block. |
| `AppContainer.init` `#if DEBUG` block | `KYCSessionStore.seedMidUploadStateForUITest()` | Called when `seed == .midUpload` | WIRED | AppContainer:576 calls `kycStore.seedMidUploadStateForUITest()` inside `.midUpload` case. |
| `ci-device.yml` `device-security-surface` job | `KYCForceQuitResumeUITests`, `KYCProfileEntryUITests`, `KYCHardGateUITests`, `KYCCaptureLifecycleUITests` | Class-scoped `-only-testing:validationLedgerUITests/<ClassName>` flags | WIRED | Lines 123-126 of `ci-device.yml` confirmed. |
| `ci-device.yml` `changes` PATTERN | `validationLedgerUITests/` path | Regex includes `validationLedgerUITests/` | WIRED | Line 55 confirmed. |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|------------|------------|-------------|--------|----------|
| KYC-01 | 05-01–05-06 | KYCCoordinator orchestrates capture flow: face → DL front → DL back → vehicle/trailer/plate | SATISFIED | KYCCoordinator exists; capture flow verified in prior verification passes |
| KYC-02 | 05-05 | Live face capture with Vision quality gate | SATISFIED | FaceCaptureViewModel + Vision gate; `CameraSessionLifecycleTests` covers timeout resilience |
| KYC-03 | 05-05 | DL capture via VisionKit DataScannerViewController | SATISFIED | DLScanViewController exists; prior verification |
| KYC-04 | 05-04 | GPS attached via AVCapturePhoto/CGImageDestination, never UIImage | SATISFIED | `KYCGPSUploadPayloadIntegrationTests` GREEN |
| KYC-05 | 05-07 | KYC status UI renders 4 states with controlled-vocabulary rejection copy | SATISFIED | `KYCStatusViewModelTests` GREEN; `KYCProfileEntryUITests` device-verifies the screen opens |
| KYC-06 | 05-03 | In-progress KYC survives backgrounding via encrypted on-disk persistence | SATISFIED | `KYCSessionStore` encryption confirmed; `LogoutPreservesKYCSessionTests` GREEN |
| UPL-01 | 05-02 | KYCUploader chunked upload, 512 KB default chunk size | SATISFIED | KYCUploader exists; chunk size confirmed |
| UPL-02 | 05-02 | Resumable uploads persist chunk state; resume from last committed chunk | SATISFIED | `KYCUploaderResumeTests` GREEN; `KYCForceQuitResumeUITests` device-verified |
| UPL-03 | 05-02 | Exponential backoff with jitter, max 5 attempts | SATISFIED | `KYCUploaderRetryTests` asserts exactly 5 attempts |
| UPL-04 | 05-02 | Upload progress via Progress object, UIProgressView | SATISFIED | Progress wiring confirmed in prior verification |
| UPL-05 | 05-03 | BGProcessingTaskRequest for background uploads | SATISFIED (scheduling logic) / HUMAN-UAT (end-to-end) | `BackgroundUploadSchedulingTests` GREEN; `BackgroundUploadSchedulingTests` proves scheduling logic; end-to-end is SC-4 human item |

All 11 requirement IDs tracked in REQUIREMENTS.md as Complete / Phase 5.

---

### Anti-Patterns Found (Plans 05-11 / 05-12 / 05-13)

No `TBD`, `FIXME`, or `XXX` debt markers found in any of the 10 gap-closure files reviewed (`SceneDelegate.swift`, `AppContainer.swift`, `KYCSessionStore.swift`, `MockOTPRoleFixtureRegistry.swift`, the four XCUITest files, `ci-device.yml`, `docs/ci.md`).

The code review (`05-REVIEW.md`, gap-closure scope) found 1 critical issue and 5 warnings, all in the DEBUG-only test-seam code:

| File | Finding | Severity | Impact on Phase Goal |
|------|---------|----------|----------------------|
| `AppContainer.swift` lines 524-588 | **CR-01**: `AppContainer.kycTestSeed` static never cleared after consumption — seed re-fires on every subsequent `AppContainer` construction | WARNING (DEBUG-only) | Does not block phase goal. All 4 device XCUITests pass 4/4 with this bug present. Harms are latent: `.midUpload` resume semantics could be corrupted if a future test drives real `resumeAllPendingUploads`. Fix: add `AppContainer.kycTestSeed = nil` immediately after reading the static. A `--fix` follow-up is recommended. |
| `SceneDelegate.swift` lines 231-256 | WR-01: Seam never calls `MockURLProtocol.reset()`; fixture source implicit | Warning | Non-blocking. Fixture registration happens incidentally via `MockDefaultFixtures.registerAppDefaults()`. Tests pass. |
| `SceneDelegate.swift` line 251 | WR-02: Throwaway probe container spins up and orphans full composition root | Warning | Non-blocking. Orphaned graph emits confusing extra init/deinit logs. Existing tests pass. |
| `SceneDelegate.swift` lines 475-487 | WR-03: Biometric-lock suppression over-scoped — disables SESS-02 foreground re-prompt as well as SESS-01 cold-boot lock | Warning | Non-blocking for current tests. Latent: any future seeded UITest exercising SESS-02 background-timeout re-prompt is silently impossible. |
| `KYCCaptureLifecycleUITests.swift` | WR-04: Hard-fails on simulator instead of skipping | Warning | Non-blocking for device CI lane. Would produce a misleading red failure if run on simulator locally. Fix: add `#if targetEnvironment(simulator)` throw `XCTSkip`. |
| `KYCSessionStore.swift` lines 271-294 | WR-05: `seedMidUploadStateForUITest` seeds `localDataAvailable: true` with no corresponding `artifactData` — internally inconsistent | Warning | Non-blocking for current tests (no test drives real `resumeAllPendingUploads` against the seed). Latent trap for future tests. |

CR-01 is classified as "critical" in the code review's internal severity system but is strictly `#if DEBUG` with zero Release footprint. The four device XCUITests passed 4/4 on the physical device runner with CR-01 present. This does not constitute a BLOCKER for phase goal achievement.

Pre-existing WARNINGs from earlier full-phase review (WR-01 through WR-05 in `CameraSession.swift`/`FaceCaptureViewModel.swift`) also carry forward unchanged.

---

### Behavioral Spot-Checks

Step 7b SKIPPED — requires a booted simulator + app. Orchestrator-provided gate (367 unit tests + 4 device XCUITests, 0 failures) is the authority.

---

### Probe Execution

No probe scripts declared. No conventional `scripts/*/tests/probe-*.sh` present. SKIPPED.

---

### Human Verification Required

The following items require physical-device testing and are tracked in `05-HUMAN-UAT.md`. After the plan 05-11/05-12/05-13 device-UAT automation, only **2** human-UAT items remain (down from 5):

---

**1. SC-4 — Background-Upload Completion**

**Test:** With an artifact mid-upload, background the app (Home / swipe up but do NOT kill). Wait. Re-open the app.

**Expected:** Artifact shows committed — upload completed while backgrounded via `BGProcessingTaskRequest` runtime.

**Why human:** iOS grants `BGProcessingTaskRequest` on its own schedule. `BackgroundUploadSchedulingTests` proves the scheduling decision logic. End-to-end completion under real OS suspension is not reproducible in CI.

---

**2. Test 10 — Deliberate AVCaptureSessionRuntimeError Injection (hardware fault path)**

**Test:** On a physical iPhone, when a genuine `AVCaptureSessionRuntimeError` occurs (a real camera-hardware fault), confirm within ~5 seconds the capture screen shows a recoverable cue ("The camera needs a moment. Try the photo again.") with the shutter button ENABLED — not a dead/unresponsive shutter — and tapping the shutter fires another capture attempt.

**Expected:** The capture screen recovers gracefully within ~5s with `shutterButton.isEnabled = true`. Tapping the shutter retries capture.

**Why human:** A genuine `AVCaptureSessionRuntimeError` is a real camera-hardware fault that cannot be forced on demand by any XCUITest — the live `AVFoundation.runtimeErrorNotification` only fires on a real device under a real fault. `CameraSessionLifecycleTests` proves the VM-layer shutter re-arm (`captureInFlight` cleared, `.captureUnavailable` state reached). The runtime-error rebuild path is hardware-only. (The background/foreground portion of Test 10 is now automated by `KYCCaptureLifecycleUITests` on the device CI lane.)

---

### Gaps Summary

No open gaps. Plans 05-11, 05-12, and 05-13 delivered the device-UAT automation as planned:

- The `-KYCTestSeedForUITest` launch seam is in the codebase, `#if DEBUG`-gated, zero Release footprint.
- All four XCUITest files exist and pass 4/4 on the physical device runner.
- The device CI lane (`ci-device.yml`) runs the four KYC XCUITest classes on every merge.
- `05-HUMAN-UAT.md` documents the automation and records exactly 2 remaining human items.

The remaining `human_needed` status reflects **2** physical-device items that are irreducibly human-UAT. The code review (05-REVIEW.md, gap-closure scope) found CR-01 (non-consume-once seam static) and 5 warnings — all in the `#if DEBUG` test-seam code, all non-blocking for phase goal achievement. A `--fix` follow-up addressing CR-01 and WR-04/WR-05 is recommended before the seam is extended.

---

_Verified: 2026-05-18T20:00:00Z_
_Verifier: Claude (gsd-verifier) — re-verification pass 3 (gap-closure plans 05-11, 05-12, 05-13)_
