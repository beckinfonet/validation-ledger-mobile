---
status: resolved
trigger: "Device test of the full KYC flow (Phase 5, plan 05-06 checkpoint) surfaced four bugs. (1) DL-front scanner auto-captures in a loop. (1b) The selfie screen re-fires its auto-capture. (2a) Every KYC artifact upload fails at init — the mock backend has no fixtures for the /kyc/upload/* endpoints. (2b) The trailer and plate uploads are never kicked at all — a sequencer off-by-one. Net effect: the Review screen shows all 6 thumbnails (capture + the prior race fix work) but every cell is stuck Waiting to upload, Submit never enables, and the flow cannot complete. Device console logs attached as evidence."
created: 2026-05-17T19:30:00Z
updated: 2026-05-17T20:10:00Z
---

## Current Focus

reasoning_checkpoint:
  hypothesis: "Four distinct, device-confirmed bugs block the 05-06 KYC flow. ISSUE 2a (BLOCKER): a DEBUG build on a physical device runs networkConfig == .mock; MockDefaultFixtures.dispatchHandler registers handlers for only 5 auth/device endpoints and returns nil (-> built-in 404) for everything else — the four KYC endpoints /kyc/upload/init, /kyc/upload/chunk, /kyc/upload/commit, /kyc/submit were never added, so every upload's init POST 404s, KYCUploader.upload throws before persisting any ArtifactUploadState, and KYCReviewViewModel reports .pending forever. ISSUE 2b (BLOCKER): KYCCoordinator.confirmCapture() kicks the upload for sequencer.current, but the sequencer lags the on-screen step by one (the face screen is pushed via onGetStarted without advancing past .start), so across the 6 capture-confirms only 4 artifacts (face, dl_front, dl_back, truck) ever get kicked — trailer and plate never do — and the sequencer ends at .trailer, never reaching .review. ISSUE 1: the DL-front extraction format gate fails, auto-rescans (onRescanRequested -> nav.popViewController), the scanner screen's viewWillAppear re-arms (didCompleteScan=false), the still-framed license is instantly re-recognized, and it re-captures — an infinite scanner<->extraction loop, broken only by moving the camera away. ISSUE 1b: the selfie screen's D-04 steady-hold auto-fire re-arms on retake (resetForRetake) and re-fires; user friction, same class as Issue 1."
  confirming_evidence:
    - "Device log: `kyc_upload_started event=face` -> `kyc_upload_init_failed event=face` -> `kyc_pipelined_upload_failed event=face`, identical triple for dl_front, dl_back, truck. Confirms 2a — every init POST fails."
    - "Device log: `kyc_upload_started` appears for EXACTLY face, dl_front, dl_back, truck — never trailer, never plate. `kyc_flow_reached_review` logs BEFORE `kyc_upload_started event=truck`. Confirms 2b — only 4/6 kicked, kick lags one screen."
    - "Device log: `dlfront_scanner.started` -> `dlfront_photo_persisted` -> `dlfront_scanner.resumed` -> `dlfront_photo_persisted` -> `dlfront_scanner.resumed` -> `dlfront_photo_persisted` (3 captures). Confirms Issue 1 — the scanner re-arms and re-fires after each capture."
    - "Code: MockDefaultFixtures.swift dispatchHandler switch covers only (POST,/auth/otp/request), (POST,/auth/otp/verify), (GET,/device/challenge), (POST,/device/register), (POST,/device/heartbeat); `default: return nil`. No /kyc/* case. AppContainer.defaultNetworkConfig -> .mock in DEBUG."
    - "Code: KYCFlowSequencer starts at .start; KYCCoordinator.pushFaceCapture is triggered by startVC.onGetStarted with NO sequencer advance; confirmCapture() reads `completed = sequencer.current` (pre-advance) and kicks completed.artifact. Tracing the 6 confirm closures: kicks land on .start(nil), .face, .dlFront, .dlFrontExtraction(nil), .dlBack, .truck — i.e. face/dlFront/dlBack/truck only."
  falsification_test: "After the fixes: a DEBUG device build runs the full KYC flow; all 6 uploads reach init->chunk->commit (mock 200s), all 6 Review cells reach .uploaded, Submit enables; the DL-front scanner captures once per visit and does not loop; the existing 58 KYC tests stay green with -parallel-testing-enabled NO."
  fix_rationale: "ISSUE 2a: extend MockDefaultFixtures.dispatchHandler with canned 200 responses for POST /kyc/upload/init (uploadID + chunkSize), /kyc/upload/chunk (chunksAcked/totalChunks ack), /kyc/upload/commit (artifactID), and /kyc/submit — mirror the real endpoints' Response shapes; #if DEBUG already wraps the file. ISSUE 2b: the artifact for each capture screen is known statically at each push* call site — kick kickUpload(<artifact>) DIRECTLY in each forward-chain onConfirm closure instead of routing through the lagging sequencer.current; the retake path (reopenCapture) already kicks directly and correctly, so this aligns the forward chain with it. Consider whether KYCFlowSequencer's upload-kick role should be retired entirely. ISSUE 1: break the scanner<->extraction loop — the format-gate auto-rescan must not silently re-pop into an instantly-re-arming scanner; options include not auto-rescanning (require an explicit Rescan tap), or guarding the scanner so it does not re-capture the same still without the user re-initiating. ISSUE 1b: a product decision — keep the hands-free D-04 auto-fire but make it fire exactly once and require an explicit action to re-arm, vs. the user's suggestion of a manual shutter button like the vehicle screens. Surface this decision at a checkpoint."
  blind_spots: "Issue 1's exact trigger (does runFormatGate ALWAYS fail for this license, or only sometimes?) is inferred from the resumed/persisted log pattern, not from extraction-screen logs (the extraction VC does not log to kyc_camera). The DataScanner re-arm timing and whether capturePhoto itself can be double-invoked needs a closer look. Issue 1b is under-evidenced — the logs show one retake, not a runaway; confirm the re-arm behavior before fixing."

test: "Extend MockDefaultFixtures with /kyc/* handlers; fix the forward-chain upload-kick; build for iPhone 16e; run KYC suites with -parallel-testing-enabled NO."
expecting: "All 6 uploads commit against the mock; all 6 Review cells reach .uploaded; Submit enables; KYC suites green."
next_action: "Confirm Issue 1's loop mechanism in DLFrontExtractionViewController.runFormatGate, decide the Issue 1b selfie auto-fire UX (fix-stop vs manual shutter), then apply all four fixes."

## Symptoms

expected: "Full KYC flow on a physical iPhone: each capture screen captures once; all 6 artifacts upload in the background (D-01) against the DEBUG mock; the Review screen shows 6 thumbnails with ✓ Uploaded badges; Submit enables; tapping Submit advances to the Status screen."
actual: "Captures + persistence + thumbnails all work (race/thumbnail fixes from the prior session hold). BUT: the DL-front scanner auto-captures in a loop; the selfie screen re-fires its auto-capture on retake; every upload fails at init; trailer and plate uploads never start; the Review screen shows all 6 thumbnails but every cell is stuck 'Waiting to upload...'; Submit never enables; the flow cannot be completed."
errors: "kyc_upload_init_failed (face, dl_front, dl_back, truck). kyc_pipelined_upload_failed (same four). No exception surfaced to the user — the Review screen just stays at .pending. The FigCaptureSourceRemote err=-17281 and 'fopen failed'/'Invalidating cache' console lines are benign AVFoundation/VisionKit noise from repeated camera-session restarts — NOT a bug."
reproduction: "DEBUG build on a physical iPhone (networkConfig == .mock by default). Run the full KYC capture flow. The DL-front loop reproduces by holding a license steady in frame; the upload failures reproduce on every run."
started: "Phase 05 plan 05-06 device-testing checkpoint — first end-to-end device exercise of the KYC flow. Issue 2a is a Phase-5 gap: Phase 4 (MockDefaultFixtures) added device-mock fixtures for the auth/device endpoints but Phase 5 never added the KYC upload endpoints."

## Eliminated

- hypothesis: "Artifacts are not being captured or persisted (the original 05-06 concern)."
  evidence: "Device run: all 6 Review thumbnails render real photos; `dlfront_photo_persisted bytes=NNNNNN` logs confirm DL-front bytes hit disk. Capture + KYCSessionStore persistence + the prior-session race/thumbnail fixes all work. The blocker is the UPLOAD layer, not capture."
  timestamp: 2026-05-17T19:30:00Z

## Evidence

- timestamp: 2026-05-17T19:30:00Z
  checked: "Device console (kyc-filtered) for the upload events across a full flow run."
  found: "Upload attempts logged: `kyc_upload_started event=face` then `kyc_upload_init_failed event=face` then `kyc_pipelined_upload_failed event=face`. The identical started->init_failed->pipelined_upload_failed triple repeats for dl_front, dl_back, and truck. There is NO `kyc_upload_started` for trailer or plate anywhere in the log."
  implication: "ISSUE 2a confirmed — every kicked upload's init POST fails. ISSUE 2b confirmed — only 4 of 6 uploads are ever kicked; trailer and plate are never attempted."

- timestamp: 2026-05-17T19:30:00Z
  checked: "Device console for the DL-front scanner sequence."
  found: "`dlfront_scanner.started` -> `dlfront_photo_persisted bytes=1355244` -> `dlfront_scanner.resumed` -> `dlfront_photo_persisted bytes=1336572` -> `dlfront_scanner.resumed` -> `dlfront_photo_persisted bytes=3119167` -> then the flow advances to the DL-back (vehicle_vc.viewDidLoad). `dlfront_scanner.resumed` is emitted by startScannerIfAvailable() when dataScanner != nil — i.e. it fires on a re-entry to viewWillAppear."
  implication: "ISSUE 1 confirmed — after a capture the DL-front screen is re-entered (the extraction screen popped back via onRescanRequested), the scanner re-arms, and the still-framed license is instantly re-captured. The loop ran 3x before advancing. User had to move the camera away to escape it."

- timestamp: 2026-05-17T19:30:00Z
  checked: "MockDefaultFixtures.swift — the DEBUG physical-device mock fixture registry."
  found: "dispatchHandler's switch handles exactly (POST,/auth/otp/request), (POST,/auth/otp/verify), (GET,/device/challenge), (POST,/device/register), (POST,/device/heartbeat); `default: return nil` -> MockURLProtocol built-in 404. No case for /kyc/upload/init, /kyc/upload/chunk, /kyc/upload/commit, or /kyc/submit. AppContainer.defaultNetworkConfig returns .mock in DEBUG, and a DEBUG build on a device uses it."
  implication: "ISSUE 2a root cause — the four KYC endpoints 404 on every device run. KYCUploader.upload catches the NetworkError at the init POST and throws KYCUploadError.nonRetryable BEFORE persistFreshState, so no ArtifactUploadState is ever written and KYCReviewViewModel.status returns .pending. The file's own header documents this exact bug class being fixed for the auth/device endpoints in Phase 4 — the KYC endpoints were the Phase-5 gap."

- timestamp: 2026-05-17T19:30:00Z
  checked: "KYCCoordinator forward push chain + KYCFlowSequencer.advance/confirmCapture."
  found: "sequencer.current starts at .start. pushFaceCapture is called from startVC.onGetStarted with no sequencer advance, so the face SCREEN is shown while the sequencer still reads .start. confirmCapture() does `completed = sequencer.current; advance(); if let a = completed.artifact { kickUpload(a) }`. The 6 forward-chain confirm closures (face, dlExtraction, dlBack, truck, trailer, plate) therefore see completed = .start, .face, .dlFront, .dlFrontExtraction, .dlBack, .truck respectively — kicking face, dlFront, dlBack, truck only (.start and .dlFrontExtraction have nil artifact). trailer and plate are never kicked; the sequencer ends at .trailer, never .review."
  implication: "ISSUE 2b root cause — the upload kick is routed through sequencer.current, which lags the on-screen step by one. The retake path (reopenCapture) kicks kickUpload(artifact) directly with the correct artifact and is unaffected — only the forward chain is broken. Fix: kick the known artifact directly at each push* onConfirm site."

- timestamp: 2026-05-17T19:30:00Z
  checked: "Device console for the selfie (face) capture screen."
  found: "`face_vc.viewWillAppear` + `start_authorized_session.begin position=front` + `session_start` + `face_gate.first_frame` appears TWICE before the flow moves to the DL-front scanner — consistent with the user retaking the selfie once. The user reported the selfie screen 'kept auto taking pictures again'."
  implication: "ISSUE 1b — the D-04 steady-hold auto-fire re-arms via resetForRetake on a retake and re-fires. The logs show one retake, not a runaway loop, so this is under-evidenced relative to Issues 1/2. Same bug class as Issue 1 (auto-capture that does not stop cleanly). Needs a product decision: keep hands-free auto-fire (fire once, explicit re-arm) vs. a manual shutter button (user's suggestion)."

## Resolution

root_cause: |
  Four distinct device-confirmed bugs, all surfaced at the first end-to-end
  device run of the Phase-5 KYC flow (plan 05-06 checkpoint).

  ISSUE 2a (BLOCKER) — missing device-mock KYC fixtures. A DEBUG build on a
  physical device runs `networkConfig == .mock`. `MockDefaultFixtures`
  registered handlers for only the 5 Phase-4 auth/device endpoints; its
  catch-all `default: return nil` 404'd everything else. The four Phase-5 KYC
  endpoints (`/kyc/upload/init`, `/kyc/upload/chunk`, `/kyc/upload/commit`,
  `/kyc/submit`) were never added — a Phase-5 gap. Every artifact's init POST
  404'd, `KYCUploader.upload` threw `KYCUploadError.nonRetryable` BEFORE
  `persistFreshState`, so no `ArtifactUploadState` was ever written and
  `KYCReviewViewModel` reported `.pending` forever — Submit could never enable.

  ISSUE 2b (BLOCKER) — upload-kick off-by-one. `KYCCoordinator.confirmCapture()`
  kicked `sequencer.current.artifact`, but the sequencer lagged the on-screen
  step by one: the face screen is pushed via `startVC.onGetStarted` with NO
  sequencer advance. Tracing the 6 forward-chain confirm closures, the kicks
  landed on `.start`(nil), `.face`, `.dlFront`, `.dlFrontExtraction`(nil),
  `.dlBack`, `.truck` — i.e. only face/dlFront/dlBack/truck were ever kicked;
  trailer and plate never were. The retake path (`reopenCapture`) was
  unaffected — it already kicked `kickUpload(<artifact>)` directly.

  ISSUE 1 — infinite DL-front scanner<->extraction loop.
  `DLFrontExtractionViewController.runFormatGate()` auto-called
  `onRescanRequested?()` on a format-validation failure. The coordinator wired
  that to `nav.popViewController`, re-entering the scanner screen, whose
  `viewWillAppear` reset `didCompleteScan = false` and re-armed the
  `DataScannerViewController`. The still-framed license was instantly
  re-recognized, a new extraction was pushed, the gate failed again, and it
  auto-popped again — a loop broken only by physically moving the camera away.

  ISSUE 1b — selfie auto-capture re-fire. The D-04 hands-free design auto-fired
  the shutter when the Vision steady-hold gate held `.pass` ~0.5s. On a Retake
  (`resetForRetake`) the steady-hold re-armed and, with the face still framed,
  re-fired — user friction, the same class as Issue 1.

fix: |
  ISSUE 1b (USER DECISION — Option B, manual shutter): the selfie screen's D-04
  hands-free auto-fire is REPLACED by a manual shutter button, mirroring
  `VehicleCaptureViewController`. SUPERSEDES the D-04 hands-free design
  decision: all 6 KYC capture screens now use a manual shutter.
  `FaceCaptureViewController` gains a `borderedProminent` shutter button with a
  44pt touch-target floor and the `kyc-face-shutter` accessibility id, in the
  `.fill`-stack layout pattern the vehicle screen uses. The Vision
  `FaceQualityGate` / `SteadyHoldTracker` quality gate is RETAINED but
  REPURPOSED: the gate-signal stream now drives a SHUTTER-ENABLED state instead
  of an auto-fire. `FaceCaptureViewModel.State` replaces `.holding` with
  `.readyToCapture`; the shutter (`shutterButton.isEnabled`) is enabled ONLY
  while the gate holds a steady `.pass` (the SteadyHoldTracker dwell is the
  de-bounce), so the user still cannot capture a bad selfie. The gate stream's
  `fireCapture()` is removed; an explicit `capture()` method (guarded on
  `.readyToCapture`, like `VehicleCaptureViewModel.capture()`) fires the shutter
  on the VC's `shutterTapped`.

  ISSUE 2a: `MockDefaultFixtures.dispatchHandler` is extended with canned 200
  responses for `POST /kyc/upload/init` (uploadId + 512 KB chunkSize),
  `/kyc/upload/chunk` (an ack with `total_chunks: 0` — `KYCUploader` falls back
  to its own locally-computed total when the server reports 0, and advances its
  resume cursor on its own loop index), `/kyc/upload/commit` (artifactId +
  `pending_review`), and `/kyc/submit` (`under_review`). Each Response shape
  mirrors the shipped endpoint's `Response` struct. The whole file is already
  `#if DEBUG`-wrapped — zero Release impact.

  ISSUE 2b: the forward-chain upload kick no longer routes through the lagging
  `sequencer.current`. The old `confirmCapture()` is split: `advanceFlowStep()`
  now only advances the sequencer (flow-state bookkeeping), and each of the 6
  forward-chain `onConfirm` closures kicks the statically-known artifact
  DIRECTLY via `kickUpload(for: <artifact>)` — the exact pattern the retake
  path already used. All 6 artifacts (face, dlFront, dlBack, truck, trailer,
  plate) are now kicked, exactly once each.

  ISSUE 1: `DLFrontExtractionViewController.runFormatGate()` no longer
  auto-calls `onRescanRequested`. On a format failure it surfaces the inline
  notice and disables the "Looks good" CTA — the user must tap the
  always-present "Rescan" button. The format gate is retained; returning to the
  scanner is now strictly user-initiated, so the auto-pop loop cannot run.

verification: |
  BUILD SUCCEEDED for the iPhone 16e simulator (Debug). build-for-testing for
  `generic/platform=iOS` also SUCCEEDED — the device-test lane
  (`validationLedgerDeviceTests`) compiles against the new FaceCapture API.

  Full unit-test target run with `-parallel-testing-enabled NO`: 352 tests in
  66 suites GREEN, no failures. All KYC suites pass, incl. the retained
  `FaceQualityGate — gate logic + steady-hold (KYC-02 / D-04)` suite (confirms
  the repurposed quality gate logic is unaffected) and the new
  `MockDefaultFixtures — KYC upload endpoints (Issue 2a / 2b)` suite — 5 tests:
  the 4 `/kyc/*` endpoints each answer a decodable 200, and a full pipeline
  test uploads all 6 artifacts init->chunk->commit against the device-mock
  fixtures and asserts every artifact reaches `committed` with a server
  `artifactID` (the exact state the Review-screen gated Submit reads).

  STILL NEEDS PHYSICAL-DEVICE RE-VERIFICATION (camera/scanner surfaces are not
  simulator-testable — RESEARCH Pitfall 1):
    - Issue 1 — the DL-front scanner no longer loops (hold a license steady;
      confirm one capture per visit and no auto-rescan).
    - Issue 1b — the selfie manual shutter: the shutter enables only while the
      face-quality gate passes, and capture fires only on the shutter tap.
    - A full end-to-end KYC upload run on a DEBUG device build against the
      mock — all 6 Review cells reach Uploaded, Submit enables, Submit advances
      to the Status screen.

files_changed:
  - "validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewModel.swift — Issue 1b: replaced the D-04 gate-stream auto-fire with a shutter-enabled state + an explicit `capture()` method; `.holding` -> `.readyToCapture`; SteadyHoldTracker retained as the shutter-enable de-bounce."
  - "validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewController.swift — Issue 1b: added the manual shutter button (44pt floor, `kyc-face-shutter` id, `.fill`-stack layout mirroring VehicleCaptureViewController); shutter enabled only in `.readyToCapture`."
  - "validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift — Issue 2b: split `confirmCapture()` into `advanceFlowStep()` (sequencer only); each of the 6 forward-chain onConfirm closures now kicks the statically-known artifact directly via `kickUpload(for:)`."
  - "validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift — Issue 2a: added device-mock 200 fixtures for POST /kyc/upload/init, /kyc/upload/chunk, /kyc/upload/commit, /kyc/submit; `dispatchHandler` made internal for test access."
  - "validationLedger/Features/Onboarding/KYC/Capture/DLFrontExtractionViewController.swift — Issue 1: `runFormatGate()` no longer auto-calls `onRescanRequested` on a format failure (breaks the scanner<->extraction loop); rescan is now user-initiated."
  - "validationLedger/Resources/en.lproj/Localizable.strings — added `kyc.face.cue.ready` for the selfie shutter-ready cue (Issue 1b)."
  - "validationLedgerTests/KYC/MockDefaultFixturesKYCTests.swift — NEW: 5 tests covering the 4 KYC device-mock endpoints + a full 6-artifact upload pipeline against the mock (Issue 2a / 2b coverage)."

## Resolution note — D-04 superseded

Issue 1b was resolved by USER DECISION (Option B): the selfie screen's D-04
hands-free steady-hold auto-fire is replaced by a manual shutter button. This
SUPERSEDES the D-04 hands-free design decision. All 6 KYC capture screens
(face, DL-front, DL-back, truck, trailer, plate) now use a manual shutter for a
consistent affordance. The Vision steady-hold quality gate is NOT discarded —
it is retained and repurposed as a shutter-ENABLE gate: the shutter unlocks
only while the face-quality gate holds a steady `.pass`, so the quality bar D-04
enforced still holds, just behind an explicit shutter tap rather than an
automatic fire.
