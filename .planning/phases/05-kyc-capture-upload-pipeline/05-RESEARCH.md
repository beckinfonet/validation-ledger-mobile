# Phase 5: KYC Capture & Upload Pipeline - Research

**Researched:** 2026-05-16
**Domain:** iOS native capture (AVFoundation / Vision / VisionKit), EXIF GPS metadata injection (ImageIO/CoreGraphics), resumable chunked background upload (URLSession + BackgroundTasks), UIKit coordinator-driven multi-step flow
**Confidence:** MEDIUM-HIGH — codebase patterns and endpoint contracts are VERIFIED from the repo; Apple-framework behaviour is CITED from official docs and cross-verified; one architectural conflict (background-session file requirement vs. JSON-body chunk contract) is HIGH-confidence and must be resolved by the planner.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Phase boundary (do NOT re-discuss):**
- Capture flow order + 6 artifacts: face → DL front → DL back → truck → trailer → plate → review → submit (KYC-01).
- GPS-injection mechanism: `AVCapturePhoto.fileDataRepresentation()` → `CGImageDestination`, **never through `UIImage`** (ROADMAP goal + PITFALLS Pitfall 6).
- **Liveness detection is deferred from M1** — M1 captures a face meeting basic Vision quality gates (detected, centered, in focus); no liveness check.
- DL capture uses `VisionKit.DataScannerViewController`; vehicle artifacts are plain photos.
- 512 KB default chunk size (backend can override via `chunkSize` in the init response), jittered exponential backoff, 5-attempt cap, background `URLSession` + `BGProcessingTaskRequest`.
- Contract-first endpoints + 8 KYC mock fixtures already shipped in Phase 2 (NET-01/02).

**Implementation decisions (D-01 .. D-14) — copied verbatim:**
- **D-01:** Pipelined per-artifact upload. Each artifact begins uploading in the background the instant it is captured and confirmed — `init` → `chunk` loop → `commit` runs while the user keeps capturing.
- **D-02:** In-progress KYC session persists until complete or explicit cancel. Encrypted on-disk session survives cold boots indefinitely; cleared only on full submit OR explicit discard. **Logout does NOT wipe it.** Committed artifact's local copy deleted immediately after its `commit` succeeds.
- **D-03:** Review screen — Submit gated on all 6 artifacts acked. 6 thumbnails with per-artifact upload status; Submit disabled until all 6 committed; failed artifact shows inline "Retry upload" / "Retake". Submit fires only the final KYC-submission call.
- **D-04:** Face capture auto-fires on Vision quality-gate pass. Oval framing guide; Vision continuously evaluates detected / centered / in-focus; on steady hold (~0.5s) photo fires automatically with a "Hold still" cue.
- **D-05:** DL front — read-only extraction confirmation + rescan. Extracted fields shown read-only ("Looks good" / "Rescan"); failed format check auto-prompts rescan. User **cannot hand-edit** extracted fields.
- **D-06:** DL back — plain framed photo. No PDF417/AAMVA barcode scan.
- **D-07:** Per-shot "Use / Retake" preview before advancing.
- **D-08:** Status screen reachable from two entry points (post-submit + role-shell Profile row), one screen.
- **D-09:** Status refresh: fetch-on-appear + pull-to-refresh. No background polling timers.
- **D-10:** Rejection recovery: re-capture only the rejected artifacts. Verified artifacts stay verified.
- **D-11:** Rejection-reason copy: backend sends a stable code, iOS owns the copy. Planner defines a typed Swift enum, coordinates the code set with backend, provides a graceful unknown-code fallback.
- **D-12:** KYC is a hard gate before the role shell. New `AppPhase` case (e.g. `.kyc`) wired into `SceneDelegate` / `AppCoordinator.makeRoot(for:)`.
- **D-13:** KYC state cached in Keychain, refreshed via `GET /kyc/status`. `OTPVerifyEndpoint.Response` extended with a `kycStatus` field, cached alongside `session.role` / `session.userID`.
- **D-14:** Sign-out affordance in the KYC chrome — runs `LogoutService.logout(reason: .userInitiated)`, returns to phone-entry. Partial KYC session persists on disk (D-02).

### Claude's Discretion

Researcher/planner judgement (confirm during planning):
- Camera-session lifecycle — `AVCaptureSession` setup/teardown, preview-layer management, preview `UIImage` vs upload `Data` split.
- Encrypted on-disk store for KYC-06 — `Core/Storage` is currently Keychain-only; planner picks the file-store mechanism. Must honour "no sensitive data in plain files."
- `GeoContext` actor — fresh-`CLLocation` cache updated at flow start, read at capture, rejecting >30s / >100m fixes. Reuse the Phase 3 `LocationProvider` where possible.
- Background-upload wiring — reconcile `URLSessionConfiguration.background(withIdentifier:)` with `BGProcessingTaskRequest`.
- `AppPhase` shape for the KYC gate — new case vs sub-state of onboarding.
- Camera-permission-denied UX — reuse the Phase 3 GEO permission-denied pattern.
- GPS-staleness / quality-gate failure copy — planner finalizes strings.
- Idempotency-key strategy for chunk replay — `KYCUploader` supplies a *stable* key per chunk so retries dedupe.

### Deferred Ideas (OUT OF SCOPE)

- Screenshot / screen-recording block on the DL-capture screen — flag for roadmap backlog; do NOT silently expand Phase 5.
- MC/DOT entry + live FMCSA lookup — SHOULD-level, M1.5/M2.
- Liveness detection — deferred from M1; end-of-M1 decision gate.
- Active polling / push-driven status refresh — M3 (NOTIF-*).
- Tamper-evident device-signed location field (PITFALLS Pitfall 6 step 5) — M1 does EXIF-only per ROADMAP.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| KYC-01 | `Features/Onboarding/KYCCoordinator` orchestrates capture flow: face → DL front → DL back → truck → trailer → plate → review → submit | Coordinator pattern (Architecture Pattern 1), mirrors `AuthCoordinator`; flow state machine documented |
| KYC-02 | Live face capture uses Vision framework for face detection + on-screen framing guides; **liveness deferred** — quality gates only (detected, centered, in focus) | `VNDetectFaceRectanglesRequest` / `VNDetectFaceLandmarksRequest` on `AVCaptureVideoDataOutput` buffer stream (Pattern 2); auto-fire on steady gate-pass (D-04) |
| KYC-03 | DL capture uses `VisionKit.DataScannerViewController` for optical text extraction; client-side format check only | `DataScannerViewController` with `.text` recognized-data type; `isSupported`/`isAvailable` gate (Pitfall 1); read-only confirm (D-05) |
| KYC-04 | Vehicle capture (truck, trailer, plate) as separate photos; GPS metadata attached at capture time before any `UIImage` conversion | GPS-EXIF injection path (Pattern 3); `GeoContext` actor for fresh fix |
| KYC-05 | KYC status UI: Pending / Under Review / Verified / Rejected with backend rejection reasons rendered via controlled vocabulary | `KYCStatusEndpoint.Response` already returns `overallStatus` + per-artifact `rejectionReason`; reason-code enum + string-catalog mapping (D-11) |
| KYC-06 | In-progress KYC survives backgrounding/network blips via encrypted on-disk persistence in `Core/Storage`; resume from last completed step | Encrypted file store (Don't-Hand-Roll #1); `NSFileProtectionComplete` + persisted session model |
| UPL-01 | `Core/Identity/KYCUploader` uploads artifacts via the chunked NET-01 contract; chunk size default 512 KB, configurable | `KYCUploadInitEndpoint` returns `chunkSize`; `KYCUploader` actor drives `init`/`chunk`/`commit` (Pattern 4) |
| UPL-02 | Resumable uploads persist chunk state to disk; killed mid-upload resumes from last committed chunk | Per-chunk progress (`chunksAcked`/`totalChunks`) persisted in the encrypted store; resume on `KYCUploader` re-init (Pattern 4 + Pitfall 4) |
| UPL-03 | Exponential backoff with jitter on retryable failures (5xx, network errors); max 5 attempts before surfacing failure | Backoff formula (Pattern 5); existing `RetryInterceptor` is GET-only — UPL-03 needs a POST-aware retry inside `KYCUploader` (Pitfall 7) |
| UPL-04 | Upload progress reported per chunk commit (not per byte); UI surfaces a determinate `UIProgressView` | Progress from server ack only (Pitfall 3); `Progress` object updated on each `chunk` response |
| UPL-05 | Upload runs inside a `BGProcessingTaskRequest` when the app backgrounds, so in-flight uploads finish | `BGProcessingTaskRequest` + background `URLSession` reconciliation (Pattern 6, Pitfall 2) |
</phase_requirements>

## Summary

Phase 5 builds the trust-boundary subsystem of the entire product: capturing six identity/vehicle artifacts with provably-fresh GPS metadata and getting them to the backend reliably over poor connectivity. The codebase foundation is mature — Phases 1–4 already shipped the typed networking facade (`APIClient`), the four KYC endpoint contracts with 8 mock fixtures, the `LocationProvider` CoreLocation wrapper, the `AuthCoordinator` template, `LogoutService`, the `KeychainStore` with scope-based deletion, and the `IdempotencyInterceptor` that already respects caller-supplied keys "for Phase 5 replay." Phase 5 *consumes* all of this; it adds only the capture surfaces, the `KYCUploader`, a `GeoContext` actor, an encrypted on-disk store, and the `.kyc` `AppPhase` gate.

The research surfaced **one architectural conflict the planner must resolve**: the locked decision says use a background `URLSession`, but background `URLSession` upload tasks **only continue running after app suspension if they upload from a file** — `httpBody`/`Data`-based uploads are silently dropped. The existing `KYCUploadChunkEndpoint` is a JSON `POST` carrying `chunkData` as a base64 string in the body, routed through `APIClient`. Those two facts are incompatible for true background continuation. There are three viable resolutions (detailed in Pitfall 2 and Pattern 6); the planner must pick one and the choice shapes how `KYCUploader` is structured. The simplest M1-correct answer, given the app is mock-backed and there is no real backend yet, is the **foreground-`URLSession` chunk loop + `BGProcessingTaskRequest` extension** model — it satisfies UPL-05's literal wording, keeps the existing JSON chunk contract intact, and defers the file-based background-session rework to when a real backend exists. This is the recommended primary; document the tradeoff explicitly so the planner makes an informed call.

Second key finding: `DataScannerViewController` does **not** work on the simulator (returns `ScanningUnavailable`), and `AVCaptureSession` produces no real frames on the simulator. This means a large fraction of Phase 5's UI cannot be exercised by the simulator CI pipeline — capture/scanner tests belong on the physical-device CI lane established in Phase 4. The planner must structure the code so the *upload pipeline, GPS-injection, persistence, status state machine, and reason-code mapping* are all testable on the simulator (pure logic behind protocols), and only the live-camera surfaces require device CI or HUMAN-UAT.

**Primary recommendation:** Build `KYCUploader` as an `actor` in `Core/Identity/` driving the existing `init`/`chunk`/`commit` endpoints through `APIClient` with its own POST-aware jittered-retry loop (the shipped `RetryInterceptor` is GET-only and must NOT be reused for chunk POSTs). Persist a `KYCSession` model (artifact `Data` + `uploadID`s + `chunksAcked`) to a new `Core/Storage` encrypted file store protected with `NSFileProtectionComplete`. Inject GPS at the AVFoundation layer via `AVCapturePhoto.fileDataRepresentation(withReplacementMetadata:)` — the cleanest correct path, no `CGImageDestination` round-trip needed. Gate the flow behind a new `.kyc` `AppPhase` case. For UPL-05, ship the foreground-loop + `BGProcessingTaskRequest` model and record the background-`URLSession`-needs-file constraint as a known M2 follow-up.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Camera frame capture, preview layer | Client (UIKit `UIViewController` + AVFoundation) | — | Physical capture is inherently device/UI tier; CLAUDE.md mandates UIKit for camera surfaces |
| Face quality gating (detected/centered/in-focus) | Client (Vision on-device) | — | On-device Vision; no network. Liveness (the part that *would* be server-assisted) is deferred |
| DL optical text extraction | Client (VisionKit on-device) | API (authoritative re-verification) | Client extraction is a format gate only; backend re-verifies the photo (D-05) |
| GPS metadata acquisition + injection | Client (CoreLocation + ImageIO) | — | Capture-time injection must happen on-device before bytes leave |
| Chunked upload orchestration | Client (`KYCUploader` in `Core/Identity`) | API (`/kyc/upload/*` endpoints) | Client owns chunking/resume/retry; backend owns assembly + idempotency dedup |
| Idempotency / duplicate-chunk prevention | API (server-side key dedup) | Client (supplies stable key) | Per CONTEXT D-decisions + SC-5: server-side keys prevent duplicate commits; client supplies stable keys |
| In-progress KYC persistence | Client (encrypted `Core/Storage` file store) | — | Resume state is device-local; must survive cold boot (KYC-06, UPL-02) |
| KYC status / verdict | API (`GET /kyc/status` authoritative) | Client (renders, caches in Keychain) | Backend is sole authority on verification verdict; client caches `kycStatus` for fast cold-boot routing (D-13) |
| Rejection-reason vocabulary | API (stable code) | Client (owns localized copy) | D-11: backend owns the code set, iOS owns the wording |
| Background upload continuation | Client (`BGProcessingTaskRequest` + URLSession) | OS (BackgroundTasks scheduler) | iOS scheduler grants runtime; app must register + schedule (UPL-05) |

## Standard Stack

### Core

| Library / Framework | Version | Purpose | Why Standard |
|---------------------|---------|---------|--------------|
| `AVFoundation` | iOS 17 SDK (system) | `AVCaptureSession`, `AVCapturePhotoOutput`, `AVCaptureVideoDataOutput`, `AVCaptureVideoPreviewLayer` — still-photo capture + live frame stream | First-party, no dependency; the only supported way to do custom camera UI. `[CITED: developer.apple.com/documentation/avfoundation]` |
| `Vision` | iOS 17 SDK (system) | `VNDetectFaceRectanglesRequest` / `VNDetectFaceLandmarksRequest` for face quality gating on the live buffer stream | First-party on-device ML; CLAUDE.md pre-approved ("Apple Vision for liveness"). `[CITED: developer.apple.com/documentation/vision]` |
| `VisionKit` | iOS 17 SDK (system) | `DataScannerViewController` for DL optical text extraction (KYC-03) | First-party live-text scanner; CONTEXT locks it as the DL capture mechanism. iOS 16+; enhanced in iOS 17 with optical-flow tracking. `[CITED: developer.apple.com/documentation/visionkit/datascannerviewcontroller]` |
| `ImageIO` / `CoreGraphics` | iOS 17 SDK (system) | `CGImageSource` / `CGImageDestination` for EXIF GPS injection when the AVFoundation replacement-metadata path is not used | First-party; the metadata-preserving image-rewrite API. `[CITED: developer.apple.com/documentation/imageio]` |
| `CoreLocation` | iOS 17 SDK (system) | `CLLocation` freshness for capture-time GPS — consumed via the existing `LocationProvider` | Already wired in Phase 3 (`Core/Identity/Geo/LocationProvider`). `[VERIFIED: repo — Core/Identity/Geo/LocationProvider.swift]` |
| `BackgroundTasks` | iOS 17 SDK (system) | `BGTaskScheduler` + `BGProcessingTaskRequest` to acquire background runtime so in-flight uploads finish (UPL-05) | First-party; the supported background-execution API since iOS 13. `[CITED: developer.apple.com/documentation/backgroundtasks]` |
| `CryptoKit` | iOS 17 SDK (system) | `SHA256` for full-artifact `sha256` (init) and per-chunk `chunkSha256` (chunk endpoint) | First-party; the endpoint contracts already require hex SHA-256. `[CITED: developer.apple.com/documentation/cryptokit]` |
| `UIKit` | iOS 17 SDK (system) | All capture / review / status / extraction-confirmation screens | CLAUDE.md hard constraint — SwiftUI forbidden on camera surfaces. `[VERIFIED: CLAUDE.md]` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Nuke` | 13.0.2 (already pinned) | Thumbnail rendering on the Review screen and status-screen rows | Already in `Package.swift` (STACK-01); 05-UI-SPEC says reuse it. Do NOT add a new image library. `[VERIFIED: repo — Package.swift]` |
| `os_log` / `OSLogStore` (via `Core/Logging/Logger`) | system | PII-scrubbed structured logging for the upload pipeline | All logging routes through `Core/Logging/Logger` (LOG-01). Never log image bytes, DL numbers, or coordinates. `[VERIFIED: repo]` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `AVCapturePhoto.fileDataRepresentation(withReplacementMetadata:)` for GPS | `CGImageSource`→`CGImageDestination` round-trip | The `withReplacementMetadata:` overload injects GPS during the initial encode — one step, no recompression, no second decode. The `CGImageDestination` path is the fallback when you only have `Data` (e.g. a `DataScanner`-produced image) and need to add metadata after the fact. CONTEXT names `CGImageDestination` explicitly, so document both; the AVFoundation overload is the cleaner primary for the 5 plain-photo artifacts. |
| Background `URLSession` with file uploads | Foreground `URLSession` chunk loop + `BGProcessingTaskRequest` | Background-session uploads MUST be from a file and bypass `APIClient`'s interceptor chain (no Idempotency-Key injection, no cert-pinning delegate composition) — a significant rework. See Pitfall 2. |
| New encrypted file store in `Core/Storage` | SQLite / Core Data with file protection | Either works; the artifact `Data` blobs are large (multi-MB) so storing them as `NSFileProtectionComplete`-protected files on disk with a small JSON/SQLite index is simpler than blobbing them into a database. Planner's call (Claude's Discretion). |
| Hand-rolled retry loop in `KYCUploader` | Reuse `RetryInterceptor` | `RetryInterceptor` is **GET-only by design** (NET-05) — it explicitly does not retry POSTs. Chunk uploads are POSTs. UPL-03 retry must live inside `KYCUploader`. Do not reuse. |

**Installation:**
```
No new SwiftPM dependencies. All Phase 5 frameworks ship with the iOS 17 SDK.
Package.swift is unchanged — Nuke 13.0.2 + SwiftLintPlugins 0.63.2 remain the only dependencies.
```

**Version verification:** `[VERIFIED: repo — Package.swift]` confirms `Nuke 13.0.2` and `SwiftLintPlugins 0.63.2` are the only pinned packages. No registry lookup is needed because Phase 5 adds zero third-party packages — every framework is part of the Apple iOS 17 SDK shipped with Xcode. `[CITED: CLAUDE.md "pre-approved shortlist only" + 05-UI-SPEC "Phase 5 adds no new UI dependency"]`

## Package Legitimacy Audit

> Phase 5 installs **zero external packages**. All capture/upload functionality uses Apple first-party frameworks bundled with the iOS 17 SDK.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| (none) | — | — | — | — | — | No third-party packages added in Phase 5 |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

`Nuke 13.0.2` is reused (not newly installed) and was vetted when added in Phase 1 (STACK-01). The slopcheck gate is vacuously satisfied — there is nothing to install. CLAUDE.md forbids adding any dependency outside the pre-approved shortlist without explicit approval, and the 05-UI-SPEC explicitly confirms Phase 5 adds no new UI dependency.

## Architecture Patterns

### System Architecture Diagram

```
                          ┌─────────────────────────────────────────────┐
   OTP verify ───────────►│  AppCoordinator.makeRoot(for: AppPhase)      │
   (kycStatus in response)│  cold boot reads cached kycStatus (Keychain) │
                          └───────────────┬─────────────────────────────┘
                            kyc not verified│        kyc verified
                                            ▼                  ▼
                          ┌──────────────────────┐    ┌──────────────────┐
                          │  KYCCoordinator       │    │  Role shell       │
                          │  owns UINavigation-   │    │  (RoleCoordinator)│
                          │  Controller           │    └──────────────────┘
                          └──────────┬────────────┘
                                     │ pushes capture VCs in flow order
        ┌────────────────────────────┼────────────────────────────────────┐
        ▼              ▼             ▼              ▼            ▼          ▼
   FaceCapture     DLFront       DLBack        Truck       Trailer      Plate
   (AVCapture +    (DataScanner  (AVCapture)   (AVCapture) (AVCapture)  (AVCapture)
    Vision gate)    OCR)
        │              │             │              │            │          │
        │   each VC, on "Use photo" confirm, hands raw photo Data + ArtifactType
        ▼              ▼             ▼              ▼            ▼          ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │  CaptureService:  AVCapturePhoto.fileDataRepresentation(              │
   │                      withReplacementMetadata: <GPS dict>)            │
   │   GPS dict built from GeoContext actor (fresh <30s / <100m CLLocation)│
   │   → produces upload-ready Data WITH EXIF GPS  (never via UIImage)     │
   └──────────────────────────────────────┬───────────────────────────────┘
                                          │ artifact Data
                                          ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │  KYCUploader  (actor, Core/Identity)        ◄── D-01 pipelined:       │
   │   per artifact:                                 starts at capture     │
   │   1. POST /kyc/upload/init  (totalChunks, totalBytes, sha256)         │
   │   2. loop POST /kyc/upload/chunk (chunkIndex, chunkData b64,          │
   │        chunkSha256)  — stable Idempotency-Key per (uploadID,index)    │
   │        → on 5xx/network: jittered backoff, ≤5 attempts (UPL-03)       │
   │        → progress = chunksAcked/totalChunks  (UPL-04, server ack)     │
   │   3. POST /kyc/upload/commit → artifactID + status                   │
   │   4. delete local artifact copy (D-02 footprint control)             │
   └───────────────┬───────────────────────────────┬──────────────────────┘
                   │ persists after every chunk    │ all 6 committed
                   ▼                                ▼
   ┌──────────────────────────┐         ┌──────────────────────────────────┐
   │ Core/Storage encrypted   │         │ Review screen: Submit enabled     │
   │ file store               │         │ → POST final KYC submission       │
   │ (NSFileProtectionComplete│         └───────────────┬───────────────────┘
   │  KYCSession + chunk state│                         ▼
   │  survives cold boot —    │         ┌──────────────────────────────────┐
   │  KYC-06 / UPL-02 resume) │         │ KYCStatusViewController            │
   └──────────────────────────┘         │ GET /kyc/status on appear +       │
                                        │ pull-to-refresh (D-09)            │
   ┌──────────────────────────┐         │ Pending/UnderReview/Verified/     │
   │ AppDelegate registers    │         │ Rejected; reason-code → copy      │
   │ BGTaskScheduler handler  │         │ rejected → per-artifact re-capture│
   │ schedules BGProcessing-  │         └──────────────────────────────────┘
   │ TaskRequest when app     │
   │ backgrounds mid-upload   │
   │ (UPL-05)                 │
   └──────────────────────────┘
```

### Component Responsibilities

| File / Type | Layer | Responsibility |
|-------------|-------|----------------|
| `Features/Onboarding/KYC/KYCCoordinator` | Feature | Owns the KYC `UINavigationController`; sequences the 6 capture VCs → review → status; `onKYCSubmitted` callback bubbles to `AppCoordinator`. Mirrors `AuthCoordinator`. |
| `Features/Onboarding/KYC/*CaptureViewController` + ViewModels | Feature | UIKit capture surfaces. Face, DL-front (DataScanner), DL-back + 3 vehicle (plain photo). Per-shot Use/Retake preview (D-07). |
| `Features/Onboarding/KYC/KYCReviewViewController` | Feature | 6 thumbnails + per-artifact upload status; Submit gated on all-acked (D-03). |
| `Features/Onboarding/KYC/KYCStatusViewController` + ViewModel | Feature | Renders 4-state status; reason-code → copy; per-artifact re-capture (D-10); fetch-on-appear + pull-to-refresh (D-09). |
| `Core/Identity/Capture/CameraSession` | Core | `AVCaptureSession` lifecycle wrapper; preview layer; front/back device selection; produces `AVCapturePhoto`. |
| `Core/Identity/Capture/FaceQualityGate` | Core | Wraps `Vision` face requests over the `AVCaptureVideoDataOutput` buffer stream; emits detected/centered/in-focus signal for D-04 auto-fire. |
| `Core/Identity/Capture/GPSMetadataInjector` | Core | Builds `kCGImagePropertyGPSDictionary`; injects via `fileDataRepresentation(withReplacementMetadata:)` (primary) or `CGImageDestination` (fallback). |
| `Core/Identity/Geo/GeoContext` | Core | Actor; caches a fresh `CLLocation` updated at flow start via `LocationProvider`; rejects >30s / >100m fixes at read time. |
| `Core/Identity/KYCUploader` | Core | Actor; `init`/`chunk`/`commit` orchestration, jittered retry, resume, progress. |
| `Core/Storage/KYCSessionStore` (new) | Core | Encrypted on-disk store: `KYCSession` model + per-chunk state. `NSFileProtectionComplete`. |
| `App/AppDelegate` (extended) | App | Registers the `BGTaskScheduler` handler for the upload-continuation task (UPL-05). |
| `App/SceneDelegate` + `App/AppCoordinator` (extended) | App | New `.kyc` `AppPhase`; cold-boot reads cached `kycStatus`; schedules `BGProcessingTaskRequest` on background. |
| `Core/Networking/Endpoints/OTPVerifyEndpoint` (extended) | Core | `Response` gains a `kycStatus` field (D-13). |
| `Core/Networking/Endpoints/KYCSubmitEndpoint` (likely new) | Core | The final "all artifacts confirmed, submit KYC" call (D-03). Verify whether a fixture/endpoint already exists; CONTEXT lists only init/chunk/commit/status. |

### Recommended Project Structure

```
Features/Onboarding/KYC/                # sibling of Features/Onboarding/Auth/
├── KYCCoordinator.swift                # KYC-01 — owns the nav controller
├── KYCStartViewController.swift        # "Let's verify your identity" intro (UI-SPEC empty state)
├── Capture/
│   ├── FaceCaptureViewController.swift      # KYC-02 — Vision gate + auto-fire
│   ├── FaceCaptureViewModel.swift
│   ├── DLFrontScanViewController.swift      # KYC-03 — DataScannerViewController
│   ├── DLFrontExtractionViewController.swift# D-05 read-only confirm
│   ├── DLBackCaptureViewController.swift    # D-06 plain photo
│   ├── VehicleCaptureViewController.swift   # KYC-04 — reused for truck/trailer/plate
│   └── CapturePreviewViewController.swift   # D-07 Use/Retake
├── KYCReviewViewController.swift       # D-03
├── KYCReviewViewModel.swift
├── KYCStatusViewController.swift       # KYC-05
└── KYCStatusViewModel.swift

Core/Identity/                          # KYCUploader + capture services live here
├── KYCUploader.swift                   # UPL-01..04 — actor
├── Capture/
│   ├── CameraSession.swift             # AVCaptureSession wrapper
│   ├── FaceQualityGate.swift           # Vision face requests
│   └── GPSMetadataInjector.swift       # KYC-04 EXIF injection
├── Geo/
│   └── GeoContext.swift                # NEW — fresh-CLLocation actor (builds on LocationProvider)
└── KYC/
    ├── KYCSession.swift                # in-progress session model (Codable)
    ├── ArtifactUploadState.swift       # per-artifact chunk progress
    └── RejectionReasonCode.swift       # D-11 controlled-vocabulary enum

Core/Storage/
└── KYCSessionStore.swift               # NEW — encrypted file store (NSFileProtectionComplete)

App/
├── AppDelegate.swift                   # extended — BGTaskScheduler.register(...)
├── SceneDelegate.swift                 # extended — .kyc phase + BGProcessingTaskRequest schedule
└── AppCoordinator.swift                # extended — .kyc case in makeRoot

Resources/en.lproj/Localizable.strings  # rejection-reason copy + capture/quality-gate strings
```

### Pattern 1: Coordinator-driven multi-step capture flow

**What:** `KYCCoordinator` owns a single `UINavigationController`, pushes one capture VC per artifact in flow order, and exposes an `onKYCSubmitted` callback that bubbles to `AppCoordinator` (which root-swaps to the role shell).
**When to use:** The whole KYC flow — KYC-01.
**Example:**
```swift
// Pattern mirrors the SHIPPED Features/Onboarding/Auth/AuthCoordinator.swift
// [VERIFIED: repo — AuthCoordinator.swift]
@MainActor
final class KYCCoordinator {
    let rootViewController: UIViewController          // a UINavigationController
    var onKYCSubmitted: (() -> Void)?                 // bubbles to AppCoordinator
    var onSignOut: (() -> Void)?                      // D-14 — runs LogoutService

    private let nav: UINavigationController
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        let start = KYCStartViewController(/* injects KYCUploader, GeoContext, store */)
        let nav = UINavigationController(rootViewController: start)
        self.nav = nav
        self.rootViewController = nav
        // nav bar carries the D-14 sign-out affordance on every screen
    }
    // pushFaceCapture() → pushDLFront() → ... → pushReview() → pushStatus()
    // each step advances only after the per-shot Use/Retake confirm (D-07)
}
```
> **Retention note:** `AppCoordinator` must hold the `KYCCoordinator` instance — `AuthCoordinator` had exactly this bug fixed in Phase 3 (`AppCoordinator` retains `authCoordinator` or it deallocates immediately after `makeRoot`). `[VERIFIED: repo — AppCoordinator.swift comment lines 22-26]`

### Pattern 2: Vision face quality gate on a live buffer stream

**What:** Run `VNDetectFaceRectanglesRequest` (or `VNDetectFaceLandmarksRequest` for finer centering) against each `CMSampleBuffer` from an `AVCaptureVideoDataOutput`, deriving detected / centered / in-focus signals. When all hold steady ~0.5s, fire `AVCapturePhotoOutput.capturePhoto`.
**When to use:** Face capture only — KYC-02 / D-04.
**Example:**
```swift
// Source: [CITED: developer.apple.com/documentation/vision/vndetectfacerectanglesrequest]
// AVCaptureVideoDataOutput delivers CMSampleBuffers; AVCapturePhotoOutput takes the still.
func captureOutput(_ output: AVCaptureOutput,
                   didOutput sampleBuffer: CMSampleBuffer,
                   from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
    let request = VNDetectFaceRectanglesRequest { request, _ in
        guard let face = (request.results as? [VNFaceObservation])?.first else {
            self.qualityGate.update(.noFace); return
        }
        // boundingBox is normalized (0..1); centered = within tolerance of (0.5, 0.5)
        let centered = abs(face.boundingBox.midX - 0.5) < 0.12
                    && abs(face.boundingBox.midY - 0.5) < 0.12
        let largeEnough = face.boundingBox.width > 0.35   // close enough to camera
        self.qualityGate.update(centered && largeEnough ? .pass : .adjust)
    }
    try? handler.perform([request])
}
```
> Liveness (`VNDetectFaceLandmarksRequest` blink/pose analysis, depth, or a commercial SDK) is **deferred from M1** — do NOT add it. M1 ships the quality gate only. `[VERIFIED: CONTEXT.md, KYC-02]`

### Pattern 3: GPS EXIF injection without `UIImage`

**What:** Inject `kCGImagePropertyGPSDictionary` into the captured photo bytes. Two correct paths; primary is the AVFoundation replacement-metadata overload.
**When to use:** Every artifact — KYC-04. This is the product's trust boundary; PITFALLS Pitfall 6 is dedicated to it.
**Example — primary path (AVFoundation, no recompression):**
```swift
// Source: [CITED: developer.apple.com/documentation/avfoundation/avcapturephoto/
//   filedatarepresentation(withreplacementmetadata:...)]
func uploadData(from photo: AVCapturePhoto, location: CLLocation) -> Data? {
    // 1. Start from the photo's own metadata so EXIF/orientation are preserved.
    var metadata = photo.metadata
    // 2. Build the GPS dictionary. CoreGraphics expects unsigned magnitudes + ref letters.
    let gps: [String: Any] = [
        kCGImagePropertyGPSLatitude as String:  abs(location.coordinate.latitude),
        kCGImagePropertyGPSLatitudeRef as String:  location.coordinate.latitude >= 0 ? "N" : "S",
        kCGImagePropertyGPSLongitude as String: abs(location.coordinate.longitude),
        kCGImagePropertyGPSLongitudeRef as String: location.coordinate.longitude >= 0 ? "E" : "W",
        kCGImagePropertyGPSTimeStamp as String: ISO8601DateFormatter().string(from: location.timestamp),
        kCGImagePropertyGPSHPositioningError as String: location.horizontalAccuracy,
    ]
    metadata[kCGImagePropertyGPSDictionary as String] = gps
    // 3. Re-emit the file representation WITH the merged metadata. No UIImage. No recompression.
    return photo.fileDataRepresentation(withReplacementMetadata: metadata,
                                        replacementEmbeddedThumbnailPhotoFormat: nil,
                                        replacementEmbeddedThumbnailPixelBuffer: nil,
                                        replacementDepthData: nil)
}
```
**Example — fallback path (`CGImageDestination`, when you only hold `Data`):**
```swift
// Source: [CITED: developer.apple.com/documentation/imageio]
// Use this when the bytes came from somewhere other than AVCapturePhoto
// (e.g. a DataScanner-produced image) and you must add GPS after the fact.
func injectGPS(into imageData: Data, gps: [String: Any]) -> Data? {
    guard let src = CGImageSourceCreateWithData(imageData as CFData, nil),
          let uti = CGImageSourceGetType(src) else { return nil }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, uti, 1, nil) else { return nil }
    var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]) ?? [:]
    props[kCGImagePropertyGPSDictionary as String] = gps
    CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}
```
> The preview `UIImage` is rendered **separately and only for on-screen display** — it is never the upload source. Keep the preview path and the upload path strictly distinct (Claude's-Discretion item: "preview `UIImage` vs upload `Data` split").

### Pattern 4: `KYCUploader` actor — pipelined chunked upload with disk-persisted resume

**What:** An `actor` driving `init` → `chunk` loop → `commit` for one artifact at a time, persisting `chunksAcked` after every chunk so a force-quit resumes from the last committed chunk.
**When to use:** UPL-01, UPL-02, UPL-04.
**Example:**
```swift
// Drives the SHIPPED endpoint contracts through the SHIPPED APIClient.
// [VERIFIED: repo — KYCUploadInitEndpoint/ChunkEndpoint/CommitEndpoint.swift]
actor KYCUploader {
    private let apiClient: APIClient
    private let store: KYCSessionStore     // encrypted on-disk persistence

    func upload(artifact: CapturedArtifact) async throws {
        // 1. Resume-aware: if an uploadID already exists for this artifact, skip init.
        let state = store.state(for: artifact.type)
        let uploadID: String
        let chunkSize: Int
        if let existing = state, existing.uploadID != nil {
            uploadID = existing.uploadID!; chunkSize = existing.chunkSize
        } else {
            let chunks = artifact.data.chunked(into: 512 * 1024)   // UPL-01 default
            let initResp = try await apiClient.request(KYCUploadInitEndpoint(
                artifactType: artifact.type,
                totalChunks: chunks.count,
                totalBytes: artifact.data.count,
                sha256: artifact.data.sha256Hex()))
            uploadID = initResp.uploadID
            chunkSize = initResp.chunkSize          // backend may override 512 KB
            store.persist(/* new state: uploadID, chunkSize, chunksAcked: 0 */)
        }
        // 2. Chunk loop — resumes from the persisted chunksAcked.
        let chunks = artifact.data.chunked(into: chunkSize)
        for index in (store.state(for: artifact.type)?.chunksAcked ?? 0)..<chunks.count {
            try await sendChunkWithRetry(uploadID: uploadID, index: index, chunk: chunks[index])
            store.markChunkAcked(artifact.type, upTo: index + 1)   // persist AFTER server ack
        }
        // 3. Commit, then delete the local artifact copy (D-02 footprint control).
        let commit = try await apiClient.request(KYCUploadCommitEndpoint(uploadID: uploadID))
        store.markCommitted(artifact.type, artifactID: commit.artifactID)
        store.deleteLocalArtifactData(artifact.type)
    }
}
```
> **Idempotency key (Claude's-Discretion):** the chunk request must carry a *stable* `Idempotency-Key` per `(uploadID, chunkIndex)` so a retry of the *same* chunk dedupes server-side rather than committing twice (SC-5). The `IdempotencyInterceptor` already "respects a caller-supplied key" — so set the header before the request reaches the interceptor. `[VERIFIED: repo — IdempotencyInterceptor.swift "Don't overwrite a caller-supplied key (Phase 5 explicit-replay path)"]` A deterministic value such as `"<uploadID>:<chunkIndex>"` (or a UUIDv5 derived from it) is stable across retries. **Note:** `APIEndpoint` structs do not currently carry per-request headers — the planner must add a header-injection seam (per-endpoint header dictionary, or a dedicated chunk-send path) so the stable key reaches the request.

### Pattern 5: Exponential backoff with jitter, 5-attempt cap

**What:** On a 5xx or network error, retry the *same* chunk with `delay = min(cap, base · 2^attempt) · random(0.5...1.5)`, capped at 5 attempts.
**When to use:** UPL-03 — inside `KYCUploader.sendChunkWithRetry`, NOT via `RetryInterceptor` (GET-only).
**Example:**
```swift
// Source: [CITED: PITFALLS.md Pitfall 7] — full-jitter backoff prevents synchronized retry storms.
private func sendChunkWithRetry(uploadID: String, index: Int, chunk: Data) async throws {
    let base = 1.0, cap = 30.0, maxAttempts = 5
    var attempt = 0
    while true {
        do {
            _ = try await apiClient.request(KYCUploadChunkEndpoint(
                uploadID: uploadID, chunkIndex: index,
                chunkData: chunk.base64EncodedString(),
                chunkSha256: chunk.sha256Hex()))
            return
        } catch let error where isRetryable(error) {     // 5xx + URLError network cases
            attempt += 1
            guard attempt < maxAttempts else { throw KYCUploadError.retriesExhausted(index) }
            let delay = min(cap, base * pow(2, Double(attempt))) * Double.random(in: 0.5...1.5)
            try await Task.sleep(for: .seconds(delay))
        }
        // non-retryable (4xx other than 429, decoding) → throw immediately
    }
}
```
> `isRetryable` should match `NetworkError.httpError(statusCode:)` for 500–599 and `NetworkError` cases wrapping `URLError` connectivity failures. Treat `NetworkError.rateLimited` (429) per its `retryAfter` rather than the jitter schedule.

### Pattern 6: `BGProcessingTaskRequest` for upload continuation (UPL-05)

**What:** Register a background-task handler at launch; when the app backgrounds with uploads in flight, submit a `BGProcessingTaskRequest` so iOS grants runtime to finish the chunk loop.
**When to use:** UPL-05.
**Example:**
```swift
// Source: [CITED: developer.apple.com/documentation/backgroundtasks]
// In AppDelegate.didFinishLaunching — registration MUST happen before launch completes.
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.maldin.validationLedger.kyc-upload",   // also in Info.plist
    using: nil
) { task in
    Task {
        let processing = task as! BGProcessingTask
        processing.expirationHandler = { /* persist progress, KYCUploader checkpoints */ }
        await container.kycUploader.resumeAllPendingUploads()
        processing.setTaskCompleted(success: true)
    }
}

// In SceneDelegate.sceneDidEnterBackground — schedule if uploads are pending.
func scheduleUploadContinuation() {
    let request = BGProcessingTaskRequest(identifier: "com.maldin.validationLedger.kyc-upload")
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    try? BGTaskScheduler.shared.submit(request)
}
```
> **Info.plist:** add `BGTaskSchedulerPermittedIdentifiers` with the task identifier, and `UIBackgroundModes` → `processing`. Without the Info.plist declaration, `register` traps at runtime.
> **Reconciling the two mechanisms (the Claude's-Discretion question):** ROADMAP says "background `URLSessionConfiguration`"; UPL-05 says `BGProcessingTaskRequest`. These are different tools. See Pitfall 2 — they are NOT interchangeable, and the background-`URLSession` path conflicts with the current JSON chunk contract. **Recommended M1 model:** foreground `URLSession` chunk loop (through the existing `APIClient`) + `BGProcessingTaskRequest` to keep the loop alive across a background transition. This satisfies the literal UPL-05 wording, keeps the shipped contract intact, and is the right scope for a mock-backed M1.

### Anti-Patterns to Avoid

- **Routing capture bytes through `UIImage` before upload** — strips EXIF GPS silently. The product's entire fraud-detection premise depends on the GPS tag. (PITFALLS Pitfall 6.)
- **Reusing `RetryInterceptor` for chunk POSTs** — it is GET-only by deliberate design (NET-05). Chunk retry must be a separate loop in `KYCUploader`.
- **`beginBackgroundTask` as the primary background-upload strategy** — gives only ~30s; the upload "succeeds" client-side but the server never gets the final bytes. Acceptable only as a last-second flush. (PITFALLS Pitfall 7.)
- **Progress from `didSendBodyData` / `bytesWritten`** — reports buffer writes, not server acks; the bar hits 100% then hangs. Progress must be `chunksAcked / totalChunks`. (UPL-04, Pitfall 3.)
- **Persisting artifact `Data`, `uploadID`s, or chunk state to `UserDefaults` or a plain file** — violates the CLAUDE.md "no sensitive data in plain files" hard constraint and the `ban_userdefaults_tokens` SwiftLint rule. Use the `NSFileProtectionComplete` encrypted store.
- **Backoff with no jitter** — synchronized retry storms DDoS the backend when N phones reconnect together. (Pitfall 7.)
- **Hand-editable DL fields** — A13 fraud vector; the photo is authoritative (D-05).
- **SwiftUI on any camera/capture/scanner/review screen** — CLAUDE.md hard constraint.
- **Logging raw image bytes, DL numbers, or coordinates** — route everything through `Core/Logging/Logger`; coordinates may only travel as `PlatformPayloadField` (GEO-03 compile-time guarantee).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Encrypted on-disk persistence | A custom AES file format | `Data.write(to:options: .completeFileProtection)` — i.e. `NSFileProtectionComplete` | iOS encrypts files at rest tied to the passcode; rolling your own crypto is the canonical security mistake. `[CITED: developer.apple.com/documentation/foundation/filemanager]` |
| EXIF GPS injection | Manual JPEG segment parsing | `AVCapturePhoto.fileDataRepresentation(withReplacementMetadata:)` / `CGImageDestination` | EXIF/TIFF byte layout has many edge cases; ImageIO is the correct, lossless API. (Pattern 3.) |
| DL text extraction | Custom OCR | `VisionKit.DataScannerViewController` | First-party live-text with optical-flow tracking; CONTEXT locks it. |
| Face detection | Custom CV model | `Vision` `VNDetectFaceRectanglesRequest` | On-device, hardware-accelerated, free. |
| SHA-256 hashing | A bespoke hash | `CryptoKit.SHA256` | First-party; the endpoint contract already mandates hex SHA-256. |
| Background execution scheduling | Polling timers / `beginBackgroundTask` loops | `BGTaskScheduler` + `BGProcessingTaskRequest` | The supported, battery-respecting API since iOS 13. |
| Idempotency-key injection | Re-implementing header logic | The shipped `IdempotencyInterceptor` (respects caller-supplied keys) | Already built "for Phase 5 replay" — supply the stable key, let the interceptor pass it through. |
| Multi-step nav flow | A custom screen-router | The `Coordinator` pattern (`AuthCoordinator` template) | Established project pattern (ARCH-04); consistency + memory rules already documented (FOUND-03). |
| Retry/backoff on idempotent GETs | A new retry path | The shipped `RetryInterceptor` (status fetch is a GET) | `GET /kyc/status` retry is already covered by `RetryInterceptor` (NET-05, max 3). Only chunk POSTs need the new loop. |

**Key insight:** Phase 5's *novel* code is small — a `KYCUploader` actor, a `GeoContext` actor, an encrypted store, capture VCs, and the `.kyc` gate. Everything else is composition of shipped primitives and Apple frameworks. The risk is not "what to build" but "wiring it correctly" — especially the background-upload mechanism (Pitfall 2) and the EXIF path (Pitfall 6).

## Runtime State Inventory

> Phase 5 is a greenfield feature build, not a rename/refactor — a full runtime-state inventory is not the primary concern. The relevant cross-cutting state changes are:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | NEW: encrypted `KYCSession` file store under `Core/Storage` (artifact `Data`, `uploadID`s, `chunksAcked`). NEW Keychain entry `session.kycStatus` (D-13). | New code — no migration of existing data. The new Keychain key joins `KeychainScope.session` so it is wiped by `deleteAll(under: .session)` — **but D-13/D-02 interaction must be confirmed:** logout wipes `session.*` Keychain keys, yet D-02 says the on-disk KYC session must survive logout. The Keychain `kycStatus` cache and the on-disk `KYCSession` blob are *different stores* — the planner must keep the on-disk blob OUT of any logout-triggered cleanup. |
| Live service config | None — M1 is `MockURLProtocol`-backed; no real backend service config. | None. |
| OS-registered state | NEW: a `BGTaskScheduler` identifier (`com.maldin.validationLedger.kyc-upload`) must be declared in `Info.plist` `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes`. | Add Info.plist keys; register the handler in `AppDelegate`. |
| Secrets/env vars | None — no new secrets. The `Idempotency-Key` is generated client-side per chunk, not a stored secret. | None. |
| Build artifacts | None — no package or build-config rename. `Package.swift` unchanged. | None. |

**`OTPVerifyEndpoint.Response` change (D-13):** adding a `kycStatus` field changes the wire contract. The Phase 2 `otp-verify-success.json` fixture (and any role-specific fixtures) must be updated to include the new field, or decoding will fail if the field is non-optional. Make it optional or update all fixtures — the planner decides; flag it as a Wave-0 fixture task.

## Common Pitfalls

### Pitfall 1: DataScannerViewController and AVCaptureSession do not work on the simulator

**What goes wrong:** `DataScannerViewController` returns `ScanningUnavailable` on the simulator even with a simulated camera; `AVCaptureSession` produces no real frames. Tests that exercise the capture/scanner UI pass falsely or fail unhelpfully in the simulator CI lane.
**Why it happens:** No camera hardware; VisionKit explicitly rejects the simulator.
**How to avoid:** Gate every entry into a scanner/capture surface on `DataScannerViewController.isSupported && DataScannerViewController.isAvailable` (and `AVCaptureDevice` availability for plain capture). Structure the code so the *testable logic* — `KYCUploader`, `GPSMetadataInjector`, `KYCSessionStore`, the status state machine, `RejectionReasonCode` mapping — lives behind protocols and is fully simulator-testable. Camera/scanner surfaces go to the **physical-device CI lane** established in Phase 4 (CI-03) or to HUMAN-UAT. Provide a `#if DEBUG` fixture-driven seam (Phase 1/3 pattern) so the status screen and review screen can be driven in XCUITests without a camera.
**Warning signs:** A capture test in `validationLedgerTests` (the simulator target) that asserts on a captured photo; a `DataScannerViewController` instantiated without an `isSupported` guard.
`[VERIFIED: WebSearch — multiple sources confirm ScanningUnavailable on simulator; CITED: developer.apple.com/documentation/visionkit/datascannerviewcontroller/issupported]`

### Pitfall 2: Background URLSession upload tasks require a *file* — incompatible with the JSON chunk contract

**What goes wrong:** A background `URLSessionConfiguration.background(withIdentifier:)` upload task that uploads from `Data` / `httpBody` is **not resumed after app suspension** — iOS silently drops it. Apple's rule: "Upload tasks from `NSData` are not supported in background sessions"; background uploads must use `uploadTask(with:fromFile:)`. The shipped `KYCUploadChunkEndpoint` is a JSON `POST` carrying `chunkData` as a base64 string inside the request body and is routed through `APIClient` (which sets `httpBody`). So a *true* background-session upload of the current contract is impossible without rework.
**Why it happens:** The locked decision named "background `URLSessionConfiguration`" before the file-only constraint was surfaced. Background sessions also bypass `APIClient`'s interceptor chain entirely (no `Idempotency-Key` injection, no cert-pinning delegate, delegate-only completion — no async/await).
**How to avoid — three options, planner picks one:**
1. **(Recommended for M1) Foreground `URLSession` chunk loop + `BGProcessingTaskRequest`.** Keep the JSON chunk contract and `APIClient` exactly as shipped; run the chunk loop on the normal foreground session; when the app backgrounds mid-upload, a `BGProcessingTaskRequest` grants runtime to keep looping. Satisfies UPL-05's literal wording ("Upload runs inside a `BGProcessingTaskRequest` when the app backgrounds"). Simplest; zero contract change; correct for a mock-backed M1. Tradeoff: a force-kill while *not* in a granted background window pauses (not loses — the resume path covers it) the upload until next launch.
2. **Switch the chunk transport to file-based background `URLSession`.** Write each chunk to a temp file, `uploadTask(with:fromFile:)` on a background session, handle completion via `URLSessionDelegate` + `urlSession(_:didFinishEventsForBackgroundURLSession:)`, and reconstruct the Idempotency-Key/pinning behaviour on the background session manually. True OS-managed resumption. Tradeoff: large rework — the JSON `chunkData`-in-body contract would need to become a raw-file `PUT`, breaking the shipped fixtures; cert pinning + idempotency must be re-wired onto a delegate-based session.
3. **Hybrid:** foreground loop while foregrounded; on background, hand off remaining chunks to a file-based background session. Most robust, most code.
**Recommendation:** Option 1 for M1. Record options 2/3 as an explicit M2 follow-up (M2 integrates the real backend — that is the natural point to renegotiate the chunk transport).
**Warning signs:** `URLSession(configuration: .background(withIdentifier:))` combined with `uploadTask` from `Data` or with a request that has an `httpBody`; expecting `async/await` results from a background session.
`[VERIFIED: WebSearch — Apple docs + multiple sources: "Upload tasks only continue in the background if uploading from a file"; CITED: developer.apple.com/documentation/foundation/urlsession/1411638-uploadtask]`

### Pitfall 3: Progress bar that lies

**What goes wrong:** Progress derived from `URLSession`'s `didSendBodyData` (`totalBytesSent`) shows 100% while the server is still assembling, then errors. Feels broken.
**Why it happens:** Byte-level callbacks report buffer writes, not server confirmation.
**How to avoid:** Drive the `Progress` object (UPL-04) purely from the `chunk` endpoint's `chunksAcked` / `totalChunks` response — bump the determinate `UIProgressView` only when the server acks a chunk.
**Warning signs:** A `URLSessionTaskDelegate.didSendBodyData` implementation feeding the progress bar.
`[CITED: PITFALLS.md Pitfall 7 §5]`

### Pitfall 4: "Resumable" upload that restarts from zero

**What goes wrong:** Force-quit mid-upload, relaunch, and the artifact re-uploads from chunk 0 because chunk state was held only in memory.
**Why it happens:** Resume state was never persisted, or was persisted only at upload *completion*.
**How to avoid:** Persist `chunksAcked` to the encrypted store **after every server ack**, not at the end. On `KYCUploader` re-init, read the persisted `chunksAcked` and resume the loop from there (Pattern 4). SC-2 verifies exactly this with a physical-device force-quit test during a 6 MB upload.
**Warning signs:** Chunk state in an in-memory dictionary only; `store.persist(...)` called once after `commit`.
`[CITED: PITFALLS.md Pitfall 7 §1; ROADMAP SC-2]`

### Pitfall 5: Stale or wrong GPS at capture

**What goes wrong:** GPS is injected from a `CLLocation` that is 60+ seconds old, or is the *previous* capture's location, because the location read happens on a different thread/timeline than the capture.
**Why it happens:** No freshness gate; capture and location reads race.
**How to avoid:** A `GeoContext` actor caches a fresh `CLLocation` (updated at flow start via the existing `LocationProvider`). The capture step reads the cached location synchronously and **rejects the photo if the fix is older than 30s or accuracy worse than 100m** — surfacing the UI-SPEC copy *"We couldn't confirm your location..."* and blocking capture until a fresh fix arrives. SC-1's round-trip unit test asserts the GPS value reaches the upload payload.
**Warning signs:** `CLLocationManager.location` read inline in the capture handler; no `timestamp` / `horizontalAccuracy` check before injection.
`[CITED: PITFALLS.md Pitfall 6 §3; VERIFIED: repo — LocationProvider already enforces <30s/<100m for the auth path]`

### Pitfall 6: KYCCoordinator deallocates immediately after `makeRoot`

**What goes wrong:** `AppCoordinator.makeRoot` creates a `KYCCoordinator`, installs its `rootViewController`, and the coordinator deallocates because nothing retains it — callbacks never fire.
**Why it happens:** Coordinators are reference types; only the VC is retained by the window.
**How to avoid:** `AppCoordinator` must hold a strong reference to the `KYCCoordinator` (exactly as it holds `authCoordinator`). This is a documented Phase 3 fix.
**Warning signs:** `KYCCoordinator` created as a local `let` inside `makeRoot` with no stored property.
`[VERIFIED: repo — AppCoordinator.swift lines 22-26 document the identical AuthCoordinator fix]`

### Pitfall 7: iPad camera orientation and native rendering

**What goes wrong:** `AVCaptureVideoPreviewLayer` and the captured photo come out rotated or mis-cropped on iPad, or the capture UI just scales the iPhone layout instead of rendering natively.
**Why it happens:** Preview-layer `connection.videoRotationAngle` (iOS 17+, replaces the deprecated `videoOrientation`) is not updated on rotation; iPad supports more interface orientations than iPhone.
**How to avoid:** Update the preview connection's rotation on `viewWillTransition`/orientation change; verify the captured `Data`'s EXIF orientation is correct on iPad; lay out the capture chrome with Auto Layout against the safe area (CLAUDE.md: "iPad must render natively, not just scale"). Add an iPad-landscape checkpoint to HUMAN-UAT — Phase 4 already established the iPad-landscape UAT pattern.
**Warning signs:** Hard-coded portrait frames in a capture VC; use of the deprecated `AVCaptureConnection.videoOrientation`.
`[CITED: developer.apple.com/documentation/avfoundation — videoRotationAngle is the iOS 17 API; ASSUMED for the iPad-specific failure mode based on training knowledge]`

## Code Examples

### Building the artifact chunk list + per-artifact SHA-256
```swift
// Source: [CITED: developer.apple.com/documentation/cryptokit/sha256]
import CryptoKit

extension Data {
    func sha256Hex() -> String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
    func chunked(into size: Int) -> [Data] {
        stride(from: 0, to: count, by: size).map {
            subdata(in: $0 ..< Swift.min($0 + size, count))
        }
    }
}
```

### Reason-code controlled vocabulary (D-11)
```swift
// iOS owns the copy; backend owns the stable code. Unknown codes get a graceful fallback.
enum RejectionReasonCode: String, Decodable {
    case dlFrontGlare       = "dl_front_glare"
    case dlFrontBlurry      = "dl_front_blurry"
    case dlExpired          = "dl_expired"
    case faceNotCentered    = "face_not_centered"
    case faceObscured       = "face_obscured"
    case vehiclePlateUnreadable = "vehicle_plate_unreadable"
    // ... coordinate the full set with the backend team

    var localizedCopy: String {
        switch self {
        case .dlFrontGlare:
            return NSLocalizedString("kyc.reject.dl_front_glare",
                value: "There's glare on your license. Retake it away from direct light.",
                comment: "KYC rejection reason")
        // ... one finalized sentence per code
        }
    }
    /// Graceful fallback for an unknown/unmapped code.
    static func copy(for rawCode: String) -> String {
        RejectionReasonCode(rawValue: rawCode)?.localizedCopy
            ?? NSLocalizedString("kyc.reject.generic",
                 value: "This photo needs to be retaken. Tap to try again.",
                 comment: "KYC rejection — unknown reason code")
    }
}
```

### KYC status state machine (KYC-05)
```swift
// Drives the SHIPPED KYCStatusEndpoint.Response.overallStatus string.
// [VERIFIED: repo — KYCStatusEndpoint.swift: overallStatus is "pending"|"under_review"|"verified"|"rejected"]
enum KYCOverallStatus: String, Decodable {
    case pending, underReview = "under_review", verified, rejected
}
// VC renders per the 05-UI-SPEC status-state color table:
//   pending      → .secondaryLabel + "clock" SF Symbol
//   underReview  → .secondaryLabel + "hourglass" SF Symbol
//   verified     → DS.Colors.primary checkmark + "Continue" CTA → role shell
//   rejected     → DS.Colors.destructive label + reason copy + per-artifact "Retake"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `AVCaptureConnection.videoOrientation` | `AVCaptureConnection.videoRotationAngle` (a `CGFloat`) + `RotationCoordinator` | iOS 17 | Use the iOS 17 API; the old enum is deprecated. Relevant to Pitfall 7. |
| Custom OCR / `VNRecognizeTextRequest` hand-rolled UI | `VisionKit.DataScannerViewController` | iOS 16, enhanced iOS 17 | Locked by CONTEXT for DL extraction; iOS 17 adds optical-flow tracking. |
| `UIImageJPEGRepresentation` / `jpegData()` then add metadata | `AVCapturePhoto.fileDataRepresentation(withReplacementMetadata:)` | iOS 11+ (`fileDataRepresentation`), the replacement-metadata overload also iOS 11+ | The metadata-preserving capture path; the whole point of Pitfall 6. |
| `application(_:performFetchWithCompletionHandler:)` background fetch | `BGTaskScheduler` + `BGProcessingTaskRequest` / `BGAppRefreshTaskRequest` | iOS 13 | The supported background-execution API; UPL-05 names it directly. |
| `withCheckedContinuation`-bridged delegate location reads | Same — the project's `LocationProvider` already does this | n/a | `GeoContext` should build on the existing `LocationProvider`, not re-bridge CoreLocation. |

**Deprecated/outdated:**
- `AVCaptureConnection.videoOrientation` — deprecated in iOS 17; use `videoRotationAngle`.
- `beginBackgroundTask(expirationHandler:)` as a *primary* upload strategy — never correct for multi-MB uploads; only a last-second flush.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The final "submit KYC" call (D-03) needs a **new** endpoint/fixture — CONTEXT lists only `init`/`chunk`/`commit`/`status`. | Component Responsibilities | If a submit endpoint already exists in `Core/Networking/Endpoints/`, the planner reuses it; if not, a new `KYCSubmitEndpoint` + fixture is a Wave-0 task. Low risk — easily verified by the planner reading the endpoints directory. |
| A2 | The recommended UPL-05 model is foreground-loop + `BGProcessingTaskRequest` (Pitfall 2 option 1). | Pattern 6, Pitfall 2 | If the team wants true OS-managed background resumption in M1, option 2 (file-based background session) is needed — a significant rework that breaks the shipped JSON chunk fixtures. Surface this as an explicit planner decision. |
| A3 | iPad camera orientation mis-rendering is a real failure mode for this app's capture surfaces. | Pitfall 7 | If iPad capture works first-try the checkpoint is cheap insurance; the underlying `videoRotationAngle` API guidance is CITED and correct regardless. |
| A4 | The new encrypted on-disk `KYCSession` store must be excluded from logout cleanup (D-02 says logout does not wipe the partial session, but logout *does* wipe `KeychainScope.session`). | Runtime State Inventory | If the planner accidentally routes the on-disk blob through logout cleanup, D-02 breaks. Medium risk — explicitly flagged for the planner. |
| A5 | `DataScannerViewController` text recognition is sufficient to extract DL name/number/expiry for the D-05 format gate. | Pattern (KYC-03) | DL layouts vary by US state; if DataScanner's generic text recognition cannot reliably isolate the three fields, the format gate may need `recognizedDataTypes: [.text(...)]` tuning or fall back to a looser "scan succeeded" gate. The uploaded photo is authoritative regardless (D-05), so this only affects the early-catch UX. |
| A6 | `BGProcessingTaskRequest` (not `BGAppRefreshTaskRequest`) is the right task type for upload continuation. | Pattern 6 | `BGProcessingTask` is for longer, deferrable work and is the correct choice for finishing an upload; `BGAppRefreshTask` is short (~30s). Low risk — UPL-05 names `BGProcessingTaskRequest` explicitly. |

## Open Questions

1. **Does a KYC-submit endpoint already exist?**
   - What we know: CONTEXT lists `init`/`chunk`/`commit`/`status` endpoints + 8 fixtures. D-03 says "Submit fires only the final KYC-submission call."
   - What's unclear: whether that final call has an endpoint struct + fixture, or needs creating.
   - Recommendation: planner reads `Core/Networking/Endpoints/` first; if absent, add `KYCSubmitEndpoint` + success/failure fixtures as a Wave-0 task.

2. **How does the stable per-chunk Idempotency-Key reach the request?**
   - What we know: `IdempotencyInterceptor` respects a caller-supplied `Idempotency-Key` header; `APIEndpoint` structs currently expose only `path`/`method`/`body` — no per-request headers.
   - What's unclear: the mechanism to set a per-chunk header before the interceptor runs.
   - Recommendation: planner adds a header-injection seam — either an optional `headers` dictionary on `APIEndpoint`, or a dedicated `KYCUploader` send path. Confirm with the Phase 2 endpoint conventions.

3. **`OTPVerifyEndpoint.Response.kycStatus` — optional or required, and fixture impact?**
   - What we know: D-13 extends the response; Phase 2 shipped `otp-verify-success.json` (+ role fixtures).
   - What's unclear: whether existing fixtures break on a non-optional addition.
   - Recommendation: make `kycStatus` optional with a safe default, OR update every OTP-verify fixture in the same Wave-0 task. Optional is lower-risk for backward compatibility.

4. **Background-`URLSession` vs `BGProcessingTaskRequest` — final M1 scope.**
   - What we know: ROADMAP and UPL-05 name different mechanisms; the background-session path conflicts with the JSON chunk contract (Pitfall 2).
   - What's unclear: whether M1 must demonstrate true OS-managed background resumption or the foreground-loop + `BGProcessingTaskRequest` model is acceptable.
   - Recommendation: adopt option 1 (foreground loop + `BGProcessingTaskRequest`) for M1; record options 2/3 as an M2 follow-up tied to real-backend integration. Confirm with the user during planning if SC-4's "completion notification fires" wording implies more.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| iOS 17 SDK (AVFoundation, Vision, VisionKit, ImageIO, BackgroundTasks, CryptoKit) | All capture/upload code | ✓ (CLAUDE.md: Xcode 26.4 / iOS SDK) | iOS 17 SDK | — |
| Physical iOS device with camera | Live capture, DataScanner, on-device CI for KYC-02/03 | ✓ (Phase 4 established a self-hosted Mac runner + iPhone 16 CI lane) | iPhone 16 | — |
| iOS Simulator | `KYCUploader`, `GPSMetadataInjector`, `KYCSessionStore`, status state machine, reason-code mapping tests | ✓ | — | — |
| Camera-dependent UI in simulator CI | DataScanner / AVCaptureSession surfaces | ✗ — `ScanningUnavailable`; no real frames | — | Route capture/scanner tests to the physical-device CI lane (CI-03) + HUMAN-UAT; keep logic protocol-backed and simulator-testable |
| Real backend | True end-to-end upload | ✗ (M1 is mock-backed by design) | — | `MockURLProtocol` fixtures — by design, not a gap |

**Missing dependencies with no fallback:** none — every required framework ships with the iOS 17 SDK.

**Missing dependencies with fallback:** simulator cannot run camera/scanner surfaces — covered by the physical-device CI lane (already exists, Phase 4) plus HUMAN-UAT; this is a known iOS constraint, not a project gap.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`@Suite`/`@Test`) for new unit tests; XCTest (`XCTestCase`) for UI tests — per STACK-03 `[VERIFIED: repo]` |
| Config file | none — Swift Testing needs no config; targets are `validationLedgerTests` (simulator unit), `validationLedgerUITests` (XCUITest), `validationLedgerDeviceTests` (physical-device) `[VERIFIED: repo — test target dirs]` |
| Quick run command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:validationLedgerTests/KYCUploaderTests` |
| Full suite command | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16'` (simulator) + the `ci-device.yml` device lane on merge to `main` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| KYC-01 | Coordinator sequences 6 artifacts → review → submit | unit (flow state) + UI (XCUITest, fixture-driven) | `-only-testing:validationLedgerTests/KYCCoordinatorTests` | ❌ Wave 0 |
| KYC-02 | Face quality gate emits pass on detected/centered/in-focus | unit (gate logic over stub observations) + device (live capture) | `-only-testing:validationLedgerTests/FaceQualityGateTests` | ❌ Wave 0 |
| KYC-03 | DataScanner availability gate + extracted-field format check | unit (format check) + device (live scan) | `-only-testing:validationLedgerTests/DLExtractionFormatTests` | ❌ Wave 0 |
| KYC-04 | GPS round-trips: known `CLLocation` → injected EXIF → upload payload (SC-1) | unit | `-only-testing:validationLedgerTests/GPSMetadataInjectorTests` | ❌ Wave 0 |
| KYC-05 | Status screen renders all 4 states from mock fixtures (SC-3) | unit (state machine) + UI (fixture-driven) | `-only-testing:validationLedgerTests/KYCStatusViewModelTests` | ❌ Wave 0 |
| KYC-06 | In-progress session persists + resumes from last step | unit (round-trip the encrypted store) | `-only-testing:validationLedgerTests/KYCSessionStoreTests` | ❌ Wave 0 |
| UPL-01 | `KYCUploader` runs init→chunk→commit; 512 KB default chunk | unit (MockURLProtocol) | `-only-testing:validationLedgerTests/KYCUploaderTests` | ❌ Wave 0 |
| UPL-02 | Force-quit mid-upload → resume from last committed chunk (SC-2) | unit (simulated kill) + device (real force-quit, 6 MB) | `-only-testing:validationLedgerTests/KYCUploaderResumeTests` + device lane | ❌ Wave 0 |
| UPL-03 | Backoff caps at 5 attempts on injected 5xx/network failures (SC-5) | unit | `-only-testing:validationLedgerTests/KYCUploaderRetryTests` | ❌ Wave 0 |
| UPL-04 | Progress object updates per chunk ack, not per byte | unit | `-only-testing:validationLedgerTests/KYCUploaderProgressTests` | ❌ Wave 0 |
| UPL-05 | `BGProcessingTaskRequest` scheduled on background; loop resumes (SC-4) | unit (scheduler stub) + device/HUMAN-UAT (real background) | `-only-testing:validationLedgerTests/BackgroundUploadSchedulingTests` | ❌ Wave 0 |
| SC-5 | Stress test injecting transient failures → no duplicate chunk commits | unit (MockURLProtocol counts commits per chunk) | `-only-testing:validationLedgerTests/KYCUploaderIdempotencyTests` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test ... -only-testing:validationLedgerTests/<SuiteForThisTask>`
- **Per wave merge:** full simulator suite — `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16'`
- **Phase gate:** full simulator suite green + the `ci-device.yml` physical-device lane green (camera/force-quit tests) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `validationLedgerTests/KYCUploaderTests.swift` — covers UPL-01
- [ ] `validationLedgerTests/KYCUploaderResumeTests.swift` — covers UPL-02 / SC-2 (simulator portion)
- [ ] `validationLedgerTests/KYCUploaderRetryTests.swift` — covers UPL-03 / SC-5
- [ ] `validationLedgerTests/KYCUploaderProgressTests.swift` — covers UPL-04
- [ ] `validationLedgerTests/KYCUploaderIdempotencyTests.swift` — covers SC-5 duplicate-chunk assertion
- [ ] `validationLedgerTests/GPSMetadataInjectorTests.swift` — covers KYC-04 / SC-1 round-trip
- [ ] `validationLedgerTests/KYCSessionStoreTests.swift` — covers KYC-06 persistence
- [ ] `validationLedgerTests/KYCStatusViewModelTests.swift` — covers KYC-05 4-state rendering
- [ ] `validationLedgerTests/FaceQualityGateTests.swift` + `DLExtractionFormatTests.swift` + `KYCCoordinatorTests.swift`
- [ ] `validationLedgerTests/BackgroundUploadSchedulingTests.swift` — covers UPL-05 scheduling logic
- [ ] New mock fixtures: 4 KYC-status states (`kyc-status-pending/under-review/verified/rejected.json`) + rejection-reason-code fixtures + (if needed) `kyc-submit-success/failure.json`
- [ ] Updated `otp-verify-*.json` fixtures with the new `kycStatus` field (D-13)
- [ ] `validationLedgerDeviceTests/` additions — live capture + force-quit-resume on the physical-device lane

*(The simulator portions of every SC are automatable; the live-camera and real-background-suspension portions belong to the device lane / HUMAN-UAT — see Pitfall 1.)*

## Security Domain

> `security_enforcement` is not set in `.planning/config.json` — treated as **enabled**. This phase is squarely a security-sensitive surface: it handles identity documents, biometric-adjacent face images, and precise location.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no (handled Phase 3) | KYC runs *after* OTP-verify; the `.kyc` gate consumes the existing session |
| V3 Session Management | yes | KYC state cached in Keychain alongside `session.*` (D-13); `LogoutService` is the single teardown funnel (D-14); D-02 on-disk session deliberately survives logout — confirm it is excluded from `deleteAll(under: .session)` |
| V4 Access Control | yes | KYC is a hard gate (D-12) — role shell unreachable until KYC submitted; enforced at `AppCoordinator.makeRoot` routing |
| V5 Input Validation | yes | Client-side DL format check (D-05) is defense-in-depth only — backend is authoritative; `chunkSha256` / full `sha256` verified server-side; reject unknown reason codes gracefully (D-11) |
| V6 Cryptography | yes | `CryptoKit.SHA256` for artifact + chunk hashes (never hand-roll); `NSFileProtectionComplete` for the on-disk KYC session (OS-managed at-rest encryption — never hand-roll) |
| V7 Error Handling & Logging | yes | All logging via `Core/Logging/Logger` with `PIIScrubber` (LOG-01) — never log image bytes, DL numbers, names, or coordinates; coordinates may travel only as `PlatformPayloadField` (GEO-03) |
| V8 Data Protection | yes | Zero PII in analytics/crash logs (CLAUDE.md); committed artifacts' local copies deleted immediately post-commit (D-02); no sensitive data in `UserDefaults` or plain files |
| V9 Communications | yes | All traffic over the cert-pinned `.live` session (SEC-01); ATS-strict (SEC-02). **Caveat:** a file-based background `URLSession` (Pitfall 2 option 2) would bypass the `PinningSessionDelegate` — another reason option 1 is the safer M1 choice |
| V13 API & Web Service | yes | Idempotency-keyed chunk POSTs prevent duplicate commits (SC-5); `init`/`chunk`/`commit` contract is server-authoritative |

### Known Threat Patterns for iOS KYC capture + upload

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| GPS metadata stripped → location/identity can't be correlated (fraud blind spot) | Tampering / Repudiation | Inject EXIF GPS at capture via the AVFoundation/`CGImageDestination` path; never route through `UIImage` (Pitfall 6) |
| Stale/spoofed location attached to a fresh capture | Spoofing | `GeoContext` freshness gate — reject >30s / >100m fixes (Pitfall 5) |
| In-progress KYC artifacts (DL, face) readable from device storage | Information Disclosure | `NSFileProtectionComplete` encrypted store; delete committed artifacts immediately (D-02) |
| Duplicate chunk commits from retried requests | Tampering | Stable per-chunk `Idempotency-Key`; server-side dedup (SC-5) |
| Editable DL fields used to bypass the format gate | Tampering | Read-only extraction confirmation — no hand-editing (D-05 / anti-feature A13) |
| KYC bypassed to reach the role shell | Elevation of Privilege | Hard gate at `AppCoordinator` routing (D-12); role shell unreachable until KYC submitted |
| Identity PII leaked into logs/crash reports | Information Disclosure | `PIIScrubber` middleware + `Logger`-only logging (LOG-01); compile-time `PlatformPayloadField` for coordinates (GEO-03) |
| Background-session upload bypassing cert pinning | Spoofing / MITM | Keep uploads on the pinned foreground session (Pitfall 2 option 1); if a background session is ever used, re-attach pinning |

## Project Constraints (from CLAUDE.md)

The planner MUST verify every plan against these — they have the same authority as locked decisions:

- **UIKit-first; SwiftUI forbidden on camera/KYC/scanner/BOL screens.** Every Phase 5 capture/review/status/extraction screen is a UIKit `UIViewController`. SwiftUI permitted only for non-critical surfaces (not applicable here).
- **Swift Package Manager only** — no CocoaPods, no Carthage. Phase 5 adds zero packages.
- **iOS 17.0 minimum deployment** — all APIs used must be iOS 17-available (they are).
- **iPhone + iPad, iPad renders natively (not scaled).** Capture chrome must lay out natively on iPad — see Pitfall 7.
- **Zero PII in analytics or crash logs.** No image bytes, DL numbers, names, or coordinates in any log.
- **All tokens in Keychain; all keys in Secure Enclave; no sensitive data in `UserDefaults` or plain files.** The KYC session store must use `NSFileProtectionComplete`; the `ban_userdefaults_tokens` SwiftLint rule is active.
- **Pre-approved dependency shortlist only.** AVFoundation, Apple Vision, CoreImage/ImageIO, URLSession — all pre-approved. Anything else requires explicit approval.
- **iOS never calls Anthropic directly** — not applicable to Phase 5 (no AI traffic).
- **US-only logins; client-side country pre-check via `CLLocationManager`.** Already enforced Phase 3; KYC capture reuses `LocationProvider` for GPS only.
- **Logging via `Core/Logging/Logger` only** — no `print()`, no direct `os_log()` (SwiftLint-enforced).
- **GSD workflow enforcement** — file edits go through a GSD command (this is a planning input, not an execution step).

## Sources

### Primary (HIGH confidence)
- Repo source — `Core/Networking/Endpoints/KYCUpload{Init,Chunk,Commit}Endpoint.swift`, `KYCStatusEndpoint.swift` — endpoint contracts, `ArtifactType` enum, response shapes
- Repo source — `Core/Networking/Interceptors/IdempotencyInterceptor.swift` (caller-supplied-key behaviour), `RetryInterceptor` (GET-only, NET-05)
- Repo source — `Features/Onboarding/Auth/AuthCoordinator.swift` (coordinator template), `App/AppCoordinator.swift` (retention requirement + `AppPhase`), `App/AppContainer.swift` (`makeSession` factory), `Core/Networking/NetworkClient.swift`, `App/AppDelegate.swift`
- Repo source — `Core/Identity/Geo/LocationProvider.swift` (existing `<30s/<100m` CoreLocation wrapper)
- Repo source — `Core/Storage/Keychain/*` (KeychainStore, KeychainKey, scope-based deletion)
- `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/research/PITFALLS.md` Pitfalls 6 & 7, `.planning/research/ARCHITECTURE.md` KYC data-flow
- `developer.apple.com/documentation` — AVFoundation, Vision, VisionKit/DataScannerViewController, ImageIO, BackgroundTasks, CryptoKit, URLSession `uploadTask(with:fromFile:)`

### Secondary (MEDIUM confidence)
- WebSearch — DataScannerViewController `ScanningUnavailable` on simulator (multiple corroborating sources)
- WebSearch — background `URLSession` upload tasks require a file, not `Data`/`httpBody` (Apple docs + avanderlee.com + Apple Developer Forums)
- WebSearch — `BGProcessingTaskRequest` vs background `URLSession` distinction (Apple Developer Forums + community articles)
- WebSearch — `AVCapturePhoto.fileDataRepresentation(withReplacementMetadata:)` for GPS injection (Apple docs + Medium walkthroughs)

### Tertiary (LOW confidence)
- iPad-specific camera orientation failure mode (Pitfall 7) — based on training knowledge; the `videoRotationAngle` iOS 17 API guidance itself is CITED and reliable

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all Apple first-party frameworks, versions tied to the iOS 17 SDK; zero third-party packages; codebase reuse verified directly
- Architecture: HIGH — coordinator/actor/DI patterns are established in the repo and verified; the `KYCUploader` design composes shipped endpoint contracts
- Pitfalls: HIGH for the two big ones (background-session file requirement, EXIF stripping) — cross-verified against Apple docs and multiple sources; MEDIUM for the iPad-orientation pitfall
- Background-upload mechanism: MEDIUM — the *constraint* is HIGH-confidence, but the *recommended resolution* is a scope decision the planner/user must ratify (see Open Question 4)

**Research date:** 2026-05-16
**Valid until:** 2026-06-15 (30 days — Apple frameworks are stable; re-check only if Xcode/iOS SDK majorly revs)
