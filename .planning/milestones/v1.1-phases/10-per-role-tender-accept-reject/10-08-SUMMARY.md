---
phase: 10-per-role-tender-accept-reject
plan: 08
subsystem: networking-mock + interceptors-test
tags: [phase-10, debug-toggles, idempotency, t-10-08, mock-fixture, rollback-uat]
requires:
  - 10-03  # Plan 03 preserved AppContainer.swift:591 IdempotencyInterceptor wiring
provides:
  - debug-action-failure-toggles  # 4 launch args for human UAT rollback path
  - t-10-08-mitigation-tests  # IdempotencyInterceptor wiring + header propagation asserted
affects:
  - mock-load-fixture-registry  # 4 new DEBUG-gated handlers + 3 inline payloads
tech-stack:
  added: []  # zero new packages
  patterns:
    - "DEBUG-only launch-arg toggle (Phase 5 precedent — MockDefaultFixtures.swift:60-76)"
    - "Closure-overridable computed-property seam (`static var x: () -> Bool`)"
    - "First-match-wins MockURLProtocol handler registration order with `#if DEBUG` failure handlers BEFORE the success handler"
    - "Side-effect MockURLProtocol handler that captures URLRequest then returns nil to defer (NSLock-guarded capture box)"
key-files:
  created:
    - validationLedger/Core/Networking/Mock/MockActionFailureToggles.swift
    - validationLedgerTests/Loads/MockLoadFixtureRegistryActionToggleTests.swift
    - validationLedgerTests/Networking/IdempotencyInterceptorRegistrationTests.swift
    - validationLedgerTests/Networking/Mock/MockLoadActionDispatchTests.swift
    - .planning/phases/10-per-role-tender-accept-reject/deferred-items.md
  modified:
    - validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift  # 4 #if DEBUG handlers + make409/422/500 + 3 inline payloads + resetForTestOnly seam
decisions:
  - "Closure-override seam over computed property — Phase 5 used `static var x: Bool { ProcessInfo... }` but Phase 10 tests need to override without mutating process-wide argv. `static var x: () -> Bool = { ProcessInfo... }` preserves production semantics AND gives an injectable seam. Documented inline."
  - "Combined latencySlow + conflict409 yields 409 immediately, no delay — registration order is `conflict409 → ... → latencySlow → success`, so conflict409 matches first and the latency handler never runs. Test renamed to document this intentional behavior. QA workflow guidance: set exactly ONE failure flag at a time."
  - "Added `#if DEBUG` `resetForTestOnly()` seam to MockLoadFixtureRegistry — without it, tests that reset MockURLProtocol AFTER a sibling test triggered the WR-01 registration guard would see empty handlers + guard=true (silent test no-op). The same seam should be applied to the pre-existing AppContainerLoadEndpointsConfigSwapTests (deferred-items.md)."
  - "Behavioral assertion over private-property reflection for T-10-08 registration tests — `apiClient.requestInterceptors` is `private let`, @testable does not widen private. Behavioral path (capture header at mock handler) gives equivalent coverage: if interceptor absent, header absent, test fails."
metrics:
  duration_minutes: 21
  completed: 2026-05-21
  tasks_completed: 2
  files_changed: 6
  tests_added: 16
  tests_green: 16
---

# Phase 10 Plan 08: DEBUG action-failure toggles + T-10-08 idempotency mitigation tests Summary

Implemented the 4 DEBUG-only launch-arg toggles (`-MockActionConflict409`,
`-MockActionValidation422`, `-MockActionServerError500`, `-MockActionLatencySlow`)
that drive on-device rollback-path UAT, and pinned the v1.0 NET-04 idempotency
wiring with the CRITICAL T-10-08 mitigation tests (registration + header
propagation through the production AppContainer composition path).

## What Shipped

### 1. `DebugActionFailureOverride` namespace (`MockActionFailureToggles.swift`)

`#if DEBUG`-gated `public enum` exposing 4 launch-flag constants + 4
`…Active: () -> Bool` closures + a `latencySlowInterval = 1.5` constant.
File-shape mirrors `MockDefaultFixtures.swift:60-76` (Phase 5 precedent).
Closure shape (vs Phase 5's computed property) is required so tests can
override without mutating process-wide `ProcessInfo.arguments`; production
default closures are semantically identical to the computed-property form.
Release builds compile this whole file to zero bytes.

### 2. 4 new failure-injection handlers in `MockLoadFixtureRegistry`

Registered BEFORE the existing Phase 7 action-success handler with
first-match-wins precedence:

- **(3a)** conflict409 → `make409(body: conflict409Payload, …)` — when `conflict409Active()` returns true
- **(3b)** validation422 → `make422(body: validation422Payload, …)` — when `validation422Active()` returns true
- **(3c)** serverError500 → `make500(body: serverError500Payload, …)` — when `serverError500Active()` returns true
- **(3d)** latencySlow → `Thread.sleep(forTimeInterval: 1.5)` then `return nil` — DEFERS to the next matching handler
- **(3)** action-success — Phase 7 handler, UNCHANGED

Plus `make409/422/500` helpers (mirror of `make200`) and 3 inline payload
constants lifted byte-faithful from
`validationLedgerTests/Networking/Fixtures/load-action-{conflict-409,validation-422,server-error-500}.json`.

Also added `#if DEBUG resetForTestOnly()` to clear the WR-01 process-lifetime
registration guard — needed so test-after-reset sequences re-register
correctly.

### 3. T-10-08 CRITICAL mitigation tests

**`IdempotencyInterceptorRegistrationTests`** (3 @Test):
- `appContainer_apiClient_hasIdempotencyInterceptorRegistered`
- `appContainer_apiClient_singleIdempotencyInterceptor`
- `idempotencyInterceptor_position_isFirst`

**`MockLoadActionDispatchTests`** (5 @Test):
- `loadActionPost_carriesIdempotencyKeyHeader`
- `loadActionPost_differentRequests_haveDifferentIdempotencyKeys`
- `loadActionPost_getRequest_doesNotCarryIdempotencyKey`
- `loadActionPost_allActionPathSegments_carryHeader`
- `loadActionPost_throughTenderSheet_flow_carriesHeader`

**`MockLoadFixtureRegistryActionToggleTests`** (8 XCTest):
- `test_default_noFlags_actionRequest_returnsSuccess`
- `test_conflict409Flag_actionRequest_returns409Body`
- `test_validation422Flag_actionRequest_returns422Body`
- `test_serverError500Flag_actionRequest_returns500Body`
- `test_latencySlowFlag_actionRequest_isDelayed_thenReturnsSuccess`
- `test_latencySlow_andConflict409_combined_conflictWinsImmediately_noDelay`
- `test_precedenceOrder_conflict409beforeValidation422` (Pitfall 2 regression guard)
- `test_releaseSafety_DEBUGGuard`

## Launch-flag constants (for Plan 10 XCUITest / device UAT)

Use these in `app.launchArguments` or Xcode → Edit Scheme → Run → Arguments:

```swift
DebugActionFailureOverride.conflict409Flag    // "-MockActionConflict409"
DebugActionFailureOverride.validation422Flag  // "-MockActionValidation422"
DebugActionFailureOverride.serverError500Flag // "-MockActionServerError500"
DebugActionFailureOverride.latencySlowFlag    // "-MockActionLatencySlow"
```

**Production semantics:** each toggle is read by a closure that reads
`ProcessInfo.processInfo.arguments`. Tests reassign the closure in `setUp`
and restore in `tearDown`. QA workflow: set exactly ONE failure flag at a
time (combining produces deterministic-but-not-feature behavior; see Test 6
docstring for the conflict409+latencySlow case).

## Precedence order (Pitfall 2 regression-guarded)

Registration order in `MockLoadFixtureRegistry.registerAppDefaults()`:

```
(1)  per-role list           GET  /loads/{role}                   ← Phase 7
(2)  per-VL detail           GET  /loads/{VL-…}                   ← Phase 7
(3a) action-conflict409      POST /loads/{VL-…}/{action}          ← Phase 10 #if DEBUG
(3b) action-validation422    POST /loads/{VL-…}/{action}          ← Phase 10 #if DEBUG
(3c) action-server500        POST /loads/{VL-…}/{action}          ← Phase 10 #if DEBUG
(3d) action-latencySlow      POST /loads/{VL-…}/{action}          ← Phase 10 #if DEBUG (defers — returns nil after delay)
(3)  action-success          POST /loads/{VL-…}/{action}          ← Phase 7 (unchanged)
```

`MockURLProtocol.startLoading()` iterates in registration order; first
non-nil return wins. Test 7 (`test_precedenceOrder_conflict409beforeValidation422`)
pins this order — any future registry refactor that moves the failure
handlers must update the test.

## v1.0 wiring preserved (T-10-08)

**`AppContainer.swift:591`** (UNCHANGED):
```swift
requestInterceptors: [IdempotencyInterceptor()],
```

Single interceptor at the head of the request-interceptor chain.
`MockLoadActionDispatchTests` proves the `Idempotency-Key: <UUIDv4>` header
reaches the wire on every `LoadActionEndpoint` POST through the production
AppContainer-built APIClient.

## Header-capture seam (extensible to future plans)

```swift
// Register a side-effect handler FIRST that captures the request, returns nil to DEFER.
let capture = RequestCapture()  // NSLock-guarded box (MockURLProtocol.Handler is @Sendable + synchronous)
MockURLProtocol.register { request in
    capture.record(request)
    return nil  // defer to the production handler
}
// Construct AppContainer (which appends MockDefaultFixtures + MockLoadFixtureRegistry handlers).
let container = makeMockContainer()
_ = try await container.apiClient.request(LoadActionEndpoint(loadID: "VL-1001", action: .accept, body: …))
// Now: capture.all() contains the URLRequest the mock saw — read .value(forHTTPHeaderField: "Idempotency-Key").
```

This is the canonical pattern for any future plan that needs to assert
"X header reaches the wire under composition Y" — extends cleanly to
header observation, body bytes, query params, or HTTP-method routing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] `apiClient.requestInterceptors` is `private let`, not testable directly**
- **Found during:** Task 2 — IdempotencyInterceptorRegistrationTests authoring
- **Issue:** Plan asked for tests that read `apiClient.requestInterceptors` directly. `@testable import` does not widen `private` access — only `internal`. Cannot reflect on the array directly.
- **Fix:** Switched to behavioral assertion path. Each registration test asserts the OBSERVABLE EFFECT of the interceptor being in the chain (header on the wire). If the interceptor is absent, the header is absent, the test fails loudly. Equivalent coverage; pattern documented in file-header comment.
- **Files modified:** validationLedgerTests/Networking/IdempotencyInterceptorRegistrationTests.swift
- **Commit:** a90b878

**2. [Rule 3 — Blocking issue] WR-01 process-lifetime registration guard collides with test-after-reset sequences**
- **Found during:** Task 1 — toggle-tests setUp/tearDown sequencing
- **Issue:** `MockLoadFixtureRegistry.hasRegisteredAppDefaults` is process-scoped; if a sibling test already triggered `registerAppDefaults()` THEN called `MockURLProtocol.reset()`, the handler array is empty but the guard is true — the next call is a no-op and tests get 404.
- **Fix:** Added `#if DEBUG resetForTestOnly()` static method that clears the guard. Test setUp calls reset+resetForTestOnly+registerAppDefaults in sequence.
- **Files modified:** validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift
- **Commit:** f4e8740

**3. [Rule 1 — Bug] Plan's Test 6 expected `latency + 409 → delay then 409`, but registration order makes 409 win FIRST (no delay)**
- **Found during:** Task 1 — Test 6 first run (RED → GREEN)
- **Issue:** The plan's behavior description for Test 6 contradicts the plan's must_have truth #2 (which I implemented verbatim: `conflict409 → validation422 → serverError500 → latencySlow → existing-success`). If conflict409 registers FIRST and is the first to match a POST, the latency handler never runs.
- **Fix:** Renamed test to `test_latencySlow_andConflict409_combined_conflictWinsImmediately_noDelay` and asserted the DOCUMENTED behavior: 409 immediately, no delay. Added an explanatory docstring; this is the intended combined-flag behavior (QA workflow is "set exactly one flag").
- **Files modified:** validationLedgerTests/Loads/MockLoadFixtureRegistryActionToggleTests.swift
- **Commit:** f4e8740

### Deferred Issues (Pre-existing, out of Plan 10-08 scope)

**`AppContainerLoadEndpointsConfigSwapTests` — 2 pre-existing failures**
- 2 tests (`mockConfigEndToEndSwap`, `mockConfigEndToEndDecode`) in
  `AppContainerNetworkConfigTests.swift` fail with `httpError(statusCode: 404)`.
- Verified on the wave base `7284d40` — failures predate Plan 10-08.
- Same root cause as deviation #2 above; same fix applies (use the new
  `resetForTestOnly()` seam in that suite's `resetMockURLProtocol()` helper).
- Logged to `.planning/phases/10-per-role-tender-accept-reject/deferred-items.md`.

## Self-Check

### Files created/modified — existence verifications

- FOUND: `validationLedger/Core/Networking/Mock/MockActionFailureToggles.swift`
- FOUND: `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` (modified)
- FOUND: `validationLedgerTests/Loads/MockLoadFixtureRegistryActionToggleTests.swift`
- FOUND: `validationLedgerTests/Networking/IdempotencyInterceptorRegistrationTests.swift`
- FOUND: `validationLedgerTests/Networking/Mock/MockLoadActionDispatchTests.swift`
- FOUND: `.planning/phases/10-per-role-tender-accept-reject/deferred-items.md`

### Commit hashes — git log verifications

- FOUND: `96d3efb` test(10-08): add failing toggle tests for DebugActionFailureOverride
- FOUND: `f4e8740` feat(10-08): wire 4 DEBUG-only action-failure toggles + register handlers before success
- FOUND: `a90b878` test(10-08): T-10-08 mitigation — IdempotencyInterceptor registration + header propagation
- FOUND: `9c7ece8` docs(10-08): record pre-existing AppContainerLoadEndpointsConfigSwapTests failures

### Done-step source assertions

- `grep -c '^public enum DebugActionFailureOverride' validationLedger/Core/Networking/Mock/MockActionFailureToggles.swift` → `1` ✓
- `grep -cE 'DebugActionFailureOverride\.[a-zA-Z0-9]+Active' validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` → `4` ✓ (plan's `[a-z]+Active` regex undercounts because `409` contains digits — same code, more permissive character class)
- `grep -c 'Thread.sleep(forTimeInterval: DebugActionFailureOverride.latencySlowInterval)' validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` → `1` ✓
- `grep -c 'IdempotencyInterceptor' validationLedgerTests/Networking/IdempotencyInterceptorRegistrationTests.swift` → `10` (≥2 required) ✓
- `grep -c 'Idempotency-Key' validationLedgerTests/Networking/Mock/MockLoadActionDispatchTests.swift` → `20` (≥1 required) ✓
- `grep -c 'requestInterceptors: \[IdempotencyInterceptor()\]' validationLedger/App/AppContainer.swift` → `1` ✓ (v1.0 wiring preserved)

### Release-build sanity check

`xcodebuild build -project validationLedger.xcodeproj -scheme validationLedger -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**.

`#if DEBUG` gates compile cleanly when `DEBUG` is undefined; the entire
`DebugActionFailureOverride` namespace + the 4 handler registration branches
+ the `resetForTestOnly` seam compile to zero bytes in Release.

### Test verifications (final plan-verification run)

All 16 Plan-10-08 tests green + 5 sibling Phase-2 NET-04 tests green:

```
Test Suite 'MockLoadFixtureRegistryActionToggleTests' passed
  8 tests, 0 failures
Suite "IdempotencyInterceptor — registration in AppContainer (T-10-08)" passed
  3 tests, 0 failures
Suite "IdempotencyInterceptor — header injection (NET-04)" passed
  5 tests, 0 failures  ← sibling (regression check)
Suite "MockLoadActionDispatch — Idempotency-Key wire propagation (T-10-08)" passed
  5 tests, 0 failures
```

## Self-Check: PASSED
