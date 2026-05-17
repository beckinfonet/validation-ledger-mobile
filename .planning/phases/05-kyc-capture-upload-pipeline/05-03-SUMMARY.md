---
phase: 05-kyc-capture-upload-pipeline
plan: 03
subsystem: kyc-capture
tags: [kyc, capture, geo, exif, gps, vision, avfoundation, tdd, actor, protocol]

# Dependency graph
requires:
  - phase: 03-otp-auth-role-shell-session
    provides: LocationProvider protocol + DefaultLocationProvider, LocationError, PlatformPayloadField
  - phase: 05-kyc-capture-upload-pipeline
    plan: 01
    provides: GeoContextTests / GPSMetadataInjectorTests / FaceQualityGateTests RED scaffolds
provides:
  - GeoContext actor — fresh-CLLocation cache over LocationProvider with the <30s/<=100m freshness gate
  - GPSMetadataInjector — capture-time EXIF GPS injection (AVCapturePhoto primary + CGImageDestination fallback) with zero UIKit image decode
  - CameraSession protocol + AVFoundationCameraSession — AVCaptureSession lifecycle wrapper, nonisolated isCameraAvailable hardware gate
  - FaceQualityGate protocol + VisionFaceQualityGate — pure evaluate() per-frame decision + SteadyHoldTracker D-04 auto-fire trigger
affects: [05-04, 05-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Thin actor cache over a shipped protocol — GeoContext builds ON LocationProvider, does not re-bridge CoreLocation"
    - "Pure-decision-function extraction — camera/Vision logic split so evaluate()/SteadyHoldTracker are simulator-testable behind a device-only protocol"
    - "EXIF-preserving image transform via ImageIO only — never a UIKit image decode/re-encode (RESEARCH Pitfall 6)"
    - "Injected now closure — deterministic freshness-gate testing without a real clock"

key-files:
  created:
    - validationLedger/Core/Identity/Geo/GeoContext.swift
    - validationLedger/Core/Identity/Capture/GPSMetadataInjector.swift
    - validationLedger/Core/Identity/Capture/CameraSession.swift
    - validationLedger/Core/Identity/Capture/FaceQualityGate.swift
  modified:
    - validationLedgerTests/KYC/GeoContextTests.swift
    - validationLedgerTests/KYC/GPSMetadataInjectorTests.swift
    - validationLedgerTests/KYC/FaceQualityGateTests.swift

key-decisions:
  - "evaluate() reached via the VisionFaceQualityGate concrete conformer, not the bare FaceQualityGate protocol metatype — Swift does not permit a static-member call on (any P).Type"
  - "isCameraAvailable declared nonisolated static so a caller on any actor (and the nonisolated simulator test) can branch on the hardware gate without a MainActor hop"
  - "GeoContext.gateError omits no-fix-cached as a separate error — a never-cached fix attempts one refresh then surfaces the provider's own LocationError"
  - "GPSMetadataInjector omits kCGImagePropertyGPSHPositioningError when horizontalAccuracy is negative (an invalid fix), rather than recording a negative error"

patterns-established:
  - "Capture-tier services live in Core/Identity/Capture/; the GPS/coordinate-handling file there reads CLLocation.coordinate properties only — no raw coordinate literal init, so ban_raw_coordinate_literal is not tripped outside the Geo/ allow-list"
  - "TDD gate sequence per task: test(...) RED commit then feat(...) GREEN commit, both scoped 05-03"

requirements-completed: [KYC-02, KYC-04]

# Metrics
duration: 24min
completed: 2026-05-16
---

# Phase 5 Plan 03: KYC Capture-Tier Services Summary

**The capture-tier services for Phase 5 KYC: a `GeoContext` actor that caches a fresh `CLLocation` over the shipped `LocationProvider` behind a <30s/<=100m freshness gate, a `GPSMetadataInjector` that injects EXIF GPS into captured bytes via ImageIO with zero UIKit image decode (the KYC-04 trust boundary), and `CameraSession` + `FaceQualityGate` protocol-backed services whose pure decision logic is simulator-testable while the live AVFoundation/Vision surface stays behind protocols for device CI.**

## Performance

- **Duration:** 24 min
- **Started:** 2026-05-16T22:46:00Z
- **Completed:** 2026-05-16T23:10:00Z
- **Tasks:** 3 (all TDD)
- **Files modified:** 7 (4 created, 3 RED suites turned GREEN)

## Accomplishments

- **GeoContext (KYC-04 / RESEARCH Pitfall 5):** a `public actor` thin cache over the shipped `LocationProvider`. `refresh()` caches a one-shot fix at KYC-flow start; `freshLocation()` re-validates the cached fix against the `<30s` / `0 <= accuracy <= 100m` gate at capture time and triggers exactly one refresh if it has gone stale. An injected `now` closure makes the freshness gate deterministically testable. Lives in `Core/Identity/Geo/` (the `ban_raw_coordinate_literal` allow-list directory) and reuses `LocationError` — no parallel error type.
- **GPSMetadataInjector (KYC-04 / SC-1):** capture-time EXIF GPS injection with both RESEARCH Pattern 3 paths — the primary `AVCapturePhoto.fileDataRepresentation(withReplacementMetadata:)` path and the fallback `CGImageSource`/`CGImageDestination` path for non-`AVCapturePhoto` bytes. `buildGPSDictionary` emits unsigned magnitudes + N/S/E/W ref letters, UTC date/time stamps, and `kCGImagePropertyGPSHPositioningError`. `readGPSDictionary` reads EXIF back out for the SC-1 round-trip and `KYCUploader` verification. Zero UIKit image decode/re-encode anywhere — the `grep "UIImage"` gate returns 0.
- **CameraSession (KYC-02 / KYC-04):** a `public protocol` for `AVCaptureSession` lifecycle (configure / start / stop / switch camera / capture still / preview layer) plus the `AVFoundationCameraSession` Default impl using the continuation-bridged still-capture delegate copied from `LocationProvider`. A `nonisolated static var isCameraAvailable` hardware gate returns `false` on the simulator so the capture VCs never instantiate a live session.
- **FaceQualityGate (KYC-02 / D-04):** a `public protocol` for the live gate-signal stream plus the `VisionFaceQualityGate` Default impl. The testable core is two pure pieces: `evaluate(faceBoundingBox:brightness:)` — the per-frame `noFace`/`adjust(reason)`/`pass` decision (centering tolerance 0.12, minimum face width 0.35 — RESEARCH Pattern 2) — and `SteadyHoldTracker`, the D-04 auto-fire trigger that reports `readyToFire` only after `.pass` holds continuously for the ~0.5s dwell. Liveness is intentionally NOT implemented (KYC-02 deferred from M1) — the only `liveness` mentions are comments recording the deferral.

## Task Commits

Each TDD task produced a RED `test(...)` commit and a GREEN `feat(...)` commit:

1. **Task 1: GeoContext actor** — RED `ac17145` (test) → GREEN `f204419` (feat). No refactor needed.
2. **Task 2: GPSMetadataInjector** — RED `3b0806f` (test) → GREEN `268b7c3` (feat). No refactor needed.
3. **Task 3: CameraSession + FaceQualityGate** — RED `06849d9` (test) → GREEN `deb81b5` (feat). No refactor needed.

**Plan metadata:** see final docs commit.

## Files Created/Modified

- `validationLedger/Core/Identity/Geo/GeoContext.swift` — new `public actor` fresh-CLLocation cache over `LocationProvider` with the freshness gate
- `validationLedger/Core/Identity/Capture/GPSMetadataInjector.swift` — new EXIF GPS injection utility (both injection paths + read-back helper); first file in the new `Core/Identity/Capture/` directory
- `validationLedger/Core/Identity/Capture/CameraSession.swift` — new `CameraSession` protocol + `AVFoundationCameraSession` Default impl + hardware gate
- `validationLedger/Core/Identity/Capture/FaceQualityGate.swift` — new `FaceQualityGate` protocol + `VisionFaceQualityGate` impl + pure `evaluate()` + `SteadyHoldTracker`
- `validationLedgerTests/KYC/GeoContextTests.swift` — Wave 0 RED placeholder replaced with 6 deterministic tests (StubLocationProvider + fixed `now`)
- `validationLedgerTests/KYC/GPSMetadataInjectorTests.swift` — RED placeholder replaced with 5 tests (real JPEG `Data` via `CGImageDestination`, SC-1 round-trip, hemisphere ref letters, EXIF preservation)
- `validationLedgerTests/KYC/FaceQualityGateTests.swift` — RED placeholder replaced with 11 tests (`evaluate()` pass/adjust/noFace, `SteadyHoldTracker` dwell behavior, `isCameraAvailable` simulator gate)

## Decisions Made

- `evaluate()` is reached through the `VisionFaceQualityGate` concrete conformer, not the bare `FaceQualityGate` protocol metatype. Swift does not permit a static-member call on `(any P).Type`; the pure logic still lives in the `FaceQualityGate` protocol family and is exercised without a camera, satisfying the plan's intent. See Deviation 1.
- `isCameraAvailable` is `nonisolated static` (not just `static` on the `@MainActor` class) so a caller on any actor — and the nonisolated simulator test — can branch on the hardware gate without a `MainActor` hop. See Deviation 2.
- `GeoContext` does not define a no-fix-cached error case: a never-cached `freshLocation()` attempts exactly one `refresh()` and surfaces the provider's own `LocationError` (e.g. `.timedOut`) — fail-closed, no stale/`nil` value.
- `GPSMetadataInjector` omits `kCGImagePropertyGPSHPositioningError` when `horizontalAccuracy` is negative (CoreLocation's "invalid fix" marker) rather than embedding a negative positioning error.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `evaluate()` cannot be called on the bare `FaceQualityGate` protocol metatype**
- **Found during:** Task 3 (GREEN build verification)
- **Issue:** The plan specifies `static func evaluate(...)` on a `public protocol FaceQualityGate` and the acceptance criterion references `FaceQualityGate.evaluate`. Swift does not permit calling a `static` member on a bare protocol metatype `(any FaceQualityGate).Type` — the compiler reports "static member 'evaluate' cannot be used on protocol metatype". The same affected `FaceAdjustReason` contextual-base inference in the test.
- **Fix:** Kept `evaluate()` + the tolerance constants as `static` members of the `FaceQualityGate` protocol family (a protocol extension), and changed the test call sites to reach them through the concrete `VisionFaceQualityGate` conformer (`VisionFaceQualityGate.evaluate(...)`). The pure decision logic is unchanged and is still exercised with no camera — the plan's intent ("`evaluate` and the steady-hold tracker are pure functions exercised without a camera") holds.
- **Files modified:** `validationLedgerTests/KYC/FaceQualityGateTests.swift` (5 call sites + the file header comment).
- **Verification:** `FaceQualityGateTests` GREEN (10 tests).
- **Committed in:** `deb81b5` (Task 3 GREEN commit).

**2. [Rule 3 - Blocking] `AVFoundationCameraSession.isCameraAvailable` was MainActor-isolated**
- **Found during:** Task 3 (GREEN build verification)
- **Issue:** `AVFoundationCameraSession` is `@MainActor`-isolated, so its `static var isCameraAvailable` inherited `@MainActor` isolation. The plan's `CameraSessionAvailabilityTests` runs in a nonisolated context — the compiler reported "main actor-isolated class property 'isCameraAvailable' can not be referenced from a nonisolated context". Capture VCs branching on the gate from a non-MainActor path would hit the same wall.
- **Fix:** Declared the property `public nonisolated static var isCameraAvailable` — the hardware-discovery query touches no `@MainActor` state, so making it `nonisolated` is correct and lets any caller branch on it without a hop.
- **Files modified:** `validationLedger/Core/Identity/Capture/CameraSession.swift`.
- **Verification:** `CameraSessionAvailabilityTests` GREEN; full app build succeeds.
- **Committed in:** `deb81b5` (Task 3 GREEN commit).

**3. [Rule 3 - Blocking] Simulator destination `iPhone 16` unavailable — used `iPhone 16e`**
- **Found during:** Task 1 (test verification)
- **Issue:** The plan's `<verify><automated>` commands target `platform=iOS Simulator,name=iPhone 16`; this environment's installed simulators are `iPhone 16e`, `iPhone 17`, `iPhone 17 Pro`, `iPhone 17 Pro Max`, `iPhone Air` — no plain `iPhone 16`. (Identical to plan 05-01 Deviation 1.)
- **Fix:** Ran all `xcodebuild test` / `build` verifications against `iPhone 16e`. Source/test code is destination-agnostic; only the verification destination changed.
- **Files modified:** None (verification command only).
- **Verification:** All 22 tests GREEN and `** BUILD SUCCEEDED **` on `iPhone 16e`.
- **Committed in:** N/A (no code change).

---

**Total deviations:** 3 auto-fixed (2 Swift-concurrency/metatype blockers in this plan's own code, 1 environment toolchain substitution).
**Impact on plan:** No scope creep. Deviations 1 and 2 are local Swift-language corrections to keep the delivered protocol-backed design compiling; the artifacts and behavior match the plan. Deviation 3 is the same simulator substitution recorded in plan 05-01.

## Issues Encountered

- None beyond the deviations above. All three RED scaffolds converted cleanly to GREEN; no pre-existing test regressed (full app build succeeds).

## TDD Gate Compliance

All three tasks followed the RED → GREEN cycle. For each task a `test(05-03): ...` RED commit landed first (verified failing — "Cannot find ... in scope"), followed by a `feat(05-03): ...` GREEN commit. No REFACTOR commit was needed — each GREEN implementation was already clean. Gate sequence verified in `git log`: `ac17145`(test)→`f204419`(feat), `3b0806f`(test)→`268b7c3`(feat), `06849d9`(test)→`deb81b5`(feat).

## Known Stubs

- `VisionFaceQualityGate.signals()` / `process(pixelBuffer:)` and the live `AVFoundationCameraSession` `AVCaptureSession` body are device-only surfaces. They are NOT stubs in the defect sense — they are fully implemented but cannot run on the simulator (RESEARCH Pitfall 1: `AVCaptureSession` produces no frames there). They are deliberately behind protocols so plan 05's capture VCs and plan 04's `KYCUploader` stay simulator-testable; the live path is exercised on the Phase 4 physical-device CI lane / HUMAN-UAT. This is the plan's stated design, not deferred work.

## Threat Flags

None. No new security-relevant surface beyond the plan's `<threat_model>`. `GPSMetadataInjector` (T-05-03-01) and `GeoContext` (T-05-03-02) mitigations are implemented as planned; coordinates never route through `LogField` (T-05-03-03) — no logger dependency exists in either file.

## Next Phase Readiness

- The capture-tier services are landed and GREEN. Plan 05-04 (`KYCUploader`) can consume `GPSMetadataInjector` for capture-time GPS injection and `GeoContext.freshLocation()` for the fresh fix. Plan 05-05 (capture VCs / DataScanner integration) can consume `CameraSession` and `FaceQualityGate` behind their protocols.
- `FaceQualityGate.SteadyHoldTracker` is the D-04 auto-fire signal source plan 05's face-capture screen acts on.
- The new `Core/Identity/Capture/` directory is auto-discovered by the project's `PBXFileSystemSynchronizedRootGroup` — no `project.pbxproj` edit was needed.

## Self-Check: PASSED

All created files verified on disk (GeoContext.swift, GPSMetadataInjector.swift, CameraSession.swift, FaceQualityGate.swift). All 6 task commits verified in git history (ac17145, f204419, 3b0806f, 268b7c3, 06849d9, deb81b5). All 22 tests across the 4 suites GREEN; full app build succeeds.

---
*Phase: 05-kyc-capture-upload-pipeline*
*Completed: 2026-05-16*
