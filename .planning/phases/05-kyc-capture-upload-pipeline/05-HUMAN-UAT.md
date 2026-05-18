# Phase 5 — HUMAN-UAT Checklist

> Physical-device verification items for Phase 5 (KYC Capture + Upload Pipeline)
> that cannot run in the iOS Simulator or in CI. This file is the durable record
> of the plan 05-08 Task 3 `checkpoint:human-verify` gate.
>
> **Phase 5 is complete only once every item below is verified on a physical
> iPhone.** Once approved, run `/gsd:verify-work 5`.

> **Device-UAT automation note (2026-05-18).** The device-UAT automation landed
> via plans 05-11 (the `-KYCTestSeedForUITest` DEBUG launch seam), 05-12 (the four
> device XCUITest files), and 05-13 (wiring `validationLedgerUITests` into the
> `ci-device.yml` device lane). **The manual-UAT burden dropped from 5 items to 2.**
> Four of the five items below are now AUTOMATED as device XCUITests that run on
> the self-hosted device CI lane on every merge to `main`; each is annotated below
> with its covering XCUITest file. **Only items 2 (SC-4) and the deliberate
> runtime-error-injection portion of item 5 (Test-10) remain human-UAT.**

---

## Plan 05-08 Task 3 — `checkpoint:human-verify` (`gate="blocking"`)

**What was built (Tasks 1-2, automated, COMPLETE):**
- D-08 — a role-shell Profile "Verification status" row that opens the KYC status screen.
- `KYCEndToEndIntegrationTests` — full init→chunk→commit→submit→status pipeline (simulator, GREEN).
- `LogoutPreservesKYCSessionTests` — D-02/A4 logout-preservation (simulator, GREEN).
- `KYCForceQuitResumeDeviceTests` — SC-2 force-quit-resume (compiles for the `ci-device.yml` device lane).
- `05-VALIDATION.md` — reconciled, approved, Nyquist-compliant.

**What needs a physical iPhone:** the simulator-untestable Phase 5 success
criteria — SC-2 (force-quit mid-upload) and SC-4 (background upload) — plus the
D-08 Profile entry UX and the D-12 hard gate.

### Checklist

- [x] **1. SC-2 — force-quit resume. — AUTOMATED (device CI lane).**
  Covered by `KYCForceQuitResumeUITests` (plan 05-12) running on the
  `ci-device.yml` `validationLedgerUITests` device lane (plan 05-13). The XCUITest
  performs a real `XCUIApplication().terminate()` (an ungraceful process kill)
  between two `.launch()` calls under the `midUpload` seed, then asserts the
  resumed KYC state is non-error / non-zeroed — the XCUITest-observable proxy for
  "the upload resumes, not restarts from 0%". The device-CI
  `KYCForceQuitResumeDeviceTests` additionally automates the pipeline + persistence
  portion on real hardware.
  *(Historical record of the original manual procedure:* Start the KYC capture
  flow and let artifact uploads begin (pipelined, D-01). While a ~6 MB artifact is
  mid-upload, force-quit the app, relaunch, and confirm the progress bar restores
  to the prior `chunksAcked/totalChunks`, **NOT 0%**.*)*

- [ ] **2. SC-4 — background upload completion. — REMAINS HUMAN-UAT.**
  With an artifact mid-upload, background the app (Home / swipe up but do NOT
  kill). Wait. Confirm the upload continues and completes — re-open the app and
  confirm the artifact shows ✓ committed. (iOS grants `BGProcessingTaskRequest`
  runtime on its own schedule; this may take a short while.) This is the
  end-to-end check for the truth that `BackgroundUploadSchedulingTests` only
  proves at the scheduling-logic level.
  **Why this cannot be automated:** iOS schedules `BGProcessingTaskRequest`
  discretionarily — the OS decides *if and when* to grant background runtime
  based on battery, charging state, and system load. No XCUITest or `xcodebuild
  test` run can force the OS to grant that runtime on demand, so end-to-end
  completion under a real OS suspension is irreducibly a human-UAT item.

- [x] **3. D-08 — Profile entry to the KYC status screen. — AUTOMATED (device CI lane).**
  Covered by `KYCProfileEntryUITests` (plan 05-12) running on the `ci-device.yml`
  `validationLedgerUITests` device lane (plan 05-13). The XCUITest launches under
  the `underReview` seed, taps the Profile `nav-avatar`, taps the
  `profile-kyc-status` "Verification status" row, and asserts
  `KYCStatusViewController` opens — the live tap-through D-08 specifies.
  *(Historical record of the original manual procedure:* Complete (or
  fixture-seed) KYC to a verified/under-review state, reach the role shell, open
  Profile (the top-bar avatar), and confirm a "Verification status" row that opens
  the KYC status screen and re-fetches status.*)*

- [x] **4. D-12 — hard gate. — AUTOMATED (device CI lane).**
  Covered by `KYCHardGateUITests` (plan 05-12) running on the `ci-device.yml`
  `validationLedgerUITests` device lane (plan 05-13). The XCUITest launches under
  the `nonVerified` seed, asserts the `kyc-start-heading` KYC-gate element exists,
  and asserts no role tab bar button (`Loads`, etc.) exists — proving the role tab
  bar was never constructed for a non-verified account.
  *(Historical record of the original manual procedure:* Confirm a non-verified
  account cannot reach the role shell — after OTP-verify it lands in the KYC flow,
  not the role tab bar.*)*

- [ ] **5. Test 10 — camera runtime-error / lifecycle resilience on device. — PARTIALLY AUTOMATED.**

  - **Background/foreground portion — AUTOMATED (device CI lane).** Covered by
    `KYCCaptureLifecycleUITests` (plan 05-12) running on the `ci-device.yml`
    `validationLedgerUITests` device lane (plan 05-13). The XCUITest enters the
    capture flow under the `nonVerified` seed, backgrounds the app with
    `XCUIDevice.shared.press(.home)`, foregrounds it with
    `XCUIApplication().activate()`, and asserts the `kyc-face-shutter` is
    `isHittable` again — proving the `AVCaptureSession` background/foreground
    observers restored a working session.
  - **Deliberate `AVCaptureSessionRuntimeError` injection — REMAINS HUMAN-UAT.**
    After an ungraceful force-quit mid-capture and relaunch, confirm the capture
    screen's shutter is responsive within ~5 s — a recoverable "The camera needs
    a moment. Try the photo again." cue appears with the shutter enabled (no
    permanent dead shutter). **Why this cannot be automated:** a genuine
    `AVCaptureSessionRuntimeError` is a real camera-hardware fault. No XCUITest can
    force the camera hardware to fault on demand — the live `AVFoundation`
    `runtimeErrorNotification` only fires on a real device under a real fault, so
    confirming the recoverable-cue / shutter-re-arm path stays a human-UAT item.

  `CameraSessionLifecycleTests` proves the VM-layer shutter re-arm in the
  simulator; the live `AVFoundation` `runtimeErrorNotification` /
  `wasInterrupted` / background-foreground observers only fire on real
  hardware. Added by the 05-10 gap-closure verification (2026-05-18).

### Resume signal

Type **"approved"** to close the checkpoint and complete Phase 5, or describe
issues observed:
- upload restarts from zero after force-quit
- background upload stalls / never completes
- the Profile "Verification status" row is missing or broken
- the D-12 gate is bypassable (a non-verified account reaches the role shell)

Once approved, run `/gsd:verify-work 5`.

---

## Carried open items (non-blocking, for the verifier's awareness)

- **`CameraPermissionViewController` is never presented** — denied camera
  permission currently shows inline `.failed` copy instead of the blocking
  permission screen plan 05-05 Task 4 specified. A product decision is pending
  (wire the blocking screen vs. keep inline copy). Recorded in STATE.md
  Blockers/Concerns; not a Phase 5 acceptance blocker.

## Notes

- The 05-05-04 and 05-06-03 HUMAN-UAT items (live camera/scanner capture, iPad
  rotation, Review/Status visual rendering) were **already verified** during
  the plan 05-06 Task 3 device cycle (3 GSD debug sessions, ~19 device-only
  defects fixed). They are recorded as PASSED in `05-VALIDATION.md`. Only the
  05-08 Task 3 items above remain open.

- **UAT gap closure (2026-05-18).** `05-UAT.md` Tests 9 and 10 (the two
  diagnosed gaps) are now **closed at the code/automated level** by plans
  05-09 (`GET /kyc/status` device-mock route) and 05-10 (timeout-bounded
  `capturePhoto()` + `AVCaptureSession` runtime-error/lifecycle observers).
  Both new test suites pass in the CI-matching serial run (367 tests, 0
  failures). Item 5 above is the device-only confirmation of the 05-10
  live-`AVFoundation` behavior.
