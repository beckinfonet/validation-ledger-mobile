---
phase: 05-kyc-capture-upload-pipeline
plan: 09
subsystem: networking-mock
tags: [kyc, device-mock, gap-closure, regression-test]
requires:
  - "MockDefaultFixtures.dispatchHandler (device-mock catch-all)"
  - "KYCStatusEndpoint.Response"
provides:
  - "(GET, /kyc/status) device-mock route"
  - "kycStatusResponseJSON() canned body builder"
  - "MockDefaultFixturesKYCTests Gap (Test 9) regression test"
affects:
  - "KYCStatusViewModel.fetchStatus() on DEBUG device builds"
  - "UAT Test 9 (post-Submit status screen), UAT Test 12 (Profile Verification-status row)"
tech-stack:
  added: []
  patterns:
    - "Device-mock (method, path) dispatch case + matching snake_case JSON body builder"
key-files:
  created: []
  modified:
    - "validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift"
    - "validationLedgerTests/KYC/MockDefaultFixturesKYCTests.swift"
decisions:
  - "kycStatusResponseJSON() serves overall_status=under_review (agrees with kycSubmitResponseJSON post-submit status) + empty artifacts array (device mock cannot inspect the request body)"
metrics:
  duration: ~3min
  completed: 2026-05-17
---

# Phase 5 Plan 09: KYC Status Device-Mock Route Gap Closure Summary

Adds the missing `(GET, /kyc/status)` route to `MockDefaultFixtures.dispatchHandler` so a DEBUG physical-device build (`networkConfig == .mock`) renders an Under Review verdict on the KYC status screen instead of the "Couldn't load status" error state.

## What Was Built

**Task 1 — `(GET, /kyc/status)` device-mock route** (`feat`, commit `6d25b56`)
- Added `case ("GET", "/kyc/status"): return make200(body: kycStatusResponseJSON(), url: request.url)` to `MockDefaultFixtures.dispatchHandler`, placed immediately after the `("POST", "/kyc/submit")` case and before the `default` branch, inside the existing "KYC upload flow" section.
- Added the `kycStatusResponseJSON()` private static body builder in the "KYC upload JSON bodies" section, immediately after `kycSubmitResponseJSON()`. It returns a `Data` whose snake_case body mirrors `KYCStatusEndpoint.Response`: `{"overall_status":"under_review","artifacts":[]}`.
- `overall_status` is `under_review` so the status screen reached straight after Submit agrees with `kycSubmitResponseJSON()`'s post-submit `under_review`. `artifacts` is an empty array — the device mock cannot inspect the request body to know which artifact IDs to echo, and the under-review verdict copy needs no per-artifact rejection detail; an empty array decodes cleanly into `[Artifact]`.
- A doc comment was added on the builder matching the surrounding builders' style.
- The whole addition is inside the file-level `#if DEBUG` — no new gate, zero Release bytes.

**Task 2 — GET /kyc/status regression test** (`test`, commit `dacb716`)
- Added one `@Test` ("Gap (Test 9): the device-mock dispatch handler answers GET /kyc/status with 200 + a decodable Response") to the `MockDefaultFixturesKYCTests` suite, in the "Issue 2a" section.
- It issues `KYCStatusEndpoint()` through the existing `requestThroughMockDefaults(_:)` helper (which registers ONLY `MockDefaultFixtures.dispatchHandler` through a real `APIClient`) and asserts a non-throwing `Response` with `overallStatus == "under_review"` and `artifacts.isEmpty`.
- Before this route, the request 404'd and the helper threw `NetworkError.httpError(404)`; the test passing proves the route now serves a decodable verdict.

## Verification

- Task 1 automated `grep` verify: `ROUTE_PRESENT` — the file contains a non-commented `kyc/status` reference and `kycStatusResponseJSON`.
- Task 2: `xcodebuild test -only-testing:validationLedgerTests/MockDefaultFixturesKYCTests` — **TEST SUCCEEDED**, all 6 tests in the suite passed (including the new Gap Test 9 test) in 3.6s.

## TDD Gate Compliance

Plan task 2 carries `tdd="true"` (frontmatter `type: execute`, not a plan-level `type: tdd`). The plan's two tasks are sequential within a single gap-closure plan: Task 1 lands the route, Task 2 lands the regression test. Because Task 1 (the implementation) was committed before Task 2's test, the new test passed on first run rather than failing first.

This is the correct ordering for this plan as written — the plan explicitly sequences Task 1 (route) before Task 2 (test), and the RED state described in the plan ("before this route, the request 404'd") is a historical statement about the codebase prior to Task 1, not a separate RED commit. The `feat` commit precedes the `test` commit in git log; a strict RED→GREEN gate sequence (test commit before feat commit) was not followed because the plan did not author the tasks in that order. No behavior regression risk: the test is a pure assertion against the just-added route and passes deterministically.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Simulator destination substitution**
- **Found during:** Task 2 verification
- **Issue:** The plan's verify command names `platform=iOS Simulator,name=iPhone 16`, but the only available simulator on this machine is `iPhone 16e`.
- **Fix:** Ran `xcodebuild test` with `name=iPhone 16e`. No code change — the substitution affects only the test-run destination.
- **Files modified:** none
- **Commit:** n/a

### Notes (not deviations)

- The `TGA` thumbnail `err=-50` log lines emitted during the `allSixArtifactsUploadAgainstMockDefaults` test are pre-existing simulator-only image-decode noise from the upload-pipeline test (unrelated to this plan's GET /kyc/status route). That test passed.

## Known Stubs

The `kycStatusResponseJSON()` builder serves a hard-coded `under_review` verdict with an empty `artifacts` array. This is intentional and documented in the plan and the builder's doc comment: the device mock cannot read the request body, and the under-review verdict copy needs no per-artifact detail. The whole file is `#if DEBUG` — it is never compiled into Release (Release also forces `networkConfig = .live`). Not a gap; this is the correct device-mock behavior for the post-Submit status screen.

## Self-Check: PASSED

- FOUND: validationLedger/Core/Networking/Mock/MockDefaultFixtures.swift (modified)
- FOUND: validationLedgerTests/KYC/MockDefaultFixturesKYCTests.swift (modified)
- FOUND commit: 6d25b56 (feat 05-09: add (GET, /kyc/status) device-mock route)
- FOUND commit: dacb716 (test 05-09: assert device-mock answers GET /kyc/status)
