---
status: awaiting_human_verify
trigger: "Proactive audit of the entire KYC capture/review/status flow for the class of device-only bugs found at the 05-06 checkpoint (wiring gaps, layout collapse, pipeline breaks). Batch-fix before a single device test."
created: 2026-05-17T00:00:00Z
updated: 2026-05-17T12:00:00Z
---

## Current Focus

reasoning_checkpoint:
  hypothesis: "Five concrete inspection-findable bugs of the wiring/pipeline/layout class exist beyond FaceCapture: (1) DL-front has no photo capture/persist path so its upload throws artifactDataMissing and Submit can never enable; (2) Review thumbnails never get their image set; (3) DataScanner host collapses to 0 height; (4) CapturePreview imageView can collapse to 0; (5) DL extraction auto-rescan can double-fire."
  confirming_evidence:
    - "grep of DLFrontScanViewController: zero capturePhoto/CameraSession/sessionStore/persist — DL-front never produces bytes."
    - "KYCReviewViewController.ArtifactCell.apply(status:) never touches thumbnail.image; ArtifactRow has no image field."
    - "scannerContainer is a plain UIView in a `.fill` stack pinned top+bottom with no height/hugging constraint — identical to the eliminated FaceCapture round-2 collapse."
  falsification_test: "Build for iPhone 16e after fixes; KYC suites stay green; trace shows dl_front bytes reach KYCSessionStore.artifactData and Review reads artifactData into the thumbnails."
  fix_rationale: "DL-front: capture a still via DataScannerViewController.capturePhoto(), GPS-inject via injectGPS(into:location:), persist under .dlFront — the exact pipeline the plan specifies. Thumbnails: surface artifactData through the VM and render it. Layout: apply the same hugging-priority + min-height fix that fixed FaceCapture. All address root causes, not symptoms."
  blind_spots: "Live DataScanner/camera frame behavior cannot run on the simulator — the capturePhoto() success path and live OCR still need device verification."

test: "Apply fixes; build for iPhone 16e; run KYC test suites."
expecting: "BUILD SUCCEEDED, KYC suites green, no new failures beyond the known ~40 MockURLProtocol flakes."
next_action: "Fix BUG 1 — DL-front photo capture + persist pipeline."

## Symptoms

expected: "Every KYC screen (face, DL front scan, DL extraction, DL back, truck, trailer, plate, Use/Retake previews, Review, Status) works end-to-end on device: captures persist, uploads enqueue, coordinator advances, layouts fill the screen."
actual: "Unknown — these screens were never run end-to-end (simulator has no camera). FaceCapture alone surfaced 8 device-only bugs of the wiring/layout/pipeline class."
errors: "None yet — pre-emptive audit."
reproduction: "On-device walkthrough of the full KYC flow."
started: "Phase 05 — capture flow built in plans 05-03/05/06 but never exercised on device."

## Eliminated

- hypothesis: "KYCCoordinator push chain is incomplete / callbacks orphaned."
  evidence: "All 9 push methods wire the next VM callback before pushViewController; AppCoordinator retains kycCoordinator in a strong property (line 44/66-67). Reviewed full file — chain is sound."
  timestamp: 2026-05-17T00:00:00Z
- hypothesis: "Capture VCs collapse the preview host to 0 (the FaceCapture round-2/3 bug)."
  evidence: "FaceCaptureViewController + VehicleCaptureViewController already carry the round-3 hugging-priority fix + round-4 CameraPreviewView layerClass host + a 240pt min-height floor. Those two are clean."
  timestamp: 2026-05-17T00:00:00Z

## Evidence

- timestamp: 2026-05-17T00:00:00Z
  checked: "DLFrontScanViewController.swift — full file + grep for capturePhoto/sessionStore/persist/artifactData."
  found: "The DL-front screen runs ONLY DataScannerViewController text OCR. It never captures a photo, never touches CameraSession, never writes any `dl_front` bytes into KYCSessionStore. The plan (05-05 Task 2a) explicitly requires 'the uploaded DL-front artifact is the captured photo Data (GPS-injected)'."
  implication: "CRITICAL pipeline break. KYCCoordinator.confirmCapture() after the extraction screen kicks kickUpload(.dlFront); KYCUploader.upload(.dlFront) does `guard let data = loadSession()?.data(for:.dlFront)` → nil → throws artifactDataMissing(.dlFront). The Review screen shows dl_front permanently .pending → Submit can NEVER enable → the whole flow is dead-ended on a real device."
- timestamp: 2026-05-17T00:00:00Z
  checked: "KYCReviewViewController.ArtifactCell — thumbnail UIImageView + KYCReviewViewModel.ArtifactRow."
  found: "ArtifactCell has a `thumbnail` UIImageView but `apply(status:)` only sets the badge — `thumbnail.image` is NEVER assigned. ArtifactRow carries only artifact + status, no image. KYCSession.artifactData HAS the captured bytes but the VM never reads them and the cell never renders them."
  implication: "All 6 Review thumbnails render as empty surface-colored boxes — the 'constructed but never wired' bug class. 05-06 PLAN must_have: 'Review screen shows 6 artifact thumbnails'."
- timestamp: 2026-05-17T00:00:00Z
  checked: "DLFrontScanViewController scannerContainer + CapturePreviewViewController imageView layout."
  found: "scannerContainer is a plain UIView in a `.fill` vertical stack pinned top+bottom, with NO height constraint and NO content-hugging override — the exact FaceCapture round-2 collapse bug. CapturePreviewViewController.imageView is a UIImageView with scaleAspectFit in a `.fill` stack with no firm height and default hugging 250 — collapses to 0 when previewImage is nil."
  implication: "On a real full-size device the DataScanner host can collapse to 0 height (scanner shows nothing); the Use/Retake preview shows a 0-height image box when the render-only decode fails."
- timestamp: 2026-05-17T00:00:00Z
  checked: "DLFrontExtractionViewController.runFormatGate() invoked from viewDidAppear."
  found: "On a format failure runFormatGate() calls onRescanRequested?() which the coordinator wires to nav.popViewController. But the extraction VC stays on the stack mid-pop and runFormatGate can re-fire. Also the manual 'Rescan' button + the auto-prompt both call the same path — a double-pop is possible if viewDidAppear re-fires."
  implication: "Minor — a benign-but-sloppy nav race. Guard the auto-rescan so it fires exactly once."

## Resolution

root_cause: "Multiple wiring/pipeline/layout gaps across the KYC flow beyond FaceCapture, all of the same class as the 8 FaceCapture device bugs: constructed-but-unwired components, pipelines built in pieces but not joined, layout hosts with no intrinsic size collapsing to 0. The dominant one: the DL-front photo artifact had no capture+persist path at all, dead-ending the whole flow on a real device."

fix: |
  BUG 1 (CRITICAL — commits aee1358 + 273a2f1): DLFrontScanViewController now
  captures a still via DataScannerViewController.capturePhoto() at scan-
  completion, GPS-injects via GPSMetadataInjector.injectGPS(into:location:),
  and persists the bytes under .dlFront into KYCSessionStore. KYCCoordinator
  supplies the new geo/gps/store/logger deps. Also fixed the scannerContainer
  layout collapse (hugging-priority + 240pt min-height floor).

  BUG 2 (commit 273a2f1): KYCCoordinator.reopenCapture() for face/dlFront/
  dlBack no longer runs the forward push chain — it now captures, kicks ONLY
  that artifact's upload, and pops back to the originating Review/Status
  screen via the new popBack(to:) helper. pushFaceCapture/pushDLFrontScan/
  pushDLBack take an optional onConfirm.

  BUG 3 (commit 33dbdb0): Review screen renders the 6 captured-photo
  thumbnails. ArtifactRow gains thumbnailData; refresh() populates it from
  KYCSession.artifactData; ArtifactCell.apply(status:thumbnailData:) decodes
  + renders the image with a placeholder fallback post-commit.

  BUG 4 (commit 055469e): CapturePreviewViewController.imageView no longer
  collapses to 0 (hugging-priority + 240pt min-height floor).
  DLFrontExtractionViewController.runFormatGate() is one-shot guarded so the
  D-05 auto-rescan cannot double-pop the nav stack.

verification: "BUILD SUCCEEDED for iPhone 16e. build-for-testing (device-test lane) succeeds — DLExtractionScannerDeviceTests compiles with the new DLFrontScanViewController init. All 31 tests across 5 KYC suites GREEN (KYCReviewViewModel, KYCStatusViewModel, KYCCoordinator, DLExtractionFormat, KYCCapturePreviewLayout). No new failures introduced. Live camera/DataScanner behavior still needs on-device verification — see the DEVICE-TEST GUIDE in the audit report."

files_changed:
  - "validationLedger/Features/Onboarding/KYC/Capture/DLFrontScanViewController.swift — DL-front photo capture + persist pipeline; scannerContainer collapse fix"
  - "validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift — DL-front dep wiring; retake re-uploads only the retaken artifact + popBack(to:) helper"
  - "validationLedger/Features/Onboarding/KYC/KYCReviewViewModel.swift — ArtifactRow.thumbnailData; refresh() populates it"
  - "validationLedger/Features/Onboarding/KYC/KYCReviewViewController.swift — ArtifactCell renders the captured-photo thumbnail"
  - "validationLedger/Features/Onboarding/KYC/Capture/CapturePreviewViewController.swift — imageView collapse fix"
  - "validationLedger/Features/Onboarding/KYC/Capture/DLFrontExtractionViewController.swift — one-shot format-gate guard"
  - "validationLedgerDeviceTests/DLExtractionScannerDeviceTests.swift — updated for the new DLFrontScanViewController init"

## Audit Section — full-flow code inspection (2026-05-17)

Audited every KYC screen + transition for the 8-bug FaceCapture class. Per-screen verdict:

- KYCStartViewController — CLEAN. Centered intro, safe-area layout, native iPad.
- FaceCaptureViewController / ViewModel — CLEAN (already fixed in rounds 1-5; full chain re-verified: layerClass preview host, hugging-priority layout, video-frame pipeline wired, GPS at capture, persist to .face).
- DLFrontScanViewController — 2 BUGS FIXED: (1) no photo capture/persist for the dl_front artifact; (2) scannerContainer collapse. The DataScanner availability gate + extraction handoff were sound.
- DLFrontExtractionViewController — 1 BUG FIXED: format-gate auto-rescan could double-fire. Read-only fields (no UITextField) confirmed — D-05/T-05-05-01 holds.
- DLBackCaptureViewController — CLEAN. 5-line subclass of VehicleCaptureViewController; inherits all the (clean) vehicle capture behavior.
- VehicleCaptureViewController / ViewModel — CLEAN. layerClass preview host, hugging-priority layout, shutter 44pt floor, GPS at capture, persist per artifactType.
- CapturePreviewViewController — 1 BUG FIXED: imageView could collapse to 0 height. Use/Retake callbacks correctly wired by both face + vehicle VCs.
- CameraPermissionViewController — CLEAN. Centered layout, Open Settings deep-link, viewWillAppear re-checks authorization. NOTE: not currently presented by any code path — see NOT FIXABLE / device-verification list.
- CameraPreviewView — CLEAN. layerClass-backed, the round-4 structural fix.
- KYCCoordinator — 1 BUG FIXED: retake path re-ran the forward chain. Push chain, sign-out chrome, GeoContext refresh, D-01 upload kick, AppCoordinator retention all sound.
- KYCReviewViewController / ViewModel — 1 BUG FIXED: thumbnails never rendered. Gated Submit, retry/retake affordances, finalizer-once all sound. NOTE: live KYCUploader.onProgress hook is not wired — see NOT FIXABLE list.
- KYCStatusViewController / ViewModel — CLEAN. 4-state rendering, fetch-on-appear, pull-to-refresh, reason-code mapping, per-artifact recapture, verified-clear all sound.
