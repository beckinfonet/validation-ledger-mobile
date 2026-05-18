---
phase: 05-kyc-capture-upload-pipeline
reviewed: 2026-05-17T00:00:00Z
depth: standard
review_scope: gaps-only
files_reviewed: 8
files_reviewed_list:
  - validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift
  - validationLedger/Core/Identity/Capture/CameraSession.swift
  - validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewModel.swift
  - validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewModel.swift
  - validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewController.swift
  - validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewController.swift
  - validationLedgerTests/KYC/MockDefaultFixturesKYCTests.swift
  - validationLedgerTests/KYC/CameraSessionLifecycleTests.swift
findings:
  critical: 0
  warning: 5
  info: 4
  total: 9
status: issues_found
---

# Phase 5: Code Review Report (gaps-only)

**Reviewed:** 2026-05-17T00:00:00Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

This is a `--gaps-only` review covering only the 8 files changed by gap-closure
plans 05-09 (KYC status device-mock route) and 05-10 (camera force-quit
recovery). Diff base is `263ea06` — the commit immediately before gap closure.
This report supersedes the prior full-Phase-5 review (which is preserved in git
history); the 9 findings below are scoped strictly to the gap-closure diff.

The `MockDefaultFixtures` change (the new `(GET, /kyc/status)` route) is
correctly contained inside `#if DEBUG`. The route, the `kycStatusResponseJSON()`
body, and the `MockDefaultFixturesKYCTests` coverage are all sound: the JSON
shape (`overall_status` + empty `artifacts`) matches `KYCStatusEndpoint.Response`
under `.convertFromSnakeCase`, the empty `artifacts` array decodes cleanly into
`[Artifact]`, and there is no Release-path leakage — the file compiles out
entirely in Release. No security concern in the gap-closure diff.

The substantive concerns are all in `CameraSession.swift`'s new force-quit
recovery machinery. None rise to BLOCKER — they do not corrupt data, leak PII,
or crash on the happy path — but several are real correctness/robustness gaps:
the new `captureTimeoutTask` has no protection against a re-entrant
`capturePhoto()` leaking a continuation, the lifecycle recovery handlers issue a
blocking `sessionQueue.sync` from the main actor, the in-flight capture
continuation is silently orphaned (for a full 5s) when the app backgrounds
mid-capture, and the face VM's still-live gate stream can immediately overwrite
the recoverable-timeout cue.

No structural pre-pass (`<structural_findings>`) was provided.

## Warnings

### WR-01: `capturePhoto()` overwrites an in-flight continuation/timeout on a re-entrant call

**File:** `validationLedger/Core/Identity/Capture/CameraSession.swift:549-577`
**Issue:** `capturePhoto()` unconditionally assigns `self.captureContinuation`
and `self.captureTimeoutTask` at the start of the
`withCheckedThrowingContinuation` closure. There is no guard against a second
`capturePhoto()` arriving while a prior capture is still in flight. If a second
call lands first, it overwrites `captureContinuation` — the first continuation
is **leaked** (never resumed), which traps fatally under
`withCheckedThrowingContinuation`'s leak detector — and overwrites
`captureTimeoutTask` without cancelling the prior task, so the orphaned timeout
survives and later fires `resolveCapture` against the *second* capture's
continuation.

The two capture VMs guard re-entry with `captureInFlight`, so a single VM does
not re-enter today. But `AVFoundationCameraSession` is a standalone object with
no internal guard, and the new force-quit recovery paths
(`handleWillEnterForeground`, `handleInterruptionEnded`) now restart the session
asynchronously — a foreground restart racing a still-pending capture is exactly
the kind of overlap the new lifecycle code introduces. The class should defend
its own invariant rather than trust every caller.

**Fix:** Guard re-entry inside `capturePhoto()` before installing the
continuation:
```swift
public func capturePhoto() async throws -> AVCapturePhoto {
    guard Self.isCameraAvailable else { throw CameraSessionError.cameraUnavailable }
    guard captureContinuation == nil else {
        throw CameraSessionError.captureFailed(
            NSError(domain: "CameraSession", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "capture already in flight"]))
    }
    // ... existing body
}
```

### WR-02: Lifecycle recovery handlers run a blocking `sessionQueue.sync` on the main actor

**File:** `validationLedger/Core/Identity/Capture/CameraSession.swift:447-491`
(`handleRuntimeError`, `handleWillEnterForeground`)
**Issue:** Both handlers are `@MainActor` (hopped to via `Task { @MainActor }`)
and call `configureSessionInputs(position:)`, which does `sessionQueue.sync { ... }`
(line 510). If a runtime-error or foreground notification fires while
`startSession()`'s async block is mid-`session.startRunning()` on `sessionQueue`,
the `sync` call **blocks the main thread** until `startRunning()` returns. The
file's own comments (lines 196-202, 316-318) repeatedly stress that
`startRunning()` is blocking and "MUST NOT run on the main thread" — yet these
new recovery paths can stall the main thread on exactly that call. A force-quit
recovery (the precise scenario this code was added for) is the most likely time
a runtime error and a session start overlap, so the new code is most exposed in
its target scenario.

**Fix:** Make the recovery handlers do their session work off the main actor —
dispatch the `configureSessionInputs` + `startSession` sequence onto
`sessionQueue.async` rather than calling the `sync`-bodied
`configureSessionInputs` from the main actor, or split `configureSessionInputs`
into a main-actor entry that hops to `sessionQueue.async` internally.

### WR-03: In-flight capture continuation is orphaned for 5s when the app backgrounds mid-capture

**File:** `validationLedger/Core/Identity/Capture/CameraSession.swift:469-472`
(`handleDidEnterBackground`) and `549-577` (`capturePhoto`)
**Issue:** If the user backgrounds the app while a `capturePhoto()` await is in
flight, `handleDidEnterBackground` calls `stopSession()`, which tears the
session down. The `AVCapturePhotoCaptureDelegate` callback will then never fire.
The capture is *eventually* resolved by the 5-second `captureTimeoutTask`, so it
does not leak — but the user is left on a `.capturing` screen with a disabled
shutter for a full 5 seconds after returning to the foreground, with no
indication anything is wrong. This is the exact dead-shutter window the Test 10
gap fix set out to eliminate; the new background-stop observer reintroduces a
shorter version of it.

**Fix:** In `handleDidEnterBackground`, if a capture is in flight, resolve it
immediately as recoverable rather than waiting out the timeout:
```swift
private func handleDidEnterBackground() {
    if captureContinuation != nil {
        resolveCapture(.failure(CameraSessionError.captureTimedOut))
    }
    stopSession()
}
```

### WR-04: Face VM's still-live gate stream overwrites the recoverable-timeout cue

**File:** `validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewModel.swift:296-310`
(`performCapture` timeout branch) and `242-263` (`handle(signal:)`)
**Issue:** On a `captureTimedOut` error, `performCapture()` resets
`captureInFlight`, resets `steadyHold`, and sets `.captureUnavailable` — but it
does **not** clear `cameraSession.videoFrameHandler`, and the gate-signal `Task`
started in `observeGateSignals()` keeps running. `handle(signal:)` only bails
when `captureInFlight` is true or the state is `.captured` — neither holds in
`.captureUnavailable`. So the still-live gate stream can immediately drive the
state straight back to `.adjusting`/`.readyToCapture` on the very next frame,
overwriting the "The camera needs a moment. Try the photo again."
(`kyc.error.camera_recoverable`) cue the Test 10 fix intends to show. The
recoverable-state messaging is racy in the face path. (The vehicle VM has no
gate stream and is unaffected.)

**Fix:** Have `handle(signal:)` also ignore signals while
`state == .captureUnavailable` (mirroring the existing `.captured` guard), so
the recoverable cue is stable until the user retries:
```swift
private func handle(signal: FaceGateSignal) {
    guard !captureInFlight else { return }
    if case .captured = state { return }
    if case .captureUnavailable = state { return }   // hold the recoverable cue
    // ...
}
```

### WR-05: `captureTimeoutTask` is not cancelled by `stop()`, so a torn-down screen still runs a 5s timer

**File:** `validationLedger/Core/Identity/Capture/CameraSession.swift:309-314`
(`stop`), `587-593` (`resolveCapture`)
**Issue:** `stop()` (called from each VC's `viewWillDisappear`) clears
`intendedRunning` and stops the session, but does nothing to a capture currently
in flight. If the user navigates away from the capture screen while
`capturePhoto()` is awaiting, the `captureTimeoutTask` keeps running for up to 5
seconds after the screen is gone. The task is `[weak self]`-captured and routes
through `resolveCapture`, so it does not leak or crash — the awaiting
`performCapture()` continuation resumes correctly with `.captureTimedOut`. But a
5-second background timer outliving its screen is wasteful and makes the capture
lifecycle harder to reason about; a VC torn down and a new one constructed
within 5s would have two timers and continuations from two `AVFoundationCameraSession`
instances racing (only mitigated because each VC gets its own session).

**Fix:** Cancel any in-flight capture on `stop()` — resolve the continuation as
`.captureTimedOut` (or a dedicated `.cancelled`) and cancel the timeout task:
```swift
public func stop() {
    intendedRunning = false
    if captureContinuation != nil {
        resolveCapture(.failure(CameraSessionError.captureTimedOut))
    }
    stopSession()
}
```

## Info

### IN-01: Round-4 diagnostic logging on the camera path has outlived its investigation

**File:** `validationLedger/Core/Identity/Capture/CameraSession.swift` (throughout —
e.g. 268, 280, 296, 327, 329, 448, 470, 481, 519, 526, 543, 545, 571),
`VehicleCaptureViewController.swift:177,190,206,231-244`,
`FaceCaptureViewController.swift:217,230,249,282-295`
**Issue:** The `kycCameraLog` channel emits a large volume of `info`-level lines
per capture-screen appearance (`viewDidLoad`, `viewWillAppear`, every
`viewDidLayoutSubviews` pass, the 2s `final_state` snapshot, and every session
lifecycle transition). These were added for the resolved
`front-camera-preview-black` debug session and the round-4 diagnostic. The lines
correctly carry no PII (verified — only AVFoundation/layout facts, all
`privacy: .public` values are booleans/sizes/enum names). This is not a
correctness defect, but the round-4 `scheduleFinalStateSnapshot` and the
per-layout-pass logging are debug instrumentation that has served its purpose
now that the black-preview bug is resolved.
**Fix:** Gate the heaviest diagnostics behind `#if DEBUG`, or remove
`scheduleFinalStateSnapshot` and the per-layout-pass log lines, leaving only the
session-lifecycle transitions (which remain genuinely useful for force-quit
diagnosis).

### IN-02: `scheduleFinalStateSnapshot` uses a magic `2`-second literal

**File:** `validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewController.swift:227`,
`FaceCaptureViewController.swift:278`
**Issue:** `DispatchQueue.main.asyncAfter(deadline: .now() + 2)` hard-codes the
settle delay as a bare `2`. If this diagnostic is retained (see IN-01), the delay
should be a named constant; if it is removed, this is moot.
**Fix:** Extract a `private static let finalStateSnapshotDelay: TimeInterval = 2`
or remove the snapshot per IN-01.

### IN-03: `.captureUnavailable` UI-handling block and the camera-unavailable string are duplicated

**File:** `validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewController.swift:265-275`
and `FaceCaptureViewController.swift:334-346`; string literal
`kyc.error.camera_unavailable` repeated in `VehicleCaptureViewModel.swift:174,242,254`
and `FaceCaptureViewModel.swift:170,316,330`
**Issue:** The `.captureUnavailable` case body (the `kyc.error.camera_recoverable`
`NSLocalizedString` with an identical `value`/`comment` plus
`shutterButton.isEnabled = true`) is duplicated verbatim across the two VCs, and
the `kyc.error.camera_unavailable` localized string is repeated several times
across the two VMs. Minor maintainability cost — a copy edit must be made in
multiple places.
**Fix:** Extract the shared KYC capture-error copy into a small helper (e.g. a
`KYCCaptureCopy` enum) referenced by both VMs/VCs. Not blocking.

### IN-04: `make200` force-unwraps `HTTPURLResponse.init` (pre-existing, in scope only by file)

**File:** `validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift:190-198`
**Issue:** `HTTPURLResponse(url:statusCode:httpVersion:headerFields:)!` is
force-unwrapped. This is **not** introduced by the gap-closure diff (the new
`kycStatusResponseJSON()` route reuses the existing `make200` builder) and is
`#if DEBUG`-only test-fixture code where the inputs are always valid, so the
unwrap cannot realistically fail. Flagged only for completeness because the file
is in scope.
**Fix:** No action required for this phase. If touched later, a `guard let ...
else { ... }` would be cleaner than the force-unwrap.

---

_Reviewed: 2026-05-17T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (gaps-only — plans 05-09, 05-10)_
