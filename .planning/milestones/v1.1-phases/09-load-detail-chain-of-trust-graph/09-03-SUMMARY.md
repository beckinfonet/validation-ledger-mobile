---
phase: 09-load-detail-chain-of-trust-graph
plan: 03
subsystem: ui-shell
tags:
  - mvvm-coordinators
  - uikit-programmatic
  - state-machine
  - cancel-and-replace
  - factory-closure
  - load-05
  - zero-pii
  - swift-testing
  - xcuitest

# Dependency graph
dependency_graph:
  requires:
    - phase: 09-load-detail-chain-of-trust-graph
      plan: 01
      provides: TrustNode.priorRelationships migrated contract + the 12 re-authored load-detail-VL-*.json fixtures decode end-to-end through APIClient.defaultDecoder()
    - phase: 09-load-detail-chain-of-trust-graph
      plan: 02
      provides: validationLedgerTests/Loads/LoadDetailViewModelTests.swift Wave 0 shell (4 empty @Test methods); validationLedgerUITests/Loads/LoadDetailFlowTests.swift Wave 0 shell (5 XCTSkip methods)
    - phase: 07-load-domain-model-mock-contract
      provides: LoadDetailEndpoint(loadID:) typed Decodable endpoint; APIClient.request(_:); MockURLProtocol latency + forced-failure injection; load-detail-VL-1001..1012.json fixture corpus
    - phase: 08-role-filtered-load-list
      provides: LoadListViewController + LoadListViewModel state-machine VC template (PATTERNS E1/E2); AppContainer.makeLoadListScreen(role:) factory pattern (PATTERNS E12); LoadRowItem diffable item wrapper; loads-list.row.VL-* accessibility identifiers; RoleLoadsTabSmokeTests driveFullOTPFlow helper (PATTERNS E11)
  provides:
    - LoadDetailViewModel — @MainActor 3-case state machine (.loading / .loaded(Load, ChainOfTrust) / .error(message: String))
    - LoadDetailViewModel.fetchLoadDetail() — BL-01 cancel-and-replace fetch with two Task.isCancelled checkpoints
    - LoadDetailViewModel.userFacingMessage(for:) — nonisolated static; collapses every error to the locked NSLocalizedString("loads.detail.error.generic")
    - LoadDetailViewController — programmatic UIKit shell with three pre-attached state containers (load-detail.skeleton / load-detail.error-state / load-detail.body) toggled by render(state:) via isHidden ONLY (D-20 — never VC swap)
    - AppContainer.makeLoadDetailScreen(loadID:) factory — REUSES LoggingSubsystem.app + category 'feature.loads' (NO new subsystem case)
    - AppContainer.makeLoadListScreen(role:) threads detailScreenFactory closure into LoadListViewController.init
    - LoadListViewController.collectionView(_:didSelectItemAt:) — UICollectionViewDelegate conformance that pushes detailScreenFactory(item.load.id) onto the nav stack (LOAD-05)
    - LoadDetailViewModelTests — 4 @Test methods (loading→loaded; forced-500→error; BL-01 cancel-and-replace; zero-PII collapsing)
    - LoadDetailFlowTests.test_rowTap_pushesDetail() — 5-role XCUITest iteration via XCTContext.runActivity asserting load-detail element appears
  affects:
    - phase: 09-load-detail-chain-of-trust-graph (Plan 04 populates skeletonContainer + errorContainer; Plan 05 populates body timeline; Plan 06 populates body graph; Plan 09 populates body banner + iPad split)
    - Phase 8 LoadListViewController — additive init signature (detailScreenFactory: defaulted closure preserves backward compat)

# Tech tracking
tech_stack:
  added: []  # No new SwiftPM dependencies; Package.swift byte-identical
  patterns:
    - "Detail VC state-machine ports PATTERNS E1 verbatim — bindViewModel uses MainActor.assumeIsolated + WR-06 priming pump; render(state:) toggles isHidden on pre-attached state subviews (NEVER swaps VCs)"
    - "VM state-machine ports PATTERNS E2 verbatim — @MainActor public final class, public enum State: Equatable Sendable, fetchTask?.cancel() + Task.isCancelled checkpoints, fields: [:] logger discipline"
    - "Composition-root factory closure pattern (PATTERNS E12) — makeLoadDetailScreen(loadID:) mirrors makeLoadListScreen(role:); threaded into LoadListViewController via init extension; [weak self] capture in the closure even though AppContainer is app-scoped"
    - "Identity-only Equatable shim on Load + ChainOfTrust scoped to the State.Equatable contract — avoids cascading Equatable conformance through every Phase 7 Core/Load value type (mirrors Phase 8 LoadListItem Equatable extension shape)"
    - "nonisolated static for pure utility functions on a @MainActor class — userFacingMessage(for:) reads no actor-isolated state and is called from synchronous Swift Testing @Test bodies, so making it nonisolated is the right ergonomic without giving up actor safety elsewhere"

key_files:
  created:
    - validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift
    - validationLedger/Features/Loads/Detail/LoadDetailViewController.swift
  modified:
    - validationLedger/App/AppContainer.swift (makeLoadDetailScreen + detail-factory threading)
    - validationLedger/Features/Loads/LoadListViewController.swift (detailScreenFactory property + init extension + collectionView.delegate=self + UICollectionViewDelegate extension)
    - validationLedgerTests/Loads/LoadDetailViewModelTests.swift (populated 4 @Test shells with real implementations)
    - validationLedgerUITests/Loads/LoadDetailFlowTests.swift (populated test_rowTap_pushesDetail; 4 others remain XCTSkip)

key_decisions:
  - "userFacingMessage(for:) is nonisolated static — required so Swift Testing @Test methods (sync nonisolated contexts) can call it without an `await MainActor.run` wrapper for a function that reads no actor-isolated state"
  - "Load + ChainOfTrust gain identity-only Equatable in LoadDetailViewModel.swift (NOT in Core/Load/) — mirrors the Phase 8 LoadListViewModel.swift `extension LoadListItem: Equatable` precedent; avoids cascading Equatable through every Phase 7 frozen value type"
  - "detailScreenFactory init parameter has a defaulted empty-VC closure — preserves backward compat with the implicit test-only LoadListViewController(viewModel:navTitle:) construction path; the AppContainer threads the real factory; a tap on a list constructed without the factory pushes an inert blank screen (logically unreachable in production)"
  - "Factory closure chosen over thin LoadDetailCoordinator per CONTEXT line 111 — no coordinator state to retain across a single push; mirrors the kycStatusScreenFactory precedent already established in AppContainer.makeKYCStatusScreen()"
  - "Test 3 (BL-01) uses two DIFFERENT fixture bodies (VL-1001 latency vs VL-1002 quick) on the SAME registered path so the terminal state's load.id distinguishes which fetch's response landed — mirror of LoadListViewModelTests.concurrentFetchesNewerWinsBL01 (broker vs empty payload)"

metrics:
  duration: ~20min
  completed: 2026-05-20
---

# Phase 9 Plan 03: LoadDetailViewModel + LoadDetailViewController shell + LOAD-05 navigation wiring — Summary

## One-liner

Shipped the @MainActor 3-case state-machine spine for the load-detail screen (`LoadDetailViewModel` + `LoadDetailViewController`), the `AppContainer.makeLoadDetailScreen(loadID:)` factory + threading into the list VC, and the `UICollectionViewDelegate.didSelectItemAt` push wiring (LOAD-05) — with 4 Swift Testing `@Test` methods green and the 5-role XCUITest `test_rowTap_pushesDetail` green on iPhone 17 simulator.

## Performance

- **Duration:** ~20 min (wall-clock includes UI test runs of ~95s each; coding/commit time ~10 min)
- **Started:** 2026-05-20 (worktree agent-a1986b1e2e94a9914 spawn)
- **Completed:** 2026-05-20
- **Tasks:** 2 (committed atomically per task)
- **Files modified:** 4 production + 2 test = 6 + 1 SUMMARY

## Accomplishments

- **D-20 3-case state machine shipped** — `LoadDetailViewModel.State` has exactly `.loading / .loaded(Load, ChainOfTrust) / .error(message: String)`; the negative gate `grep -c 'case empty' …` returns 0.
- **BL-01 cancel-and-replace** — `fetchLoadDetail()` cancels any in-flight `fetchTask` before assigning state and starts a fresh task; two `Task.isCancelled` checkpoints (post-network, pre-state-write) close the last-write-wins race. Locked by Test 3 (`cancelAndReplaceOnRapidRefetch`).
- **T-09-04 / T-08-08 zero-PII discipline** — `userFacingMessage(for:)` returns ONLY the locked `loads.detail.error.generic` NSLocalizedString; every actual logger invocation (`load_detail_fetch_failed`, `load_detail_loaded`) passes `fields: [:]`. Test 4 synthesises a `DecodingError.keyNotFound(VL-1001-PII-PROBE)` and asserts the probe key does NOT echo into the user-facing string. View layer file (LoadDetailViewController) has zero Logger/os_log/OSLog — negative grep gate returns 0.
- **LOAD-05 row-tap → detail push** — `LoadListViewController.collectionView(_:didSelectItemAt:)` resolves the tapped row via `dataSource.itemIdentifier(for: indexPath)`, hands `item.load.id` to the threaded `detailScreenFactory`, and pushes onto the navigation stack (default UIKit push, no animation override). Locked end-to-end by the 5-role XCUITest.
- **AppContainer factory** — `makeLoadDetailScreen(loadID:)` reuses `LoggingSubsystem.app + category "feature.loads"` (no new subsystem case); threads into `makeLoadListScreen(role:)` via a `[weak self]` closure capture (PATTERNS E12 mirror).
- **Phase 8 backward compat preserved** — `LoadListViewController.init` signature extended with a defaulted `detailScreenFactory` parameter; existing call sites (the AppContainer one + the FactoringTabBarController reference comment) compile unchanged. `RoleLoadsTabSmokeTests` regression smoke passes 5/5.

## Task Commits

| Task | Title | Commit | Files |
|------|-------|--------|-------|
| 1 | LoadDetailViewModel 3-state machine + cancel-and-replace + zero-PII + tests | `cb98633` | LoadDetailViewModel.swift (new); LoadDetailViewModelTests.swift |
| 2 | LoadDetailViewController shell + AppContainer factory + LOAD-05 row-tap push + XCUITest | `29e32b7` | LoadDetailViewController.swift (new); AppContainer.swift; LoadListViewController.swift; LoadDetailFlowTests.swift |

## Files Created / Modified

### Created

- `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift` (193 lines)
  - `@MainActor public final class LoadDetailViewModel` with the 3-case `State` enum, `state` property + `onStateChange` callback, `fetchTask: Task<Void, Never>?` slot, BL-01 cancel-and-replace `fetchLoadDetail()`, `performFetch()` body with two `Task.isCancelled` checkpoints, `nonisolated static userFacingMessage(for:)` collapsing every error to the locked localized copy, identity-only Equatable extensions on Load + ChainOfTrust scoped to the State.Equatable contract.

- `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` (159 lines)
  - `public final class LoadDetailViewController: UIViewController` with `init(viewModel:)` (programmatic-only; init?(coder:) fatalErrors), three pre-attached state containers pinned edge-to-edge in `view.safeAreaLayoutGuide`, `viewDidLoad → layoutContent / wireActions / bindViewModel`, `viewWillAppear → Task { await viewModel.fetchLoadDetail() }`, `bindViewModel` with `MainActor.assumeIsolated` + WR-06 priming pump, `render(state:)` toggling `isHidden` on the three containers. ZERO Logger / os_log / OSLog calls (T-08-08 lock).

### Modified

- `validationLedger/App/AppContainer.swift` (+39 lines)
  - Added `@MainActor func makeLoadDetailScreen(loadID:) -> UIViewController` factory (PATTERNS E12 mirror).
  - Threaded `detailScreenFactory: { [weak self] loadID in self?.makeLoadDetailScreen(loadID: loadID) ?? UIViewController() }` into `LoadListViewController.init` from `makeLoadListScreen(role:)`.

- `validationLedger/Features/Loads/LoadListViewController.swift` (+33 lines)
  - Added `private let detailScreenFactory: (String) -> UIViewController` stored property (defaulted empty-VC closure for backward compat with non-AppContainer construction paths).
  - Extended `init(viewModel:navTitle:detailScreenFactory:)` with the closure parameter (existing call site in AppContainer compiles unchanged; tests that don't pass a factory get the default).
  - Added `collectionView.delegate = self` inside `viewDidLoad`.
  - Added `extension LoadListViewController: UICollectionViewDelegate` with `collectionView(_:didSelectItemAt:)` implementing LOAD-05.

### Modified — Tests

- `validationLedgerTests/Loads/LoadDetailViewModelTests.swift` (entire body rewritten from XCTSkip-style shell to 4 real `@Test` methods)
  - Test 1 (`loadingToLoadedOnFixture`): drives `load-detail-VL-1001.json` via MockURLProtocol; asserts terminal `.loaded(load, chain)` with `load.id == "VL-1001"` and non-empty chain.
  - Test 2 (`loadingToErrorOnForcedFailure`): forced HTTP 500 on `/loads/VL-9999`; asserts terminal `.error(message: expectedErrorCopy)`.
  - Test 3 (`cancelAndReplaceOnRapidRefetch`): fetch A under 300ms latency (VL-1001 body), then fetch B with VL-1002 body — under BL-01, terminal state's `load.id` is "VL-1002" (fetch B wins).
  - Test 4 (`userFacingMessageIsZeroPIIOnDecodeAndNetworkErrors`): synthesises `DecodingError.keyNotFound(VL-1001-PII-PROBE)` + `URLError(.notConnectedToInternet)`; both collapse to the SAME locked copy; the locked copy does NOT echo the probe key or the system error description.
  - Reuses the `StateRecorder` + `RecordingLogger` helper pattern from `LoadListViewModelTests.swift` (PATTERNS E2) — copied verbatim into this file (the simpler path per `<action>` Step B).

- `validationLedgerUITests/Loads/LoadDetailFlowTests.swift`
  - Populated `test_rowTap_pushesDetail()` with a 5-role iteration via `XCTContext.runActivity(named: "Role: \(role)")` — per role, launch app with `-MockOTPRoleForUITest <role>`, drive OTP, tap Loads/Invoices tab, tap the first `loads-list.row.VL-*` cell, assert `load-detail` element appears within 5s.
  - The other 4 test methods remain `throw XCTSkip("Wave 0 shell — populated by Plan 10")`.
  - `driveFullOTPFlow(_:)` helper copied verbatim from `RoleLoadsTabSmokeTests` (PATTERNS E11, the simpler path — no shared helper file to invent).

## Decisions Made

1. **`userFacingMessage(for:)` is `nonisolated static`** — required because the class is `@MainActor` (project compiles under `-default-isolation=MainActor`), but the function reads no actor-isolated state and is called from synchronous Swift Testing `@Test` bodies. Without `nonisolated`, the test surface would need to wrap the call in `await MainActor.run` for a pure function — a worse API ergonomic for no isolation benefit. The Phase 8 `LoadListViewModel.userFacingMessage` is also static but lives on a `@MainActor` class without the explicit `nonisolated` keyword (it's never called from a sync nonisolated context, only from inside the @MainActor `performFetch`).
2. **`Load + ChainOfTrust` Equatable shim lives in `LoadDetailViewModel.swift`** (NOT in `Core/Load/`) — same pattern Phase 8 used for `LoadListItem: Equatable` in `LoadListViewModel.swift`. Identity-only: `Load == Load` compares `id`; `ChainOfTrust == ChainOfTrust` compares verdict + node count + edge count. Sufficient for the `State.Equatable` synthesised conformance the test recorder needs; avoids cascading Equatable through every Phase 7 frozen value type.
3. **`detailScreenFactory` init parameter is defaulted** to an empty-VC closure — preserves backward compat with the only existing test-style `LoadListViewController(viewModel:navTitle:)` construction path (none exists today, but the spirit of the Phase 8 init was "tests can build the VC without the AppContainer factory"). The AppContainer always threads the real factory in production; the fallback path is logically unreachable.
4. **Factory closure chosen over thin LoadDetailCoordinator** per CONTEXT line 111 — no coordinator state to retain across a single push; mirrors the `kycStatusScreenFactory` precedent already established in `AppContainer.makeKYCStatusScreen()`. A future plan (Phase 10 tender flow?) can introduce a `LoadDetailCoordinator` if the detail screen later needs to present multiple modal sub-screens with shared state.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] `userFacingMessage(for:)` needed `nonisolated`**

- **Found during:** Task 1 verification (`xcodebuild test` for `LoadDetailViewModelTests` failed with `Call to main actor-isolated static method 'userFacingMessage(for:)' in a synchronous nonisolated context` × 2 — both Test 4 assertions on `decodeMsg` and `networkMsg`).
- **Issue:** The class is `@MainActor`, so all members (including `static`) inherit MainActor isolation by default. The Swift Testing `@Test func userFacingMessageIsZeroPIIOnDecodeAndNetworkErrors()` is a synchronous nonisolated function, so the call `LoadDetailViewModel.userFacingMessage(for: decodeErr)` requires either `await MainActor.run { … }` wrapping OR `nonisolated` on the function.
- **Fix:** Added `nonisolated` to the function declaration with a doc comment explaining the rationale (reads no actor-isolated state; called from sync test contexts).
- **Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift`
- **Verification:** Test 4 passes; the function still works correctly from inside `performFetch()` (the @MainActor caller bridges to nonisolated automatically — Sendable through the nonisolated hop).
- **Committed in:** `cb98633` (the same Task 1 commit; the fix landed before commit).

**2. [Rule 3 — Bookkeeping] LoadDetailFlowTests file-header comment mentioned "XCTSkip" by literal name**

- **Found during:** Task 2 acceptance-criteria audit. The plan's grep gate says `grep -c 'XCTSkip' validationLedgerUITests/Loads/LoadDetailFlowTests.swift returns 4`. My first-draft file's header comment said `the other 4 methods remain `XCTSkip` until Plans 07/08/10 populate them` — that bumped the count to 5.
- **Issue:** The header comment's literal `XCTSkip` was documentation, not a stub, but the strict grep gate doesn't distinguish. Same pattern as Plan 02's `prior_relationship_count` literal scope reduction.
- **Fix:** Reworded the header comment to "the other 4 methods stay shelled until Plans 07/08/10 populate them" — preserves intent without matching the grep regex.
- **Files modified:** `validationLedgerUITests/Loads/LoadDetailFlowTests.swift`
- **Verification:** `grep -c 'XCTSkip' validationLedgerUITests/Loads/LoadDetailFlowTests.swift` returns 4 (the 4 actual `throw XCTSkip(...)` method bodies).
- **Committed in:** `29e32b7` (the Task 2 commit; the fix landed before commit).

**Total deviations:** 2 auto-fixed (1 Rule 1 Swift-compiler isolation requirement; 1 Rule 3 doc grep-compliance — both required for the plan's own verification gates to pass).

## Open Questions (planner discretion)

- **Plan AC acceptance criterion "every logger invocation passes `fields: [:]`" grep gate has a 1 false-positive on the init param declaration.** The exact gate:
  ```bash
  grep -v '^//' …/LoadDetailViewModel.swift | grep -E 'Logger|os_log' | grep -v 'fields: \[:\]' | grep -v 'private let logger' | grep -v 'Logger?' | wc -l
  ```
  returns `1` because the init signature is `init(loadID: String, apiClient: APIClient, logger: (any Logger)? = nil)` — the literal substring `Logger` matches, but the filter list (which strips `Logger?`, `private let logger`) doesn't anticipate `(any Logger)?` (the modern Swift form). The actual semantic invariant holds — every real logger CALL passes `fields: [:]` (verified by direct grep: `grep -nE 'logger\?\.|logger\.'` returns only 2 lines, both with `fields: [:]`). Documentation-only mismatch; not blocking.

- **`test_rowTap_pushesDetail` grep gate "returns 1" but actually returns 3.** The gate `grep -c 'test_rowTap_pushesDetail' validationLedgerUITests/Loads/LoadDetailFlowTests.swift` returns 3 because the function name appears in (a) the file-header comment shell-listing, (b) the doc reference, and (c) the function declaration itself. The implementation gate (the function exists and the XCUITest passes) is met; the grep gate's "=1" was indicative, not strict. Same documentation-grep pattern Plan 02 also encountered.

- **Should `LoadDetailCoordinator` be introduced in a future Phase 10 plan?** The current factory-closure approach (per CONTEXT line 111) is sufficient for the single push in Phase 9. If Phase 10 tender flow ends up presenting multiple sheets / cascading modal flows / needing back-navigation policy, a `LoadDetailCoordinator` retain-pattern (PATTERNS E13) would be the natural extension point. Recorded for planner consideration; not a Plan 03 concern.

- **`Load.id` is the correct identifier for `LoadDetailEndpoint(loadID:)`** (confirmed by reading `Load.swift:103-107` — "Stable load identifier (e.g. 'VL-1001'). Wire form is the bare string 'id' per the Plan 05 fixture convention"). The `referenceNumber` field (e.g. "REF-100A") is the human-readable display string, NOT an addressable identifier — confirmed by the mock backend route table which keys on `VL-####`. The wiring in `collectionView(_:didSelectItemAt:)` calls `detailScreenFactory(rowItem.item.load.id)` correctly.

## Known Stubs

None — every modified surface is functional. The `bodyContainer`, `skeletonContainer`, and `errorContainer` on `LoadDetailViewController` are intentionally empty placeholders for Plans 04-09 to populate; per the plan's `<objective>` they are "the spine; Plans 04-09 build subview composition on top of this shell." Each container has a locked accessibilityIdentifier so the XCUITest surface can probe their visibility transitions from day one. This is not a stub — it is the deliberately-shaped extension surface the downstream plans contract against.

## User Setup Required

None — no external service configuration required. The 5-role XCUITest runs against the `-MockOTPRoleForUITest` launch-arg path with `MockLoadFixtureRegistry.registerAppDefaults()` serving every `/loads/VL-####` detail route from in-tree fixtures (Plan 01 D-04 / Phase 7 D-17).

## Next Phase Readiness

- **Plan 04 (LOAD-06 timeline + skeleton + error-state)** can populate `skeletonContainer` with `LoadDetailSkeletonView`, `errorContainer` with the `UIContentUnavailableView` + "Try again" CTA wired to `viewModel.fetchLoadDetail()`, and add the timeline view to `bodyContainer`. The state machine + container scaffolding are in place.
- **Plan 05 (status timeline)** can compose `StatusTimelineView` into `bodyContainer` reading `Load.stateHistory`.
- **Plan 06 (trust graph)** can compose `TrustGraphView` into `bodyContainer` reading `chainOfTrust.nodes / .edges / .integrity`.
- **Plan 07/08 (verification-basis sheet / handoff sheet)** can present sheets from `LoadDetailViewController` via `UISheetPresentationController` with `[.medium, .large]` detents — the VC's `wireActions()` is the wiring point.
- **Plan 09 (banner + iPad split)** can add the banner to `bodyContainer`'s top and branch on `traitCollection.horizontalSizeClass` inside `bodyContainer` for the 60/40 split (the outer VC layout stays single-column; the split lives inside `bodyContainer`).

## Verification Summary

- ✓ `xcodebuild build` exits 0 (`** BUILD SUCCEEDED **`)
- ✓ `xcodebuild test -only-testing:validationLedgerTests/LoadDetailViewModelTests` — 4/4 passes, ~0.4s
- ✓ `xcodebuild test -only-testing:validationLedgerUITests/LoadDetailFlowTests/test_rowTap_pushesDetail` — 1/1 passes across all 5 role subtests, ~93s wall-clock
- ✓ `xcodebuild test -only-testing:validationLedgerUITests/RoleLoadsTabSmokeTests` — 5/5 passes, ~81s (Phase 8 regression smoke green)
- ✓ Zero-PII grep: `grep -v '^[[:space:]]*//' LoadDetailViewController.swift | grep -cE 'Logger|os_log|OSLog'` → 0
- ✓ Subsystem reuse: `grep -c 'category: "feature.loadDetail"' AppContainer.swift` → 0
- ✓ All Task 1 + Task 2 source grep acceptance gates pass (modulo two documentation-grep false-positives noted under Open Questions)

## Self-Check: PASSED

Verification commands run before SUMMARY commit:

- ✓ `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift` exists (`ls`)
- ✓ `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` exists (`ls`)
- ✓ Commits `cb98633` (Task 1) and `29e32b7` (Task 2) exist in `git log --oneline -5`
- ✓ Build green; 4 VM tests green; XCUITest green; Phase 8 RoleLoadsTabSmokeTests green (no regression)

---
*Phase: 09-load-detail-chain-of-trust-graph*
*Completed: 2026-05-20*
