---
phase: 10-per-role-tender-accept-reject
plan: 03
subsystem: load-detail-action-state-machine
tags: [swift, ios, vm, state-machine, optimistic-ui, rollback, bl-01, cancel-and-replace, xctest, tdd, wave-2]

# Dependency graph
requires:
  - phase: 10-per-role-tender-accept-reject
    plan: 01
    provides: LoadActionPredictor.predict(load:action:body:) -> Load — the pure forward predictor; Load.with(status:respondByAt:) extension; LoadStatus.localizedDisplayName.
  - phase: 10-per-role-tender-accept-reject
    plan: 02
    provides: RoleLoadPolicy.availableActions(for:in:) wrapper; LoadActionTitleResolver namespace — consumed by Plan 04 (NOT this plan). Plan 03 depends on Plan 02 only insofar as both wave-2 plans share the Phase 7 frozen surface; no direct symbol consumption.
  - phase: 07-load-domain-contract-and-mock-endpoints
    provides: Load + ChainOfTrust value types; LoadAction 6-case enum; LoadActionEndpoint typed POST; IdempotencyInterceptor (already in apiClient.requestInterceptors at AppContainer.swift:572 — T-10-08 mitigation, byte-identical in this plan).
  - phase: 09-load-detail
    provides: LoadDetailViewModel 3-case state machine; BL-01 cancel-and-replace pattern (performFetch); userFacingMessage(for:); LoadDetailViewController.render(state:); the T-09-04 fields: [:] view-layer lock.
provides:
  - "LoadDetailViewModel.State.actionInFlight(predicted: Load, frozenChain: ChainOfTrust, action: LoadAction) — Phase 10 D-12 / D-13 optimistic-UI in-flight transition."
  - "LoadDetailViewModel.State.actionFailed(rollbackTo: Load, frozenChain: ChainOfTrust, errorCopyKey: String) — Phase 10 D-15 rollback terminal state."
  - "LoadDetailViewModel.submit(action: LoadAction, body: LoadActionEndpoint.RequestBody) async — single public action-submission entry; BL-01 cancel-and-replace verbatim per PATTERNS §8."
  - "LoadDetailViewModel.role (public let) — D-22 / D-23: session role set at designated-init time, fixed for the screen's lifetime; consumed by Plan 04's RoleLoadPolicy.availableActions(for: viewModel.role, in: load) call."
  - "LoadDetailViewModel.errorCopyKey(for: LoadAction) -> String — nonisolated static; exhaustive switch (no default arm) over the 6 LOCKED per-action localization keys per UI-SPEC line 343-348."
  - "AppContainer.makeLoadDetailScreen(loadID:role:) — composition-root factory signature evolution; the factory closure inside makeLoadListScreen(role:) captures the outer role and forwards it."
affects:
  - "10-04-PLAN — render arms for .actionInFlight + .actionFailed (currently MINIMAL stubs in this plan; Plan 04 lands the action-region UI overlay + the localized error banner reading state.actionFailed.errorCopyKey)."
  - "10-08-PLAN — IdempotencyInterceptor header-on-the-wire assertion (this plan's Test 6 proves the dispatch path reaches LoadActionEndpoint; Plan 08 owns the header propagation assertion)."

# Tech tracking
tech-stack:
  added: []  # No new SwiftPM packages, no new SDKs. Phase 10 installs ZERO new dependencies (per 10-RESEARCH § Package Legitimacy Audit).
  patterns:
    - "BL-01 cancel-and-replace extended from fetchLoadDetail() to submit(action:body:) — a twin actionTask slot; [weak self] capture inherits the Phase 9 Pitfall-9 safety."
    - "submit() guard accepts {.loaded, .actionInFlight, .actionFailed} predecessors — necessary for Test 5's cancel-and-replace invariant (broader than the PATTERNS §8 verbatim shape, which only listed .loaded; the broader guard is correct per the must_haves truth 'rapid back-tap mid-action inherits the Phase 9 safety')."
    - "errorCopyKey resolver as a nonisolated static exhaustive switch — no default arm; a new LoadAction case forces a compile-time update here (Plan 04's view layer never invents an error key)."
    - "Test infrastructure duplication between LoadDetailViewModelActionTests + LoadDetailViewModelRollbackTests (~150 lines of MockAPIClient + RecordingLogger + StateRecorder + PathCapturingRequestInterceptor + makeLoad/makeChain/makeActionResponseBody helpers) — keeps each file self-contained per the Plan 10-03 Task 2 <action> block's permission ('extract to a small shared file or duplicate the small spies'); chose duplication."
    - "Minimal VC render arms for the two new states (applyLoadedRender against the predicted/rollback Load + frozen chain) — Rule 3 fix to satisfy Swift exhaustiveness; Plan 04 will overlay the action-region UI without changing what's rendered here."

key-files:
  created:
    - validationLedgerTests/Loads/LoadDetailViewModelActionTests.swift  # 737 lines, 7 XCTest cases (Task 1)
    - validationLedgerTests/Loads/LoadDetailViewModelRollbackTests.swift  # 687 lines, 8 XCTest cases (Task 2)
    - .planning/phases/10-per-role-tender-accept-reject/10-03-SUMMARY.md
  modified:
    - validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift  # +~140 lines: 2 new State cases, role: Role plumb, submit/performAction/errorCopyKey
    - validationLedger/App/AppContainer.swift  # signature: makeLoadDetailScreen(loadID: String, role: Role); factory closure captures outer role; line 572 IdempotencyInterceptor() UNCHANGED
    - validationLedger/Features/Loads/Detail/LoadDetailViewController.swift  # MINIMAL: 2 new render arms + viewWillAppear suppression for the in-flight/failed states (Rule 3 — Swift exhaustiveness)
    - validationLedger/Features/Loads/LoadListViewController.swift  # docstring update (factory signature reference)
    - validationLedgerTests/Loads/LoadDetailViewModelTests.swift  # makeViewModel adds role: .broker (Rule 3 — existing tests must continue to compile)
    - validationLedgerTests/Loads/LoadDetailViewControllerCompositionTests.swift  # same — role: .broker added at VM init
    - validationLedgerTests/Loads/LoadDetailViewControllerSizeClassRoutingTests.swift  # same — role: .broker added at VM init

decisions:
  - "AppContainer signature change LANDED IN TASK 1 GREEN, not Task 2 (Rule 3 — blocking compile error). The Plan 10-03 Task 2 <action> block scheduled the AppContainer modification for Task 2, but the VM's init signature change (loadID:role:apiClient:logger:) immediately breaks AppContainer's existing call site. Bundling the AppContainer edit into Task 1 GREEN was the smallest atomic change that lets the test build succeed; the alternative — a default value for role: on the VM init — would hide the role-not-plumbed bug class the D-22 must_haves truth explicitly calls out (Pitfall 4: 'no window where role is plumbed but unconsumed')."
  - "submit() guard accepts .actionInFlight + .actionFailed as valid predecessors, NOT only .loaded. PATTERNS §8 verbatim showed only .loaded — but Test 5 (BL-01 cancel-and-replace) requires the second submit() to be able to supersede an in-flight first submit(). Confirmed at iteration 2 of Task 1 GREEN: the strict-loaded guard caused Test 5 to fail with the VM stuck in .actionInFlight permanently after the first task was cancelled. The broadened guard uses the in-flight predicted Load (or the actionFailed rollback Load) as the new pre-tap snapshot, matching the user-visible truth on screen."
  - "Two new VC render arms (.actionInFlight, .actionFailed) added in Plan 03 despite the plan stating 'DO NOT modify LoadDetailViewController.swift in this plan' — Swift's exhaustiveness check is a hard blocker; Rule 3 (auto-fix blocking) authorizes the minimal addition. Each arm calls `applyLoadedRender(predictedOrRollback, frozenChain)` — visually identical to a .loaded render of the same payload; no action-region overlay (Plan 04 owns that). The plan's stated intent ('two new VM states will simply not have a render handler until Plan 04 lands') is unachievable in Swift; the minimal stub is the correct interpretation."
  - "viewWillAppear suppresses re-fetch from .actionInFlight + .actionFailed — the existing logic was '.loaded -> return; else fetch'. Without extending this, returning to the screen while an action is mid-flight would re-fetch and clobber the optimistic UI. Same rationale applies after a rollback: re-fetch would clobber the rollback with a potentially stale cached server payload."
  - "Test framework: XCTest, NOT Swift Testing. Matches the Wave 1 XCTest neighbors (LoadActionPredictorTests, LoadActionTitleResolverTests, RoleLoadPolicyAvailableActionsTests). Honors the ios-test-suite-pitfalls memory: -only-testing silently drops XCTest when mixed with Swift Testing in a single invocation."
  - "Test 1 (test_init_storesRole) is declared async throws (single defensive `await Task.yield()`) despite being a synchronous assertion — XCTest's iOS-sim runner can crash with `malloc: pointer being freed was not allocated` when a synchronous test holds a URLSession with MockURLProtocol that gets released before the next test starts. The async-lane spawn forces proper URLSession invalidation."

requirements-completed:
  - ACTION-01  # broker tender — VM submit() supports the .tender action; predictor + endpoint dispatch verified
  - ACTION-02  # accept/reject — VM submit() supports .accept + .reject; per-action errorCopyKey table covers both
  - ACTION-03  # cancel — VM submit() supports .cancel from non-terminal source statuses; per-action errorCopyKey covers
  - ACTION-04  # status advance — VM submit() supports .advanceStatus; per-action errorCopyKey covers
  - ACTION-05  # optimistic-UI rollback contract — D-15: rollback Load + frozen chain + per-action errorCopyKey verified across 4 fault classes (500/422/409/URLError)
  - ACTION-08  # idempotency — VM submit() dispatches via LoadActionEndpoint (POST); IdempotencyInterceptor at AppContainer.swift:572 is byte-identical; header-on-wire assertion owned by Plan 08

# Metrics
duration: ~33m42s
started_at: 2026-05-21T14:23:02Z
completed_at: 2026-05-21T14:56:44Z
tasks: 2
commits: 3  # Task 1 RED + Task 1 GREEN (bundled AppContainer change per Rule 3) + Task 2 tests
tests_added: 15  # 7 Action + 8 Rollback
tests_green: 15
---

# Phase 10 Plan 03: LoadDetailViewModel Action State Machine + Rollback Contract + Role Plumb — Summary

**The single VM owns the screen's state machine — extended from 3 cases to 5. `submit(action:body:) async` drives the optimistic predict → 200/error → loaded/rollback transition with BL-01 cancel-and-replace; the chain-of-trust is NEVER predicted client-side (D-13); the rollback errorCopyKey is one of the 6 LOCKED per-action localization keys per UI-SPEC line 343-348 (T-09-04 view-layer lock extended). `role: Role` is plumbed all the way from `makeLoadListScreen(role:)` through `makeLoadDetailScreen(loadID:role:)` into the VM's `public let role`, ready for Plan 04's policy-lookup consumer.**

## Performance

- **Duration:** ~33 minutes (one wall-clock pass; no checkpoints)
- **Tasks:** 2 (both TDD discipline; 3 atomic commits — Task 1 RED + Task 1 GREEN + Task 2)
- **Tests:** 15 new XCTest cases — 7 in `LoadDetailViewModelActionTests`, 8 in `LoadDetailViewModelRollbackTests`. 15/15 green on iPhone 17 simulator (scoped, non-parallel).
- **Existing-test stability:** 4 Swift Testing `LoadDetailViewModelTests` cases (Phase 9 fetch path) remain green — no regression.

## Task Commits

| # | Type | Hash | Message |
|---|------|------|---------|
| 1 | test | `0fdb754` | `test(10-03): add failing tests for LoadDetailViewModel submit() + role plumb` (RED — 7 tests; build fails for the right reasons: missing `role:` init parameter, missing `submit`, missing `.actionInFlight`) |
| 2 | feat | `672ec00` | `feat(10-03): extend LoadDetailViewModel with action state machine + role plumb` (GREEN — VM + AppContainer + minimal VC render arms; 7 + 4 = 11 tests green; existing-test compile fix-up for the role parameter addition) |
| 3 | test | `08fb1b3` | `test(10-03): add rollback-path tests for LoadDetailViewModel.submit()` (8 rollback tests pin the D-15 contract + the T-09-04 view-layer lock; the Task 2 production change — AppContainer signature evolution — was already shipped in commit #2 per Rule 3) |

## State Enum Shape (Phase 10 Plan 03)

| Case | Associated values | Purpose |
|------|-------------------|---------|
| `.loading` | — | Phase 9 D-19 skeleton-with-shimmer initial / fresh-fetch state. |
| `.loaded` | `Load, ChainOfTrust` | Phase 9 D-20 + Phase 10 D-14 successful-fetch / successful-action terminal state. |
| `.actionInFlight` | `predicted: Load, frozenChain: ChainOfTrust, action: LoadAction` | **NEW** — Phase 10 D-12 / D-13 optimistic-UI in-flight transition. `predicted` is `LoadActionPredictor.predict(...)` output; `frozenChain` is the pre-tap chain (NEVER predicted client-side). |
| `.actionFailed` | `rollbackTo: Load, frozenChain: ChainOfTrust, errorCopyKey: String` | **NEW** — Phase 10 D-15 rollback terminal state. `rollbackTo` is the pre-tap Load; `errorCopyKey` is one of the 6 LOCKED UI-SPEC line 343-348 localization keys (NEVER a server-supplied substring). |
| `.error` | `message: String` | Phase 9 D-20 fetch-path-only terminal-error state. Locked generic copy `loads.detail.error.generic`; action failures route through `.actionFailed` instead. |

## submit() Signature + Pre-Tap Snapshot Table

```swift
public func submit(action: LoadAction, body: LoadActionEndpoint.RequestBody) async
```

The pre-tap snapshot is derived from the current state (broader than PATTERNS §8 verbatim per the decision-note above):

| Current state | Pre-tap snapshot | Behavior |
|---------------|------------------|----------|
| `.loaded(load, chain)` | `(load, chain)` | Canonical entry point. |
| `.actionInFlight(predicted, frozenChain, _)` | `(predicted, frozenChain)` | Cancel A; B uses A's predicted state as pre-tap (BL-01 cancel-and-replace). |
| `.actionFailed(rollbackTo, frozenChain, _)` | `(rollbackTo, frozenChain)` | Retry after rollback; the rollback snapshot IS the new pre-tap snapshot. |
| `.loading` / `.error` | — | No-op (no load payload). |

## Per-Action `errorCopyKey` Table (UI-SPEC line 343-348 — LOCKED)

Exhaustive switch over the 6 LoadAction cases, no default arm. Plan 04's view layer renders these via `NSLocalizedString` against `state.actionFailed.errorCopyKey`.

| LoadAction | Locked localization key |
|------------|--------------------------|
| `.tender` | `loads.actions.error.tender_failed` |
| `.accept` | `loads.actions.error.accept_failed` |
| `.reject` | `loads.actions.error.reject_failed` |
| `.cancel` | `loads.actions.error.cancel_failed` |
| `.post` | `loads.actions.error.post_failed` |
| `.advanceStatus` | `loads.actions.error.advance_failed` |

The classification (HTTP 4xx/5xx vs URLError vs decode) is LOGGED via `logger?.error(event: LogEvent("load_action_failed"), fields: [:])` but never rendered (UI-SPEC line 354 lock; T-09-04 view-layer lock extended).

## AppContainer Signature Change

Before:
```swift
@MainActor
func makeLoadDetailScreen(loadID: String) -> UIViewController { ... }

// in makeLoadListScreen(role:)
let detailFactory: (String) -> UIViewController = { [weak self] loadID in
    guard let self else { return UIViewController() }
    return self.makeLoadDetailScreen(loadID: loadID)
}
```

After (D-22 / Pitfall 4 — no window where role is plumbed but unconsumed):
```swift
@MainActor
func makeLoadDetailScreen(loadID: String, role: Role) -> UIViewController {
    let featureLogger = OSLogLoggerImpl(subsystem: LoggingSubsystem.app, category: "feature.loads")
    let viewModel = LoadDetailViewModel(loadID: loadID, role: role, apiClient: apiClient, logger: featureLogger)
    return LoadDetailViewController(viewModel: viewModel)
}

// in makeLoadListScreen(role:)
let detailFactory: (String) -> UIViewController = { [weak self] loadID in
    guard let self else { return UIViewController() }
    return self.makeLoadDetailScreen(loadID: loadID, role: role)   // outer-scope role captured
}
```

T-10-08 infrastructure (`requestInterceptors: [IdempotencyInterceptor()]` at AppContainer.swift:572) is **byte-identical** to its pre-Plan-03 form.

## Test Coverage Tables

### `LoadDetailViewModelActionTests` (Task 1 — 7 tests)

| # | Test | Asserts |
|---|------|---------|
| 1 | `test_init_storesRole` | D-22: VM stores `role` at designated-init time; `vm.role == .broker`. |
| 2 | `test_submit_fromLoaded_transitionsToActionInFlight_withPredictedLoad` | D-12 / D-13: predicted Load = `LoadActionPredictor.predict(load: preLoad, action: .tender, body)`; frozen chain = pre-tap chain. |
| 3 | `test_submit_serverResponds200_transitionsToLoaded_withResponseLoadAndChain` | D-14: both `response.load` AND `response.chainOfTrust` swap from the wire (the chain returns a different verdict than the pre-tap). |
| 4 | `test_submit_fromNonLoadedState_isNoOp` | Submit from `.loading` is a no-op: no state transitions, no network dispatch. |
| 5 | `test_submit_cancelAndReplace_supersedesEarlierAction` | BL-01 cancel-and-replace: a fresher `.cancel` supersedes an in-flight `.tender`; terminal state is `.loaded(.cancelled)`, NOT `.loaded(.tendered)`. |
| 6 | `test_submit_pluggedIntoIdempotencyInterceptor_chain_dispatches` | `submit(.tender, ...)` dispatches `POST /loads/{loadID}/tender` (LoadActionEndpoint shape); proves the IdempotencyInterceptor's mutation site is reachable. Plan 08 owns the header-on-the-wire assertion. |
| 7 | `test_submit_concurrentToFetch_doesNotInterfere` | submit() + fetchLoadDetail() are independent lifecycles; both tasks complete cleanly with the well-defined terminal state. |

### `LoadDetailViewModelRollbackTests` (Task 2 — 8 tests)

| # | Test | Asserts |
|---|------|---------|
| 1 | `test_submit_serverReturns500_transitionsToActionFailed_withRollbackLoad` | D-15: 500 -> `.actionFailed(rollbackTo: preLoad, frozenChain: preChain, errorCopyKey: "loads.actions.error.tender_failed")`. |
| 2 | `test_submit_serverReturns422_transitionsToActionFailed_perActionKey` | 422 + `.accept` -> `errorCopyKey == "loads.actions.error.accept_failed"`. |
| 3 | `test_submit_serverReturns409_transitionsToActionFailed_perActionKey` | 409 + `.cancel` -> `errorCopyKey == "loads.actions.error.cancel_failed"`. |
| 4 | `test_submit_urlErrorNetworkOffline_transitionsToActionFailed` | `URLError(.notConnectedToInternet)` -> `.actionFailed` with the per-action key (NOT a network-specific key); UI-SPEC line 354 lock. |
| 5 | `test_submit_failure_doesNotLeakServerTextIntoState` | PII-shaped server body `{"error":"Internal server error: party_id not found (VL-R-5-PII-PROBE)"}` does NOT echo into `state.errorCopyKey` — T-09-04 view-layer lock. |
| 6 | `test_submit_failure_loggerCalledWith_emptyFieldsDict` | `logger.error(event: load_action_failed, fields: <X>)` asserts `X.isEmpty == true` — T-09-04 / T-08-08 view-layer lock extended to actions. |
| 7 | `test_submit_cancelledMidFlight_doesNotOverwriteFresherState` | BL-01 invariant 3: a cancelled task's catch arm observes `Task.isCancelled` BEFORE writing `.actionFailed`; the older task does NOT overwrite the newer task's terminal state. |
| 8 | `test_submit_vcDeallocMidFlight_noOp_noCrash` | Pitfall 9 / `[weak self]` inherited Phase 9 safety: VM dealloc mid-action is a no-op (the terminal write becomes a no-op when self is nil); no crash, no memory corruption. |

## Notes for Plan 04 (Action Region UI)

- **`viewModel.role` is a `public let`**: read it directly at the action-region call site —
  `LoadActionsView.configure(actions: RoleLoadPolicy.availableActions(for: viewModel.role, in: load), ...)`.
  No need to thread `role` through the VC constructor; it's already on the VM.
- **The two new VM states ALREADY have minimal render arms** in `LoadDetailViewController.render(state:)`:
  `.actionInFlight` -> `applyLoadedRender(predicted, frozenChain)`,
  `.actionFailed` -> `applyLoadedRender(rollbackTo, frozenChain)`.
  Plan 04's action-region work overlays the spinner + the localized error banner; the body content rendering is correct without further change.
- **viewWillAppear already suppresses re-fetch** from `.actionInFlight` + `.actionFailed`. No additional plumbing needed.
- **`errorCopyKey` is a LOCALIZATION KEY**: Plan 04 calls
  `NSLocalizedString(state.actionFailed.errorCopyKey, value: <english fallback>, comment: ...)`.
  All 6 keys are in the table above; the resolver is a `nonisolated static` so it's addressable without a VM instance if a SwiftUI preview wants to drive an in-test render.
- **NO new networking required**: `submit(action:body:)` already dispatches via `LoadActionEndpoint`; Plan 08 (NOT 04) owns the IdempotencyInterceptor header assertion test.

## Deviations from Plan

### Rule 3 — Blocking compile errors auto-fixed

**1. AppContainer signature change bundled into Task 1 GREEN, not Task 2**

- **Found during:** Task 1 GREEN — first `xcodebuild build-for-testing` after the VM `init(loadID:role:apiClient:logger:)` change.
- **Issue:** The Task 2 `<action>` block scheduled the AppContainer modification (`makeLoadDetailScreen(loadID:role:)` + the factory closure capture) for Task 2. But the VM's init signature change immediately breaks AppContainer's existing call site (line 283-294, `LoadDetailViewModel(loadID: loadID, apiClient: apiClient, logger: featureLogger)` — missing `role:`). The project cannot build between Task 1 and Task 2 unless AppContainer is updated atomically.
- **Fix:** Bundled the AppContainer modification into Task 1 GREEN. The Task 2 done-criteria source assertions (`grep -c 'func makeLoadDetailScreen(loadID: String, role: Role)'` etc.) all evaluate to the expected values at the Task 1 GREEN HEAD; Task 2's commit is therefore a pure `test:` commit (the rollback test suite).
- **Files modified (in Task 1 GREEN):** `validationLedger/App/AppContainer.swift` (factory signature + closure capture); `validationLedger/Features/Loads/LoadListViewController.swift` (docstring reference to the old factory signature, Rule 1 doc accuracy).
- **Files modified (Rule 3 — existing tests must compile after VM signature change):**
  - `validationLedgerTests/Loads/LoadDetailViewModelTests.swift` (makeViewModel adds `role: .broker`)
  - `validationLedgerTests/Loads/LoadDetailViewControllerCompositionTests.swift` (same)
  - `validationLedgerTests/Loads/LoadDetailViewControllerSizeClassRoutingTests.swift` (same)
- **Verification:** Whole-project `xcodebuild build` returns `BUILD SUCCEEDED`; all 4 existing Swift Testing `LoadDetailViewModelTests` cases remain green.
- **Committed in:** `672ec00` (Task 1 GREEN).

**2. LoadDetailViewController.render(state:) gains MINIMAL render arms for the two new VM states**

- **Found during:** Task 1 GREEN — `xcodebuild build-for-testing` after the State enum got 2 new cases.
- **Issue:** The Plan 10-03 `<action>` block step "DO NOT modify `LoadDetailViewController.swift` in this plan" is unachievable with Swift's exhaustiveness check on the 2 existing switches (`viewWillAppear` line 425 + `render(state:)` line 1111). The two new VM cases force compile failure on both switches.
- **Fix:** Two minimal arms in `render(state:)`:
  - `.actionInFlight(let predicted, let frozenChain, _)` -> `applyLoadedRender(load: predicted, chainOfTrust: frozenChain)`
  - `.actionFailed(let rollbackTo, let frozenChain, _)` -> `applyLoadedRender(load: rollbackTo, chainOfTrust: frozenChain)`
  And the `viewWillAppear` switch is extended so `.actionInFlight` + `.actionFailed` suppress the re-fetch (would clobber optimistic state mid-action / freshly-applied rollback).
- **Why not `default:` arm:** Would silently mask future case additions and contradicts the plan's "exhaustive switch" discipline established in the LoadStatus / LoadAction resolvers (Plan 01, 02). The minimal-stub approach matches the plan's stated intent ("the VC's render(state:) in Plan 04 will add two new arms that re-render against the predicted Load") more accurately than a default arm would.
- **Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` (+~30 lines).
- **Plan 04 impact:** Plan 04 will OVERLAY the action-region UI + the localized error banner; the body content rendering for `.actionInFlight` / `.actionFailed` is correct without further change in Plan 04 (only additive work).
- **Committed in:** `672ec00` (Task 1 GREEN).

### Rule 1 — Correctness fixes during TDD GREEN

**3. submit() guard broadened to accept `.actionInFlight` + `.actionFailed` predecessors**

- **Found during:** Task 1 GREEN — Test 5 (`test_submit_cancelAndReplace_supersedesEarlierAction`) failed at first iteration with the VM stuck in `.actionInFlight` permanently.
- **Issue:** PATTERNS §8 verbatim shows `guard case .loaded(let preLoad, let preChain) = state else { return }`. Under this strict guard, when submit() is called against `.actionInFlight` (Test 5's scenario: a second submit() supersedes an in-flight first), the guard returns immediately — the first task is cancelled (per `actionTask?.cancel()` above the guard) but no replacement task starts, leaving the VM permanently stuck waiting for a response that won't come.
- **Fix:** Broadened the guard to derive the pre-tap snapshot from `.loaded`, `.actionInFlight` (using `(predicted, frozenChain)` as the new pre-tap), and `.actionFailed` (using `(rollbackTo, frozenChain)`). `.loading` and `.error` still no-op. This matches the must_haves truth: 'BL-01 cancel-and-replace ... extends to actions — Pitfall 9 (rapid back-tap mid-action) inherits the Phase 9 safety.'
- **Verification:** Test 5 green; the 7 + 8 = 15 new tests all green; no regression on the 4 existing fetch-path tests.
- **Committed in:** `672ec00` (Task 1 GREEN).

### Rule 3 — Test-runner stability fix

**4. Test 1 (`test_init_storesRole`) declared `async throws` despite being a synchronous assertion**

- **Found during:** Task 1 GREEN — first scoped `xcodebuild test ... -only-testing:...LoadDetailViewModelActionTests/test_init_storesRole`.
- **Issue:** The test crashes the iOS-sim test runner with `malloc: *** error for object 0x...: pointer being freed was not allocated`. When `xcodebuild test` runs the synchronous test method, the URLSession (constructed inside `makeAPIClient()`) gets released after the test method returns; the URLSession's internal teardown queue and `MockURLProtocol` static state collide somewhere, producing the malloc error. The other 6 tests in the file are all `async throws` and don't crash.
- **Fix:** Declared Test 1 as `async throws` (with a defensive `await Task.yield()` so it actually has a suspension point); the async-lane spawn lets the URLSession's internal queues drain before ARC tears down the test frame.
- **Files modified:** `validationLedgerTests/Loads/LoadDetailViewModelActionTests.swift` (Test 1 signature).
- **Verification:** Standalone Test 1 run -> PASSED; full scoped run (7 action + 4 detail VM Swift Testing) -> 7 + 4 = 11 tests green.
- **Committed in:** `672ec00` (Task 1 GREEN).

### Environment-side (no source change)

**5. `iPhone 16` simulator destination -> `iPhone 17`**

- **Found during:** First scoped `xcodebuild test` invocation.
- **Issue:** The plan's `<verify>` blocks specify `-destination 'platform=iOS Simulator,name=iPhone 16'`. Per project memory `ios-test-suite-pitfalls`, iPhone 16 is NOT installed on this host — iPhone 17 is the working simulator.
- **Fix:** Substituted `iPhone 17` in every test invocation. Runner-side only; no source change.
- **Recommendation:** Plan 04 forward should use `iPhone 17` from the start; the Phase 10 verify-block template should be updated.

**6. `-only-testing` folder-segment selects 0 tests on XCTest suites**

- **Found during:** First scoped `xcodebuild test -only-testing:validationLedgerTests/Loads/LoadDetailViewModelActionTests`.
- **Issue:** Per Plan 02 deviation note #2: the XCTest runner does not parse the folder segment (`/Loads/`); the canonical form is `validationLedgerTests/<CLASS>` with NO folder segment.
- **Fix:** Used the canonical form `-only-testing:validationLedgerTests/LoadDetailViewModelActionTests` etc. throughout this plan's verify cycle.

---

**Total deviations:** 6 — 4 Rule 3 (blocking), 1 Rule 1 (correctness during GREEN), 1 environment-side (no source change). All documented; no architectural change required; no Rule 4 (architectural) decision needed.

## Threat Surface Scan

No new threat surface beyond what's already enumerated in the plan's `<threat_model>` (T-10-02 / T-10-05 / T-09-04-extended / T-10-PR-01 / T-10-08 / T-10-PR-SC). Specifically:

- **No new network endpoints.** `submit(...)` dispatches `LoadActionEndpoint` — Phase 7 frozen.
- **No new auth paths.** Role is captured in `AppContainer.makeLoadListScreen(role:)` from the post-OTP session role (D-22 / D-23); not client-changeable mid-screen.
- **No new file access patterns.** Pure-Swift state machine.
- **No new schema at trust boundaries.** The chain-of-trust is NEVER predicted client-side (D-13); the rollback Load is a value-type copy of the pre-tap snapshot.
- **No new packages.** Phase 10 installs ZERO new SwiftPM dependencies.

No `## Threat Flags` section needed.

## Known Stubs

None in the source files this plan creates/modifies. The two new `LoadDetailViewController.render(state:)` arms render the predicted/rollback Load + frozen chain through the existing `applyLoadedRender(...)` — which is fully wired (Phase 9 LOAD-05). Plan 04 will OVERLAY the action-region UI; nothing in Plan 03 is a placeholder that needs Plan 04 to "fix" — the body content rendering is already correct.

## TDD Gate Compliance

- ✓ Task 1: `test(10-03): add failing tests for LoadDetailViewModel submit() + role plumb` (RED, `0fdb754`) -> `feat(10-03): extend LoadDetailViewModel with action state machine + role plumb` (GREEN, `672ec00`).
- The AppContainer change Rule-3-bundled into Task 1 GREEN does not separately re-enter RED for Task 2; the rollback test suite (`test(10-03): add rollback-path tests ...`, `08fb1b3`) is a `test:` commit that pins the contract already implemented in Task 1 GREEN.
- No refactor pass required — implementation was minimal and idiomatic on the first GREEN pass after the Rule-1 correctness fix to the submit() guard.

## Self-Check

Verified at HEAD `08fb1b3`:

- [x] FOUND: `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift` (modified — +~140 lines)
- [x] FOUND: `validationLedger/App/AppContainer.swift` (modified — signature evolution)
- [x] FOUND: `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` (modified — 2 minimal render arms + viewWillAppear suppression)
- [x] FOUND: `validationLedger/Features/Loads/LoadListViewController.swift` (modified — docstring update only)
- [x] FOUND: `validationLedgerTests/Loads/LoadDetailViewModelActionTests.swift` (737 lines, NEW)
- [x] FOUND: `validationLedgerTests/Loads/LoadDetailViewModelRollbackTests.swift` (687 lines, NEW)
- [x] FOUND commit `0fdb754` (Task 1 RED)
- [x] FOUND commit `672ec00` (Task 1 GREEN — bundled AppContainer change per Rule 3)
- [x] FOUND commit `08fb1b3` (Task 2 — rollback tests)
- [x] Source assertion: `grep -c 'case actionInFlight' LoadDetailViewModel.swift` returns 1
- [x] Source assertion: `grep -c 'case actionFailed' LoadDetailViewModel.swift` returns 1
- [x] Source assertion: `grep -c 'public let role: Role' LoadDetailViewModel.swift` returns 1 (declaration; an additional docstring match brings the literal count to 2 but only one is the declaration)
- [x] Source assertion: `grep -nE 'actionTask\?\.cancel\(\)' LoadDetailViewModel.swift` returns 1 hit
- [x] Source assertion: `grep -cE 'fields: \[:\]' LoadDetailViewModel.swift` returns 10 (≥2 required; existing fetch path had several already)
- [x] Source assertion: `grep -c 'func makeLoadDetailScreen(loadID: String, role: Role)' AppContainer.swift` returns 1
- [x] Source assertion: `grep -c 'self.makeLoadDetailScreen(loadID: loadID, role: role)' AppContainer.swift` returns 1
- [x] Source assertion: `grep -c 'requestInterceptors: [IdempotencyInterceptor()]' AppContainer.swift` returns 1 (UNCHANGED — T-10-08 infrastructure preserved)
- [x] 15/15 new XCTest cases green on iPhone 17 simulator (scoped, non-parallel)
- [x] 4/4 existing Swift Testing LoadDetailViewModelTests cases green (no fetch-path regression)
- [x] Whole-project `xcodebuild build` returns `BUILD SUCCEEDED` — proves the `makeLoadDetailScreen` signature change has no orphan call sites

## Self-Check: PASSED

---
*Phase: 10-per-role-tender-accept-reject*
*Plan: 03*
*Wave: 2*
*Completed: 2026-05-21*
