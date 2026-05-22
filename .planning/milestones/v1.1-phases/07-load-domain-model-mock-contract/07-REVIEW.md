---
phase: 07-load-domain-model-mock-contract
reviewed: 2026-05-19T00:00:00Z
depth: standard
files_reviewed: 49
files_reviewed_list:
  - validationLedger/App/AppContainer.swift
  - validationLedger/Core/Load/ChainIntegrity.swift
  - validationLedger/Core/Load/ChainOfTrust.swift
  - validationLedger/Core/Load/DeviceBindingStatus.swift
  - validationLedger/Core/Load/Load.swift
  - validationLedger/Core/Load/LoadAction.swift
  - validationLedger/Core/Load/LoadStatus.swift
  - validationLedger/Core/Load/LoadStatusEvent.swift
  - validationLedger/Core/Load/RoleLoadPolicy.swift
  - validationLedger/Core/Load/USDOTAuthorityStatus.swift
  - validationLedger/Core/Load/VerificationState.swift
  - validationLedger/Core/Networking/Endpoints/LoadActionEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift
  - validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift
  - validationLedger/Core/Networking/Mock/MockURLProtocol.swift
  - validationLedger/Roles/Role.swift
  - validationLedgerTests/App/AppContainerNetworkConfigTests.swift
  - validationLedgerTests/Load/ChainOfTrustDecodeTests.swift
  - validationLedgerTests/Load/LoadDomainDecodeTests.swift
  - validationLedgerTests/Load/LoadStateHistoryTests.swift
  - validationLedgerTests/Load/RoleLoadPolicyTests.swift
  - validationLedgerTests/Load/VerificationStateDecoderTests.swift
  - validationLedgerTests/Networking/LoadEndpointsTests.swift
  - validationLedgerTests/Networking/MockURLProtocolForcedFailureTests.swift
  - validationLedgerTests/Networking/MockURLProtocolLatencyTests.swift
  - validationLedgerTests/Networking/Fixtures/loads-list-broker.json
  - validationLedgerTests/Networking/Fixtures/loads-list-carrier.json
  - validationLedgerTests/Networking/Fixtures/loads-list-dispatch.json
  - validationLedgerTests/Networking/Fixtures/loads-list-empty.json
  - validationLedgerTests/Networking/Fixtures/loads-list-factoring.json
  - validationLedgerTests/Networking/Fixtures/loads-list-shipper.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1001.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1002.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1003.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1004.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1005.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1006.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1007.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1008.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1009.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1010.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1011.json
  - validationLedgerTests/Networking/Fixtures/load-detail-VL-1012.json
  - validationLedgerTests/Networking/Fixtures/load-action-success.json
  - validationLedgerTests/Networking/Fixtures/load-action-conflict-409.json
  - validationLedgerTests/Networking/Fixtures/load-action-validation-422.json
  - validationLedgerTests/Networking/Fixtures/load-action-server-error-500.json
  - .planning/phases/07-load-domain-model-mock-contract/07-CONTEXT.md
findings:
  critical: 0
  warning: 3
  info: 2
  total: 5
status: issues_found
---

# Phase 7: Load Domain Model & Mock Contract — Code Review Report

**Reviewed:** 2026-05-19
**Depth:** standard
**Files Reviewed:** 49
**Status:** issues_found

## Summary

This phase delivers the Core/Load/ domain model, three typed APIEndpoint conformers, the MockLoadFixtureRegistry, additive latency/forced-failure injection on MockURLProtocol, and the full 22-fixture test matrix. The implementation is structurally sound and nearly complete. The fail-closed security primitives (D-09) are correctly implemented and exhaustively tested. The DEBUG gate (Threat T-07-27) is present and correct. D-17's no-reset() contract is honoured. D-19's POST method is in place.

Three findings were identified. None are correctness bugs in production code paths. Two are test-infrastructure reliability gaps that could cause intermittent failures under Swift Testing's parallel scheduler; one is a latent maintenance footgun in the duplicate-handler registration pattern introduced by `AppContainerLoadEndpointsConfigSwapTests`.

---

## Warnings

### WR-01: `reset()` does not clear forced-failure handlers — violates stated "reset() story" requirement

**File:** `validationLedger/Core/Networking/Mock/MockURLProtocol.swift:57-59`

**Issue:** The phase emphasis block explicitly requires: *"MockURLProtocol.reset() must still clear all state, including the new latency/forced-failure state added in Wave 1."* Latency fixtures are routed through the existing `register(_:)` API and therefore ARE cleared by `reset()`. However, forced-failure handlers live in a separate `_failureHandlers` array that is only cleared by the separate `resetFailureHandlers()` method. `reset()` does not touch `_failureHandlers`.

This is a genuine design violation of the stated invariant. Any test author who reasonably infers that `reset()` fully resets MockURLProtocol state — consistent with its documented role as the canonical teardown call — will leave stale forced-failure handlers visible to subsequent tests. The risk is compounded by:

1. `AppContainerLoadEndpointsConfigSwapTests` defers only `MockURLProtocol.reset()` (not `resetFailureHandlers()`). If `MockURLProtocolForcedFailureTests` runs in parallel (Swift Testing can parallelize between separate `.serialized` suites), a stale `.urlError(.timedOut)` or `.http(409:...)` handler could survive into the `AppContainer` end-to-end tests, causing them to fail with an unexpected error rather than the broker/carrier fixture.

2. The forced-failure tests do call both reset functions correctly. But the split contract creates a two-call ceremony that future test authors will miss.

The inline comment documents the split: *"resetFailureHandlers() clears it WITHOUT touching _handlers (must_haves truth #3: reset() body preserved byte-identical)"*. The SC #5 byte-identical constraint on `reset()` is real, but the solution creates an undocumented footgun.

**Fix:** Two acceptable approaches, in preference order:

Option A — Make `reset()` widen internally while preserving byte-identical calling convention. The SC #5 requirement is about the *external API* not changing; adding a `failureHandlersLock.withLock { _failureHandlers.removeAll() }` call inside `reset()` does not change the calling convention at all. The "byte-identical body" comment is over-reading SC #5.

```swift
public static func reset() {
    handlersLock.withLock { _handlers.removeAll() }
    // Also clear failure handlers so callers have one authoritative teardown call.
    failureHandlersLock.withLock { _failureHandlers.removeAll() }
}
```

Option B — If SC #5 is interpreted strictly as byte-identical body, add an overload with a clear name and update `AppContainerLoadEndpointsConfigSwapTests` defers:

```swift
// In every test that could share state with forced-failure tests:
defer {
    MockURLProtocol.reset()
    MockURLProtocol.resetFailureHandlers()
}
```

Whichever option is chosen, update the doc comment on `reset()` to explicitly state whether forced-failure handlers are or are not cleared.

---

### WR-02: `AppContainerLoadEndpointsConfigSwapTests` double-registers load handlers, obscuring real wiring coverage

**File:** `validationLedgerTests/App/AppContainerNetworkConfigTests.swift:170-208`

**Issue:** The `registerLoadFixtures()` helper calls `MockURLProtocol.reset()` then `MockLoadFixtureRegistry.registerAppDefaults()`. It is then immediately followed by constructing `AppContainer(env:networkConfig:.mock)`. In DEBUG, `AppContainer.init` unconditionally calls both `MockDefaultFixtures.registerAppDefaults()` and `MockLoadFixtureRegistry.registerAppDefaults()` again when `resolvedConfig == .mock`.

The handler list at request time is therefore:
```
[load-handlers-A (from registerLoadFixtures)]
[MockDefaultFixtures-handlers (from AppContainer init)]
[load-handlers-B (from AppContainer init)]  ← duplicate
```

Tests pass because first-match-wins returns `load-handlers-A`'s result. But the actual production registration path — what `AppContainer.init` does — is never tested in isolation: the test pre-populates the registry before `AppContainer` adds its handlers, so the `AppContainer`-registered handlers (B) are effectively shadowed and never exercised.

If `MockLoadFixtureRegistry.registerAppDefaults()` were removed from the `AppContainer` DEBUG block, these tests would still pass (because A was registered before the container was built). The intended SC #5 claim — that "the 3 new Load endpoints flow through AppContainer.init's DEBUG block" — is therefore not actually proven by Tests 1 and 3.

**Fix:** Remove the pre-population step from `registerLoadFixtures()` and rely solely on `AppContainer.init` to register the fixtures, which is what SC #5 actually tests:

```swift
private func registerLoadFixtures() {
    MockURLProtocol.reset()
    // Do NOT call MockLoadFixtureRegistry.registerAppDefaults() here.
    // AppContainer(networkConfig: .mock) registers both MockDefaultFixtures
    // and MockLoadFixtureRegistry in its DEBUG block — that is the production path.
}
```

Then the defer in each test must clean up the state that AppContainer registered:

```swift
defer {
    MockURLProtocol.reset()
    MockURLProtocol.resetFailureHandlers()
}
```

---

### WR-03: `actionPathSegments` in `MockLoadFixtureRegistry` is a maintenance-coupled literal set

**File:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift:149-151`

**Issue:** The action-success handler validates the path segment against a hardcoded `Set<String>`:

```swift
private static let actionPathSegments: Set<String> = [
    "post", "tender", "accept", "reject", "cancel", "status",
]
```

The comment correctly identifies this as a drift risk: *"if a new LoadAction case is added, this set must be extended in lock-step."* However, the set is not derived from `LoadAction.allCases.map { $0.pathSegment }`. If a new `LoadAction` case is added (e.g., `.reassign`) with a new `pathSegment`, the production `RoleLoadPolicy` and endpoint will compile and run correctly, but the DEBUG tap-through action handler will silently return `nil` (falling through to 404) for the new action. This will not surface as a compiler error.

The registry is `#if DEBUG`-only, so this is not a production correctness bug. But it breaks the DEBUG tap-through for the new action before a developer catches it, potentially causing confusion during Phase 10 development.

**Fix:** Derive the set from the source of truth at static initialisation time. Since `MockLoadFixtureRegistry` is `#if DEBUG`-only, the `LoadAction.allCases` reference is safe:

```swift
private static let actionPathSegments: Set<String> =
    Set(LoadAction.allCases.map { $0.pathSegment })
```

This removes the manual sync requirement and makes any future `LoadAction` addition automatically appear in the DEBUG handler.

---

## Info

### IN-01: `LoadDetailEndpoint` and `LoadActionEndpoint` perform no client-side sanitisation of `loadID`

**File:** `validationLedger/Core/Networking/Endpoints/LoadDetailEndpoint.swift:52` and `validationLedger/Core/Networking/Endpoints/LoadActionEndpoint.swift:127`

**Issue:** Both endpoints compose their `path` by interpolating `loadID` directly:

```swift
self.path = "/loads/\(loadID)"
self.path = "/loads/\(loadID)/\(action.pathSegment)"
```

A `loadID` containing `/` (e.g., `"VL-1001/../admin"`) would produce a path with extra segments. For the mock backend this is harmless — the fixture registry guards `!suffix.contains("/")` before dispatching — but for the real backend it would be a malformed request path. Since `loadID` is sourced from `Load.id`, which itself is decoded from the server response, a malicious backend would be required to exploit this. The risk is therefore server-trust-boundary, not a client validation failure.

**Fix:** Add a precondition in `DEBUG` builds to catch invalid IDs during development:

```swift
public init(loadID: String) {
    assert(!loadID.contains("/"), "loadID must not contain path separators: \(loadID)")
    self.path = "/loads/\(loadID)"
}
```

---

### IN-02: Missing `Equatable` conformance declaration on `LoadAction` (relies on implicit synthesis)

**File:** `validationLedger/Core/Load/LoadAction.swift:29`

**Issue:** `RoleLoadPolicyTests` compares `[LoadAction]` arrays with `==`, which requires `LoadAction: Equatable`. The conformance is provided implicitly because `LoadAction` has a `String` raw value and Swift auto-synthesizes `Equatable` for `RawRepresentable` enums whose `RawValue` is `Equatable`. This works correctly today.

However, the code comment in `RoleLoadPolicyTests.swift:15-16` acknowledges this reliance: *"Swift synthesizes Equatable for String-raw enums automatically."* Making the conformance explicit documents intent and removes the reliance on a synthesis rule that, while stable, is easy to miss when reviewing the type definition in isolation.

**Fix:** Add the conformance explicitly:

```swift
public enum LoadAction: String, Sendable, CaseIterable, Equatable {
```

---

_Reviewed: 2026-05-19_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
