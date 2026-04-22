---
phase: 04-app-attest-physical-device-ci-hardening
plan: 11
status: complete
self_check: PASSED
human_verification_status: resolved
human_verification_resolved_at: "2026-04-22T11:30:00-07:00"
inserted_during_execution: true
inserted_reason: "Dev-UX gap surfaced during Plan 04-08's human-verify checkpoint. DEBUG build on physical device hung at 'Send code' because MockURLProtocol had no default handlers for the organic tap-through flow (-MockOTPRoleForUITest had masked this by bypassing OTP)."
commits:
  - c0be147  # feat(04-11): initial MockDefaultFixtures + AppContainer DEBUG gate
  - a67f5c4  # fix(04-11): unconditional 200 on /auth/otp/verify (httpBody-vs-httpBodyStream bug)
key_files:
  created:
    - validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift
  modified:
    - validationLedger/App/AppContainer.swift
requirements_addressed: []
requirements_touched: [DEV-04]
self_check_matrix:
  - "xcodebuild build Debug iPhone 16 sim: BUILD SUCCEEDED, 0 errors"
  - "xcodebuild build Release generic/iOS: BUILD SUCCEEDED (entire file compiles to zero bytes in Release; triple-gated DEBUG block)"
  - "Phase 3 -MockOTPRoleForUITest smoke test (testShipperFullFlow): PASS (no regression; launch-arg guard `isUITestRolePath` prevents double-registration)"
  - "Phase 4 LimitedTrustBannerTests (XCUITests): PASS (no regression)"
  - "Physical iPhone organic walk-through: phone entry → Send code → OTP verify → role shell with softwareOnly banner visible (screenshot 2026-04-22 11:30 PT)"
---

# Plan 04-11 — DEBUG Mock-OTP Device Fixtures — SUMMARY

Status: **complete**. Inserted into Wave 4 to unblock Plan 04-08's human-verify checkpoint on
physical iPhone/iPad. Ships `MockDefaultFixtures.swift` (DEBUG-only catch-all handler covering the
5 endpoints the organic onboarding flow hits) + a triple-gated call from `AppContainer.init`.
Zero Release footprint.

## Why This Existed

DEBUG builds default `networkConfig` to `.mock` (`AppContainer.defaultNetworkConfig`). `MockURLProtocol`
is explicitly empty by design (Phase 2 Plan 01 removed the `/ping` default so tests must register
their own fixtures). The existing `-MockOTPRoleForUITest` launch arg bypasses OTP entirely, so
Phase 3 Plan 12 UITests passed — but a developer running a DEBUG build on a physical device with
NO launch args had nothing registered for `POST /auth/otp/request`. The MockURLProtocol built-in
404 fired after APIClient's retry/timeout, which manifested as a silent hang at "Send code".

User hit this at 2026-04-22 10:50 PT while trying to run Plan 04-08's iPad visual checkpoint.

## What Was Built

### `MockDefaultFixtures.swift` (NEW, DEBUG-only)

One catch-all `MockURLProtocol.Handler`. Inspects `(method, path)`, routes to a canned response:

| Method | Path | Response |
|---|---|---|
| POST | `/auth/otp/request` | 200 + `otp_session_id` + `expires_in_seconds` |
| POST | `/auth/otp/verify` | 200 + `session_token` + `role: carrier` + `user_id` (unconditional — see §Commits) |
| GET  | `/device/challenge` | 200 + `challenge` + `expires_at` + `nonce` |
| POST | `/device/register` | 200 + `device_id` + `registered_at` + **`trust_tier: softwareOnly`** |
| POST | `/device/heartbeat` | 200 + `heartbeat_accepted_at` + **`trust_tier: softwareOnly`** |
| * | * other | `nil` → falls through to MockURLProtocol built-in 404 (loud miss, not silent hang) |

`trust_tier: softwareOnly` is the default so the Plan 04-08 Limited-Trust banner is visible
organically on the role shell during the walk-through — two birds, one stone.

### `AppContainer.init` — triple-gated registration

```swift
#if DEBUG
let isUITestRolePath = ProcessInfo.processInfo.arguments.contains("-MockOTPRoleForUITest")
if case .mock = resolvedConfig, !isUITestRolePath {
    MockDefaultFixtures.registerAppDefaults()
}
#endif
```

Three conditions — all must hold:
1. `#if DEBUG` — Release compiles the entire block + the `MockDefaultFixtures.swift` file to zero bytes.
2. `resolvedConfig == .mock` — if DevMenu flipped to `.live`, skip.
3. `-MockOTPRoleForUITest` NOT present — that path has its own fixtures via `MockOTPRoleFixtureRegistry`.

Defense-in-depth: `defaultNetworkConfig(env:)` already forces `.live` in Release, so `MockURLProtocol`
isn't even in the URLSession's `protocolClasses` in Release. The DEBUG gate is belt-plus-suspenders.

## Commits

### `c0be147` — initial implementation
First revision registered handlers + added the AppContainer gate. Also added a body-inspection check
on `/auth/otp/verify` that returned 400 unless the request body contained a 6-digit string.

### `a67f5c4` — fix: unconditional 200 on /auth/otp/verify
Body-inspection was broken because async URLSession moves the request body into `httpBodyStream`,
leaving `URLRequest.httpBody == nil`. The "is this a 6-digit code" check always returned false →
mock returned 400 → OTPViewModel hit its generic catch branch → `state = .error("Verification failed")`
rendered in small red `.footnote` text that was easy to miss. User reported the OTP screen as "stuck"
after entering 6 digits and tapping Verify.

Fix: remove the body inspection. Dev-mock should be forgiving. Any request to `/auth/otp/verify` gets
200 back. Also removed dead helpers (`makeError`, `isAnySixDigitCode`).

After the fix, the user confirmed the full flow works end-to-end on a physical iPhone:
phone → Send code → OTP entry → any 6 digits → Verify → SE key gen → /device/register (mock) →
Face ID prompt → role shell with softwareOnly Limited-Trust banner visible (screenshot 11:30 PT).

## Self-Check (Automated)

| Verification | Result |
|---|---|
| `xcodebuild build` iPhone 16 sim Debug | BUILD SUCCEEDED, 0 errors |
| `xcodebuild build` generic/iOS Release | BUILD SUCCEEDED (zero Release footprint) |
| Phase 3 `testShipperFullFlow` | PASS (no regression) |
| Phase 4 `LimitedTrustBannerTests` | PASS (no regression) |
| Physical iPhone walk-through → role shell + banner | PASS (user screenshot 2026-04-22 11:30 PT) |

## Non-goals

- Not a replacement for `-MockOTPRoleForUITest` (that path bypasses OTP entirely; Phase 3 Plan 12 owns it).
- Not a test double — tests still register their own fixtures via `MockURLProtocol.reset() + register(...)`.
- Not a production surface — hard-coded `dev-mock-session-token` is explicitly DEBUG-only.

## Follow-ups

None carried forward from this plan. Plan 04-08's deferred items (real `/device/register.trust_tier`
consumer, iPad HUMAN-UAT visual checks) are owned by those plans' artifacts.
