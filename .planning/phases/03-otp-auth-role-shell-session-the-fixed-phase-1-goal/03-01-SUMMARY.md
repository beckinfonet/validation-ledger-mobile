---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 01
subsystem: testing
tags: [ios, swift-testing, test-infrastructure, wave-0, fixtures, stubs, mockurlprotocol]

# Dependency graph
requires:
  - phase: 02-networking-contract-and-device-keys
    provides: FixtureLoader + MockURLProtocol registry + existing Fixtures/ directory (14 JSON fixtures, NSLock-guarded) + Swift Testing @Suite+@Test conventions
provides:
  - One new MockURLProtocol fixture body (otp-verify-rate-limited.json) for D-02 429 path
  - 13 Swift Testing @Suite stub files across Auth/Networking/Identity/Geo/Features/App
  - Two new test target subdirectories (Identity/Geo/, Features/Onboarding/Auth/) auto-included by PBXFileSystemSynchronizedRootGroup
  - Red→green targets pre-seeded for every Wave 1+ plan (02, 03, 05, 06, 07, 08, 09, 11)
affects: [03-02-endpoint-encoding, 03-03-platform-payload-field, 03-05-apiclient-rate-limit, 03-06-session-restore-biometric, 03-07-logout-sensitive-auth401, 03-08-geo-gate, 03-09-onboarding-viewmodels, 03-11-app-coordinator-routing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wave 0 stub pattern: @Suite + @Test(.disabled(\"Wave N Plan NN implements\")) for pre-seeded red→green targets that compile + register as skipped"
    - "Fixture body + Retry-After HTTP header separation (body is informational; header is set by MockURLProtocol registerFixture call in consuming plan)"

key-files:
  created:
    - validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json
    - validationLedgerTests/Auth/SessionRestoreServiceTests.swift
    - validationLedgerTests/Auth/BiometricServiceTests.swift
    - validationLedgerTests/Auth/LogoutServiceTests.swift
    - validationLedgerTests/Auth/SensitiveActionServiceTests.swift
    - validationLedgerTests/Networking/Auth401ResponseInterceptorTests.swift
    - validationLedgerTests/Networking/APIClientRateLimitTests.swift
    - validationLedgerTests/Networking/EndpointEncodingTests.swift
    - validationLedgerTests/Identity/PlatformPayloadFieldTests.swift
    - validationLedgerTests/Identity/Geo/LocationProviderTests.swift
    - validationLedgerTests/Identity/Geo/CountryGateTests.swift
    - validationLedgerTests/Features/Onboarding/Auth/PhoneEntryViewModelTests.swift
    - validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift
    - validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift
  modified: []

key-decisions:
  - "Each stub declares one @Test(.disabled(\"Wave N Plan NN implements\")) placeholder — Swift Testing requires at least one @Test per @Suite to register the suite in test discovery"
  - "otp-verify-rate-limited.json body uses retry_after_seconds (informational) — the actual Retry-After: 60 HTTP header is set by the MockURLProtocol registerFixture call in Plan 05, not by the fixture file"
  - "No source-target changes — pure test-target plumbing; zero application behavior change"
  - "Used iOS 26.4 iPhone 17 Pro destination (booted) instead of the plan-suggested iPhone 15 / iOS 17.5 — iPhone 15 / iOS 17.5 runtime is not installed in this environment; project deployment target is iOS 17.0 so both work; iOS 26.4 simulator is what's actually available and the SDK the scheme links against"

patterns-established:
  - "Wave 0 test-stub seeding pattern: centralize all new-test-file boilerplate in one plan so Wave 1+ plans MODIFY (not CREATE) to land red→green cycles"
  - "Project path + Suite-name + Plan-owner traceability in stub header comments — makes it trivial to grep `Wave N Plan NN implements` to audit pending work"

requirements-completed: []

# Metrics
duration: 3min
completed: 2026-04-21
---

# Phase 03 Plan 01: Wave 0 Test Stub Seeding Summary

**1 MockURLProtocol fixture + 13 Swift Testing @Suite stub files seeded; TEST BUILD SUCCEEDED — every Wave 1+ Phase 3 plan now has a pre-existing red→green target file to modify instead of create.**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-21 (first task commit 34d52aa)
- **Completed:** 2026-04-21 (metadata commit pending)
- **Tasks:** 2 / 2
- **Files created:** 14 (1 fixture + 13 Swift Testing stubs)
- **Files modified:** 0

## Accomplishments

- Seeded 13 Swift Testing `@Suite` stub files across 6 test subsystems (Auth × 4, Networking × 3, Identity × 1, Identity/Geo × 2, Features/Onboarding/Auth × 2, App × 1) — each compiles, imports `Testing` (never XCTest), carries one `@Test(.disabled("Wave N Plan NN implements"))` placeholder, and links via `@testable import validationLedger`.
- Added `otp-verify-rate-limited.json` fixture (5 lines, mirrors `otp-verify-failure.json` analog) for D-02 429-rate-limited path; Plan 05 will pair it with a MockURLProtocol handler that injects `Retry-After: 60` as an HTTP header.
- Created two new test target subdirectories (`validationLedgerTests/Identity/Geo/`, `validationLedgerTests/Features/Onboarding/Auth/`) — auto-included via Phase 1's `PBXFileSystemSynchronizedRootGroup` setup, no `project.pbxproj` edit required.
- `xcodebuild build-for-testing -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/vl-build` → `** TEST BUILD SUCCEEDED **` (verified twice).

## Task Commits

Each task was committed atomically (worktree mode, `--no-verify` per parallel-execution policy):

1. **Task 1: Create otp-verify-rate-limited.json fixture (D-02)** — `34d52aa` (test)
2. **Task 2: Create 13 stub test files across Auth/Networking/Identity/Geo/Features/App** — `5db0220` (test)

**Plan metadata commit:** pending (appended with SUMMARY.md).

## Files Created

### Fixture (1)

- `validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json` — D-02 429 body (`error_code=auth.rate_limited`, `retry_after_seconds=60`); Retry-After HTTP header is set by the MockURLProtocol registerFixture call that Plan 05 will land.

### Stub-to-Plan Mapping (13)

| # | Path | Suite (REQ IDs) | Filled by Plan |
|---|------|-----------------|----------------|
| 1 | `validationLedgerTests/Auth/SessionRestoreServiceTests.swift` | SessionRestoreService — cold-boot probe (SESS-01, AUTH-03) | Plan 06 |
| 2 | `validationLedgerTests/Auth/BiometricServiceTests.swift` | BiometricService — LAContext wrapper + domainState capture (SESS-03, D-09, D-10) | Plan 06 |
| 3 | `validationLedgerTests/Auth/LogoutServiceTests.swift` | LogoutService — single-funnel teardown (SESS-04, AUTH-04, D-16) | Plan 07 |
| 4 | `validationLedgerTests/Auth/SensitiveActionServiceTests.swift` | SensitiveActionService — M1 constructibility surface (AUTH-06, D-11, D-12) | Plan 07 |
| 5 | `validationLedgerTests/Networking/Auth401ResponseInterceptorTests.swift` | Auth401ResponseInterceptor — non-OTP 401 → logout (AUTH-05, D-28) | Plan 07 |
| 6 | `validationLedgerTests/Networking/APIClientRateLimitTests.swift` | APIClient — 429 + Retry-After parsing (AUTH-02, D-02) | Plan 05 |
| 7 | `validationLedgerTests/Networking/EndpointEncodingTests.swift` | Endpoint encoding — acronym CodingKeys snake_case bridge (Pre-Phase-3 IN-01, IN-05) | Plan 02 |
| 8 | `validationLedgerTests/Identity/PlatformPayloadFieldTests.swift` | PlatformPayloadField — phantom-typed enum disjoint from LogField (GEO-03, D-23) | Plan 03 |
| 9 | `validationLedgerTests/Identity/Geo/LocationProviderTests.swift` | LocationProvider — CLLocationManager async wrapper (GEO-01, D-20) | Plan 08 |
| 10 | `validationLedgerTests/Identity/Geo/CountryGateTests.swift` | CountryGate — reverse-geocode US-only refusal (GEO-02, D-20, D-21) | Plan 08 |
| 11 | `validationLedgerTests/Features/Onboarding/Auth/PhoneEntryViewModelTests.swift` | PhoneEntryViewModel — E.164 + geo gate orchestration (AUTH-01, GEO-01, GEO-02, D-20, D-26) | Plan 09 |
| 12 | `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift` | OTPViewModel — Retry-After countdown + D-27 7-step orchestration (AUTH-02, AUTH-03, D-02, D-27) | Plan 09 |
| 13 | `validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift` | AppCoordinator — .auth + .anotherActiveSession routing (SHELL-01, DEV-06, D-01, D-18) | Plan 11 |

## Decisions Made

- **Destination substitution (env-adaptive):** Plan requested `iPhone 15 / iOS 17.5` but that runtime is not installed; project deployment target is iOS 17.0 so the scheme builds against any iOS 17.0+ simulator. Used `iPhone 17 Pro / iOS 26.4` (the currently booted simulator) — equivalent verification result, `** TEST BUILD SUCCEEDED **` achieved. Documented as Deviation 1 below (Rule 3 — blocking env correction).
- **Disabled-test reason strings embed wave AND plan number** (e.g., `"Wave 3 Plan 06 implements"`) — makes future audit trivial: `grep -R "Wave . Plan .. implements" validationLedgerTests` lists every pending stub and maps to owner.
- **No XCTest imports anywhere in new stubs** — verified by full-tree `Grep(pattern: "import XCTest", path: validationLedgerTests)` returning zero files. Existing validationLedgerTests suite was already 100% Swift Testing pre-Phase-3; this plan preserves the invariant.
- **Stub placeholder function is `func placeholder()` consistently across all 13 files** — uniform name makes it grep-able and makes Wave 1+ consumers trivially rename/replace.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking Env Correction] Substituted `iPhone 17 Pro / iOS 26.4` for plan-specified `iPhone 15 / iOS 17.5` destination**
- **Found during:** Task 2 `xcodebuild build-for-testing` step
- **Issue:** `xcrun simctl list devices available` shows the environment has no iPhone 15 / iOS 17.5 runtime installed. Available runtimes: iOS 15.2, 18.0, 18.1, 18.2, 18.4, 26.2, 26.4. The iOS 26.4 iPhone 17 Pro is the currently *booted* simulator and matches the project's Xcode 26.4 SDK (CLAUDE.md §Technology Stack / Runtime).
- **Fix:** Ran `xcodebuild build-for-testing -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -derivedDataPath /tmp/vl-build`. iOS 17.0 minimum deployment target means any iOS 17+ destination produces equivalent compile-gate verification for the 13 new stub files.
- **Files modified:** None (only CLI invocation differs from plan text).
- **Verification:** `** TEST BUILD SUCCEEDED **` — identical acceptance signal as the plan prescribes.
- **Committed in:** 5db0220 (Task 2 commit, where the build gate was exercised).

---

**Total deviations:** 1 auto-fixed (1 blocking env correction)
**Impact on plan:** No scope change; environment-only destination swap. Wave 1+ plans running the same build-for-testing gate should either use the same iPhone 17 Pro / iOS 26.4 destination or any installed iOS 17+ simulator runtime.

## Known Stubs

**All 13 stub files are intentional wave-0 scaffolding** — the entire objective of this plan is to seed stubs that Wave 1+ plans fill in. Each is traceable to its owning plan via:

- The `Wave N Plan NN implements` reason string on `@Test(.disabled(...))`.
- The Stub-to-Plan Mapping table above.
- Plan frontmatter `files_modified` list in `03-01-PLAN.md`.

No stubs block Phase 3's *stated* goal — Phase 3's goal is OTP auth + role shell + session, landed incrementally across Waves 1–6. Wave 0 is explicitly described in 03-RESEARCH.md §Wave 0 Gaps and 03-VALIDATION.md lines 53–62 as test-target-only plumbing. The stubs here are prerequisites, not gaps.

## Threat Flags

(Per plan `<threat_model>`: Wave 0 has no production-surface threats — all changes are test-target-only. `@testable import validationLedger` is test-process-only; fixture JSON is never loaded by application code.)

No new threat surface introduced. No threat flags.

## Issues Encountered

None. Plan executed as written. The only real-world adjustment was the simulator destination swap (documented as Deviation 1); no compile errors, no test-target disruption, no missing dependencies.

## User Setup Required

None — no external services configured, no secrets needed, no dashboard changes.

## Next Phase Readiness

- **Wave 1 plans (02, 03, 04) can immediately MODIFY stubs to land assertions** — no CREATE step required. Specifically:
  - Plan 02 (`EndpointEncoding`) modifies `validationLedgerTests/Networking/EndpointEncodingTests.swift`.
  - Plan 03 (`PlatformPayloadField`) modifies `validationLedgerTests/Identity/PlatformPayloadFieldTests.swift`.
- **Wave 2 plan 05 (`APIClientRateLimit`)** has both the fixture (`otp-verify-rate-limited.json`) AND the stub test file (`APIClientRateLimitTests.swift`) pre-seeded — it needs only to register a MockURLProtocol handler with `Retry-After: 60` HTTP header and add `#expect` assertions.
- **Wave 3 plan 06** has two stubs pre-seeded (`SessionRestoreService`, `BiometricService`).
- **Wave 4 plan 07** has three stubs pre-seeded (`LogoutService`, `SensitiveActionService`, `Auth401ResponseInterceptor`).
- **Wave 4 plan 08** has two stubs pre-seeded in `Identity/Geo/` (`LocationProvider`, `CountryGate`).
- **Wave 5 plan 09** has two stubs pre-seeded in `Features/Onboarding/Auth/` (`PhoneEntryViewModel`, `OTPViewModel`).
- **Wave 6 plan 11** has `AppCoordinatorPhase3RoutingTests` pre-seeded.
- Swift Testing test discovery should register 13 additional `@Suite`s — all reporting `1 disabled` on run — once any Wave 1+ plan runs `-test-run` for the first time.

## Self-Check

Files claimed created:

- `validationLedgerTests/Networking/Fixtures/otp-verify-rate-limited.json` — FOUND
- `validationLedgerTests/Auth/SessionRestoreServiceTests.swift` — FOUND
- `validationLedgerTests/Auth/BiometricServiceTests.swift` — FOUND
- `validationLedgerTests/Auth/LogoutServiceTests.swift` — FOUND
- `validationLedgerTests/Auth/SensitiveActionServiceTests.swift` — FOUND
- `validationLedgerTests/Networking/Auth401ResponseInterceptorTests.swift` — FOUND
- `validationLedgerTests/Networking/APIClientRateLimitTests.swift` — FOUND
- `validationLedgerTests/Networking/EndpointEncodingTests.swift` — FOUND
- `validationLedgerTests/Identity/PlatformPayloadFieldTests.swift` — FOUND
- `validationLedgerTests/Identity/Geo/LocationProviderTests.swift` — FOUND
- `validationLedgerTests/Identity/Geo/CountryGateTests.swift` — FOUND
- `validationLedgerTests/Features/Onboarding/Auth/PhoneEntryViewModelTests.swift` — FOUND
- `validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift` — FOUND
- `validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift` — FOUND

Commits claimed made:

- `34d52aa` (Task 1) — FOUND
- `5db0220` (Task 2) — FOUND

## Self-Check: PASSED

---
*Phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal*
*Completed: 2026-04-21*
