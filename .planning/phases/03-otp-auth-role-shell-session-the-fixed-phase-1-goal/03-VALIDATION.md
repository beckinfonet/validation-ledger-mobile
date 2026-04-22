---
phase: 3
slug: otp-auth-role-shell-session-the-fixed-phase-1-goal
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-21
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Sourced from 03-RESEARCH.md `## Validation Architecture` (line 1843+).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest + XCUITest (built-in, no SPM dep) |
| **Config file** | `validationLedger.xcodeproj` (existing schemes: validationLedger, validationLedgerTests, validationLedgerUITests, validationLedgerDeviceTests) |
| **Quick run command** | `xcodebuild test -project validationLedger.xcodeproj -scheme validationLedgerTests -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:validationLedgerTests/<TargetClass>` |
| **Full suite command** | `xcodebuild test -project validationLedger.xcodeproj -scheme validationLedgerTests -destination 'platform=iOS Simulator,name=iPhone 15'` (unit) + `-scheme validationLedgerUITests` (UI smoke) |
| **Estimated runtime** | ~30s unit · ~120s UI smoke (5 role tests) · device tests deferred to Phase 4 CI hardening |

---

## Sampling Rate

- **After every task commit:** Run scoped `-only-testing:` for the file under test (≤10s feedback)
- **After every plan wave:** Run full `validationLedgerTests` scheme (~30s)
- **Before `/gsd-verify-work`:** Full unit suite green + 5 UI smoke tests green + planner-flagged HUMAN-UAT items captured in VERIFICATION.md
- **Max feedback latency:** 30 seconds (unit); UI smoke runs at wave boundaries only

---

## Per-Task Verification Map

> Populated by the planner during step 8. Each task in PLAN.md frontmatter must reference a row here OR a Wave 0 stub. Format below is the contract; rows are added when plans are written.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-XX-XX | XX | X | REQ-XX | T-03-XX / — | {expected} | unit/ui/device | `{xcodebuild ...}` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

> Test stubs and fixtures Phase 3 needs before Wave 1 can produce meaningful red→green cycles.

- [ ] `validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json` — 429 + Retry-After fixture (D-02)
- [ ] `validationLedgerTests/Auth/SessionRestoreServiceTests.swift` — stubs for SESS-01 cold-boot probe
- [ ] `validationLedgerTests/Auth/SessionLockServiceTests.swift` — extend Phase 1 stubs for SESS-02/03 LockState + LockReason
- [ ] `validationLedgerTests/Auth/BiometricServiceTests.swift` — stubs for D-09 domainState diff (uses LAContextFake)
- [ ] `validationLedgerTests/Auth/SensitiveActionServiceTests.swift` — D-12 constructibility test (M1 surface)
- [ ] `validationLedgerTests/Auth/LogoutServiceTests.swift` — stubs for D-16 6-step teardown
- [ ] `validationLedgerTests/Networking/Auth401InterceptorTests.swift` — stubs for D-28 401 interceptor
- [ ] `validationLedgerTests/Geo/PhoneEntryViewModelGeoTests.swift` — stubs for D-20 geo gate (CLLocationManagerFake + CLGeocoderFake)
- [ ] `validationLedgerTests/Identity/PlatformPayloadFieldTests.swift` — stubs proving D-23 type discipline
- [ ] `validationLedgerUITests/RoleShellSmokeTests*.swift` — convert 5 Phase 1 placeholders to real launchArg-driven tests (D-32)

---

## Manual-Only Verifications

> Per RESEARCH `## Validation Architecture`, SC-2 and SC-3 require physical-device biometric hardware. Captured for VERIFICATION.md HUMAN-UAT block at phase-end.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Cold-boot biometric prompt before content visible | SESS-01, SC-2 | Simulator has no biometric hardware; LAContext returns errors not real prompts | 1) On physical iPhone with Face/Touch ID enrolled, complete OTP-verify + reach role shell. 2) Force-quit (swipe up). 3) Toggle airplane mode ON. 4) Re-launch. 5) ASSERT: BiometricLockViewController appears OVER role shell (no role-tab content visible behind). 6) Authenticate. 7) ASSERT: role shell becomes interactive. |
| >5min background → biometric on return | SESS-02, SC-3 | Same as SC-2 | 1) On physical iPhone, complete auth + reach role shell. 2) Background app (home button). 3) Wait >5 minutes. 4) Foreground app. 5) ASSERT: BiometricLockViewController appears. 6) Background again for <5 minutes. 7) Foreground. 8) ASSERT: BiometricLockViewController does NOT appear. |
| Biometric re-enrollment triggers re-bind placeholder | SESS-03 | Requires Settings → Face ID & Passcode → Reset Face ID interaction | 1) On physical iPhone, complete auth. 2) Settings app → Face ID & Passcode → Reset Face ID → re-enroll. 3) Re-launch app. 4) ASSERT: BiometricLockViewController shows `.biometricReEnrolled` reason copy + routes to re-bind stub. |
| Secure Enclave authorization key ACL clears on logout | AUTH-04, SC-4 | Requires post-logout Keychain inspection on device | 1) On physical iPhone, complete auth → reach role shell. 2) Tap avatar → Profile → Log out. 3) Inspect Keychain via Xcode → Devices → installed app → Container → Keychain (or via debug-only KeychainStore.dump if shipped). 4) ASSERT: `sessionToken`, `session.role`, `session.userID` absent. ASSERT: SE `authorizationKey` SecItem absent. ASSERT: `deviceKey` PRESENT (device identity preserved per D-16). |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify command OR a Wave 0 dependency listed above
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING test/fixture references
- [ ] No watch-mode flags (xcodebuild always runs to completion)
- [ ] Feedback latency < 30s for unit, <120s for UI smoke
- [ ] `nyquist_compliant: true` set in frontmatter (after planner populates the per-task table and the planner-checker passes)

**Approval:** pending
