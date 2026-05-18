---
phase: 05-kyc-capture-upload-pipeline
plan: 06
subsystem: ui
tags: [kyc, uikit, review-screen, status-screen, coordinator, upload-status, rejection-reason]

# Dependency graph
requires:
  - phase: 05-kyc-capture-upload-pipeline
    plan: 01
    provides: RED KYCReviewViewModelTests / KYCStatusViewModelTests scaffolds, KYCSubmitEndpoint, 4 kyc-status fixtures
  - phase: 05-kyc-capture-upload-pipeline
    plan: 02
    provides: KYCSession / ArtifactUploadState (per-artifact committed state), KYCSessionStore, RejectionReasonCode
  - phase: 05-kyc-capture-upload-pipeline
    plan: 04
    provides: KYCUploader actor — upload(artifactType:) for the Retry-upload affordance
  - phase: 05-kyc-capture-upload-pipeline
    plan: 05
    provides: KYCCoordinator + 6 UIKit capture screens — the pushReview() stub this plan fills
provides:
  - KYCReviewViewController + KYCReviewViewModel — 6-thumbnail grid, all-6-committed gated Submit (D-03)
  - KYCStatusViewController + KYCStatusViewModel — 4-state verdict screen, fetch-on-appear + pull-to-refresh (D-08/D-09), targeted rejected-artifact re-capture (D-10)
  - KYCCoordinator push chain completed — pushReview() → pushStatus()
  - The KYC capture flow runs end-to-end on a physical device — capture → persist → pipelined upload → review → submit → status

affects: [05-08-kyc-human-uat]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Review-grid status surface: KYCReviewViewModel reads per-artifact upload status from KYCSession.uploadStates and is fed live by KYCUploader.onProgress (settable slot wired in pushReview)"
    - "Manual shutter on all 6 capture screens — the D-04 hands-free selfie auto-fire was superseded during the human-verify checkpoint; the Vision quality gate is retained as a shutter-enable gate"

key-files:
  created:
    - validationLedger/Features/Onboarding/KYC/KYCReviewViewController.swift
    - validationLedger/Features/Onboarding/KYC/KYCReviewViewModel.swift
    - validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift
    - validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift
  modified:
    - validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift
    - validationLedger/Core/Storage/KYCSessionStore.swift
    - validationLedger/Core/Identity/KYCUploader.swift
    - validationLedger/Core/Identity/KYC/KYCSession.swift
    - validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewController.swift
    - validationLedger/Features/Onboarding/KYC/Capture/DLFrontScanViewController.swift
    - validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift

key-decisions:
  - "Selfie capture switched from D-04 hands-free steady-hold auto-fire to a manual shutter button (matches the 4 vehicle screens) — supersedes the D-04 design decision; the Vision face-quality gate is kept, repurposed to gate shutter-enabled state"
  - "KYCSessionStore serialized with an NSLock + an atomic withSession read-modify-write API — the @MainActor capture path and the KYCUploader background actor were racing the unsynchronized store (lost updates)"
  - "D-02 footprint control retains a ~150px downscaled thumbnail post-commit (KYCSession.thumbnailData) so the Review grid still renders photos after the multi-MB image is freed"
  - "Device-mock KYC fixtures: MockDefaultFixtures now serves /kyc/upload/init|chunk|commit + /kyc/submit — a DEBUG device build runs networkConfig == .mock, so without them every upload 404'd"
  - "Each KYC upload is kicked directly by its known artifact at the capture-confirm site, not via the KYCFlowSequencer's lagging current step"
  - "KYCUploader.onProgress is a settable slot; KYCCoordinator.pushReview installs a weakly-captured closure so the Review screen reflects uploads that commit after it appears"

patterns-established:
  - "Gated thin-finalizer: KYCReviewViewModel.submit() is a no-op unless all 6 ArtifactUploadStates are committed; it fires KYCSubmitEndpoint once with the 6 server artifactIDs (T-05-06-01)"
  - "Controlled-vocabulary verdict copy: backend rejectionReason codes map through RejectionReasonCode.copy(for:) — unknown codes degrade to generic copy, raw codes never reach the UI (T-05-06-02)"

requirements-completed: [KYC-01, KYC-05]

# Metrics
duration: extended (human-verify checkpoint spanned a multi-session device-debugging cycle)
completed: 2026-05-17
---

# Phase 5 Plan 06: KYC Review + Status Screens Summary

**The back half of the KYC flow — `KYCReviewViewController` (6-thumbnail grid, all-6-committed gated Submit) and `KYCStatusViewController` (4-state verdict, fetch-on-appear + pull-to-refresh, targeted rejected-artifact re-capture) — completing the `KYCCoordinator` push chain, and a device-verified end-to-end run of the whole capture → upload → review → submit → status flow.**

## Performance

- **Tasks:** 3 (2 auto, 1 blocking human-verify checkpoint)
- **Completed:** 2026-05-17
- **Note:** Tasks 1–2 executed quickly against the simulator. Task 3 (the `checkpoint:human-verify` gate) became an extended physical-device debugging cycle — the simulator cannot run a camera, so the full KYC flow was exercised on a device for the first time here. It surfaced ~19 device-only defects, all fixed and committed before the checkpoint passed.

## Accomplishments

- **Task 1 — Review screen.** `KYCReviewViewModel` (`@MainActor`) exposes the 6 artifacts' upload status from `KYCSession.uploadStates`; `submitEnabled` is true only when all 6 are committed (D-03); `submit()` fires `KYCSubmitEndpoint` once with the 6 server `artifactID`s. `KYCReviewViewController` renders the 2-column 6-cell thumbnail grid with per-artifact status badges (✓ uploaded / ⟳ uploading / ⚠ failed / ⌛ pending) and inline Retry-upload + Retake on a failed cell. `KYCCoordinator.pushReview()` stub filled in.
- **Task 2 — Status screen.** `KYCStatusViewModel` defines `KYCOverallStatus` (pending / under_review / verified / rejected), fetches `GET /kyc/status` on appear, maps `rejectionReason` codes through `RejectionReasonCode.copy(for:)`, and clears the on-disk session on `verified` (D-02). `KYCStatusViewController` renders all 4 states per the UI-SPEC color map, with `UIRefreshControl` pull-to-refresh (D-09) and per-artifact re-capture of rejected artifacts only (D-10). `pushStatus()` completes the coordinator push chain.
- **Task 3 — human-verify checkpoint, PASSED.** Device-confirmed: the full KYC flow runs end-to-end on a physical iPhone — all 6 artifacts capture, persist, upload against the DEBUG mock, the Review grid shows 6 thumbnails reaching ✓ Uploaded, Submit enables, and Submit advances to the Status screen. (No live backend in M1, so the Status screen showing the submitted/awaiting state is the expected mock end state.)

## Task Commits

1. **Task 1: KYCReviewViewController + ViewModel** — `e95b271` (feat)
2. **Task 2: KYCStatusViewController + ViewModel** — `e627fb7` (feat)
3. **Task 3: human-verify checkpoint** — no code commit; passed after the checkpoint fixes below.

### Checkpoint fixes (Task 3 — device-only defects)

The human-verify checkpoint surfaced ~19 device-only defects the simulator could not catch. First-pass batch fixes (camera/preview/persistence wiring):

`41026cb` `b2983a9` `873becd` `93386af` `13a1b7c` `6db896f` `9e686eb` `d0ae874` `aee1358` `273a2f1` `33dbdb0` `055469e`

Three GSD debug sessions resolved the remaining classes (all in `.planning/debug/resolved/`):

- **`kyc-session-store-data-race`** — `0f95d0a` (NSLock + atomic `withSession` — the capture path and the upload actor were racing the unsynchronized store) · `a11ff37` (retain a downscaled Review thumbnail past the D-02 footprint-delete)
- **`kyc-upload-capture-bugs`** — `8726535` (selfie → manual shutter) · `002d837` (device-mock `/kyc/*` fixtures) · `82b2920` (kick each upload directly, not via the lagging sequencer) · `7ac0145` (stop the DL-front scanner auto-rescan loop)
- **`kyc-review-stale-status`** — `e1474d0` (live-refresh the Review screen so the last artifact's late commit is reflected)

## Files Created/Modified

- `KYCReviewViewController.swift` / `KYCReviewViewModel.swift` — NEW. The 6-thumbnail Review grid + gated-Submit state machine.
- `KYCStatusViewController.swift` / `KYCStatusViewModel.swift` — NEW. The 4-state KYC verdict screen.
- `KYCCoordinator.swift` — `pushReview()` / `pushStatus()` filled in; forward-chain upload kicks routed directly per artifact; `onProgress` slot wired into the Review VM.
- `KYCSessionStore.swift` — NSLock + atomic `withSession` API (data-race fix).
- `KYCUploader.swift` — settable `onProgress` slot; `commitAndFreeArtifactData` retains a thumbnail.
- `KYCSession.swift` — `thumbnailData` field.
- `FaceCaptureViewController.swift` — manual shutter button.
- `DLFrontScanViewController.swift` — scanner no longer auto-rescans on a format-gate failure.
- `MockDefaultFixtures.swift` — device-mock fixtures for the 4 `/kyc/*` endpoints.
- `Localizable.strings` — Review + Status screen copy.
- KYC test suites — `KYCReviewViewModelTests`, `KYCStatusViewModelTests` filled in (RED→GREEN); new `KYCSessionStoreConcurrencyTests`, `KYCThumbnailTests`, `MockDefaultFixtures` KYC-endpoint suite.

## Decisions Made

- **Selfie capture is now a manual shutter button**, consistent with the 4 vehicle screens — this supersedes the D-04 hands-free auto-fire design decision. The Vision face-quality gate is retained; it gates the shutter-enabled state instead of auto-firing. (Ratified by the user at the debug checkpoint.)
- **D-02 footprint control now keeps a ~150px thumbnail** (`KYCSession.thumbnailData`) post-commit so the Review grid renders photos after the multi-MB identity image is freed. The footprint D-02 guards (the full identity image) is still freed at commit.
- The remaining decisions (store serialization, device-mock fixtures, direct upload-kick, `onProgress` slot) are recorded in the three resolved debug-session files.

## Deviations from Plan

The two auto tasks executed as planned. The `checkpoint:human-verify` gate (Task 3) became a far larger effort than the plan anticipated: the plan expected the checkpoint to be a visual confirmation of the screens, but it was the first time the camera/scanner/upload surfaces ran on real hardware, and ~19 device-only defects surfaced. All were fixed under GSD debug sessions (not ad-hoc), each fix committed atomically, and the test suite kept green. No scope was added beyond making the planned flow actually work on a device.

## Issues Encountered

- **The simulator cannot exercise the camera/DataScanner surfaces**, so plans 05-03/05/06 had never run end-to-end before this checkpoint. The defects clustered into: camera-preview wiring, capture→`KYCSessionStore` persistence (a genuine multi-thread data race), the missing device-mock upload fixtures, an upload-kick sequencer off-by-one, a DL-front scanner auto-rescan loop, and a stale Review-screen refresh. All resolved — see the three resolved debug sessions.

## User Setup Required

None — no external service configuration. Phase 5 installs zero packages.

## Next Phase Readiness

- The KYC capture flow is device-verified end-to-end: capture → persist → pipelined upload → review → gated submit → status.
- **Plan 05-08** (Wave 4) is the last plan in Phase 5 — Profile KYC-status entry point, end-to-end integration, the logout-preserves-session test, the device force-quit-resume test, and `05-VALIDATION.md`. It carries its own HUMAN-UAT checkpoint.
- **Carried open item (non-blocking):** `CameraPermissionViewController` exists but is never presented — denied camera permission currently shows inline `.failed` copy instead of the blocking permission screen plan 05-05 Task 4 specified. A product decision is still pending (wire the blocking screen vs. keep inline copy).
- 357 tests / 66 suites pass with `-parallel-testing-enabled NO`.

---
*Phase: 05-kyc-capture-upload-pipeline*
*Completed: 2026-05-17*
