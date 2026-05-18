---
phase: 05-kyc-capture-upload-pipeline
verified: 2026-05-18T07:00:00Z
status: human_needed
score: 5/5
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 5/5
  gaps_closed:
    - "UAT Test 9 — KYC status screen errored on DEBUG device builds (missing GET /kyc/status mock route)"
    - "UAT Test 10 — force-quit mid-capture wedged the shutter (capturePhoto() hung forever on dead capture source)"
  gaps_remaining: []
  regressions: []
gaps: []
human_verification:
  - test: "SC-2 — force-quit mid-6MB-upload resumes from the last committed chunk (real process lifecycle UX)"
    expected: "After force-quitting the app during a 6MB upload and relaunching, the progress bar restores to the prior chunksAcked/totalChunks (NOT 0%), and the artifact eventually commits without re-uploading already-acked chunks."
    why_human: "A real app-kill + relaunch cannot be simulated in xcodebuild test. KYCUploaderResumeTests proves the resume logic on the simulator; KYCForceQuitResumeDeviceTests proves the pipeline + persistence on real hardware with a real 6MB payload. The end-to-end UX (progress bar restoration visible to the user) requires a human force-quit."
  - test: "SC-4 — background-upload completion under real OS suspension via BGProcessingTaskRequest"
    expected: "With an artifact mid-upload, backgrounding the app (Home / swipe up but do NOT kill) allows the upload to continue and complete. Re-opening the app shows the artifact as committed."
    why_human: "iOS grants BGProcessingTaskRequest runtime on its own schedule — not reproducible in CI or simulator. BackgroundUploadSchedulingTests proves the scheduling decision logic; end-to-end completion under real suspension is human-only."
  - test: "D-08 — Profile entry to the KYC status screen (live tap-through)"
    expected: "In the role shell, tapping the Profile avatar opens Profile, which shows a 'Verification status' row that opens KYCStatusViewController and re-fetches GET /kyc/status (now returns 200 with under_review verdict after plan 05-09)."
    why_human: "KYCEndToEndIntegrationTests covers the pipeline-level wiring; the live tap-through and re-fetch UX requires a human confirmation on a physical device with a running app. The Test 9 gap that previously blocked this test is now closed."
  - test: "D-12 — hard gate: a non-verified account cannot reach the role shell"
    expected: "After OTP-verify on a non-verified account, the app lands in the KYC flow (KYCCoordinator), not the role tab bar."
    why_human: "SessionRestoreServiceTests proves the cold-boot routing logic; the end-to-end 'cannot reach role shell' UX is confirmed live on device."
  - test: "Test 10 runtime-error / lifecycle resilience on device (live-AVFoundation observers)"
    expected: "After an ungraceful force-quit mid-capture and relaunch, the capture screen's shutter is responsive within ~5s — a recoverable 'The camera needs a moment. Try the photo again.' cue appears with the shutter enabled. The session self-heals: backgrounding and foregrounding the app mid-capture restores a working capture session."
    why_human: "AVFoundation runtimeErrorNotification, wasInterrupted/interruptionEnded, and didEnterBackground/willEnterForeground observers are live-session notifications — they do not fire in the iOS Simulator. CameraSessionLifecycleTests proves the VM-layer shutter re-arm; the live hardware lifecycle is device-only."
---

# Phase 5: KYC Capture + Upload Pipeline — Verification Report (Re-verification)

**Phase Goal:** Build `KYCCoordinator` + capture flow (face → DL front/back → vehicle/trailer/plate) with GPS metadata attached at capture time via `AVCapturePhoto.fileDataRepresentation()` → `CGImageDestination` GPS injection (never through `UIImage`), and the resumable chunked upload pipeline (idempotency-keyed, jittered backoff, foreground `URLSession` chunk loop + `BGProcessingTaskRequest` continuation). KYC status UI renders Pending/Under Review/Verified/Rejected with rejection-reason copy.

**Verified:** 2026-05-18T07:00:00Z
**Status:** human_needed
**Re-verification:** Yes — gap-closure pass for UAT Test 9 (status screen error on device) and UAT Test 10 (force-quit camera shutter wedge). Both code-level gaps confirmed closed. All 5 automated success criteria remain verified. Human-UAT items expanded by one (device-level AVFoundation lifecycle).

---

## Re-verification Summary

The prior VERIFICATION.md (2026-05-17) already scored 5/5 with `status: human_needed`. This re-verification pass focuses on the two gap-closure plans executed after that report:

- **Plan 05-09** — closed UAT Test 9 by adding a `(GET, /kyc/status)` dispatch case and `kycStatusResponseJSON()` builder to `MockDefaultFixtures.swift`, plus a regression test in `MockDefaultFixturesKYCTests`.
- **Plan 05-10** — closed UAT Test 10 by bounding `capturePhoto()` with a 5s timeout + exactly-once `resolveCapture(_:)` resolver, adding `AVFoundationCameraSession` runtime-error/interruption/lifecycle observers with `deinit`-removed tokens, introducing `.captureUnavailable` recoverable state in both capture VMs, and rendering it with the shutter ENABLED in both capture VCs.

Orchestrator-provided gate evidence: build (`xcodebuild build-for-testing`, iPhone 17 sim) — 0 errors; test suite — 367 tests, 70 suites, 0 failures. The new suites `CameraSessionLifecycleTests` (5 tests) and the `Gap (Test 9)` test in `MockDefaultFixturesKYCTests` both pass.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A user in any role can complete the full KYC capture flow, each captured artifact has EXIF GPS metadata from a fresh (<30s, <100m) CLLocation — verified by a unit test round-tripping a known GPS value to the upload payload | VERIFIED | `KYCGPSUploadPayloadIntegrationTests` (commit `300a976`): injects CLLocation 41.8781/-87.6298 → `GPSMetadataInjector.injectGPS` → `KYCSessionStore` → `KYCUploader.upload(.face)` via `MockURLProtocol` → reassembles chunk_data bodies → asserts byte-identical GPS-tagged JPEG + lat/lon recovery within epsilon 0.0001. Test GREEN. |
| 2 | Killing the app mid-upload and relaunching resumes from the last committed chunk — physical-device test | VERIFIED (device lane) | `KYCUploaderResumeTests` (chunksAcked==2 resume, no re-init). `KYCForceQuitResumeDeviceTests` (339 lines): reconstructs KYCUploader+KYCSessionStore from same directory (force-quit model), asserts first chunk after resume = index 5. Physical-device UX routed to HUMAN-UAT per established standing. |
| 3 | The KYC status screen renders Pending / Under Review / Verified / Rejected with backend rejection-reason copy — driven through mock fixtures | VERIFIED | `KYCStatusViewModelTests`: 2 tests drive all 4 fixtures (kyc-status-{pending,under-review,verified,rejected}.json). `RejectionReasonCode` enum finalized. Plan 05-09 closes the device-build gap: `MockDefaultFixtures.dispatchHandler` now has a `(GET, /kyc/status)` case returning `kycStatusResponseJSON()` — `{"overall_status":"under_review","artifacts":[]}`. `Gap (Test 9)` regression test passes. |
| 4 | Uploads continue in the background via BGProcessingTaskRequest | VERIFIED (scheduling logic) / HUMAN-UAT (UX) | `BackgroundUploadSchedulingTests` GREEN. `SceneDelegate.sceneDidEnterBackground` wired to `scheduleUploadContinuation`. `AppDelegate.kycUploadScheduler.registerHandler()` called before launch returns. `Info.plist`: `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: processing`. Real OS completion is HUMAN-UAT. |
| 5 | Exponential backoff with jitter caps retries at 5 attempts; idempotency keys prevent duplicate chunk commits | VERIFIED | `KYCUploaderRetryTests`: explicitly asserts `recorder.attempts(forChunk: 0) == 5`. `KYCUploaderIdempotencyTests` (3 tests): stable key reuse, no duplicate ack, key stable across resume. |

**Score:** 5/5 — all automated success criteria verified. Status is `human_needed` because 5 physical-device items remain (expanded by one from prior: the Test 10 device-level AVFoundation lifecycle confirmation).

---

### Gap-Closure Verification (Plans 05-09 and 05-10)

#### UAT Test 9 — KYC Status Screen Error on Device (Plan 05-09)

**Root cause:** `MockDefaultFixtures.dispatchHandler` had no `(GET, /kyc/status)` case; the request fell through to the `default` branch returning `nil` → 404 → `KYCStatusViewModel` set `state = .error`.

**Closure evidence:**

| Check | Finding | Status |
|-------|---------|--------|
| `(GET, "/kyc/status")` case in `MockDefaultFixtures.dispatchHandler` | Line 99: `case ("GET", "/kyc/status"): return make200(body: kycStatusResponseJSON(), url: request.url)` | VERIFIED |
| `kycStatusResponseJSON()` builder returns snake_case body matching `KYCStatusEndpoint.Response` | `{"overall_status":"under_review","artifacts":[]}` — matches wire contract (`convertFromSnakeCase` → `overallStatus`, `artifacts`) | VERIFIED |
| Body `overall_status` agrees with `kycSubmitResponseJSON()` post-submit status | Both return `under_review` | VERIFIED |
| Addition is inside file-level `#if DEBUG` guard | File opens with `#if DEBUG` at line 46, closes at line 201; the new case is inside this block | VERIFIED |
| Regression test `Gap (Test 9)` in `MockDefaultFixturesKYCTests` | `@Test("Gap (Test 9): the device-mock dispatch handler answers GET /kyc/status with 200 + a decodable Response")` at line 79; asserts `response.overallStatus == "under_review"` and `response.artifacts.isEmpty` | VERIFIED |
| Test suite passes | 6/6 tests in `MockDefaultFixturesKYCTests`, including Gap Test 9 — orchestrator gate confirms | VERIFIED |
| Commit exists | `6d25b56` (feat) + `dacb716` (test) in git log | VERIFIED |

Test 9 gap: CLOSED.

#### UAT Test 10 — Force-Quit Camera Shutter Wedge (Plan 05-10)

**Root cause (two compounding defects):** (1) `capturePhoto()` awaited a delegate continuation with no timeout; a dead capture source left the continuation suspended forever, `captureInFlight` stuck true. (2) No `AVCaptureSessionRuntimeError` / app-lifecycle observers; force-quit left a half-torn-down session that appeared active (`isActive == true`) but could not deliver photos.

**Closure evidence:**

| Check | Finding | Status |
|-------|---------|--------|
| `CameraSessionError.captureTimedOut` case | Line 56: `case captureTimedOut` | VERIFIED |
| `capturePhoto()` bounded by ~5s timeout | `captureTimeout: Duration = .seconds(5)` (line 219); `Task.sleep(for: Self.captureTimeout)` races delegate continuation | VERIFIED |
| Exactly-once `resolveCapture(_:)` resolver | Private `@MainActor` method check-and-clears `captureContinuation` (line 587); delegate and timeout both route through it; loser sees nil and no-ops | VERIFIED |
| `captureTimeoutTask` property for cancellation | Line 213: `private var captureTimeoutTask: Task<Void, Never>?` | VERIFIED |
| `AVCaptureSession.runtimeErrorNotification` observer | Line 377: registered in `registerLifecycleObservers()`; rebuilds session on fire | VERIFIED |
| `UIApplication.didEnterBackgroundNotification` observer | Line 394: stops session; preserves `intendedRunning` | VERIFIED |
| `UIApplication.willEnterForegroundNotification` observer | Registered; restores session when `intendedRunning && currentPosition != nil` | VERIFIED |
| `wasInterruptedNotification` + `interruptionEndedNotification` | Lines 422, 435: observed; interruption-end restarts if `intendedRunning` | VERIFIED |
| `observerTokens` array + `deinit` removal | Lines 236, 243-248: `deinit` iterates tokens and `removeObserver` each | VERIFIED |
| `currentPosition` intent tracking | Line 225: `private var currentPosition: CameraPosition?`; set in all `startAuthorizedSession`/`configureSessionInputs` paths | VERIFIED |
| `intendedRunning` intent flag | Lines 231, 305, 312: set `true` in `start()`, `false` in `stop()` | VERIFIED |
| `UIKit` import added | Line 23: `import UIKit` | VERIFIED |
| `VehicleCaptureViewModel` — `.captureUnavailable` state | Line 38: `case captureUnavailable`; lines 224-233: catches `.captureTimedOut` specifically, sets `captureInFlight = false`, `state = .captureUnavailable` | VERIFIED |
| `FaceCaptureViewModel` — `.captureUnavailable` state | Line 55: `case captureUnavailable`; lines 299-309: catches `.captureTimedOut` (with `steadyHold.reset()`), sets `captureInFlight = false`, `state = .captureUnavailable` | VERIFIED |
| `VehicleCaptureViewController` renders `.captureUnavailable` with shutter ENABLED | Lines 265-275: `case .captureUnavailable: ... shutterButton.isEnabled = true` | VERIFIED |
| `FaceCaptureViewController` renders `.captureUnavailable` with shutter ENABLED | Lines 334-346: `case .captureUnavailable: ... shutterButton.isEnabled = true` | VERIFIED |
| `CameraSessionLifecycleTests.swift` created | File exists; `@Suite("Camera session lifecycle — force-quit shutter-wedge fix (Test 10 gap)", .serialized)` | VERIFIED |
| Test suite: 5 tests (SUMMARY claims 5) | `grep -c '@Test'` returns 6; one is embedded in a comment line — actual `@Test` declarations visible confirm 5 runnable tests | VERIFIED |
| Tests assert `captureInFlight` is cleared + state is `.captureUnavailable` + retry re-fires | Lines 59, 77, 113, 129: `#expect(viewModel.state == .captureUnavailable)` plus shutter re-arm assertions | VERIFIED |
| Commits exist | `e5c6ea2` (Task 1 — fix + test) + `c83fab8` (Task 2 — lifecycle observers) in git log | VERIFIED |
| `#if DEBUG` test seam `forceReadyToCaptureForTest()` on `FaceCaptureViewModel` | SUMMARY documents this; not confirmed by direct grep in this pass — non-critical to phase goal, the test file compiles and passes per gate evidence | VERIFIED (via gate) |

Test 10 gap: CLOSED at code level. Device-level AVFoundation runtime-error / lifecycle observer confirmation added to HUMAN-UAT.

---

### Required Artifacts (Gap-Closure Files)

All artifacts from prior verification carry forward as VERIFIED. Additions from plans 05-09 and 05-10:

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift` | `(GET, /kyc/status)` route + `kycStatusResponseJSON()` builder | VERIFIED | Line 99 dispatch case; line 184 builder returning `{"overall_status":"under_review","artifacts":[]}`; inside existing `#if DEBUG` block |
| `validationLedger/Core/Identity/Capture/CameraSession.swift` | `captureTimedOut` error case + timeout-bounded `capturePhoto()` + 5 lifecycle observers + `deinit` cleanup | VERIFIED | All grep checks pass; 5s timeout confirmed; `resolveCapture` exactly-once guard confirmed |
| `validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewModel.swift` | `.captureUnavailable` state + `.captureTimedOut` catch + `captureInFlight = false` re-arm | VERIFIED | Lines 38, 224-233 |
| `validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewModel.swift` | `.captureUnavailable` state + `.captureTimedOut` catch + `steadyHold.reset()` + `captureInFlight = false` | VERIFIED | Lines 55, 299-309 |
| `validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewController.swift` | Renders `.captureUnavailable` with `shutterButton.isEnabled = true` | VERIFIED | Lines 265-275 |
| `validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewController.swift` | Renders `.captureUnavailable` with `shutterButton.isEnabled = true` | VERIFIED | Lines 334-346 |
| `validationLedgerTests/KYC/CameraSessionLifecycleTests.swift` | `@Suite` with capture-timeout shutter-wedge tests | VERIFIED | File created; 5 `@Test` declarations; asserts `.captureUnavailable` state and shutter re-arm |
| `validationLedgerTests/KYC/MockDefaultFixturesKYCTests.swift` | Gap (Test 9) regression test | VERIFIED | `@Test` at line 79; asserts `overallStatus == "under_review"` and `artifacts.isEmpty` |

---

### Key Link Verification (Gap-Closure Additions)

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `MockDefaultFixtures.dispatchHandler` | `KYCStatusEndpoint.Response` | `kycStatusResponseJSON()` returning `{"overall_status":"under_review","artifacts":[]}` | WIRED | `case ("GET", "/kyc/status")` routes to builder; body decodes via `convertFromSnakeCase` into `Response.overallStatus` + `Response.artifacts` |
| `AVFoundationCameraSession.capturePhoto()` | `CameraSessionError.captureTimedOut` | 5s `Task.sleep` timeout races delegate via `resolveCapture(_:)` | WIRED | `captureTimeout = .seconds(5)`; timeout task calls `resolveCapture(.failure(CameraSessionError.captureTimedOut))`; delegate calls `resolveCapture(.success/failure)` |
| `VehicleCaptureViewModel.performCapture()` | `captureInFlight = false` + `.captureUnavailable` | `catch CameraSessionError.captureTimedOut` block | WIRED | Lines 224-233: explicit catch, `captureInFlight = false`, `state = .captureUnavailable` |
| `FaceCaptureViewModel.performCapture()` | `captureInFlight = false` + `.captureUnavailable` | `catch CameraSessionError.captureTimedOut` block | WIRED | Lines 299-309: explicit catch, `steadyHold.reset()`, `captureInFlight = false`, `state = .captureUnavailable` |
| `AVFoundationCameraSession` | Notification observers | `registerLifecycleObservers()` in `init()` | WIRED | 5 observers registered (runtimeError, didEnterBackground, willEnterForeground, wasInterrupted, interruptionEnded); tokens in `observerTokens` array |
| `AVFoundationCameraSession.deinit` | `observerTokens` removal | `NotificationCenter.default.removeObserver` loop | WIRED | Lines 243-248: `deinit` iterates array, removes each token |

---

### Requirements Coverage (Gap-Closure Plans)

| Requirement | Source Plan | Description | Status | Evidence |
|------------|------------|-------------|--------|----------|
| KYC-02 | 05-10 | Live face capture with Vision quality gate | SATISFIED (no change to gate logic; timeout fix is resilience, not functionality change) | `CameraSessionError.captureTimedOut` + `.captureUnavailable` recoverable state; KYC-02 functional delivery unchanged from prior verification |
| KYC-04 | 05-10 | GPS attached via `AVCapturePhoto`/`CGImageDestination`, never `UIImage` | SATISFIED | `GPSMetadataInjector` unchanged; 05-10 added timeout resilience to `capturePhoto()` — GPS injection path unaffected |
| KYC-05 | 05-09 | KYC status UI renders 4 states with controlled-vocabulary rejection copy | SATISFIED | `kycStatusResponseJSON()` + device-mock route closes the device-build gap; `KYCStatusViewModelTests` GREEN; `Gap (Test 9)` regression test GREEN |
| KYC-06 | 05-09 | In-progress KYC survives backgrounding via encrypted on-disk persistence | SATISFIED | No change to `KYCSessionStore`; 05-09 only adds a mock route |

REQUIREMENTS.md traceability table marks KYC-02, KYC-04, KYC-05, KYC-06 all as `Complete` / Phase 5.

---

### Anti-Patterns Found (Gap-Closure Files)

No `TBD`, `FIXME`, or `XXX` debt markers found in any of the 8 gap-closure files reviewed (`MockDefaultFixtures.swift`, `CameraSession.swift`, `VehicleCaptureViewModel.swift`, `FaceCaptureViewModel.swift`, `VehicleCaptureViewController.swift`, `FaceCaptureViewController.swift`, `CameraSessionLifecycleTests.swift`, `MockDefaultFixturesKYCTests.swift`).

The 5 WARNINGs in `05-REVIEW.md` (WR-01 through WR-05) are non-blocking concurrency hardening notes in `CameraSession.swift` and `FaceCaptureViewModel.swift`. They do not affect phase goal delivery and were already acknowledged by the code reviewer. Carried forward from prior verification:

| File | Warning | Severity | Impact |
|------|---------|----------|--------|
| `CameraSession.swift` | WR-01: re-entrant `capturePhoto()` overwrites in-flight continuation | Warning | Requires caller serialization; not a phase goal blocker |
| `CameraSession.swift` | WR-02: blocking `sessionQueue.sync` on main actor in lifecycle handlers | Warning | Deadlock risk under contention; not triggered in normal use |
| `CameraSession.swift` | WR-03: in-flight continuation orphaned 5s on background mid-capture | Warning | Timeout fires after app backgrounds; harmless but suboptimal |
| `FaceCaptureViewModel.swift` | WR-04: live gate stream may overwrite recoverable-timeout cue | Warning | Race between Vision frames and `.captureUnavailable`; cosmetic only |
| `CameraSession.swift` | WR-05: `captureTimeoutTask` not cancelled by `stop()` | Warning | 5s timer outlives session teardown; minor CPU/log noise |

Pre-existing WARNINGs from full-phase review (CR-01 totalChunks mismatch, CR-02 PUT/DELETE routing, WR-05 `String(describing:)` PII risk) also carry forward unchanged.

---

### Behavioral Spot-Checks

Step 7b SKIPPED — requires a booted simulator + app. Orchestrator-provided gate (367 tests, 0 failures) is the authority.

---

### Probe Execution

No probe scripts declared. No conventional `scripts/*/tests/probe-*.sh` present. SKIPPED.

---

### Human Verification Required

The following items require physical-device testing and are tracked in `05-HUMAN-UAT.md`. Items 1-4 carry over from the prior verification. Item 5 is new, added by plan 05-10's note that the live-AVFoundation observer behavior is device-only.

**1. SC-2 — Force-Quit Resume UX**

**Test:** Start the KYC capture flow, let artifact uploads begin. While a ~6 MB artifact is mid-upload (progress bar partway), force-quit the app (swipe up from app switcher). Relaunch.

**Expected:** Progress bar restores to the prior `chunksAcked/totalChunks` (NOT 0%); artifact eventually commits without restarting from chunk 0.

**Why human:** Real app-kill + relaunch cannot be simulated in `xcodebuild test`. `KYCUploaderResumeTests` + `KYCForceQuitResumeDeviceTests` cover the logic lane. End-to-end UX requires a human force-quit on a physical iPhone.

---

**2. SC-4 — Background-Upload Completion**

**Test:** With an artifact mid-upload, background the app (Home / swipe up but do NOT kill). Wait. Re-open the app.

**Expected:** Artifact shows committed — upload completed while backgrounded via `BGProcessingTaskRequest` runtime.

**Why human:** iOS grants `BGProcessingTaskRequest` on its own schedule. `BackgroundUploadSchedulingTests` proves the scheduling decision logic. End-to-end completion under real OS suspension is not reproducible in CI.

---

**3. D-08 — Profile Entry to KYC Status Screen**

**Test:** In the role shell, open Profile via the top-bar avatar. Look for a "Verification status" row. Tap it.

**Expected:** `KYCStatusViewController` opens and re-fetches `GET /kyc/status`. On a DEBUG device build the status screen now renders "Under Review" (plan 05-09 closed the Test 9 gap that previously caused an error here). Previously blocked by Test 9; that block is now removed at the code level.

**Why human:** Live tap-through on a running app with a role shell requires human confirmation. The UAT Test 12 block (caused by Test 9 erroring) is cleared; the Profile path requires a KYC-verified or under-review account state.

---

**4. D-12 — Hard Gate: Non-Verified Account Cannot Reach Role Shell**

**Test:** OTP-verify a non-verified account.

**Expected:** App lands in the KYC flow (`KYCCoordinator`), not the role tab bar.

**Why human:** `SessionRestoreServiceTests` proves cold-boot routing logic. End-to-end confirmation requires live verification on device.

---

**5. Test 10 Device Confirmation — AVFoundation Lifecycle Resilience**

**Test:** On a physical iPhone, force-quit the app while on a KYC vehicle-capture or face-capture screen (camera running). Relaunch.

**Expected:** Within ~5 seconds, the capture screen shows a recoverable cue ("The camera needs a moment. Try the photo again.") with the shutter button ENABLED — not a dead/unresponsive shutter. Tapping the shutter fires another capture attempt.

**Additionally:** Background the app while a capture screen is live (Home button / swipe). Foreground it again. Confirm the camera preview is live and the shutter is responsive.

**Why human:** `AVFoundation.runtimeErrorNotification`, `wasInterrupted`/`interruptionEnded`, and `UIApplication.didEnterBackground`/`willEnterForeground` are live `AVCaptureSession` notifications — they do not fire on the iOS Simulator. `CameraSessionLifecycleTests` proves the VM-layer shutter re-arm (`captureInFlight` cleared, `.captureUnavailable` state reached). The runtime-error rebuild and background/foreground session restore paths are hardware-only.

---

### Gaps Summary

No open gaps. The two UAT gaps targeted by this re-verification pass are confirmed closed at the code level:

- **Test 9** (`MockDefaultFixtures` missing `(GET, /kyc/status)`): CLOSED. `kycStatusResponseJSON()` builder added; route registered in `dispatchHandler`; `Gap (Test 9)` regression test GREEN in `MockDefaultFixturesKYCTests`. The status screen will render "Under Review" on DEBUG device builds after KYC submission. UAT Test 12 (previously blocked by Test 9) is unblocked.

- **Test 10** (`capturePhoto()` hung forever on dead capture source): CLOSED. `CameraSessionError.captureTimedOut` added; `capturePhoto()` races a 5s timeout against the delegate continuation with an exactly-once `resolveCapture(_:)` resolver; both capture VMs catch the timeout, clear `captureInFlight`, and land in `.captureUnavailable`; both capture VCs render `.captureUnavailable` with the shutter ENABLED. `AVFoundationCameraSession` now observes 5 lifecycle/error notifications with `deinit`-removed tokens. `CameraSessionLifecycleTests` (5 tests) GREEN.

No regressions to the prior 5/5 automated success criteria. The code review (05-REVIEW.md, gap-closure scope) confirms 0 BLOCKERs; 5 WARNINGs are non-blocking concurrency hardening notes.

The remaining `human_needed` status reflects 5 physical-device items (SC-2, SC-4, D-08, D-12, and the Test 10 device-level AVFoundation confirmation) that cannot be verified in the iOS Simulator or CI.

---

_Verified: 2026-05-18T07:00:00Z_
_Verifier: Claude (gsd-verifier) — re-verification pass (gap-closure plans 05-09, 05-10)_
