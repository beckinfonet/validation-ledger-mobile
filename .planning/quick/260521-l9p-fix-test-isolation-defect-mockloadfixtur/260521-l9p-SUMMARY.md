---
phase: quick-260521-l9p
plan: 01
status: complete
subsystem: test-infrastructure
tags: [test-isolation, mock-registry, phase-7, wr-01]
requires:
  - "MockLoadFixtureRegistry.resetForTestOnly() (Phase 10 seam, already in production)"
provides:
  - "Green full-suite run for AppContainerLoadEndpointsConfigSwapTests"
affects:
  - validationLedgerTests/App/AppContainerNetworkConfigTests.swift
tech-stack:
  added: []
  patterns:
    - "Test helpers that reset MockURLProtocol must also clear the MockLoadFixtureRegistry process-lifetime guard via resetForTestOnly()"
key-files:
  created: []
  modified:
    - validationLedgerTests/App/AppContainerNetworkConfigTests.swift
decisions:
  - "Clear the WR-01 guard in the helper but do NOT call registerAppDefaults() — registration stays the job of AppContainer.init's DEBUG block (SC #5 invariant)"
metrics:
  duration: ~5 min
  completed: 2026-05-21
  tasks: 2
  files: 1
---

# Quick Task 260521-l9p: Fix test-isolation defect — MockLoadFixtureRegistry guard Summary

Added `MockLoadFixtureRegistry.resetForTestOnly()` to the `resetMockURLProtocol()` helper in `AppContainerLoadEndpointsConfigSwapTests`, so a later test's fresh `AppContainer.init` re-registers the Load handlers instead of no-op'ing on the leaked process-lifetime WR-01 idempotency guard.

## What Was Done

### Task 1 — Reset the MockLoadFixtureRegistry guard in resetMockURLProtocol()

Modified the private `resetMockURLProtocol()` helper in the `AppContainerLoadEndpointsConfigSwapTests` struct (`AppContainerNetworkConfigTests.swift`). Added a third statement after `MockURLProtocol.resetFailureHandlers()`:

```swift
MockLoadFixtureRegistry.resetForTestOnly()
```

This clears the process-lifetime `hasRegisteredAppDefaults` guard (the WR-01 fix) so the next `AppContainer.init` constructed inside a test body re-runs `registerAppDefaults()` and re-installs the Load handlers. Previously the helper cleared only the `MockURLProtocol` handler arrays — leaving the guard `true` after the first test, so every later test's Load request 404'd.

The helper's doc-comment was expanded to explain the new line: it states the helper clears the `MockLoadFixtureRegistry` process-lifetime guard (WR-01, `MockLoadFixtureRegistry.swift` lines 84-111) via the DEBUG-gated `resetForTestOnly()` seam (lines 113-125), but deliberately does NOT call `registerAppDefaults()` itself — the existing rationale (SC #5 requires `AppContainer.init`'s DEBUG block to be the thing wiring the handlers; pre-registering here would produce a false-positive) is preserved.

No production-file edits. `resetForTestOnly()` is `#if DEBUG`-gated and reachable via the existing `@testable import validationLedger` with no new import.

**Verification:** Scoped serial run of `AppContainerLoadEndpointsConfigSwapTests` + `AppContainerNetworkConfigTests` — 7/7 tests in 2 suites passed. All 3 SC #5 tests green (`mockConfigEndToEndSwap`, `liveConfigCompileCleanSwap`, `mockConfigEndToEndDecode`); sibling `AppContainerNetworkConfigTests` (4 tests) still green.

**Commit:** `d8df71c`

### Task 2 — Confirm no cross-suite regression from the new reset seam

No code change — regression gate for the new `resetForTestOnly()` call. Ran the MockLoadFixtureRegistry-dependent suites serially in scoped invocations:

- `MockLoadFixtureRegistryActionToggleTests` (XCTest) — 9/9 passed
- `CarrierDirectoryMockTests` (Swift Testing) — passed
- `MockLoadActionDispatchTests` (Swift Testing) — 5/5 passed

No suite regressed from the Task 1 change. The two correctly-written sibling suites (`MockLoadFixtureRegistryActionToggleTests`, `CarrierDirectoryMockTests`) re-register in their own setUp and are immune to sibling guard-clears, as the plan predicted.

## Deviations from Plan

### Out-of-scope discovery (not fixed — per Task 2 instruction)

**`RoleLoadsTabSmokeTests` does not exist in the codebase.** The plan named four MockLoadFixtureRegistry-dependent suites for the Task 2 regression gate, but `RoleLoadsTabSmokeTests` is not present as a `@Suite` struct or `XCTestCase` class anywhere under `validationLedgerTests/`. `xcodebuild`'s `-only-testing:` silently ignores a non-existent suite identifier, so the Task 2 verify command ran only the three suites that exist. The other three named suites all exist and pass. This is a plan-authoring naming error, not a code defect — per the Task 2 instruction ("If a suite was already failing for an unrelated pre-existing reason, note it in the SUMMARY as out-of-scope; do not attempt to fix it in this quick plan"), no suite was created. The fix's intent — confirming no cross-suite regression — is fully satisfied by the three real suites that ran green.

No other deviations. No auto-fixed bugs (Rules 1-3 not triggered). No architectural changes (Rule 4 not triggered).

## Verification Results

- `AppContainerLoadEndpointsConfigSwapTests`: 3/3 pass.
- `AppContainerNetworkConfigTests`: 4/4 pass (sibling suite, shares MockURLProtocol).
- `MockLoadFixtureRegistryActionToggleTests`: 9/9 pass.
- `CarrierDirectoryMockTests`: pass.
- `MockLoadActionDispatchTests`: 5/5 pass.
- `RoleLoadsTabSmokeTests`: does not exist (see Deviations).
- `git diff --stat HEAD~1 HEAD` shows exactly one file changed: `AppContainerNetworkConfigTests.swift` (15 insertions).
- No change to `MockLoadFixtureRegistry.swift` or `AppContainer.swift` — the production WR-01 idempotency guard is intact.
- All test runs used the scoped serial simulator-lane command (`-skip-testing:validationLedgerDeviceTests -parallel-testing-enabled NO`), never bare `xcodebuild test`.

## Success Criteria

- [x] The two previously-failing tests (`mockConfigEndToEndSwap`, `mockConfigEndToEndDecode`) pass deterministically as part of their full suite.
- [x] The fix is a single test-helper line plus its doc-comment — no production code touched.
- [x] The WR-01 idempotency guard still no-ops repeat `registerAppDefaults()` calls within a process (production file unchanged).
- [x] No sibling or MockLoadFixtureRegistry-dependent suite regresses.

## Commits

- `d8df71c`: test(quick-260521-l9p-01): clear MockLoadFixtureRegistry guard in resetMockURLProtocol()

## Self-Check: PASSED

- SUMMARY.md exists at the expected path.
- `AppContainerNetworkConfigTests.swift` exists and contains `MockLoadFixtureRegistry.resetForTestOnly()`.
- Commit `d8df71c` exists in git history.
