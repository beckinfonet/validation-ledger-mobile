# Phase 5 — HUMAN-UAT Checklist

> Physical-device verification items for Phase 5 (KYC Capture + Upload Pipeline)
> that cannot run in the iOS Simulator or in CI. This file is the durable record
> of the plan 05-08 Task 3 `checkpoint:human-verify` gate.
>
> **Phase 5 is complete only once every item below is verified on a physical
> iPhone.** Once approved, run `/gsd:verify-work 5`.

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

- [ ] **1. SC-2 — force-quit resume.**
  Start the KYC capture flow and let artifact uploads begin (pipelined, D-01).
  While a ~6 MB artifact is mid-upload (watch the determinate progress bar),
  force-quit the app (swipe up from the app switcher). Relaunch. Confirm the
  upload resumes from where it left off — the progress bar restores to the
  prior `chunksAcked/totalChunks`, **NOT 0%** — and the artifact eventually
  commits. The device-CI `KYCForceQuitResumeDeviceTests` automates the pipeline
  + persistence portion on real hardware; this confirms the real end-to-end UX.

- [ ] **2. SC-4 — background upload completion.**
  With an artifact mid-upload, background the app (Home / swipe up but do NOT
  kill). Wait. Confirm the upload continues and completes — re-open the app and
  confirm the artifact shows ✓ committed. (iOS grants `BGProcessingTaskRequest`
  runtime on its own schedule; this may take a short while.) This is the
  end-to-end check for the truth that `BackgroundUploadSchedulingTests` only
  proves at the scheduling-logic level.

- [ ] **3. D-08 — Profile entry to the KYC status screen.**
  Complete (or fixture-seed) KYC to a verified/under-review state, reach the
  role shell, open Profile (the top-bar avatar), and confirm a "Verification
  status" row that opens the KYC status screen and re-fetches status.

- [ ] **4. D-12 — hard gate.**
  Confirm a non-verified account cannot reach the role shell — after OTP-verify
  it lands in the KYC flow, not the role tab bar.

- [ ] **5. Test 10 — camera runtime-error / lifecycle resilience on device.**
  After an ungraceful force-quit mid-capture and relaunch, confirm the capture
  screen's shutter is responsive within ~5 s — a recoverable "The camera needs
  a moment. Try the photo again." cue appears with the shutter enabled (no
  permanent dead shutter). Then confirm the session self-heals: backgrounding
  and foregrounding the app mid-capture restores a working capture session.
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
