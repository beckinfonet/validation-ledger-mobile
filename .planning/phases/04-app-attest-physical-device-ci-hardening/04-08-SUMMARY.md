---
phase: 04-app-attest-physical-device-ci-hardening
plan: 08
status: checkpoint_pending
self_check: PASSED_AUTOMATED
human_verification_status: pending
commits:
  - d2a5acf  # Task 1 — LimitedTrustBannerView
  - 2886087  # Task 2 — RoleCoordinator wrap + AppCoordinator wiring
  - 1f05e13  # Task 3 — XCUITests + fixture registry launch-arg + DEBUG-only uiTestTrustTierOverride seam
key_files:
  created:
    - validationLedger/UI/LimitedTrustBannerView.swift
    - validationLedgerUITests/LimitedTrustBannerTests.swift
  modified:
    - validationLedger/Roles/RoleCoordinator.swift
    - validationLedger/App/AppCoordinator.swift
    - validationLedger/App/AppContainer.swift
    - validationLedger/App/SceneDelegate.swift
    - validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift
deviations:
  - "Execution split across two sessions due to Anthropic quota pause (2026-04-22). Tasks 1–2 landed in the first session; Task 3 landed in the continuation session. Worktree preserved — no rebase, no force-reset, no file loss."
  - "Simulator model substitution: plan specified `iPhone 15`; Xcode 26.4 ships only iPhone 16 runtimes. Task 3 XCUITests ran on iPhone 16 (functionally equivalent for Pitfall 7 safe-area verification)."
  - "Task 3 Rule-3 scope-stretch: added `AppContainer.uiTestTrustTierOverride` (DEBUG-only) and seeded `AppSession(trustTier:)` from it, because `OTPViewModel` does not currently consume the `/device/register` response's `trust_tier` field (that wiring is out-of-scope for 04-08). Without this seam the `hardwareAttested` UITest would be unreachable. Accepted with follow-up per user 2026-04-22: wire real /device/register.trust_tier → AppSession consumer in a later plan (logged in deferred-items.md)."
  - "Task 4 human-verify checkpoint pending physical-device testing. Blocked on surfaced dev-ergonomics gap: DEBUG build on physical device hangs at Send code because MockURLProtocol has no default handlers for the organic tap-through flow (-MockOTPRoleForUITest masked this by bypassing OTP). Gap addressed by inserted Plan 04-11 (DEBUG mock-OTP device fixtures). Final 04-08 SUMMARY will be promoted to `status: complete` once user approves Task 4 after 04-11 lands."
blocking_user_action: "Task 4 checkpoint — run DEBUG build on physical iPad, walk through phone entry → OTP → role shell, verify Limited-Trust banner renders per plan lines 416-426."
---

# Plan 04-08 — Limited Trust Banner — SUMMARY (preliminary, checkpoint-pending)

Status: `checkpoint_pending` — Tasks 1, 2, 3 landed and verified on simulator; Task 4 is a blocking
human-verify checkpoint that cannot be completed in-session. This preliminary SUMMARY is committed
now so the worktree can be merged to main without leaving a hole in the phase directory. Once the
user completes the visual verification on physical iPad (unblocked by Plan 04-11), this file is
updated to `status: complete` with the final checkpoint verdict.

## What Was Built

### Task 1 — `LimitedTrustBannerView` (`d2a5acf`)
UIKit `UIView` subclass:
- `isUserInteractionEnabled = false` (D-11 non-dismissibility)
- `accessibilityIdentifier = "limited-trust-banner"` (XCUITest selector)
- Copy wrapped in `NSLocalizedString` (v2 i18n readiness, English for M1)
- `systemYellow @ 85%` background; 36pt tall
- Pins label to self edges (outer pinning to safe-area topAnchor is RoleCoordinator's job — Pitfall 7)

### Task 2 — `RoleCoordinator.wrapWithLimitedTrustBanner` + `AppCoordinator` wiring (`2886087`)
- `UITabBarController.wrapWithLimitedTrustBanner(trustTier:) -> UIViewController`
  - `.hardwareAttested` → returns self (no wrap)
  - `.softwareOnly` → returns container VC with banner pinned to `safeAreaLayoutGuide.topAnchor`
    and the tab-bar view pinned below
- `AppCoordinator.presentRoot(.role(role))` calls the wrap with `container.session.trustTier`
  before assigning `window.rootViewController`

### Task 3 — XCUITests + fixture-registry extension + DEBUG seam (`1f05e13`)
- `validationLedgerUITests/LimitedTrustBannerTests.swift` (NEW)
  - `testBannerVisibleWhenTrustTierIsSoftwareOnly` — asserts banner + `isHittable == false`
  - `testBannerHiddenWhenTrustTierIsHardwareAttested` — asserts banner absent
- `MockOTPRoleFixtureRegistry.swift` — accepts `-MockOTPTrustTierForUITest {softwareOnly|hardwareAttested}` launch arg
- `AppContainer.swift` — DEBUG-only `uiTestTrustTierOverride` static + `AppSession(trustTier:)` seed (Rule-3 scope-stretch, documented in deviations)
- `SceneDelegate.swift` — parses the new launch arg in the DEBUG block

## Self-Check (Automated)

| Verification | Result |
|---|---|
| `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug` | `** BUILD SUCCEEDED **` |
| `LimitedTrustBannerTests` (2 tests) on iPhone 16 sim | 2/2 PASS (29.065s) |
| Phase 3 `RoleShellSmokeTests/testShipperFullFlow` regression | PASS |
| Grep checks (Task 1, 2, 3 acceptance criteria) | All pass — see plan file for grep matrix |

## Remaining Work

Task 4 — human visual verification on physical iPad. Originally blocked by DEBUG-on-device
Send-code hang (MockURLProtocol default-fixture gap). Unblocked by Plan 04-11.

**Reproduction after 04-11 lands:**
```
# DEBUG build on physical iPad (no launch args needed post-04-11)
# Send code → OTP verify → role shell → observe banner
```

Checklist (plan lines 416-426):
1. iPhone portrait — banner above tab bar, full copy readable
2. iPhone landscape — banner pinned to safe area top, no Dynamic Island overlap
3. Swipe + tap dismissal attempts → MUST NOT dismiss
4. iPad Pro — portrait + landscape + Split View — repeat #1-3
5. Yellow tone acceptable

## Deferred Items

- Wire real `/device/register` response `trust_tier` → `AppSession.trustTier` consumer in `OTPViewModel` (or a later Phase 4/5 plan). Current `uiTestTrustTierOverride` seam is DEBUG-only and launch-arg-driven; production runtime will need the real backend-driven path to replace it when the backend ships `trust_tier` in register responses. User-accepted follow-up (2026-04-22) — logged in `.planning/phases/04-app-attest-physical-device-ci-hardening/deferred-items.md`.
