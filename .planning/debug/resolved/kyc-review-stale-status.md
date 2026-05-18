---
status: resolved
trigger: "Device test of the KYC flow (Phase 5, plan 05-06 checkpoint): 5 of 6 Review-screen artifacts reach 'Uploaded' (Selfie, License front, License back, Truck, Trailer) but the LAST artifact — Plate — is stuck on 'Waiting to upload...' so Submit never enables and the flow cannot complete. The upload pipeline demonstrably works (5/6 committed); Plate is the only artifact whose upload is kicked at the same instant the Review screen is pushed, and the Review screen reads upload state only once (viewWillAppear) with no live-progress wiring and no pull-to-refresh — so Plate's commit lands after the screen's only refresh and is never reflected."
created: 2026-05-17T20:00:00Z
updated: 2026-05-17T20:40:00Z
---

## Current Focus

reasoning_checkpoint:
  hypothesis: "Stale Review-screen upload status, NOT a failed upload. The Plate artifact's upload IS kicked (KYCCoordinator.pushPlate onConfirm calls kickUpload(for: .plate) at line 376, then pushReview() at line 377 — both synchronous, back to back). kickUpload spawns `Task { await uploader.upload(.plate) }` and returns immediately; pushReview() then synchronously pushes KYCReviewViewController, whose viewWillAppear calls viewModel.refresh() — the ONLY store read the Review screen ever does. At that instant Plate's upload Task has not yet completed its init POST, so KYCSession has no uploadStates[plate] entry and KYCReviewViewModel.status returns .pending. A moment later the Plate upload commits and writes uploadStates[plate].committed=true to disk — but the Review screen never re-reads: KYCUploader is constructed in AppContainer (line 435) with NO onProgress closure, so KYCReviewViewModel.updateProgress is never called; there is no UIRefreshControl / pull-to-refresh; and viewWillAppear does not re-fire while the user stays on Review. Result: Plate shows 'Waiting to upload...' permanently and submitEnabled (all 6 == .uploaded) is never satisfied. The other 5 artifacts are kicked on earlier capture screens, so they commit before the Review screen's single refresh() and display correctly."
  confirming_evidence:
    - "Device screenshot: Selfie, License front, License back, Truck, Trailer all show 'Uploaded' with the ✓ badge; Plate alone shows 'Waiting to upload...' with the dashed-circle .pending badge. The upload pipeline + mock fixtures work — 5/6 committed."
    - "KYCCoordinator.swift:376-377 — pushPlate's onConfirm: `kickUpload(for: .plate)` immediately followed by `pushReview()`. Plate IS kicked (2b fix confirmed); it is just kicked simultaneously with the Review-screen push."
    - "KYCReviewViewController.swift:145-150 — refresh() is called ONLY from viewWillAppear. No UIRefreshControl, no timer, no re-refresh path in the file."
    - "AppContainer.swift:435-439 — `KYCUploader(apiClient:store:logger:)` is constructed with NO onProgress argument. KYCUploader.onProgress is therefore nil; KYCReviewViewModel.updateProgress(for:fraction:) is never invoked. The previous debug session's HANDOFF flagged this exact gap as 'non-blocking polish' — it is in fact blocking for the last artifact."
  falsification_test: "Confirm Plate's upload actually succeeded: a `kyc_upload_committed event=plate` line in the device console (no `kyc_upload_init_failed event=plate`) proves the data committed and the bug is purely display-side. After the fix: on a device run, Plate reaches 'Uploaded' without user intervention and Submit enables; the 352-test suite stays green."
  fix_rationale: "RATIFIED + APPLIED. Approach A1 (settable onProgress slot) + B (pull-to-refresh safety net). KYCUploader.onProgress became a settable slot (`setOnProgress(_:)`) since the Review VM is built long after AppContainer constructs the uploader. KYCCoordinator.pushReview() installs the slot with a closure that WEAKLY captures the freshly-built KYCReviewViewModel and hops to @MainActor; a second pushReview() on a fresh VM replaces the slot cleanly. Navigation was NOT gated on the upload — live-refresh is the fix. The uploader now also emits a guaranteed post-commit `fraction == 1.0` (suppressed only when the final chunk-ack already reported 1.0, so the UPL-04 progress-test contract is unchanged). A failed pipelined upload flips the row via the coordinator's kickUpload catch path calling markFailed on the weakly-held VM. Pull-to-refresh added as the cheap manual fallback."
  blind_spots: "Not confirmed from device logs that Plate's upload committed — code evidence ruled conclusive (RATIFIED decision 3: 5/6 succeed via identical fixtures, Plate is only timing-special). Resolved without the device-console round-trip."

test: "Wired live upload-status refresh into the Review screen; added VM-level unit tests for updateProgress / markFailed; ran the full unit suite green."
expecting: "All 6 artifacts including Plate reach 'Uploaded' without user intervention; Submit enables; the test suite stays green."
next_action: "Resolved — physical-device re-verification of the live device run is folded into the 05-06 checkpoint close-out."

## Symptoms

expected: "On the Review screen, all 6 artifacts reach 'Uploaded' (✓) as their D-01 pipelined uploads commit — including the last one, Plate — without the user having to do anything; once all 6 are committed the Submit button enables."
actual: "5 of 6 artifacts show 'Uploaded'. Plate is stuck on 'Waiting to upload...' (the .pending dashed-circle badge) indefinitely. Submit stays disabled. The flow cannot be completed."
errors: "None surfaced to the user. No on-screen error — Plate just displays the .pending state forever."
reproduction: "DEBUG build on a physical iPhone. Run the full KYC capture flow through to the Review screen. The last artifact (Plate) is reproducibly stuck because its upload is kicked at the same instant the Review screen appears, after the screen's only refresh()."
started: "Phase 05 plan 05-06 device-testing checkpoint, after the kyc-upload-capture-bugs debug session fixed the upload-kick routing (2b) and added the device-mock KYC fixtures (2a). Those fixes made 5/6 uploads work; this residual stale-display bug for the last artifact was previously masked because nothing uploaded at all."

## Eliminated

- hypothesis: "Plate's upload was never kicked (a residual of the 2b sequencer bug)."
  evidence: "KYCCoordinator.swift:376 — pushPlate's onConfirm explicitly calls `kickUpload(for: .plate)`. The 2b fix covers plate. Plate IS kicked; the issue is the Review screen not reflecting the commit that lands just after it appears."
  timestamp: 2026-05-17T20:00:00Z
- hypothesis: "The KYC upload mock fixtures (2a) are incomplete and Plate's endpoint 404s."
  evidence: "5 of 6 artifacts uploaded successfully through the same /kyc/upload/init|chunk|commit fixtures. The fixtures are not artifact-specific — they handle the endpoints, not per-artifact. Plate would 404 only if the others did."
  timestamp: 2026-05-17T20:00:00Z

## Evidence

- timestamp: 2026-05-17T20:00:00Z
  checked: "Device screenshot of the Review screen after a full flow run."
  found: "Selfie / License front / License back / Truck / Trailer = 'Uploaded' + ✓ badge. Plate = 'Waiting to upload...' + dashed-circle badge. Submit greyed out."
  implication: "The upload pipeline and mock fixtures work for 5/6. Only the last artifact is stuck — pointing at a timing/refresh issue specific to the last artifact, not an upload-pipeline failure."

- timestamp: 2026-05-17T20:00:00Z
  checked: "KYCCoordinator.swift pushPlate / pushReview; KYCReviewViewController.swift lifecycle; AppContainer.swift KYCUploader construction."
  found: "pushPlate onConfirm (line 376-377): kickUpload(for: .plate) then pushReview() — synchronous, back to back. KYCReviewViewController.refresh() (viewModel.refresh) is called ONLY from viewWillAppear (line 145-150); no UIRefreshControl / timer / re-refresh. AppContainer (line 435-439) constructs KYCUploader with no onProgress closure, so KYCReviewViewModel.updateProgress is never called."
  implication: "Plate's upload commit lands AFTER the Review screen's single refresh(), and the screen has no mechanism to observe it. Confirmed display-side stale-state bug. Fix = give the Review screen a way to reflect uploads that complete after it appears (live onProgress wiring and/or pull-to-refresh)."

- timestamp: 2026-05-17T20:40:00Z
  checked: "Full unit suite on iPhone 16e simulator, -parallel-testing-enabled NO, after applying the live-refresh fix."
  found: "357 tests in 66 suites passed (0 failures). KYCUploaderProgressTests (the UPL-04 [0.25,0.5,0.75,1.0] chunk-ack-fraction contract) stayed green — the post-commit 1.0 emission is suppressed when the final chunk-ack already reported 1.0. The 5 new live-refresh tests in KYCReviewViewModelTests are green, including updateProgressCommitsLastArtifactAndEnablesSubmit (the VM-level Plate-stuck repro: 5/6 committed, Plate pending, submitEnabled=false → updateProgress(.plate, 1.0) → Plate .uploaded, submitEnabled=true)."
  implication: "The fix is verified at the unit level on the simulator. The simulator-testable path — KYCReviewViewModel.updateProgress / markFailed flipping rows and submitEnabled — is covered. The live device behaviour (Plate reaching 'Uploaded' unattended on a physical device, Submit enabling, pull-to-refresh) needs physical-device re-verification at the 05-06 checkpoint."

## Resolution

root_cause: |
  Display-side stale state on the KYC Review screen — not a failed upload. The
  last-captured artifact (Plate) has its pipelined upload kicked
  (KYCCoordinator.pushPlate's onConfirm) at the SAME synchronous instant the
  Review screen is pushed. The Review screen read upload state exactly once, in
  viewWillAppear → KYCReviewViewModel.refresh(). Plate's commit lands a moment
  AFTER that single read, and the screen had no mechanism to observe it:
  KYCUploader was constructed in AppContainer with NO onProgress observer (the
  observer was an init-time `let`, and the Review VM does not exist at
  AppContainer.init time), there was no UIRefreshControl, and viewWillAppear does
  not re-fire while the user stays on Review. So Plate's row stayed `.pending`
  forever and the all-6-committed Submit gate (D-03) was never satisfied. The
  other 5 artifacts are kicked on earlier capture screens and commit before the
  Review screen's single refresh, so they displayed correctly.

fix: |
  Approach A1 (settable onProgress slot) + B (pull-to-refresh safety net):

  1. KYCUploader.swift — `onProgress` is now a SETTABLE slot with a new
     actor-isolated `setOnProgress(_:)` method (the init parameter is kept for
     existing tests). The chunk loop emits the raw per-ack fraction (UPL-04
     contract preserved); after `commit` succeeds the uploader emits a guaranteed
     `fraction == 1.0`, suppressed only when the final chunk-ack already reported
     exactly 1.0 — so the observer never sees a duplicate and the UPL-04
     progress-test fraction sequence is unchanged. The `already_committed`
     early-return path also emits 1.0 for an observer installed after the commit.

  2. KYCCoordinator.swift — `pushReview()` installs the uploader's `onProgress`
     slot with a closure that WEAKLY captures the freshly-built
     KYCReviewViewModel and hops to @MainActor → `viewModel.updateProgress(...)`.
     A second `pushReview()` on a fresh VM cleanly replaces the slot. The
     coordinator also holds the Review VM weakly (`reviewViewModel`) so
     `kickUpload(for:)`'s failure path flips the row to `.failed` via
     `markFailed` on the *current* Review VM (no-op if no Review screen is live
     or the VM was deallocated — a restarted KYC flow cannot drive a dead VM).
     Navigation is intentionally NOT gated on the upload.

  3. KYCReviewViewController.swift — added a UIRefreshControl pull-to-refresh on
     the Review scroll view calling `viewModel.refresh()` as a manual safety-net
     fallback (`alwaysBounceVertical = true` so the gesture works on short
     content).

  4. KYCReviewViewModel.swift — removed the redundant explicit callback calls in
     `updateProgress` / `markFailed` / `retryUpload`; the `rows` `didSet` is now
     the single source of truth that fires `onRowsChange` + `onSubmitEnabledChange`
     exactly once per change (the old code double-fired the VC render path).

verification: |
  Built for iPhone 16e (Debug). Ran the full unit suite with
  `-parallel-testing-enabled NO`: 357 tests in 66 suites passed, 0 failures.
  KYCUploaderProgressTests (UPL-04 chunk-ack-fraction contract) stayed green.
  Added 6 VM-level unit tests for the live-refresh path in
  KYCReviewViewModelTests — including the VM-level reproduction of the device
  bug (5/6 committed + Plate pending → submitEnabled=false → updateProgress(.plate,
  1.0) → Plate .uploaded → submitEnabled=true).

  STILL NEEDS PHYSICAL-DEVICE RE-VERIFICATION at the 05-06 checkpoint (cannot be
  exercised on the simulator):
   - Plate reaching 'Uploaded' unattended on a live device run.
   - Submit enabling once all 6 commit on-device.
   - The pull-to-refresh gesture on the Review scroll view.

files_changed:
  - validationLedger/Core/Identity/KYCUploader.swift
  - validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift
  - validationLedger/Features/Onboarding/KYC/KYCReviewViewController.swift
  - validationLedger/Features/Onboarding/KYC/KYCReviewViewModel.swift
  - validationLedgerTests/KYC/KYCReviewViewModelTests.swift
