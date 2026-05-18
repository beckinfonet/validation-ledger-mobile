---
type: todo
status: pending
created: 2026-05-18T17:37:55Z
source: 05-13 device-CI checkpoint
priority: medium
---

# Device CI infrastructure: biometric Face-ID hang + runner SSO popup

Surfaced during the Phase 5 plan 05-13 device-UAT checkpoint. **Pre-existing —
not caused by Phase 5.** Two separate runner/infra problems on the self-hosted
`ci-device.yml` lane:

## 1. `validationLedgerDeviceTests` biometric Face-ID hang

The in-process device suite contains a biometric-gated Secure Enclave test
(`signWithAuthorization`, biometric-required — a Phase 4 watch-item). On the
headless self-hosted runner the iPhone lies flat on the desk; the test triggers
a real Face ID prompt that cannot be satisfied, the
`com.apple.localauthentication` system alert sticks at "Face Not Recognized",
and the job hangs to its 35-min `timeout-minutes` ("cancelled" run).

- Observed: CI (Device) run `26045763938` hung ~3 min in, deep in
  `validationLedgerDeviceTests`, never reached the KYC XCUITests.
- The app-side equivalent (cold-boot `SessionLockService` Face ID) was fixed for
  the KYC XCUITests in `ffd8569` via a `-KYCTestSeedForUITest` seam bypass — but
  `validationLedgerDeviceTests` itself still has no headless-biometric story.
- Options to investigate: inject `SeededBiometricService` into the device-test
  AppContainer (the `SeededLAContext.swift` seam already exists but is not wired
  to all biometric device tests); or un-enroll Face ID on the runner so
  biometric-gated SE ops fail deterministically instead of prompting.

## 2. Recurring Mac SSO keychain popup on the runner

The runner Mac shows a recurring modal: *"Mac SSO Extension (Single Sign-On)
wants to access key 'Microsoft Workplace Join Key'"* requiring a manual
`login` keychain password + "Always Allow". On an unattended self-hosted runner
this will eventually block a `codesign` / keychain step.

- Fix direction: grant "Always Allow", or remove the Microsoft SSO extension
  from the runner account's login session, or run the runner under a dedicated
  CI user account without the corporate SSO profile.

## Why deferred

Both are device-CI runner-environment problems, independent of the Phase 5
KYC device-UAT automation (which is complete and verified — all 4 KYC
XCUITests pass 4/4 on the device). They warrant their own `/gsd-debug` or an
infra task. See `05-13-SUMMARY.md` "Known Issues".
