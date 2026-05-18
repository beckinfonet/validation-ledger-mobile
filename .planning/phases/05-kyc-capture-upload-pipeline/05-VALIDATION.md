---
phase: 5
slug: kyc-capture-upload-pipeline
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-16
approved: 2026-05-17
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
>
> Pre-filled from the 8-plan structure so the Nyquist gate could evaluate it
> before execution. Plan 08 Task 2 RECONCILED this map against the actual
> execution outcome and flipped `status`/`nyquist_compliant`/`wave_0_complete`
> to approved/true (2026-05-17).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite`/`@Test`) for new simulator unit/integration tests; XCTest (`XCTestCase`) for the physical-device test target |
| **Config file** | none — Swift Testing needs no config; targets are `validationLedgerTests` (simulator unit), `validationLedgerUITests` (XCUITest), `validationLedgerDeviceTests` (physical-device, runs via `ci-device.yml` on merge to `main`) |
| **Quick run command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:validationLedgerTests/<suite>` |
| **Full suite command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16'` (simulator) + the `ci-device.yml` device lane on merge to `main` |
| **Estimated runtime** | ~90 seconds for a single simulator suite (cold `xcodebuild` start dominates); ~6–9 minutes for the full simulator suite; device lane ~10–25 minutes |

> Environment note (reconciliation): the development/CI machine that executed
> plans 05-04..05-08 has no plain `iPhone 16` simulator installed (the
> available image is `iPhone 16e`). The canonical commands below name
> `iPhone 16` for portability; on this environment they were run against
> `iPhone 16e`. Source/test code is destination-agnostic — only the verify
> destination differs (recorded in the 05-04..05-08 SUMMARYs).

---

## Sampling Rate

- **After every task commit:** Run the quick command for the task's suite(s) — e.g. `xcodebuild test … -only-testing:validationLedgerTests/KYCUploaderTests`.
- **After every plan wave:** Run the full simulator suite command.
- **Before `/gsd:verify-work`:** Full simulator suite must be green; the device lane (`KYCForceQuitResumeDeviceTests`, `DLExtractionScannerDeviceTests`) green on the self-hosted runner.
- **Max feedback latency:** ~120 seconds (one cold `xcodebuild` quick run).

---

## Per-Task Verification Map

> Reconciled 2026-05-17. All KYC simulator suites live under
> `validationLedgerTests/KYC/`; the two device suites under
> `validationLedgerDeviceTests/`. Every code-producing row is `✅ green`; the
> three `checkpoint:human-verify` rows are `⬜ HUMAN-UAT` (routed to the
> Manual-Only table — 05-05-04 + 05-06-03 are PASSED, 05-08-03 is the open
> Phase-5-closing checkpoint).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 0 | UPL-05 (contract) | T-05-01-01 | kycStatus optional → malformed value fails closed to KYC gate | build (contract compile) | `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16'` | ✅ plan 01 | ✅ green |
| 05-01-02 | 01 | 0 | UPL-05 | T-05-01-02 / T-05-01-03 | BGTask identifier bundle-scoped; fixtures synthetic | lint (plist + JSON) | `plutil -lint validationLedger/App/Info.plist` + `plutil -lint` on the KYC fixtures | ✅ plan 01 | ✅ green |
| 05-01-03 | 01 | 0 | UPL-05 (Nyquist scaffolds) | T-05-01-03 | RED suites + device scaffold compile | build-for-testing (14 simulator RED suites + 1 device RED scaffold) | `xcodebuild build-for-testing -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16'` | ✅ plan 01 | ✅ green |
| 05-02-01 | 02 | 1 | KYC-06 / UPL-02 | T-05-02-04 | KYC session models Codable round-trip | unit (TDD) | `xcodebuild test … -only-testing:validationLedgerTests/KYCSessionStoreTests` | ✅ W0 | ✅ green |
| 05-02-02 | 02 | 1 | KYC-06 / UPL-02 | T-05-02-01 / T-05-02-02 | NSFileProtectionComplete on every write; no hand-rolled crypto | unit (TDD) | `xcodebuild test … -only-testing:validationLedgerTests/KYCSessionStoreTests` | ✅ W0 | ✅ green |
| 05-02-03 | 02 | 1 | KYC-05 (D-11) | T-05-02-03 | Unknown rejection code degrades to generic copy | unit (TDD) | `xcodebuild test … -only-testing:validationLedgerTests/RejectionReasonCodeTests` | ✅ W0 | ✅ green |
| 05-03-01 | 03 | 1 | KYC-04 (Pitfall 5) | T-05-03-02 | Stale/inaccurate location fix rejected | unit (TDD) | `xcodebuild test … -only-testing:validationLedgerTests/GeoContextTests` | ✅ W0 | ✅ green |
| 05-03-02 | 03 | 1 | KYC-04 (SC-1) | T-05-03-01 / T-05-03-03 | GPS EXIF injected without UIImage; coordinates round-trip | unit (TDD) | `xcodebuild test … -only-testing:validationLedgerTests/GPSMetadataInjectorTests` | ✅ W0 | ✅ green |
| 05-03-03 | 03 | 1 | KYC-02 | T-05-03-04 | Face quality gate (no liveness — deferred) emits pass/adjust/noFace | unit (TDD) | `xcodebuild test … -only-testing:validationLedgerTests/FaceQualityGateTests` | ✅ W0 | ✅ green |
| 05-04-01 | 04 | 2 | UPL-01 / UPL-02 / UPL-04 | T-05-04-05 | Resume from persisted chunksAcked; server-ack-driven progress | unit (TDD) | `xcodebuild test … -only-testing:validationLedgerTests/KYCUploaderTests -only-testing:…/KYCUploaderResumeTests -only-testing:…/KYCUploaderProgressTests` | ✅ W0 | ✅ green |
| 05-04-02 | 04 | 2 | UPL-03 / SC-5 | T-05-04-01 / T-05-04-02 | 5-attempt jittered backoff cap; stable per-chunk Idempotency-Key — no duplicate commit | unit (TDD) | `xcodebuild test … -only-testing:validationLedgerTests/KYCUploaderRetryTests -only-testing:…/KYCUploaderIdempotencyTests` | ✅ W0 | ✅ green |
| 05-05-01 | 05 | 2 | KYC-01 / KYC-03 | T-05-05-01 / T-05-05-05 | KYCCoordinator flow sequencing; DL format gate; D-14 sign-out | unit | `xcodebuild test … -only-testing:validationLedgerTests/KYCCoordinatorTests -only-testing:…/DLExtractionFormatTests` | ✅ W0 | ✅ green |
| 05-05-02a | 05 | 2 | KYC-02 / KYC-03 | T-05-05-01 / T-05-05-02 | Face capture + DL scan/extraction VCs compile; read-only DL fields; GPS at capture | build (compile gate) | `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16'` | N/A (compile) | ✅ green |
| 05-05-02b | 05 | 2 | KYC-03 / KYC-04 | T-05-05-02 / T-05-05-03 | DL-back/vehicle/preview/permission VCs compile; DataScanner device smoke test | build + build-for-testing | `xcodebuild build … && xcodebuild build-for-testing …` | ✅ W0 (`DLExtractionScannerDeviceTests`) | ✅ green |
| 05-05-04 | 05 | 2 | KYC-01..04 | T-05-05-01..05 | Live capture/scanner flow on physical iPhone + iPad | HUMAN-UAT (device) | manual — see Manual-Only Verifications | N/A | ⬜ HUMAN-UAT (PASSED — folded into 05-06 Task 3 device cycle) |
| 05-06-01 | 06 | 3 | KYC-01 (D-03) | T-05-06-01 | Submit gated on all-6-committed; finalizer fires once | unit | `xcodebuild test … -only-testing:validationLedgerTests/KYCReviewViewModelTests` | ✅ W0 | ✅ green |
| 05-06-02 | 06 | 3 | KYC-05 (SC-3) | T-05-06-02 | 4-state status from fixtures; unknown reason code → generic copy | unit | `xcodebuild test … -only-testing:validationLedgerTests/KYCStatusViewModelTests` | ✅ W0 | ✅ green |
| 05-06-03 | 06 | 3 | KYC-01 / KYC-05 | T-05-06-01..04 | Review thumbnail grid + 4 status states visual render | HUMAN-UAT | manual — see Manual-Only Verifications | N/A | ⬜ HUMAN-UAT (PASSED — device-verified end-to-end, 3 debug sessions) |
| 05-07-01 | 07 | 3 | KYC-01 (D-12/D-13) | T-05-07-01 / T-05-07-02 | `.kyc` hard gate; absent kycStatus fails closed to KYC gate | unit | `xcodebuild test … -only-testing:validationLedgerTests/SessionRestoreServiceTests` | ✅ plan 07 | ✅ green |
| 05-07-02 | 07 | 3 | UPL-05 | T-05-07-05 / T-05-07-06 | BGProcessingTaskRequest scheduling; handler captures scene container's uploader (no new AppContainer) | unit | `xcodebuild test … -only-testing:validationLedgerTests/BackgroundUploadSchedulingTests` | ✅ W0 | ✅ green |
| 05-08-01 | 08 | 4 | KYC-01 / KYC-06 / UPL-02 | T-05-08-02 | End-to-end pipeline; logout preserves on-disk KYC session (D-02) | integration (unit) | `xcodebuild test … -only-testing:validationLedgerTests/KYCEndToEndIntegrationTests -only-testing:…/LogoutPreservesKYCSessionTests` | ✅ plan 08 | ✅ green |
| 05-08-02 | 08 | 4 | UPL-02 (SC-2) | T-05-08-01 | Force-quit mid-6MB-upload resumes from persisted chunksAcked cursor | device (XCTest) | `xcodebuild build-for-testing …` (compile) → device lane runs `KYCForceQuitResumeDeviceTests` via `ci-device.yml` | ✅ plan 08 | ✅ green (compiles for the device lane) |
| 05-08-03 | 08 | 4 | UPL-05 (SC-4) / KYC-01 (D-08) | T-05-08-03 / T-05-08-04 | Background-upload completion under real OS suspension; Profile entry; hard gate | HUMAN-UAT (device) | manual — see Manual-Only Verifications | N/A | ⬜ HUMAN-UAT (open — the Phase-5-closing checkpoint) |

*Status: ⬜ pending/HUMAN-UAT · ✅ green · ❌ red · ⚠️ flaky*

Sampling continuity check: across the 8 plans no run of 3 consecutive
code-producing tasks lacks an automated verify — every `auto`/`tdd` task above
carries an `<automated>` command (build, build-for-testing, lint, or
`xcodebuild test`). The only non-automated rows are the three
`checkpoint:human-verify` tasks (05-05-04, 05-06-03, 05-08-03), each preceded
and followed by automated rows.

---

## Wave 0 Requirements

Wave 0 is plan 01. It landed the contract changes + the full RED test scaffold.
All of the following exist (reconciled 2026-05-17 — every file verified on
disk; the suites all turned GREEN in their owning plans):

- [x] `validationLedgerTests/KYC/KYCUploaderTests.swift` — RED stub for UPL-01 → GREEN plan 04
- [x] `validationLedgerTests/KYC/KYCUploaderResumeTests.swift` — RED stub for UPL-02 → GREEN plan 04
- [x] `validationLedgerTests/KYC/KYCUploaderRetryTests.swift` — RED stub for UPL-03 → GREEN plan 04
- [x] `validationLedgerTests/KYC/KYCUploaderProgressTests.swift` — RED stub for UPL-04 → GREEN plan 04
- [x] `validationLedgerTests/KYC/KYCUploaderIdempotencyTests.swift` — RED stub for SC-5 → GREEN plan 04
- [x] `validationLedgerTests/KYC/GPSMetadataInjectorTests.swift` — RED stub for KYC-04/SC-1 → GREEN plan 03
- [x] `validationLedgerTests/KYC/KYCSessionStoreTests.swift` — RED stub for KYC-06 → GREEN plan 02
- [x] `validationLedgerTests/KYC/KYCStatusViewModelTests.swift` — RED stub for KYC-05 → GREEN plan 06
- [x] `validationLedgerTests/KYC/KYCReviewViewModelTests.swift` — RED stub for KYC-01 (Review) → GREEN plan 06
- [x] `validationLedgerTests/KYC/RejectionReasonCodeTests.swift` — RED stub for D-11 → GREEN plan 02
- [x] `validationLedgerTests/KYC/GeoContextTests.swift` — RED stub for Pitfall 5 → GREEN plan 03
- [x] `validationLedgerTests/KYC/FaceQualityGateTests.swift` — RED stub for KYC-02 → GREEN plan 03
- [x] `validationLedgerTests/KYC/DLExtractionFormatTests.swift` — RED stub for KYC-03 → GREEN plan 05
- [x] `validationLedgerTests/KYC/KYCCoordinatorTests.swift` — RED stub for KYC-01 → GREEN plan 05
- [x] `validationLedgerTests/KYC/BackgroundUploadSchedulingTests.swift` — RED stub for UPL-05 → GREEN plan 07
- [x] `validationLedgerDeviceTests/DLExtractionScannerDeviceTests.swift` — RED device-test scaffold for KYC-03 DataScanner → GREEN (smoke) plan 05
- [x] `validationLedgerTests/Networking/APIClientEndpointTests.swift` — extended with the OTP-verify `kycStatus` regression test + the `KYCSubmitEndpoint` decode test
- [x] 6 new JSON fixtures (`kyc-status-{pending,under-review,verified,rejected}.json`, `kyc-submit-{success,failure}.json`) + the updated `otp-verify-success.json` — all present under `validationLedgerTests/Networking/Fixtures/` (the extra `kyc-status-success/failure.json` are additional KYC-status fixtures, not skeleton placeholders)

`SessionRestoreServiceTests.swift` is created/extended by plan 07 (not Wave 0) —
it tests `Auth/` code that plan 07 itself authors, so it lives with that plan,
not the RED scaffold.

*No new test framework install needed — Swift Testing + XCTest are already in
the repo. Phase 5 installed zero packages (RESEARCH Package Legitimacy Audit).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Live face-capture (manual shutter, Vision face-quality gate enabling the shutter) | KYC-02 | `AVCaptureSession` / camera frames do not exist on the iOS Simulator (RESEARCH Pitfall 1) — the gate *logic* is unit-tested (`FaceQualityGateTests`), but the live capture surface needs real hardware. Note: the D-04 hands-free auto-fire was superseded by a manual shutter at the 05-06 checkpoint; the Vision gate now gates the shutter-enabled state. | Confirmed at the 05-06 Task 3 device cycle: position face on a physical iPhone, confirm the quality gate enables the manual shutter and the photo captures. |
| DL-front DataScanner OCR: live text recognition extracting name/DL#/expiry | KYC-03 | `DataScannerViewController` reports `ScanningUnavailable` on the simulator (RESEARCH Pitfall 1). `DLExtractionScannerDeviceTests` device-CI test covers only the `isSupported`/`isAvailable` smoke check + VC instantiation + the recognized-text→DL-field heuristic; the real OCR extraction is not assertable without a physical license in front of a real camera | Confirmed at the 05-06 Task 3 device cycle: scan a real driver's license on a physical iPhone, confirm name/DL#/expiry extract and render READ-ONLY on the extraction screen. |
| iPad camera-preview rotation rendering natively | KYC-01 (iPad) | Camera preview-layer orientation (`videoRotationAngle`) only manifests with a live `AVCaptureSession` on real hardware (RESEARCH Pitfall 7) | Confirmed at the 05-06 Task 3 device cycle: rotate a physical iPad during a capture screen, confirm the preview rotates correctly and chrome renders natively. |
| Camera-permission-denied inline failure copy | KYC-02 | Requires toggling the OS camera permission in Settings, which the simulator's permission model does not exercise the same way. Note: `CameraPermissionViewController` exists but is currently not presented — denied camera permission shows inline `.failed` copy (carried open product decision, STATE.md Blockers — wire the blocking screen vs. keep inline copy). | Deny camera access in Settings on a physical iPhone, relaunch, confirm the inline "Camera access needed" copy is shown. |
| Review thumbnail grid + 4 status-state visual rendering | KYC-01 / KYC-05 | Visual layout / badge rendering / SF-Symbol + color correctness is a human visual check; the state *logic* is unit-tested (`KYCReviewViewModelTests`, `KYCStatusViewModelTests`) | Confirmed at the 05-06 Task 3 checkpoint: drove the Review grid + status fixtures, confirmed badges, gated Submit, reason copy reads as human English. |
| SC-2: force-quit mid-6MB-upload resumes from last committed chunk (real process lifecycle) | UPL-02 | A real app-kill + relaunch cannot be simulated in `xcodebuild test`. `KYCUploaderResumeTests` proves the resume *logic* on the simulator; `KYCForceQuitResumeDeviceTests` proves the pipeline + persistence on real hardware with a real 6 MB payload; the full end-to-end UX needs a human force-quit | Plan 08 Task 3 checkpoint, step 1: force-quit during a 6 MB upload on a physical iPhone, relaunch, confirm the progress bar restores (not 0%) and the artifact commits. |
| SC-4: background-upload completion under real OS suspension via BGProcessingTaskRequest | UPL-05 | iOS grants `BGProcessingTaskRequest` runtime on its own schedule — not reproducible in CI. `BackgroundUploadSchedulingTests` proves the *scheduling logic* (a request is submitted when uploads are pending); end-to-end completion under real suspension is human-only | Plan 08 Task 3 checkpoint, step 2: background the app mid-upload on a physical iPhone, wait, confirm the artifact completes. |
| D-08: the KYC status screen is reachable from the role-shell Profile row | KYC-01 | The Profile-row → KYC-status-screen wiring is exercised by `KYCEndToEndIntegrationTests` only at the pipeline level; the live tap-through (Profile avatar → "Verification status" row → status screen re-fetches GET /kyc/status) is a human UI confirmation | Plan 08 Task 3 checkpoint, step 3: in the role shell, open Profile via the top-bar avatar, tap "Verification status", confirm the KYC status screen opens and re-fetches status. |
| D-12 hard gate: a non-verified account cannot reach the role shell | KYC-01 | Cold-boot/OTP-verify routing *logic* is unit-tested (`SessionRestoreServiceTests`); the end-to-end "cannot reach the role shell" UX is confirmed live | Plan 08 Task 3 checkpoint, step 4: OTP-verify a non-verified account, confirm it lands in the KYC flow, not the role shell. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-05-17 — plan 08 Task 2 reconciled this map against
the executed plans 01–08. Every code-producing task is `✅ green`; the
simulator-untestable behaviors (SC-2, SC-4, live camera/scanner, D-08 entry,
D-12 gate) are correctly routed to the device lane + the 05-08 Task 3 HUMAN-UAT
checkpoint. The 05-05-04 + 05-06-03 HUMAN-UAT items PASSED in the 05-06 device
cycle; 05-08-03 is the open Phase-5-closing checkpoint.
