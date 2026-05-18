---
phase: 05-kyc-capture-upload-pipeline
plan: 11
subsystem: KYC test-seam composition root
tags: [debug-seam, xcuitest, kyc, launch-argument, security]
requires:
  - KYCSessionStore (Core/Storage) — locked withSession read-modify-write API
  - AppContainer DEBUG static seam pattern (uiTestLocationProvider et al.)
  - SessionRestoreProbe / DefaultSessionRestoreService cold-boot routing
  - KeychainStore session-scope keys (sessionToken / sessionRole / kycStatus)
provides:
  - "-KYCTestSeedForUITest launch argument (nonVerified / underReview / midUpload)"
  - AppContainer.KYCUITestSeed enum + AppContainer.kycTestSeed static seam
  - KYCSessionStore.seedMidUploadStateForUITest() DEBUG helper (SC-2)
affects:
  - validationLedger/App/SceneDelegate.swift
  - validationLedger/App/AppContainer.swift
  - validationLedger/Core/Storage/KYCSessionStore.swift
tech-stack:
  added: []
  patterns:
    - "#if DEBUG launch-argument test seam mirroring -MockOTPRoleForUITest"
    - "throwaway-AppContainer side-effect trigger for pre-probe Keychain seeding"
key-files:
  created: []
  modified:
    - validationLedger/App/SceneDelegate.swift
    - validationLedger/App/AppContainer.swift
    - validationLedger/Core/Storage/KYCSessionStore.swift
decisions:
  - "underReview/midUpload seed cached kycStatus=verified (not under_review) so the shipped fail-closed SessionRestoreProbe routes the seeded session to the role shell; the under_review status the 05-12 device test verifies is served by the GET /kyc/status mock route"
metrics:
  duration: ~13min
  completed: 2026-05-18
  tasks: 3
  files: 3
---

# Phase 5 Plan 11: KYC XCUITest Launch-Argument Test Seams Summary

Three `#if DEBUG`-gated test seams added to the app composition root so the plan
05-12 device XCUITests can deterministically seed the exact KYC states (non-verified,
verified/under-review, mid-upload) the 4 device-UAT items (SC-2, D-08, D-12,
Test-10) must verify — all strictly DEBUG-only with zero Release footprint.

## What Was Built

- **`KYCSessionStore.seedMidUploadStateForUITest()`** — a `#if DEBUG` helper that
  seeds a partway-through 12-chunk `.face` artifact upload (`chunksAcked == 5`,
  `committed == false`) onto the encrypted on-disk session through the locked
  `withSession(_:)` read-modify-write API. This is the SC-2 "force-quit mid-upload"
  starting state.
- **`AppContainer.KYCUITestSeed`** enum (`nonVerified` / `underReview` / `midUpload`)
  + **`AppContainer.kycTestSeed`** static seam, both `#if DEBUG`, alongside the
  existing `uiTest*` seams. The init-time `#if DEBUG` consumption block seeds
  Keychain `session`-scope state (using the shipped `KeychainStore` keys —
  `sessionToken` / `sessionRole` / `kycStatus`) and, for `.midUpload`, calls the
  Task 1 helper.
- **`SceneDelegate` `-KYCTestSeedForUITest <mode>` parsing** — a new `#if DEBUG`
  block (placed after `-MockOTPRoleForUITest`, before the `SessionRestoreProbe`
  switch) that forces `.mock` NetworkConfig, sets `AppContainer.kycTestSeed`,
  constructs one throwaway `AppContainer` to trigger the seeding side-effect, then
  deliberately falls through to the real probe switch — so the seeded Keychain
  state drives genuine routing (`nonVerified` → `.kyc` gate; `underReview` /
  `midUpload` → role shell).

## Tasks Completed

| Task | Name                                            | Commit  | Files                                          |
| ---- | ----------------------------------------------- | ------- | ---------------------------------------------- |
| 1    | KYCSessionStore DEBUG mid-upload seeding helper | 0c673b7 | validationLedger/Core/Storage/KYCSessionStore.swift |
| 2    | AppContainer DEBUG KYC test-seed seam           | bb95a13 | validationLedger/App/AppContainer.swift        |
| 3    | Parse -KYCTestSeedForUITest in SceneDelegate    | c128f1e | validationLedger/App/SceneDelegate.swift       |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1/3 - Bug] `underReview`/`midUpload` seed `kycStatus = "verified"`, not `"under_review"`**

- **Found during:** Task 2 — verifying the seam against `SessionRestoreProbe` behavior.
- **Issue:** The plan's Task 2 action and acceptance criteria literally specify
  seeding the cached `kycStatus` as `"under_review"` for the `.underReview` mode,
  "so the probe resolves `.restored`". But the shipped `DefaultSessionRestoreService.probe()`
  is a deliberate fail-closed D-13 gate (threat T-05-07-02): it routes a restored
  session to the role shell ONLY on an exact `kycStatus == "verified"` match —
  `"under_review"` (and every other non-verified value) routes to `.needsKYC`
  (the `.kyc` hard gate). Seeding `"under_review"` verbatim would make `underReview`
  land on the KYC gate, directly contradicting the plan's own `must_haves` truth
  ("under-review reaches the role shell") and the 05-12 contract (`05-12-PLAN.md`
  line 79: "`underReview` → app routes to .role shell").
- **Fix:** For `.underReview` and `.midUpload`, the init-time block seeds the
  cached `kycStatus` as `"verified"` so the probe resolves `.restored` and the
  seeded session reaches the role shell as required. The "Under Review" KYC
  status the 05-12 device test verifies is sourced from the `GET /kyc/status`
  MOCK route (which 05-12 points at an `under_review` fixture, `05-12-PLAN.md`
  line 139), not from this cached Keychain string.
- **Why not Rule 4:** Modifying `SessionRestoreProbe`'s fail-closed routing logic
  (a shipped, threat-modeled D-13 gate) would be an architectural change to a
  security-relevant component and is out of this plan's scope. Seeding `"verified"`
  is the minimal change that satisfies the load-bearing requirement (role shell
  reached) without touching the gate.
- **Files modified:** validationLedger/App/AppContainer.swift
- **Commit:** bb95a13

### Design clarification (not a deviation)

The plan's interfaces describe `AppContainer.init` consuming `kycTestSeed`, while
Task 3's `SceneDelegate` block runs `SessionRestoreProbe` (which reads Keychain)
*before* `presentRoot` builds the real `AppContainer`. To bridge this, Task 3
constructs one throwaway `AppContainer` to trigger the DEBUG seeding side-effect
before the probe runs — the exact pattern the existing `-MockOTPRoleForUITest`
block uses for its `scrubContainer` Keychain wipe. This was the plan's evident
intent (Task 2 explicitly mirrors the `-MockOTPRoleForUITest` discipline) and is
documented in the SceneDelegate code comment.

## Threat Model Compliance

All three threat-register `mitigate` dispositions are satisfied:

- **T-05-11-01 (Elevation of Privilege):** Every seam — the `SceneDelegate`
  parsing block, `AppContainer.KYCUITestSeed` + `kycTestSeed`, and
  `KYCSessionStore.seedMidUploadStateForUITest()` — is inside `#if DEBUG`. A
  `grep -rn 'KYCTestSeedForUITest\|kycTestSeed\|KYCUITestSeed\|seedMidUploadStateForUITest'`
  over `validationLedger/` confirms every real-code occurrence sits inside a
  `#if DEBUG` block. Release compiles all three to zero bytes.
- **T-05-11-02 (Spoofing):** The seam writes Keychain state only when
  `AppContainer.kycTestSeed` is non-nil, which is only ever set by the DEBUG
  `SceneDelegate` parsing block. The seeded `sessionToken` is the fixed
  non-secret placeholder `"uitest-seed-token"`.
- **T-05-11-03 (Information Disclosure):** Every seeded value — `uploadID`
  (`"uitest-seed-upload-id"`), `sha256` (a fixed 64-hex-char `"ab"×32` placeholder),
  `sessionToken` (`"uitest-seed-token"`) — is a synthetic non-secret placeholder.
  No real DL number, phone number, name, MC/DOT number, email, or coordinate is
  used. The two new log lines (`kyc_uitest_seed_applied` / `kyc_uitest_seed_failed`)
  carry empty `fields: [:]`.
- **T-05-11-SC (Tampering):** No package-manager installs; the SwiftPM dependency
  graph is unchanged.

## Verification

- **Build:** `xcodebuild build -project validationLedger.xcodeproj -scheme
  validationLedger -destination 'platform=iOS Simulator,name=iPhone 17'` — exit 0,
  zero errors, zero warnings in the three modified files. (Pre-existing Swift 6
  concurrency warnings in `CameraSession.swift` / `GPSMetadataInjector.swift` /
  `KYCCoordinator.swift` are unrelated and out of scope.)
- **Test suite:** `validationLedgerTests` — **367 passed, 0 failed** (`result:
  Passed`, via `xcresulttool`). No regression to the existing simulator suite.
- **Seam containment:** `grep -rn 'KYCTestSeedForUITest'` returns matches only
  inside `#if DEBUG` blocks (SceneDelegate:232 parsing site; AppContainer/comments).
  Same for `kycTestSeed`, `KYCUITestSeed`, `seedMidUploadStateForUITest`.

## Acceptance Criteria Status

- ✅ `KYCSessionStore.swift` has `seedMidUploadStateForUITest` inside `#if DEBUG`;
  body calls `withSession` (not `persist`, not a raw write); seeded state has
  `chunksAcked == 5`, `totalChunks == 12`, `committed == false` (strictly partial).
- ✅ `AppContainer.swift` declares `enum KYCUITestSeed` (cases `nonVerified`,
  `underReview`, `midUpload`) and `static var kycTestSeed: KYCUITestSeed?`, both
  `#if DEBUG`; the init-time consumption block is `#if DEBUG` and writes Keychain
  state via the shipped `KeychainStore` keys; `.midUpload` calls
  `seedMidUploadStateForUITest()`.
- ✅ `SceneDelegate.swift` parses `-KYCTestSeedForUITest` inside `#if DEBUG`,
  accepts `nonVerified` / `underReview` / `midUpload`, sets `kycTestSeed` +
  `currentNetworkConfigOverride = .mock`, and falls through to the probe switch
  without an early `return`.
- ✅ Build clean; existing simulator suite green (367/367).

## Self-Check: PASSED

- FOUND: validationLedger/App/SceneDelegate.swift (modified)
- FOUND: validationLedger/App/AppContainer.swift (modified)
- FOUND: validationLedger/Core/Storage/KYCSessionStore.swift (modified)
- FOUND: commit 0c673b7 (Task 1)
- FOUND: commit bb95a13 (Task 2)
- FOUND: commit c128f1e (Task 3)
