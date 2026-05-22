# Phase 5: KYC Capture & Upload Pipeline - Context

**Gathered:** 2026-05-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the KYC capture-and-upload subsystem on top of the mature M1 foundation:

1. **`KYCCoordinator`** (`Features/Onboarding/KYC/`, sibling of the existing `Features/Onboarding/Auth/`) orchestrating the 6-artifact capture flow: face → DL front → DL back → truck → trailer → plate → review → submit.
2. **GPS-tagged capture** — every artifact carries EXIF GPS metadata injected at capture time via the `AVCapturePhoto.fileDataRepresentation()` → `CGImageDestination` path. **Never through `UIImage`** (it strips EXIF — research Pitfall 6). Fresh `CLLocation` (<30s age, <100m accuracy).
3. **Resumable chunked upload pipeline** (`Core/Identity/KYCUploader`, UPL-01) — 512 KB default chunks, per-chunk idempotency keys, jittered exponential backoff (5-attempt cap), background `URLSessionConfiguration` + `BGProcessingTaskRequest`, chunk state persisted to disk for force-quit resume.
4. **KYC status UI** — Pending / Under Review / Verified / Rejected, with backend-driven rejection-reason copy.

**In scope (11 requirements):** KYC-01..06, UPL-01..05.

**Locked upstream — do NOT re-discuss:**
- Capture flow order and the 6 artifacts (KYC-01).
- GPS-injection mechanism: `fileDataRepresentation()` → `CGImageDestination`, never `UIImage` (ROADMAP goal + Pitfall 6).
- **Liveness detection is deferred from M1** (PROJECT.md / KYC-02) — M1 captures a face that meets basic Vision quality gates (detected, centered, in focus), no liveness check.
- DL capture uses `VisionKit.DataScannerViewController`; vehicle artifacts are plain photos (KYC-03/04).
- 512 KB default chunk size (backend can override via `serverChunkSize`), jittered exponential backoff, 5-attempt cap, background `URLSession` + `BGProcessingTaskRequest` (UPL-01/03/05).
- Contract-first endpoints + 8 mock fixtures already shipped in Phase 2 (NET-01).

**Out of scope (fixed by ROADMAP / other phases):**
- Liveness detection — later milestone, decision gate at end of M1.
- Real backend integration — stays `MockURLProtocol`-backed per M1 convention.
- MC/DOT live FMCSA lookup — research T21 flags it SHOULD; not a KYC-01..06 / UPL-01..05 requirement.
- Push-driven status updates — M3 (NOTIF-*).

</domain>

<decisions>
## Implementation Decisions

### Upload Pipeline & Sequencing

- **D-01:** **Pipelined per-artifact upload.** Each artifact begins uploading in the background the instant it is captured and confirmed — the `init` → `chunk` loop → `commit` sequence runs while the user keeps capturing the remaining artifacts. By the time the user reaches Review, most/all chunks are already acked. This is the right fit for the "drivers on dock LTE" reality (research Pitfall 7) and naturally exercises the UPL-02 force-quit resume path.

- **D-02:** **In-progress KYC session persists until complete or explicit cancel.** The encrypted on-disk session — un-uploaded artifact `Data` + `uploadID`s + per-chunk progress — survives cold boots indefinitely. It is cleared only when all 6 artifacts are committed + the KYC is submitted, OR the user explicitly discards/cancels. **Logout does NOT wipe it** (a logged-out user resuming on the same account picks up where they left off). On-disk footprint stays naturally small because a committed artifact's local copy is deleted immediately after its `commit` succeeds.

- **D-03:** **Review screen — Submit gated on all 6 artifacts acked.** Review shows 6 thumbnails with per-artifact upload status (✓ uploaded / ⟳ uploading / ⚠ failed). The "Submit" button stays disabled until all 6 are committed. A failed artifact (UPL-03 retries exhausted) shows inline "Retry upload" and "Retake". Tapping Submit fires only the final KYC-submission call — so a submitted KYC always means "all artifacts confirmed on the backend." Background upload (UPL-05) still matters: the app may be backgrounded *during* the capture/review phase while chunks are in flight.

### Capture Interaction

- **D-04:** **Face capture auto-fires on Vision quality-gate pass.** An oval framing guide is shown; Vision continuously evaluates detected / centered / in-focus. When all gates pass and hold steady (~0.5s), the photo fires automatically with a "Hold still" cue / brief countdown. Lowest-friction — the standard ID-capture pattern (research notes KYC friction is a top abandonment driver).

- **D-05:** **DL front — read-only extraction confirmation + rescan.** After `DataScannerViewController` extracts text, the fields (name, DL number, expiry) are shown **read-only**: "Does this look right? [Looks good] / [Rescan]". If the client-side format check fails, auto-prompt a rescan. The user **cannot hand-edit** the extracted fields — the uploaded photo is authoritative, and editable identity fields are a fraud vector (research anti-feature A13). Extraction's job is the format gate + a chance to catch a bad scan early.

- **D-06:** **DL back — plain framed photo.** No PDF417/AAMVA barcode scan. KYC-03's "optical text extraction" is satisfied by the front-side OCR; the back is documentary. Keeps the capture screen consistent across 5 of 6 artifacts and avoids per-state AAMVA parsing quirks.

- **D-07:** **Per-shot "Use / Retake" preview before advancing.** After each capture, a still preview with "Use photo" / "Retake". Confirm advances to the next artifact; Retake re-opens the camera. Catches a bad shot immediately, in context, while the subject (face, cab, trailer, plate) is still present. The final Review screen is therefore a confirm-all, not the first chance to spot a problem.

### KYC Status & Rejection Recovery

- **D-08:** **Status screen reachable from two entry points, one screen.** Tapping Submit lands the user on a dedicated KYC status screen (the natural post-submit "what now?" moment). The same status screen is also reachable later from a role-shell affordance (a row in Profile — consistent with the Phase 3 D-03 top-bar avatar → modal `ProfileViewController` pattern) so the user can re-check status without re-running KYC.

- **D-09:** **Status refresh: fetch-on-appear + pull-to-refresh.** `GET /kyc/status` fires every time the status screen appears (post-submit and each open from the role shell), plus a manual pull-to-refresh. No background polling timers. M3 push notifications will later make this reactive — M1 does not simulate that.

- **D-10:** **Rejection recovery: re-capture only the rejected artifacts.** The `KYCStatusEndpoint.Response` already returns rejection per-artifact (`Artifact { artifactID, status, rejectionReason }`). The status screen lists each rejected artifact with its reason; tapping one re-opens the capture step for just that artifact, re-uploads, re-submits. Verified artifacts stay verified. Matches the research finding that specific reasons + targeted retake cut re-upload abandonment 25–30%.

- **D-11:** **Rejection-reason copy: backend sends a code, iOS owns the copy.** The backend sends a stable reason code (e.g. `dl_front_glare`) in `rejectionReason`; iOS maps each code to a finalized, localizable sentence in the string catalog (`Resources/en.lproj`). "Copy finalized in M1" (KYC-05) means the iOS team writes the copy. The planner must: (a) define the controlled-vocabulary code set as a typed Swift enum, (b) coordinate the code set with the backend, (c) provide a graceful fallback for an unknown/unmapped code.

### Flow Entry Point & Routing

- **D-12:** **KYC is a hard gate before the role shell.** After OTP-verify, if KYC is not yet verified, the app routes into `KYCCoordinator` and the role shell is unreachable until KYC is submitted. This matches the research-modelled "kyc pending → OnboardingCoordinator" gate (ARCHITECTURE.md) and the product premise — identity is verified before the user transacts. Implementation: a new `AppPhase` case (e.g. `.kyc`) wired into `SceneDelegate` / `AppCoordinator.makeRoot(for:)` — planner confirms the exact shape.

- **D-13:** **KYC state cached in Keychain, refreshed via `GET /kyc/status`.** The `OTPVerifyEndpoint.Response` is extended with a `kycStatus` field, cached in Keychain alongside the existing `session.role` / `session.userID` entries (Phase 3 D-06/D-33). Cold-boot routing reads the cached value optimistically (fast, offline-tolerant) — consistent with the Phase 3 D-04 "valid = Keychain items present, no round-trip" philosophy — then `GET /kyc/status` refreshes once routed. Once `verified`, cold-boot goes straight to the role shell.

- **D-14:** **Sign-out affordance in the KYC chrome.** Inside the gate there is no role shell, so no Profile tab / logout affordance. `KYCCoordinator`'s nav chrome carries a sign-out / cancel affordance that runs `LogoutService.logout(reason: .userInitiated)` and returns to phone-entry. The partial KYC session persists on disk (D-02) and resumes on next login. Prevents the "trapped on a screen" anti-pattern.

### Claude's Discretion

The following were not pinned in discussion and default to research/planner judgement — confirm or adjust during planning:

- **Camera-session lifecycle** — `AVCaptureSession` setup/teardown, preview-layer management, the separate preview `UIImage` vs upload `Data` split (Pitfall 6 step 1).
- **Encrypted on-disk store for KYC-06** — `Core/Storage` currently holds **only Keychain** (no file-backed store). The planner picks the mechanism (encrypted file store, or SQLite/CoreData with file protection) for the in-progress-KYC session and chunk state. Must honour the PROJECT.md constraint "no sensitive data in plain files."
- **`GeoContext` actor** — Pitfall 6 step 3 recommends a fresh-`CLLocation` actor cache updated at flow start, read synchronously at capture, rejecting photos older than 30s / accuracy worse than 100m. Planner decides the exact actor shape; reuse the Phase 3 `Core/Identity/Geo/LocationProvider` where possible.
- **Background-upload wiring** — `URLSessionConfiguration.background(withIdentifier:)`, `urlSessionDidFinishEvents(forBackgroundURLSession:)`, `BGProcessingTaskRequest` registration in `AppDelegate`, completion notification. ROADMAP says "background `URLSessionConfiguration`"; UPL-05 says `BGProcessingTaskRequest` — researcher reconciles the two mechanisms.
- **`AppPhase` shape for the KYC gate** — new enum case vs sub-state of an onboarding phase.
- **Camera-permission-denied UX** — reuse the Phase 3 GEO permission-denied pattern (D-21: blocking state + "Open Settings" deep-link).
- **GPS-staleness / quality-gate failure copy** — standard concise UIKit messaging; planner finalizes strings.
- **Idempotency-key strategy for chunk replay** — the Phase 2 `IdempotencyInterceptor` already "respects caller-supplied keys for Phase 5 replay" (NET-04). `KYCUploader` should supply a *stable* key per chunk so retries dedupe rather than create duplicate commits (UPL-03 / SC-5).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner, executor) MUST read these before planning or implementing.**

> **⚠ TechStack.md is NOT in the repo.** Prior phase CONTEXT files cite `TechStack.md §5.2` (FR-iOS-KYC) as the authoritative product spec, but the file was never committed to git and is not present. Downstream agents should rely on `REQUIREMENTS.md` (KYC-01..06, UPL-01..05) + the research docs below as the authoritative source for this phase. Do not block on TechStack.md.

### Requirements & Roadmap (authoritative)

- `.planning/REQUIREMENTS.md` lines 93–107 — KYC-01..06 (capture) + UPL-01..05 (upload pipeline). The 11 requirements this phase delivers.
- `.planning/ROADMAP.md` lines 115–127 — Phase 5 goal + 5 success criteria. This is the goal-backward target the planner verifies against.
- `.planning/PROJECT.md` — M1 scope; constraint "no sensitive data in plain files"; liveness-deferred decision.

### Research (KYC/upload-specific — high priority)

- `.planning/research/PITFALLS.md` **Pitfall 6** (lines 175–204) — KYC camera pipeline strips GPS via `UIImage`. The exact correct path: `AVCapturePhotoOutput` → `fileDataRepresentation()` → `Data`; inject `kCGImagePropertyGPSDictionary` via `CGImageSource`/`CGImageDestination`; `GeoContext` actor for fresh location; unit test that round-trips a known GPS value.
- `.planning/research/PITFALLS.md` **Pitfall 7** (lines 208–236) — Resumable upload that isn't resumable + backoff that DDOSes the backend. ≤512 KB chunks, `Idempotency-Key` per chunk, persisted chunk state, `URLSessionConfiguration.background`, progress from server ack (`chunksAcked/totalChunks`), do NOT use `beginBackgroundTask` as primary.
- `.planning/research/ARCHITECTURE.md` lines 624–652 — KYC Capture → Upload data flow; line 130 (`Core/Identity` responsibilities); lines 119/574–577 (`AppCoordinator` → `OnboardingCoordinator` KYC-gate model — informs D-12).
- `.planning/research/FEATURES.md` lines 33–36 (T4–T7), line 148 (KYC status copy quality is a cheap abandonment win — informs D-11).

### Existing endpoint contracts (Phase 2 NET-01 — already shipped)

- `validationLedger/Core/Networking/Endpoints/KYCUploadInitEndpoint.swift` — `POST /kyc/upload/init`; `ArtifactType` enum (`face`/`dl_front`/`dl_back`/`truck`/`trailer`/`plate`); request carries `totalChunks`, `totalBytes`, `sha256`; response `uploadID` + `chunkSize`.
- `validationLedger/Core/Networking/Endpoints/KYCUploadChunkEndpoint.swift` — `POST /kyc/upload/chunk`; `chunkData` base64 + `chunkSha256`; response `ackedChunk` / `chunksAcked` / `totalChunks`.
- `validationLedger/Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift` — `POST /kyc/upload/commit`; response `artifactID` + `status`.
- `validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift` — `GET /kyc/status`; response `overallStatus` + `[Artifact { artifactID, status, rejectionReason }]`.
- `validationLedger/Core/Networking/Mock/` — 8 KYC fixtures already present (`kyc-upload-{init,chunk,commit}-{success,failure}.json`, `kyc-status-{success,failure}.json`). Phase 5 will need additional fixtures for the 4 status states (under_review / verified / rejected) and the rejection-reason codes.

### Prior phase context (patterns to mirror)

- `.planning/phases/03-otp-auth-role-shell-session-the-fixed-phase-1-goal/03-CONTEXT.md` — `AuthCoordinator` pattern (D-01: owns a `UINavigationController`, callback bubbles to `AppCoordinator`) → `KYCCoordinator` mirrors it; `LogoutService` (D-16) for D-14; `SessionRestoreService.probe()` cold-boot pattern (D-04/D-05) for D-13; `KeychainStore` `session.*` keys (D-33) for D-13; GEO permission-denied UX (D-21).
- `.planning/phases/02-networking-contract-device-keys/02-CONTEXT.md` — `IdempotencyInterceptor` respects caller-supplied keys "for Phase 5 replay" (NET-04); `MockURLProtocol` fixture registry; DER X9.62 / acronym-`CodingKeys` conventions.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **KYC endpoint structs + 8 mock fixtures** — already shipped in Phase 2 (NET-01). Phase 5 *consumes* these; it does not define the wire contract. Note `KYCUploadInitEndpoint.ArtifactType` already enumerates the 6 artifacts.
- **`AuthCoordinator`** (`Features/Onboarding/Auth/AuthCoordinator.swift`) — direct structural template for `KYCCoordinator`. Same `UINavigationController` ownership, same `onAuthenticated`-style callback bubbling to `AppCoordinator`.
- **`IdempotencyInterceptor`** (Phase 2 NET-04) — already injects `Idempotency-Key` on POST and **respects caller-supplied keys** — built specifically for Phase 5 chunk-replay dedup.
- **`Core/Identity/Geo/LocationProvider`** (Phase 3) — existing `CLLocationManager` wrapper; the `GeoContext` fresh-location cache (Pitfall 6) should build on it, not duplicate it.
- **`Core/Identity/PlatformPayloadField`** (Phase 3 D-23) — the only type that can carry a `CLLocationCoordinate2D`; the GPS-injection path must route coordinates through platform-payload types, never through `LogField`/`AnalyticsField` (compile-time GEO-03 guarantee).
- **`LogoutService`** (Phase 3 D-16) — single logout funnel; D-14 sign-out calls `logout(reason: .userInitiated)`.
- **`KeychainStore`** with `session` scope + `deleteAll(under:)` — D-13 adds a `kycStatus` entry alongside `session.role` / `session.userID`.
- **`Core/Networking/APIClient`** + `MockURLProtocol` — Phase 5 calls `init`/`chunk`/`commit`/`status` through the existing facade; new background-`URLSession` config is the one networking addition.
- **PII-scrubbed structured `Logger`** — KYC logging routes through it; never log raw image bytes, DL numbers, or coordinates (Pitfall 1/6).

### Established Patterns

- **MVVM + Coordinators, initializer DI via `AppContainer`** (ARCH-04) — `KYCCoordinator`, `KYCUploader`, the camera/Vision services slot into `AppContainer` as injected deps; no singletons.
- **UIKit-only for camera/KYC surfaces** (CLAUDE.md hard constraint) — all capture, review, and status screens are UIKit `UIViewController`s. No SwiftUI on camera layers.
- **Cross-feature comms through `Core/` protocols only** (ARCH-05) — `KYCCoordinator` reaches logout/session via `Core/Auth/` services, never imports `Features/Profile/`.
- **`#if DEBUG` compile-out for dev affordances** — any KYC dev seam (e.g. fixture-state driver for UI tests) follows the Phase 1/3 pattern.
- **Contract-first + `MockURLProtocol` fixtures, TDD RED→GREEN** — fixtures land before production code; new status-state and rejection-reason fixtures needed.
- **REQUIREMENTS file paths win on conflict** — `KYCCoordinator` lives in `Features/Onboarding/` (KYC-01), `KYCUploader` in `Core/Identity/` (UPL-01). Research ARCHITECTURE.md draft-placed `KYCCoordinator` under `Core/Identity/` — REQUIREMENTS.md is authoritative; follow it.

### Integration Points

- `App/AppDelegate.swift` — register `BGProcessingTaskRequest` / background-`URLSession` handling at launch (UPL-05).
- `App/SceneDelegate.swift` + `App/AppCoordinator.swift` — new `.kyc` `AppPhase` routing (D-12); cold-boot probe extended to read cached `kycStatus` (D-13).
- `Core/Networking/Endpoints/OTPVerifyEndpoint.swift` — `Response` extended with a `kycStatus` field (D-13). Mirror the acronym-`CodingKeys` discipline from Phase 2/3.
- `Core/Storage/` — **new** encrypted on-disk store added here (currently Keychain-only) for the in-progress KYC session + chunk state (KYC-06, UPL-02).
- `Features/Onboarding/KYC/` — new sibling group to `Features/Onboarding/Auth/`: `KYCCoordinator` + capture/review/status VCs + VMs.
- `Core/Identity/` — new `KYCUploader` (UPL-01) + `GeoContext` + GPS-EXIF-injection helper alongside `DeviceFingerprint` / `Geo/`.
- `Roles/<Role>/` Profile affordance — the role-shell entry point to the KYC status screen (D-08), reached via the Phase 3 top-bar avatar → modal Profile pattern.
- `Resources/en.lproj` — rejection-reason copy strings (D-11), framing/quality-gate copy.

</code_context>

<specifics>
## Specific Ideas

- **"Pipelined, upload starts at capture"** — the user explicitly chose early per-artifact upload over batch-at-submit. The design intent: by the time the driver finishes shooting the 6th artifact on weak dock LTE, the first five are already up. Plans should reflect that upload concurrency runs *alongside* capture, not after it.
- **"Submit means everything is confirmed on the backend"** — Submit is gated on all 6 artifacts acked (D-03). The KYC-submission call is a thin finalizer, not the upload trigger.
- **Read-only DL extraction, not editable** — deliberate. The uploaded photo is authoritative; an editable DL-number field would just be a "bypass the format gate" affordance and edges toward the mutable-identity fraud vector.
- **Hard gate, but never trapped** — KYC blocks the role shell (D-12) yet always offers an in-flow sign-out (D-14). Both halves are intentional.
- **Backend code → iOS copy** for rejection reasons — the iOS team owns the wording quality (research flags this as a cheap, high-leverage abandonment win), backend owns only the stable code vocabulary.

</specifics>

<deferred>
## Deferred Ideas

- **Screenshot / screen-recording block on the DL-capture screen** — research `FEATURES.md` D6 lists "Screenshot block on DL-capture screen (KYC subset)" as M1-relevant, but it is **not** a tracked KYC-01..06 / UPL-01..05 requirement. Flag for the roadmap backlog rather than silently expanding Phase 5 scope. If the team wants it in M1, add it as an explicit requirement or a small inserted phase; otherwise it naturally joins the M3 BOL/QR screenshot-block work.
- **MC/DOT entry + live FMCSA lookup** (research T21) — SHOULD-level, not in this phase's requirements. M1.5 / M2 candidate.
- **Liveness detection** — explicitly deferred from M1 (PROJECT.md / KYC-02); decision gate at end of M1, Vision-only vs commercial SDK (research, TechStack §12 Open Q1).
- **Active polling / push-driven status refresh** — D-09 chose fetch-on-appear + pull-to-refresh for M1; push notifications make status reactive in M3 (NOTIF-*).
- **Tamper-evident signed location field** — Pitfall 6 step 5 suggests also uploading location as a separate device-signed multipart field for tamper-evidence. M1 does EXIF-only per the ROADMAP goal; revisit if backend fraud-detection wants the signed channel.

### Reviewed Todos (not folded)

None — no pending todos existed at discussion time (`todo.match-phase` returned 0 matches).

</deferred>

---

*Phase: 05-kyc-capture-upload-pipeline*
*Context gathered: 2026-05-16*
