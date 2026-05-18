---
status: diagnosed
trigger: "After force-quitting the app mid-upload and relaunching, the KYC session survives but the app lands on a camera-open capture screen whose shutter button is unresponsive — the capture flow is stuck."
created: 2026-05-17T00:00:00Z
updated: 2026-05-17T00:00:00Z
---

## Current Focus

hypothesis: "On a force-quit-and-relaunch, the unresponsive shutter is the visible symptom of `AVFoundationCameraSession.capturePhoto()`'s `withCheckedThrowingContinuation` hanging forever. After an ungraceful force-quit (the prior process never `stopRunning()`'d its `AVCaptureSession` — no `viewWillDisappear`/`sceneDidEnterBackground`/`deinit` runs on a force-quit), the relaunched process gets an `AVCaptureSession` whose `mediaserverd` capture-source connection is dead (`FigCaptureSourceRemote err=-17281`). `photoOutput.capturePhoto(with:delegate:)` is issued but `photoOutput(_:didFinishProcessingPhoto:error:)` NEVER fires, so the stored `captureContinuation` is never resumed. There is no timeout and no `AVCaptureSessionRuntimeError`/`AVCaptureSessionWasInterrupted` recovery anywhere in the app. The VM is therefore pinned in `.capturing` (shutter `isEnabled=false`) with `captureInFlight=true` forever — no error state, no recovery."
test: "Confirmed by code inspection — see Evidence."
expecting: "Confirmed."
next_action: "Write ROOT CAUSE FOUND diagnosis (find_root_cause_only mode)."

## Symptoms

expected: While a ~6MB artifact is mid-upload (progress bar partway), force-quitting the app and relaunching resumes the upload from the prior committed chunk count (NOT 0%), the artifact eventually commits, and the user can keep capturing / advance the KYC flow normally. (Test 10, SC-2.)
actual: The KYC session DOES persist across the force-quit, but on relaunch the app lands on a camera-open capture screen — the vehicle capture view controller — that is stuck. Pressing the shutter button does nothing. The capture flow cannot be advanced.
errors: "FigCaptureSourceRemote err=-17281 (capture source remote connection died) during the force-quit + relaunch cycle. AVCaptureSession appears not to re-establish a working capture connection after relaunch even though viewDidLayoutSubviews logs report connectionActive=true."
reproduction: "Test 10 in .planning/phases/05-kyc-capture-upload-pipeline/05-UAT.md — start a ~6MB artifact upload, force-quit the app mid-upload, relaunch."
started: "Phase 05 UAT (2026-05-17)."

## Eliminated

## Evidence

- timestamp: 2026-05-17T00:00:00Z
  checked: "KYCCoordinator.init + SceneDelegate.scene(_:willConnectTo:) — the relaunch routing."
  found: "On cold boot with a persisted non-verified KYC session, `SessionRestoreProbe.probe` returns `.needsKYC(role)` → `presentRoot(.kyc(role))` → a FRESH `KYCCoordinator` is built whose `rootViewController` is a `UINavigationController(rootViewController: KYCStartViewController())`. There is NO mid-flow resume — the app always re-enters the KYC flow at the 'Let's verify your identity' start screen. The user must manually re-walk Get started → face → DL → DL-back → truck → trailer → plate. Each capture step builds its OWN fresh `AVFoundationCameraSession()` (KYCCoordinator.pushFaceCapture / pushDLBack / makeVehicleCapture all call `AVFoundationCameraSession()` directly)."
  implication: "The app does not 'land directly on' a camera VC — the user re-navigates into one. Test 3 (face capture) PASSED in the same UAT run, so the first camera VC after relaunch worked; the stuck VC is a later vehicle-capture screen. The bug is not in routing — it is in the camera session itself once a capture is attempted."

- timestamp: 2026-05-17T00:00:00Z
  checked: "AVFoundationCameraSession.capturePhoto() — CameraSession.swift:322-331 and the AVCapturePhotoCaptureDelegate callback at :337-353."
  found: "`capturePhoto()` does `try await withCheckedThrowingContinuation { continuation in self.captureContinuation = continuation; photoOutput.capturePhoto(with: settings, delegate: self) }`. The continuation is resumed ONLY inside `photoOutput(_:didFinishProcessingPhoto:error:)`. If AVFoundation never invokes that delegate callback — which is exactly what happens when the capture source connection is dead — the continuation is NEVER resumed and the `await` hangs FOREVER. There is no `withTimeout`, no `Task.sleep` race, no fallback path (grep confirmed: zero timeout primitives in CameraSession.swift / VehicleCaptureViewModel.swift / FaceCaptureViewModel.swift)."
  implication: "`capturePhoto()` is an unbounded await with a single resume site. A dead capture source = a permanent hang. This is the mechanism that strands the shutter."

- timestamp: 2026-05-17T00:00:00Z
  checked: "VehicleCaptureViewModel.capture() / performCapture() (:194-255) and VehicleCaptureViewController.handle(state:) (:250-271)."
  found: "`capture()` guards `!captureInFlight`, sets `captureInFlight = true`, sets `state = .capturing`, then `Task { await performCapture() }`. `handle(.capturing)` sets `shutterButton.isEnabled = false`. `performCapture()` first awaits `geoContext.freshLocation()` (returns or throws — not a permanent hang), THEN `await cameraSession.capturePhoto()`. When `capturePhoto()` hangs, `performCapture()` never returns: `captureInFlight` stays `true`, `state` stays `.capturing`, `shutterButton.isEnabled` stays `false`. The shutter `@objc shutterTapped` → `viewModel.capture()` is then a no-op because `captureInFlight` is `true`. No error state is ever set, no cue text, no timeout — the screen is permanently stuck with a dead shutter, exactly as reported."
  implication: "The unresponsive shutter is a downstream symptom: the VM is wedged in `.capturing` because the capture continuation never resumes. The same wedge applies to FaceCaptureViewModel (identical `capturePhoto()` await + `captureInFlight` guard)."

- timestamp: 2026-05-17T00:00:00Z
  checked: "AVCaptureSession lifecycle vs app lifecycle — grep for AVCaptureSessionRuntimeError / AVCaptureSessionWasInterrupted / AVCaptureSessionInterruptionEnded / didEnterBackground / willEnterForeground observers across all of validationLedger."
  found: "ZERO `AVCaptureSession` notification observers anywhere in the app. `AVFoundationCameraSession` has NO `AVCaptureSessionRuntimeErrorNotification` handler (the notification AVFoundation posts when the running session fails — e.g. a dead capture source) and NO `AVCaptureSessionWasInterrupted`/`InterruptionEnded` handling. Session start/stop is wired PURELY to view lifecycle: `VehicleCaptureViewController.viewWillAppear → viewModel.start()`, `viewWillDisappear → viewModel.stop()`. There is NO app-lifecycle integration — nothing reacts to background/foreground or to a runtime error."
  implication: "Even if the session enters a broken state, nothing detects it and nothing rebuilds it. A capture issued against a session that has silently lost its source produces no delegate callback and no error notification the app listens for — so the app has no signal to recover from. This is the missing-recovery half of the root cause."

- timestamp: 2026-05-17T00:00:00Z
  checked: "Force-quit teardown path — what runs (and what does NOT) when the user force-quits from the app switcher."
  found: "A force-quit (swipe-up-kill) terminates the process ABRUPTLY. iOS does NOT call `viewWillDisappear`, `viewDidDisappear`, `sceneDidEnterBackground`, `applicationWillTerminate`, or any `deinit` on a force-quit. Therefore `viewModel.stop()` → `cameraSession.stop()` → `session.stopRunning()` is NEVER reached, and the `AVCaptureSession` / `AVCapturePhotoOutput` / `AVCaptureVideoDataOutput` are never released. The OS reclaims the camera hardware, but the app's prior `mediaserverd` (`FigCaptureSource`) XPC connection is torn down ungracefully. On the NEXT launch the console shows `FigCaptureSourceRemote err=-17281` ('capture source remote connection died'). Prior debug session `front-camera-preview-black` (round 4) found `err=-17281` BENIGN on a clean cold launch — but that conclusion was reached for a normal launch, NOT a launch following an ungraceful force-quit mid-capture-session. In the force-quit case the relaunched session can fail to re-establish a working source: the `AVCaptureConnection` object exists and reports `isActive == true` (a stale flag — the connection object is wired) while the underlying source feed is dead, which is precisely the reported contradiction: `viewDidLayoutSubviews` logs `connectionActive=true` yet capture produces nothing."
  implication: "The trigger is the ungraceful force-quit, not the upload. The upload (KYCUploadScheduler) is network-only and never touches the camera — it is a red herring. The force-quit leaves the camera subsystem in a state the relaunched `AVCaptureSession` cannot cleanly reuse; with no `AVCaptureSessionRuntimeError` observer the app cannot see the failure, and with no `capturePhoto()` timeout the first shutter tap hangs the VM forever."

- timestamp: 2026-05-17T00:00:00Z
  checked: "Why face capture (Test 3) passed but the vehicle capture is stuck — and whether `connectionActive=true` contradicts the diagnosis."
  found: "Test 3 passed because that run reached the face screen on a CLEAN session (no preceding force-quit) — or the front-camera source happened to re-establish. The stuck screen is a back-camera vehicle-capture VC reached AFTER the relaunch. The `videoDataOutput`/`photoOutput` connections are created during `configureSessionInputs` and the `AVCaptureConnection.isActive` property reflects the connection OBJECT being attached + enabled — it does NOT prove the `mediaserverd` source is delivering frames. So `connectionActive=true` in `viewDidLayoutSubviews` is fully consistent with a dead source: the connection is wired, the feed is not. The `final_state` diagnostic logs `sessionRunning` but `AVCaptureSession.isRunning` likewise returns `true` once `startRunning()` was called even if the source subsequently dies without a `RuntimeError` observer to catch it."
  implication: "The single observable that WOULD disambiguate (an `AVCaptureSessionRuntimeError` notification, or a `capturePhoto()` that errors/times out) is exactly the observability the app is missing. Adding it is part of the fix direction."

## Resolution

root_cause: |
  Two compounding defects in the `AVCaptureSession` lifecycle, triggered by an
  ungraceful force-quit:

  (1) NO ungraceful-teardown / runtime-error handling. `AVFoundationCameraSession`
  registers ZERO `AVCaptureSession` notification observers — no
  `AVCaptureSessionRuntimeErrorNotification`, no `AVCaptureSessionWasInterrupted`/
  `InterruptionEnded`. Session start/stop is bound purely to VC view lifecycle
  (`viewWillAppear → start()`, `viewWillDisappear → stop()`). A force-quit bypasses
  `viewWillDisappear`/`sceneDidEnterBackground`/`deinit`, so the prior process
  never `stopRunning()`s its session — the `mediaserverd` capture-source XPC
  connection is torn down abruptly (`FigCaptureSourceRemote err=-17281` on the next
  launch). The relaunched `AVCaptureSession` can fail to re-establish a working
  source while still presenting an `AVCaptureConnection` whose `isActive` flag
  reads `true` (the connection object is wired; the feed is dead — this is why the
  logs show `connectionActive=true` on a stuck screen). Nothing in the app
  observes the failure, so nothing rebuilds the session.

  (2) `capturePhoto()` is an UNBOUNDED await with a single resume site.
  `AVFoundationCameraSession.capturePhoto()` (CameraSession.swift:322-331) bridges
  the capture via `withCheckedThrowingContinuation`; the continuation is resumed
  ONLY inside `photoOutput(_:didFinishProcessingPhoto:error:)`. When the capture
  source is dead, AVFoundation never invokes that delegate callback, so the
  continuation is never resumed and the `await` hangs forever. There is no
  timeout. `VehicleCaptureViewModel.capture()` has already set
  `captureInFlight = true` and `state = .capturing` (→ `shutterButton.isEnabled =
  false`) before the hang, and the `!captureInFlight` guard makes every
  subsequent shutter tap a silent no-op. The VM is pinned in `.capturing` with a
  dead shutter, no error state, and no recovery — exactly the reported "camera
  open, shutter does nothing, flow cannot advance". `FaceCaptureViewModel` shares
  the identical `capturePhoto()` await + `captureInFlight` guard, so it is
  vulnerable to the same wedge.

  The mid-upload aspect of Test 10 is a red herring: `KYCUploadScheduler` /
  `KYCUploader` are network-only and never touch the camera. The actual trigger
  is the ungraceful force-quit, which Test 10 happens to perform while a camera
  VC's session is alive.

fix: ""
verification: ""
files_changed: []

suggested_fix_direction: |
  Three coordinated changes (the fix plan is /gsd:plan-phase --gaps scope):
  (1) Bound `capturePhoto()` with a timeout — wrap the
  `withCheckedThrowingContinuation` in a timeout race (or a `Task` + `Task.sleep`
  cancellation) so a dead capture source surfaces as a thrown
  `CameraSessionError.captureFailed`/`.timedOut` instead of an infinite hang;
  resume the stored continuation exactly once. The VM's `.failed` path then shows
  recoverable error copy and re-arms the shutter (`captureInFlight = false`).
  (2) Observe `AVCaptureSessionRuntimeErrorNotification` (and
  `WasInterrupted`/`InterruptionEnded`) in `AVFoundationCameraSession`; on a
  runtime error, tear down and rebuild the session (`configureSessionInputs` +
  `start()`) so a dead source self-heals instead of staying broken.
  (3) Drive session stop/start off the APP lifecycle as well as the view
  lifecycle — at minimum stop the session on `sceneDidEnterBackground` and
  re-`startAuthorizedSession` on foreground for any live capture VC — so the
  session is in a known state across background/relaunch and a force-quit cannot
  strand a half-torn-down session.
  Also re-scope the prior `front-camera-preview-black` conclusion that
  `err=-17281` is "always benign": it is benign on a clean launch but is a real
  signal of a dead source on a launch following an ungraceful force-quit.
