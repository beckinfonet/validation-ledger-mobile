---
phase: 05-kyc-capture-upload-pipeline
plan: 12
subsystem: kyc-device-uat-automation
tags: [xcuitest, device-ci, kyc, sc-2, d-08, d-12, test-10]
requires:
  - "05-11: -KYCTestSeedForUITest launch-argument seam (nonVerified / underReview / midUpload)"
provides:
  - "SC-2 force-quit resume XCUITest (real terminate() + relaunch)"
  - "D-08 Profile tap-through XCUITest"
  - "D-12 hard-gate XCUITest"
  - "Test-10 background/foreground capture-lifecycle XCUITest"
affects:
  - "05-13: device CI lane includes these four XCUITest files"
tech-stack:
  added: []
  patterns:
    - "XCUITest on XCTest (STACK-03 — Swift Testing does not support XCUIApplication)"
    - "descendants(matching:.any)[id] trait-agnostic element lookup"
    - "executionTimeAllowance = 30 per-test hard cap (Warning 5)"
key-files:
  created:
    - validationLedgerUITests/KYCHardGateUITests.swift
    - validationLedgerUITests/KYCProfileEntryUITests.swift
    - validationLedgerUITests/KYCForceQuitResumeUITests.swift
    - validationLedgerUITests/KYCCaptureLifecycleUITests.swift
  modified: []
decisions:
  - "SC-2 XCUITest asserts the role shell + KYCStatusViewController render post-relaunch as the observable proxy — no progress accessibilityValue is reachable from the midUpload seed's landing surfaces"
  - "Test-10 XCUITest covers ONLY the background/foreground lifecycle portion; deliberate AVCaptureSessionRuntimeError injection stays a human-UAT item"
metrics:
  duration: ~9min
  completed: 2026-05-18
---

# Phase 5 Plan 12: KYC Device-UAT XCUITest Automation Summary

Four XCUITest files added to `validationLedgerUITests/` that convert four
physical-device UAT items (SC-2, D-08, D-12, Test-10 background/foreground) into
automated runs on the self-hosted device CI lane, each driven by the
`-KYCTestSeedForUITest` launch-argument seam from plan 05-11.

## What Was Built

| File | Requirement | Seed mode | What it proves |
|------|-------------|-----------|----------------|
| `KYCHardGateUITests.swift` | D-12 | `nonVerified` | A non-verified account lands on the KYC hard gate (`kyc-start-heading`) and no role tab bar of any kind is constructed (`tabBars.count == 0`). |
| `KYCProfileEntryUITests.swift` | D-08 | `underReview` | From the role shell, tapping `nav-avatar` then `profile-kyc-status` opens `KYCStatusViewController` (`kyc-status-heading`). |
| `KYCForceQuitResumeUITests.swift` | SC-2 | `midUpload` | A real `XCUIApplication().terminate()` between two `.launch()` calls — a genuine ungraceful process kill — leaves the app in an observable, non-error resumed state. |
| `KYCCaptureLifecycleUITests.swift` | Test-10 (lifecycle) | `nonVerified` | Backgrounding the capture screen via `XCUIDevice.shared.press(.home)` then `activate()` restores a working `AVCaptureSession` with a hittable `kyc-face-shutter`. |

All four files are `final class ...: XCTestCase` on `import XCTest` (STACK-03 —
XCUITest cannot move to Swift Testing), with `executionTimeAllowance = 30` and
`continueAfterFailure = false` in `setUp()`, mirroring the conventions of the
existing `RoleShellSmokeTests.swift` and `LimitedTrustBannerTests.swift`.

## Why XCUITest and Not In-Process XCTest

`validationLedgerDeviceTests` (in-process XCTest) cannot kill/relaunch/background
the app or tap live UIKit. `validationLedgerUITests` (XCUITest) runs in a separate
driver process: `terminate()` is a real ungraceful kill, `.launch()` is a real
relaunch, `XCUIDevice.shared.press(.home)` is a real OS suspension, and element
queries tap live UIKit. These four files convert the process-lifecycle and
live-UI halves of SC-2 / D-08 / D-12 / Test-10 — the exact gaps the in-process
device tests cannot cover — into automated runs.

## Key Decisions

- **SC-2 observable proxy.** The `midUpload` seed lands on the role shell, where
  no progress `accessibilityValue` is exposed — the determinate `UIProgressView`
  lives on `KYCReviewViewController` inside the active capture flow, unreachable
  from the role shell. `KYCForceQuitResumeUITests` therefore asserts the role
  shell and `KYCStatusViewController` render after the real `terminate()` +
  relaunch as the XCUITest-observable proxy for the SC-2 resume guarantee; the
  6 MB progress-bar UX confirmation stays a human-UAT item (documented in the
  file header).
- **Test-10 scope split.** `KYCCaptureLifecycleUITests` automates only the
  background/foreground lifecycle portion of Test-10. The deliberate
  `AVCaptureSessionRuntimeError` injection (a real camera hardware fault) cannot
  be forced on demand from an XCUITest and explicitly remains a human-UAT item —
  stated in the file header so a future reader does not assume Test-10 is fully
  automated.
- **Device-meaningful, simulator-clean.** `KYCCaptureLifecycleUITests` exercises
  a live `AVCaptureSession` and is meaningful only on the device CI lane (the
  simulator produces no camera frames, so the Vision gate never enables the
  shutter). All four files still compile cleanly under simulator
  `build-for-testing` so the plan 05-13 device-lane test action can include them.

## Deviations from Plan

None — plan executed exactly as written. The plan anticipated the SC-2
no-progress-accessibility-value case and instructed the documented fallback
(assert the KYC status screen renders without an error state); that path was
taken as specified.

One implementation note (not a deviation): `validationLedgerUITests` is a
`PBXFileSystemSynchronizedRootGroup` in the Xcode project, so the four new
`.swift` files are auto-included in the target — no `project.pbxproj` edit was
needed.

## Verification

- `xcodebuild build-for-testing -project validationLedger.xcodeproj -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17'` — **TEST BUILD SUCCEEDED**, 0 errors, with all four files in the target.
- `grep -c 'kyc-start-heading' KYCHardGateUITests.swift` → 3; `grep -c 'profile-kyc-status' KYCProfileEntryUITests.swift` → 3.
- `grep -c 'terminate()' KYCForceQuitResumeUITests.swift` → 7; `grep -c 'KYCTestSeedForUITest' KYCForceQuitResumeUITests.swift` → 3.
- `grep -c 'XCUIDevice.shared.press' KYCCaptureLifecycleUITests.swift` → 2; `grep -c 'kyc-face-shutter' KYCCaptureLifecycleUITests.swift` → 3.
- `KYCForceQuitResumeUITests` is the only file calling `terminate()`; `KYCCaptureLifecycleUITests` is the only file calling `XCUIDevice.shared.press`.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | `7596d78` | D-12 hard-gate + D-08 Profile-entry XCUITests |
| 2 | `09e3e7b` | SC-2 force-quit resume XCUITest |
| 3 | `c1ce155` | Test-10 capture-lifecycle background/foreground XCUITest |

## Known Stubs

None.

## Self-Check: PASSED

- `validationLedgerUITests/KYCHardGateUITests.swift` — FOUND
- `validationLedgerUITests/KYCProfileEntryUITests.swift` — FOUND
- `validationLedgerUITests/KYCForceQuitResumeUITests.swift` — FOUND
- `validationLedgerUITests/KYCCaptureLifecycleUITests.swift` — FOUND
- Commit `7596d78` — FOUND
- Commit `09e3e7b` — FOUND
- Commit `c1ce155` — FOUND
