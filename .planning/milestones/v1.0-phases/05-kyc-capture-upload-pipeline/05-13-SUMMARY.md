---
phase: 05-kyc-capture-upload-pipeline
plan: 13
subsystem: kyc-device-uat-automation
tags: [device-ci, xcuitest, ci-device, kyc, sc-2, d-08, d-12, test-10, biometric-lock]
requires:
  - "05-11: -KYCTestSeedForUITest launch-argument seam"
  - "05-12: the four KYC device XCUITest files"
provides:
  - "ci-device.yml device lane runs the four KYC XCUITest classes on the device destination"
  - "05-HUMAN-UAT.md / 05-VERIFICATION.md record device-UAT automation (5 human items reduced to 2)"
  - "Cold-boot biometric lock bypass under the -KYCTestSeedForUITest seam (completes 05-11)"
affects:
  - "Future device-CI changes — the lane is class-scoped, not whole-target"
tech-stack:
  added: []
  patterns:
    - "Class-scoped -only-testing on the device lane (device-designed tests only; simulator-tuned UITests stay on the simulator lane)"
    - "UI-test seam suppresses the cold-boot biometric lock so seeded .role restores are deterministic on real hardware"
key-files:
  created: []
  modified:
    - .github/workflows/ci-device.yml
    - docs/ci.md
    - .planning/phases/05-kyc-capture-upload-pipeline/05-HUMAN-UAT.md
    - .planning/phases/05-kyc-capture-upload-pipeline/05-VERIFICATION.md
    - validationLedger/App/SceneDelegate.swift
    - validationLedgerUITests/KYCForceQuitResumeUITests.swift
decisions:
  - "Device lane is scoped to the 4 KYC XCUITest classes by name, NOT -only-testing:validationLedgerUITests — the whole target also holds RoleShellSmokeTests + LimitedTrustBannerTests, which are simulator-tuned and fail on real hardware."
  - "The -KYCTestSeedForUITest seam suppresses the cold-boot biometric lock (LAContext/Face ID) — a headless device runner cannot satisfy Face ID; the lock blocked every seeded .role-restore XCUITest. DEBUG-only, zero Release footprint."
  - "validationLedgerUITests TestableReference was already un-skipped in the shared scheme — no scheme change needed."
  - "The pre-existing validationLedgerDeviceTests biometric Face-ID hang and the runner's recurring Mac SSO keychain popup are tracked as a separate infra item — not Phase 5 scope."
patterns-established:
  - "Device CI lane: name device-designed test classes explicitly in -only-testing; never sweep a whole UITest target."
  - "Any UI-test launch seam that reaches a cold-boot .role restore must also neutralize the SESS-01 biometric lock."
requirements-completed: [SC-2, D-08, D-12, Test-10-lifecycle]
duration: ~90min (incl. checkpoint resolution)
completed: 2026-05-18
---

# Phase 05 Plan 13: Wire KYC Device XCUITests into the Device CI Lane

**The four Phase 5 KYC device XCUITests are wired into `ci-device.yml` and verified passing 4/4 on the physical device runner; the manual device-UAT burden is recorded as dropping from 5 items to 2.**

## Performance

- **Duration:** ~90 min including checkpoint resolution (Tasks 1–2 autonomous; Task 3 human-verify checkpoint required device-CI debugging)
- **Completed:** 2026-05-18
- **Tasks:** 3/3
- **Files modified:** 6

## Accomplishments

- **`ci-device.yml` runs the KYC device XCUITests.** The `device-security-surface` job's `xcodebuild test` step runs `validationLedgerDeviceTests` plus the four KYC XCUITest classes on the device destination; the `changes`-job `PATTERN` includes `validationLedgerUITests/`; `timeout-minutes` raised 25 → 35. The `device-security-surface` job name is unchanged — branch protection intact.
- **Phase tracking docs updated.** `05-HUMAN-UAT.md` and `05-VERIFICATION.md` record SC-2, D-08, D-12 and the Test-10 background/foreground portion as automated; the `human_verification` array is reduced to 2 items (SC-4 background-upload completion + the deliberate Test-10 `AVCaptureSessionRuntimeError` injection).
- **All 4 KYC XCUITests verified PASSING on the physical device** (`Beck Maldin 16`, iPhone 16) — 4/4, zero retries.

## Task Commits

1. **Task 1: wire validationLedgerUITests into the device CI lane** — `af63146` (feat)
2. **Task 2: record device-UAT automation — 5 human items reduced to 2** — `3de4b11` (docs)
3. **Task 3: human-verify checkpoint** — resolved via device verification (see below)

### Checkpoint-resolution commits

The Task 3 human-verify checkpoint surfaced three defects across the gap-closure plans; each was root-caused and fixed before the checkpoint passed:

- `0f97ee3` **fix(05-13)** — scoped the device lane to the 4 KYC XCUITest *classes*. Task 1 as planned used `-only-testing:validationLedgerUITests` (the whole target); the first device run hard-failed 7/7 because that swept in the simulator-tuned `RoleShellSmokeTests` + `LimitedTrustBannerTests`.
- `bdbcd3b` **test(05-12)** — gated `KYCForceQuitResumeUITests` taps on `isHittable` (`waitForHittable` helper). Necessary but not sufficient on its own.
- `ffd8569` **fix(05-11)** — the root-cause fix. `KYCForceQuitResumeUITests` does a real `terminate()`+`launch()`; the relaunch hits the genuine cold-boot `.role` restore path → `BiometricLockViewController` → `LAContext`/Face ID. A headless device runner cannot satisfy that prompt. The `-KYCTestSeedForUITest` seam now suppresses the cold-boot biometric lock (`presentBiometricLockIfNeeded` early-returns, `#if DEBUG`).
- `fa72922` **fix(05)** — separate Wave-1 post-merge fix: `MockOTPRoleFixtureRegistry` OTP-verify fixture missing `kyc_status: verified`, which the D-12 gate (05-07) diverted to the KYC gate, breaking `RoleShellSmokeTests` on the simulator lane.

## Verification

Device run (`Beck Maldin 16`, scoped to the 4 KYC classes, `-retry-tests-on-failure -test-iterations 2`):

| XCUITest | Requirement | Result |
|----------|-------------|--------|
| `KYCForceQuitResumeUITests` | SC-2 | ✓ passed 13.1s (first try) |
| `KYCProfileEntryUITests` | D-08 | ✓ passed 9.5s |
| `KYCHardGateUITests` | D-12 | ✓ passed 3.8s |
| `KYCCaptureLifecycleUITests` | Test-10 bg/fg | ✓ passed 29.3s |

`Executed 4 tests, with 0 failures` — `** TEST SUCCEEDED **`.

## Known Issues (tracked separately — not Phase 5 scope)

- **`validationLedgerDeviceTests` biometric Face-ID hang.** The in-process device suite contains a biometric-gated Secure Enclave test (`signWithAuthorization`) that presents an interactive Face ID prompt; on a headless runner it can hang to the 35-min job timeout. Pre-existing Phase 4 device-CI fragility (a known watch-item) — independent of Phase 5.
- **Recurring Mac SSO keychain popup** on the self-hosted runner (`Microsoft Workplace Join Key`) — a runner-hygiene liability for unattended `codesign`/keychain steps.

Both are filed as a separate device-CI infrastructure debug item.

## Self-Check: PASSED
