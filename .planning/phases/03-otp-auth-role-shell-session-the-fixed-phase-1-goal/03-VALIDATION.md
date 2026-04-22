---
phase: 3
slug: otp-auth-role-shell-session-the-fixed-phase-1-goal
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-21
planned: 2026-04-21
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Sourced from 03-RESEARCH.md `## Validation Architecture` (line 1843+) + populated by the planner from the 10 PLAN files.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`import Testing`) for unit tests · XCTest for XCUITests · device tests TBD per CI-03 (Phase 4) |
| **Config file** | `validationLedger.xcodeproj` (existing schemes: validationLedger, validationLedgerTests, validationLedgerUITests, validationLedgerDeviceTests) |
| **Quick run command** | `xcodebuild test -project validationLedger.xcodeproj -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:validationLedgerTests/<TargetClass>` |
| **Full suite command** | `xcodebuild test -project validationLedger.xcodeproj -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'` (includes UI smoke) |
| **Estimated runtime** | ~30-60s unit · ~120s UI smoke (5 role tests) · device tests deferred to Phase 4 CI hardening |

---

## Sampling Rate

- **After every task commit:** Run scoped `-only-testing:` for the file under test (≤10s feedback)
- **After every plan wave:** Run full `validationLedgerTests` scheme (~30-60s)
- **Before `/gsd-verify-work`:** Full unit suite green + 5 UI smoke tests green + planner-flagged HUMAN-UAT items captured in VERIFICATION.md
- **Max feedback latency:** 60 seconds (unit); UI smoke runs at wave boundaries only

---

## Per-Task Verification Map

> Populated by the planner during step 8. Each task in PLAN.md frontmatter references a row here OR depends on a Wave 0 stub.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|--------|
| 03-01-T1 | 01 | 0 | (test infra) | — | otp-verify-rate-limited.json fixture present + valid JSON | fixture | `test -f validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json` | ⬜ pending |
| 03-01-T2 | 01 | 0 | (test infra) | T-03-01-01 | 13 stub Swift Testing files compile + register suites | unit | `xcodebuild build-for-testing -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'` | ⬜ pending |
| 03-02-T1 | 02 | 1 | (carryover CR-02 + IN-02) | T-03-02-01, T-03-02-02 | SE generateKey idempotent + SoftwareKeyStore returns DER | unit | `xcodebuild test ... -only-testing:validationLedgerTests/KeyStore/SoftwareKeyStoreTests` | ⬜ pending |
| 03-02-T2 | 02 | 1 | (carryover IN-01/05) | T-03-02-03 | 4 endpoint RequestBodies emit snake_case acronym keys | unit | `xcodebuild test ... -only-testing:validationLedgerTests/Networking/EndpointEncodingTests` | ⬜ pending |
| 03-03-T1 | 03 | 1 | GEO-03 | T-03-03-01, T-03-03-02 | PlatformPayloadField exists + LogField has no coordinate case | unit | `xcodebuild test ... -only-testing:validationLedgerTests/Identity/PlatformPayloadFieldTests -only-testing:validationLedgerTests/Logging/PIIScrubberTests` | ⬜ pending |
| 03-03-T2 | 03 | 1 | GEO-03 | T-03-03-03 | SwiftLint ban_raw_coordinate_literal rule active + 0 violations | lint | `swiftlint lint --strict validationLedger/` | ⬜ pending |
| 03-04-T1 | 04 | 1 | AUTH-03, SESS-04 | T-03-04-01, T-03-04-03, T-03-04-04 | KeychainStore.deleteAll(under: .session) idempotent + scope-correct | unit | `xcodebuild test ... -only-testing:validationLedgerTests/Storage/KeychainStoreTests` | ⬜ pending |
| 03-04-T2 | 04 | 1 | SESS-04 | T-03-04-02 | KeyStoreProtocol.deleteKey + SE SecItemDelete + Software in-memory clear | unit | `xcodebuild test ... -only-testing:validationLedgerTests/KeyStore/KeyStoreProtocolDeleteTests -only-testing:validationLedgerTests/KeyStore/SoftwareKeyStoreTests` | ⬜ pending |
| 03-05-T1 | 05 | 1 | AUTH-02 | T-03-05-01, T-03-05-03 | APIClient parses 429 + Retry-After → NetworkError.rateLimited | unit | `xcodebuild test ... -only-testing:validationLedgerTests/Networking/APIClientRateLimitTests -only-testing:validationLedgerTests/Networking/APIClientEndpointTests` | ⬜ pending |
| 03-06-T1 | 06 | 2 | SESS-01, SESS-03, AUTH-03 | T-03-06-04, T-03-06-05 | SessionRestore probe + BiometricService canEvaluate guard + SessionLockService lockState 4-state machine | unit | `xcodebuild test ... -only-testing:validationLedgerTests/Auth/SessionLockServiceTests -only-testing:validationLedgerTests/Auth/SessionRestoreServiceTests -only-testing:validationLedgerTests/Auth/BiometricServiceTests` | ⬜ pending |
| 03-06-T2 | 06 | 2 | AUTH-04, SESS-04, AUTH-06 | T-03-06-01, T-03-06-02, T-03-06-03 | LogoutService 6-step teardown + notification posted last + SensitiveActionService constructible | unit | `xcodebuild test ... -only-testing:validationLedgerTests/Auth/SensitiveActionServiceTests -only-testing:validationLedgerTests/Auth/LogoutServiceTests` | ⬜ pending |
| 03-06-T3 | 06 | 2 | AUTH-05 | T-03-06-06, T-03-06-07 | Auth401ResponseInterceptor non-OTP 401 → logout, OTP paths excluded | unit | `xcodebuild test ... -only-testing:validationLedgerTests/Networking/Auth401ResponseInterceptorTests` | ⬜ pending |
| 03-07-T1 | 07 | 2 | GEO-01 | T-03-07-02 | LocationProvider one-shot async wrapper + freshness/accuracy guards | unit | `xcodebuild test ... -only-testing:validationLedgerTests/Identity/Geo/LocationProviderTests` | ⬜ pending |
| 03-07-T2 | 07 | 2 | GEO-02 | T-03-07-03, T-03-07-04 | CountryGate D-21 defense-in-depth + Info.plist NSLocationWhenInUseUsageDescription | unit | `xcodebuild test ... -only-testing:validationLedgerTests/Identity/Geo/CountryGateTests` | ⬜ pending |
| 03-08-T1 | 08 | 3 | AUTH-01, AUTH-02, GEO-01, GEO-02 | T-03-08-01, T-03-08-02, T-03-08-03 | PhoneEntryViewModel D-20 5-step + OTPViewModel D-27 7-step + Retry-After countdown | unit | `xcodebuild test ... -only-testing:validationLedgerTests/Features/Onboarding/Auth/PhoneEntryViewModelTests -only-testing:validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests` | ⬜ pending |
| 03-08-T2 | 08 | 3 | AUTH-04, DEV-06, SESS-01..03 | T-03-08-04, T-03-08-05, T-03-08-06 | BiometricLockVC + ProfileVC + AnotherActiveSessionVC + NotAvailableInRegionVC compile + accessibility identifiers present | build/grep | `grep -q "modalPresentationStyle = .fullScreen" validationLedger/Features/Onboarding/Auth/BiometricLockViewController.swift` | ⬜ pending |
| 03-09-T1 | 09 | 4 | SHELL-01, DEV-06, SESS-01 | T-03-09-01, T-03-09-02, T-03-09-05 | AppContainer composition + SceneDelegate cold-boot probe + .sessionDidInvalidate observer + AppPhase.anotherActiveSession routing | unit | `xcodebuild test ... -only-testing:validationLedgerTests/App/AppCoordinatorPhase3RoutingTests` | ⬜ pending |
| 03-09-T2 | 09 | 4 | SHELL-02, SHELL-03, SHELL-04 | T-03-09-03 | 5 role TabBars wrap tabs in nav + install avatar UIBarButtonItem + tab inventory verbatim per TechStack §4 | build/grep | `grep -q "wrapTabsWithNavAndInstallAvatar" validationLedger/Roles/*/...TabBarController.swift` (5 files) | ⬜ pending |
| 03-10-T1 | 10 | 5 | (test infra) | T-03-10-01, T-03-10-04 | MockOTPRoleFixtureRegistry + SceneDelegate -MockOTPRoleForUITest path | build/grep | `grep -q "MockOTPRoleForUITest" validationLedger/App/SceneDelegate.swift` | ⬜ pending |
| 03-10-T2 | 10 | 5 | SHELL-01, SHELL-02, SHELL-03, SHELL-04, AUTH-01, AUTH-04, SESS-04 (SC-1) | T-03-10-03 | 5 role smoke UI tests drive full OTP → role shell → logout cycle | UI | `xcodebuild test ... -only-testing:validationLedgerUITests/RoleShellSmokeTests` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Coverage summary:**
- 19 task rows across 10 plans + 5 waves
- All 18 phase requirement IDs (AUTH-01..06, SHELL-01..04, SESS-01..04, GEO-01..03, DEV-06) addressed
- All 5 ROADMAP success criteria covered (SC-1 fully automated; SC-2/SC-3/SC-4-Keychain-inspection HUMAN-UAT; SC-4-logout-returns-to-phone-entry + SC-5 fully automated)
- All 33 design decisions D-01..D-33 mapped to at least one task

---

## Wave 0 Requirements

> Test stubs and fixtures Phase 3 needs before Wave 1 can produce meaningful red→green cycles. ALL satisfied by Plan 01.

- [x] (planned) `validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json` — 429 + Retry-After fixture (D-02) — Plan 01 Task 1
- [x] (planned) `validationLedgerTests/Auth/SessionRestoreServiceTests.swift` — stubs for SESS-01 — Plan 01 Task 2
- [x] (planned) `validationLedgerTests/Auth/SessionLockServiceTests.swift` — extend Phase 1 stubs for SESS-02/03 — Plan 06 modifies
- [x] (planned) `validationLedgerTests/Auth/BiometricServiceTests.swift` — stubs for D-09 — Plan 01 Task 2
- [x] (planned) `validationLedgerTests/Auth/SensitiveActionServiceTests.swift` — D-12 constructibility — Plan 01 Task 2
- [x] (planned) `validationLedgerTests/Auth/LogoutServiceTests.swift` — stubs for D-16 — Plan 01 Task 2
- [x] (planned) `validationLedgerTests/Networking/Auth401InterceptorTests.swift` — stubs for D-28 — Plan 01 Task 2
- [x] (planned) `validationLedgerTests/Geo/PhoneEntryViewModelGeoTests.swift` — stubs for D-20 — Plan 01 Task 2 (under Features/Onboarding/Auth/ + Identity/Geo/)
- [x] (planned) `validationLedgerTests/Identity/PlatformPayloadFieldTests.swift` — stubs for D-23 — Plan 01 Task 2
- [x] (planned) `validationLedgerUITests/RoleShellSmokeTests*.swift` — convert 5 Phase 1 placeholders to real launchArg-driven tests — Plan 10 Task 2

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

- [x] All tasks have `<automated>` verify command OR a Wave 0 dependency listed above
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING test/fixture references
- [x] No watch-mode flags (xcodebuild always runs to completion)
- [x] Feedback latency < 60s for unit, <120s for UI smoke
- [x] `nyquist_compliant: true` set in frontmatter (planner-checker can confirm)

**Approval:** ready for /gsd-execute-phase
