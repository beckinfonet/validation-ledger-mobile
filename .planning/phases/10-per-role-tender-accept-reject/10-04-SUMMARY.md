---
phase: 10-per-role-tender-accept-reject
plan: 04
subsystem: load-actions-region
tags: [swift, ios, uikit, action-region, body-mount, in-flight, lint-as-test, tdd, xctest, wave-3]

# Dependency graph
dependency_graph:
  requires:
    - phase: 10-per-role-tender-accept-reject
      plan: 01
      provides: LoadStatus.localizedDisplayName (Pitfall 5 anchor for empty-state caption interpolation); Load.with(status:respondByAt:); LoadActionPredictor.predict(...).
    - phase: 10-per-role-tender-accept-reject
      plan: 02
      provides: RoleLoadPolicy.availableActions(for:in:) (consumed once per .loaded render in the VC); LoadActionTitleResolver.title(for:currentStatus:) (consumed once per button by LoadActionsView).
    - phase: 10-per-role-tender-accept-reject
      plan: 03
      provides: LoadDetailViewModel.State 5-case enum (Plan 04 fleshes out the .actionInFlight / .actionFailed render arms); viewModel.role / viewModel.submit(action:body:).
    - phase: 09-load-detail
      provides: LoadDetailViewController size-class composition (Plan 04 mounts LoadActionsView inside bodyView.actionsContainer; the iPhone-vs-iPad composition logic stays Phase 9-frozen).
  provides:
    - "LoadActionsView (public class, open for the same-module test spy): the configure-method action-region renderer per UI-SPEC § Component Geometry lines 407-422."
    - "LoadDetailBodyView.actionsContainer at index 2 of contentStack (the body's 5-child arrangement grows to 6 with this region)."
    - "LoadDetailViewController.actionsView (internal LoadActionsView ref) + lastConfiguredActions cache (Pitfall 6 pre-tap snapshot) + chainOverlay (Pitfall 1 single ref) + presentTenderSheet() / handleActionTap(_:) routing surface."
    - "LoadDetailViewController.render(state:) gains FLESHED-OUT .actionInFlight + .actionFailed arms (Plan 03 had minimal stubs); chain overlay mount/dismount stubs land here for Plan 07 to upgrade."
    - "LoadDetailSkeletonView gains 2-button action-row skeleton at the action-region's scroll position (iPhone and iPad)."
    - "LoadDetailNoStatusSwitchTests — lint-as-test that scans Features/Loads/ for `switch.*\\.status` (regex `switch\\s+[^\\{]*\\.status`). T-10-01 mitigation."
    - "RespondByLabelTests — 4-tier date format coverage for the carrier/dispatch respond-by inline label (today / tomorrow / 4-days / 30-days)."
    - "LoadActionsView.RespondByFormatter — internal date formatter helper exposed via @testable import."
  affects:
    - "10-05-PLAN — carrier directory endpoint (orthogonal to this plan; doesn't touch the action region)."
    - "10-06-PLAN — tender sheet replaces the presentTenderSheet() stub with the actual UISheetPresentationController; the handleActionTap routing for .tender is already wired."
    - "10-07-PLAN — toast banner + chain overlay alpha-fade: replaces the chainOverlay stub with the activity-indicator + alpha-fade variant; mountChainOverlayIfNeeded() + dismissChainOverlay() API contract is locked here."
    - "10-08-PLAN — IdempotencyInterceptor header assertion (orthogonal)."

# Tech tracking
tech_stack:
  added: []
  patterns:
    - "Configure-method render contract — single public entry point `configure(actions:role:currentStatus:tenderEligibility:respondByAt:inFlight:onTap:)` that consumes the actions[] argument verbatim and never recomputes against currentStatus (Pitfall 6)."
    - "Pure helper enum (LoadActionsView.RespondByFormatter) — namespace + static API mirroring LoadActionTitleResolver / LoadActionPredictor shape; exposed `internal` for tests."
    - "Programmatic UIView with `required init?(coder:)` fatalError trap — mirrors StatusTimelineView precedent (Phase 9 LOAD-06)."
    - "iOS 17 registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) for Dynamic Type axis flip — works under traitOverrides where the legacy traitCollectionDidChange override does not."
    - "Set<LoadStatus>.contains + Set<LoadAction>.contains for destructive/terminal predicates — keeps the no-`switch.*\\.status` invariant in `Features/Loads/` satisfied while staying exhaustive."
    - "Lint-as-test pattern (LoadDetailNoStatusSwitchTests) — FileManager.enumerator over Features/Loads/*.swift + NSRegularExpression matcher; line-leading whitespace stripped before comment-prefix check."
    - "Subclass-for-test spy pattern (CapturingLoadActionsView) — production class is `public` (not `final`) and `configure(...)` is `open` for the same-module test seam; production callers do NOT subclass."
    - "Body-render extraction: applyBodyRender(load:chainOfTrust:) factored out of applyLoadedRender so .actionInFlight + .actionFailed can re-render body content WITHOUT overwriting the action region's in-flight or rollback config."

key_files:
  created:
    - validationLedger/Features/Loads/Detail/LoadActionsView.swift                     # 461 lines, programmatic UIView + RespondByFormatter helper
    - validationLedgerTests/Loads/LoadActionsViewTests.swift                           # 18 XCTest cases
    - validationLedgerTests/Loads/Lint/LoadDetailNoStatusSwitchTests.swift             # 1 lint-as-test
    - validationLedgerTests/Loads/RespondByLabelTests.swift                            # 4 date-format tests
    - validationLedgerTests/Loads/LoadDetailViewControllerActionRenderTests.swift      # 7 VC integration tests
    - .planning/phases/10-per-role-tender-accept-reject/10-04-SUMMARY.md
  modified:
    - validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift                  # +20 lines: actionsContainer + index-2 insertion
    - validationLedger/Features/Loads/Detail/LoadDetailViewController.swift            # +~180 lines: actionsView mount, lastConfiguredActions, chainOverlay stub, presentTenderSheet stub, handleActionTap routing, render arms expansion, applyBodyRender split, test seams
    - validationLedger/Features/Loads/Detail/LoadDetailSkeletonView.swift              # +~50 lines: makeActionRowSkeleton + iPhone + iPad inserts

decisions:
  - "Empty-state caption interpolation: applied to ALL non-Factoring non-`.draft` empty states, NOT just the closed terminal set per UI-SPEC line 304. Rationale: Pitfall 5's regression guard (`.inTransit` -> 'in transit', not 'in_transit') applies to ANY empty rendering path; using the `loads.actions.empty.terminal.format` key universally closes the underscore-leak surface across the full LoadStatus enum. Mid-lifecycle statuses (.accepted/.dispatched/.inTransit) have meaningful display names that read naturally in the format ('This load is in transit. No actions available.'); the alternative — using generic 'No actions available right now.' for mid-lifecycle — was rejected because it loses the status context the user needs to understand why the action region is empty."
  - "LoadActionsView is `public class` (not `final`) and `configure(...)` is `open` (not `public`): the LoadDetailViewControllerActionRenderTests' CapturingLoadActionsView spy subclass requires non-final/open access. Documented in the class header that production callers MUST NOT subclass — the open access level is a test seam only. The alternative (NSNotification-based capture or protocol-based dependency injection) would have added significant production complexity for a test-only need; subclass-for-test is the cleanest pattern in UIKit's idiom."
  - "applyBodyRender(load:chainOfTrust:) extracted from applyLoadedRender so .actionInFlight + .actionFailed can share the body-render path WITHOUT overwriting the action region. The .loaded case calls applyBodyRender + then configures the actions view with the policy-determined action set. The .actionInFlight + .actionFailed cases call applyBodyRender + configure the actions view with the pre-tap snapshot. Alternative: pass a 'configureActionsView: Bool' flag into applyLoadedRender — rejected as a code smell (boolean parameter behavior dispatch)."
  - "Chain overlay mount geometry on iPhone vertical-tree composition: anchored to (everyoneOnLoadStripView.topAnchor, chainOfVouchesView.bottomAnchor) — covers the strip + card combined (UI-SPEC line 485). Defensive fallback: if either is not yet in the hierarchy (mid-rebuild), anchor to bodyContainer."
  - "Test 1 of LoadDetailNoStatusSwitchTests scans Features/Loads/ from disk via FileManager.enumerator(atPath:); regex is `switch\\s+[^\\{]*\\.status`. Comment lines (trimmed-leading-whitespace startsWith `//`) are skipped before regex match. The shell-level grep done-criteria check `grep -rnE 'switch[[:space:]]+[^{]*\\.status' | grep -v '^[^:]*://'` is a less-careful filter — to keep BOTH the shell check and the in-test check green, the inline comment 'switch load.status' phrase was rewritten as 'status-switch in the view layer' so the literal text doesn't surface in either grep."

metrics:
  duration: ~32min  # spans Task 1 RED + Task 1 GREEN + Task 2 RED + Task 2 GREEN
  started_at: 2026-05-21T15:14:09Z
  completed_at: 2026-05-21T15:46:00Z
  tasks: 2
  commits: 4
  tests_added: 30  # 18 LoadActionsViewTests + 1 lint + 4 RespondByLabelTests + 7 LoadDetailViewControllerActionRenderTests
  tests_green: 30
  lines_added: ~1300
  files_created: 5
  files_modified: 3

requirements_completed:
  - ACTION-01    # per-role action surface
  - ACTION-04    # status advance (LoadActionTitleResolver title; render arm)
  - ACTION-05    # ACTION-05 D-15 rollback render arm
  - ACTION-07    # tenderEligibility.canTender == false -> disabled + inline reason
  - ACTION-09    # single policy source — view consumes actions[] verbatim; no policy lookup inside the view
---

# Phase 10 Plan 04: LoadActionsView + body mount + VC render-arm expansion — Summary

**The per-role action region lands in the body stack at index 2 (between timeline and freight rows), the VM's two new states (`.actionInFlight`, `.actionFailed`) get fleshed-out render arms (Plan 03 had minimal stubs), the chain "updating…" overlay gets a stub for Plan 07 to upgrade, the tender sheet gets a stub for Plan 06 to replace, the skeleton silhouette grows a 2-button action row, and the ROADMAP § Phase 10 invariant — zero `switch load.status` in `Features/Loads/` — is locked by a runtime lint-as-test.**

## What landed

### Source

| File | Change | Lines |
|------|--------|-------|
| `validationLedger/Features/Loads/Detail/LoadActionsView.swift` | NEW — public class (open for test subclass) with `configure(actions:role:currentStatus:tenderEligibility:respondByAt:inFlight:onTap:)`. Internal `RespondByFormatter` helper. 18 unit tests + 4 date-format tests cover it. | 461 |
| `validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift` | +`actionsContainer` (index 2 of `contentStack`); body grows from 5 to 6 children. | +20 |
| `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` | +`actionsView` mount, +`lastConfiguredActions` cache (Pitfall 6), +`chainOverlay` (Pitfall 1 stub), +`presentTenderSheet()` stub (Plan 06 fills), +`handleActionTap(_:)` routing, +fleshed-out `.actionInFlight` / `.actionFailed` render arms, +`applyBodyRender` split, +DEBUG test seams. | +~180 |
| `validationLedger/Features/Loads/Detail/LoadDetailSkeletonView.swift` | +`makeActionRowSkeleton()` + iPhone + iPad silhouette inserts. | +~50 |

### Tests

| File | Methods | Status |
|------|---------|--------|
| `validationLedgerTests/Loads/LoadActionsViewTests.swift` | 18 | 18/18 green |
| `validationLedgerTests/Loads/Lint/LoadDetailNoStatusSwitchTests.swift` | 1 | 1/1 green |
| `validationLedgerTests/Loads/RespondByLabelTests.swift` | 4 | 4/4 green |
| `validationLedgerTests/Loads/LoadDetailViewControllerActionRenderTests.swift` | 7 | 7/7 green |
| **Total new tests this plan** | **30** | **30/30 green** |
| Prior-wave regression sweep (LoadDetailViewModelActionTests + RollbackTests + LoadActionPredictorTests + LoadActionTitleResolverTests + RoleLoadPolicyAvailableActionsTests + LoadDetailViewControllerCompositionTests + SizeClassRoutingTests) | 44 + 6 + 3 = 53 | 53/53 green |

## LoadActionsView API surface

```swift
public class LoadActionsView: UIView {
    open func configure(
        actions: [LoadAction],
        role: Role,
        currentStatus: LoadStatus,
        tenderEligibility: TenderEligibility?,
        respondByAt: Date?,
        inFlight: LoadAction?,                // nil when not in-flight; one of `actions` when in-flight
        onTap: @escaping (LoadAction) -> Void
    )
}
```

**Rendering paths:**
- `actions.isEmpty` → buttonRow hidden, `emptyCaptionLabel` visible with 3-rule resolution:
  - `role == .factoring` → `loads.actions.empty.factoring` → "This is a view-only role. No actions available."
  - `currentStatus == .draft` (defensive) → `loads.actions.empty.generic` → "No actions available right now."
  - Otherwise → `loads.actions.empty.terminal.format` with `LoadStatus.localizedDisplayName` interpolation → "This load is in transit. No actions available."
- `actions.nonEmpty` → buttons in a horizontal `.fillEqually` `UIStackView`:
  - Per button: title via `LoadActionTitleResolver.title(for:currentStatus:)`; destructive tint (`.cancel`, `.reject`) via `DS.Colors.destructive`; otherwise `DS.Colors.primary`; min height 50pt.
  - Single action: append an invisible spacer to keep the button half-width (UI-SPEC line 417).
  - In-flight: tapped button shows `.showsActivityIndicator = true` next to the title; tapped + non-tapped buttons all have `isEnabled = false`.
  - ACTION-07 gate: when `actions.contains(.tender)` AND `tenderEligibility?.canTender == false`, the Tender button is disabled and the inline `disabledReasonLabel` shows the server-supplied `disabledReason` verbatim (UI-SPEC line 290), falling back to `loads.actions.tender.disabled.generic` → "Tender unavailable" when nil.
  - Respond-by inline label: visible only when `role ∈ {.carrier, .dispatch}` AND `currentStatus == .tendered` AND `respondByAt != nil` AND `!actions.isEmpty`. Color: `labelSecondary` for future / `destructive` for past. Format via `RespondByFormatter` 4-tier helper.
- Dynamic Type AX content sizes: `buttonRow.axis` flips to `.vertical` via iOS 17 `registerForTraitChanges([UITraitPreferredContentSizeCategory.self])`.
- Accessibility elements published in tap order: [each visible button] → `disabledReasonLabel` (if visible) → `respondByLabel` (if visible) → `emptyCaptionLabel` (empty path).

## 6-child contentStack arrangement (LoadDetailBodyView)

| Index | Child | Source |
|-------|-------|--------|
| 0 | `pinnedSummaryHeader` | Phase 9 Plan 04 |
| 1 | `timelineContainer` (hosts `StatusTimelineView`) | Phase 9 Plan 05 |
| **2** | **`actionsContainer` (hosts `LoadActionsView`)** | **Phase 10 Plan 04 NEW** |
| 3 | `freightDetailsContainer` | Phase 9 |
| 4 | `partiesContainer` | Phase 9 |
| 5 | `verdictBlockContainer` (Plan 09 hides for `.clean`) | Phase 9 Plan 09 |

## render(state:) dispatch (Phase 10 final shape)

| Case | Body content render | Action region configure | Chain overlay |
|------|---------------------|--------------------------|---------------|
| `.loading` | skeletonContainer shown | (action region hidden inside body) | (none) |
| `.loaded(load, chain)` | applyBodyRender(load, chain) | configure(actions: policy.availableActions(role, load), load.status, load.tenderEligibility, load.respondByAt, inFlight: nil) — caches into `lastConfiguredActions` | dismissChainOverlay() |
| `.actionInFlight(predicted, frozenChain, action)` | applyBodyRender(predicted, frozenChain) | configure(actions: `lastConfiguredActions` [Pitfall 6 pre-tap], currentStatus: predicted.status, tenderEligibility: nil, respondByAt: predicted.respondByAt, inFlight: action) — `onTap = no-op` | mountChainOverlayIfNeeded() |
| `.actionFailed(rollbackTo, frozenChain, errorCopyKey)` | applyBodyRender(rollbackTo, frozenChain) | configure(actions: `lastConfiguredActions`, currentStatus: rollbackTo.status, tenderEligibility: rollbackTo.tenderEligibility, respondByAt: rollbackTo.respondByAt, inFlight: nil) — `onTap` re-enabled | dismissChainOverlay() — Plan 07 inserts toast banner here |
| `.error(message)` | errorContainer shown | (action region hidden inside body) | (none) |

## Chain overlay stub API (for Plan 07 to extend)

```swift
private var chainOverlay: UIView?
private func mountChainOverlayIfNeeded()  // idempotent — does nothing if already mounted
private func dismissChainOverlay()        // idempotent — does nothing if not mounted
```

- iPhone vertical-tree composition: anchored to `(everyoneOnLoadStripView.topAnchor, chainOfVouchesView.bottomAnchor)` covering strip + card.
- iPad split / DEBUG legacy iPhone: anchored to `trustGraphView` bounds.
- Plan 07 swaps the stub UIView for the activity-indicator + alpha-fade variant WITHOUT touching `render(state:)` — the mount/dismount API surface is locked here.

## handleActionTap routing

```swift
private func handleActionTap(_ action: LoadAction) {
    if action == .tender {
        presentTenderSheet()  // Plan 06 fills in the sheet
        return
    }
    let body = LoadActionEndpoint.RequestBody(
        actorRole: viewModel.role,
        targetPartyID: nil, respondByAt: nil, note: nil
    )
    Task { [viewModel] in
        await viewModel.submit(action: action, body: body)
    }
}
```

- `.tender` → presentation of the sheet (stub today; Plan 06 wires the actual `UISheetPresentationController`).
- All other actions (`.accept`, `.reject`, `.cancel`, `.post`, `.advanceStatus`) → direct `viewModel.submit(...)` with the role-tagged body.

## Lint regex (LoadDetailNoStatusSwitchTests)

```regex
switch\s+[^\{]*\.status
```

- Matches: `switch x.status`, `switch viewModel.foo.status`, `switch (a, b.status)`.
- Comment lines (whitespace-stripped startsWith `//`) are excluded before matching.
- Scanned directory: `validationLedger/Features/Loads/` (recursive `.swift` files).
- Both `RoleLoadPolicy` (Phase 7) and `LoadActionTitleResolver` (Plan 02) live in `Core/Load/` — out of scope by location.

## Commits

| Hash | Type | Message |
|------|------|---------|
| `e310eb3` | test | test(10-04): add failing tests for LoadActionsView + lint + RespondBy |
| `dc01d21` | feat | feat(10-04): implement LoadActionsView per UI-SPEC § Component Geometry |
| `ddf8dc6` | test | test(10-04): add failing tests for VC action-region wiring + chain overlay stub |
| `fbf58d1` | feat | feat(10-04): mount LoadActionsView; wire VC render arms; skeleton row |

TDD gate compliance: Task 1 (`test:` → `feat:`) + Task 2 (`test:` → `feat:`). Each RED commit fails to compile (or fails the new test) until the corresponding GREEN commit lands.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug interpretation] Empty-state caption scope broadened from terminal-only to all non-Factoring non-`.draft` statuses**

- **Found during:** Task 1 GREEN — Test 6 (`test_configure_emptyActions_terminal_inTransitDisplayName_hasNoUnderscore`) requires the caption for `currentStatus: .inTransit` to contain "in transit" (with space). UI-SPEC line 304 cites a closed terminal set `{.delivered, .cancelled, .podCaptured, .invoiced, .funded}`, of which `.inTransit` is NOT a member. UI-SPEC line 305 says non-Factoring non-terminal statuses with empty actions get the generic copy "No actions available right now." — which contains neither "in transit" nor "in_transit".
- **Resolution:** Apply the `loads.actions.empty.terminal.format` template universally to all non-Factoring non-`.draft` statuses. The format string ("This load is %@. No actions available.") reads naturally for mid-lifecycle statuses too ("This load is in transit. No actions available."). This is the broader Pitfall 5 interpretation: the regression guard against underscore leakage applies to ANY empty caption path, not just the closed terminal set.
- **Files modified:** `validationLedger/Features/Loads/Detail/LoadActionsView.swift` (`emptyCaptionText` helper).
- **Why not Rule 4 (architectural):** No new types, no new keys, no new flows. Same `loads.actions.empty.terminal.format` key with broader application. The cleanest interpretation of Test 6 + UI-SPEC line 305 (which describes the generic fallback as "shouldn't happen given Phase 7 RoleLoadPolicy exhaustiveness — but defensive").
- **Verification:** Test 6 + Test 5 + Test 4 all green; the new interpretation cleanly covers all 3 paths of the original 3-rule table.

**2. [Rule 3 — Blocking] LoadActionsView is `open class`, configure(...) is `open` (not `final` / `public`)**

- **Found during:** Task 2 GREEN — `xcodebuild build-for-testing` after committing the VC integration tests with `CapturingLoadActionsView: LoadActionsView` subclass. Compile error: "Inheritance from a final class 'LoadActionsView'".
- **Resolution:** Changed `public final class LoadActionsView: UIView` to `public class LoadActionsView: UIView` and `public func configure(...)` to `open func configure(...)`. Documented in the class header that production callers MUST NOT subclass — the open access level is a test seam only.
- **Why this and not protocol-based DI:** The configure-method contract is a single 7-parameter call; introducing a protocol would force every test using the spy to import it AND match the protocol's actor isolation under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The subclass-for-test seam is the idiomatic UIKit shape; this matches how the Phase 9 `LoadStatusBadgeView` permits same-module test subclassing.
- **Files modified:** `validationLedger/Features/Loads/Detail/LoadActionsView.swift`.

**3. [Rule 3 — Blocking] applyBodyRender extracted from applyLoadedRender**

- **Found during:** Task 2 GREEN — initial render(state:) implementation called `applyLoadedRender(load: predicted, chainOfTrust: frozenChain)` for `.actionInFlight`, which would ALSO compute and configure the action region with the post-tap (predicted) action set — directly violating Pitfall 6 (in-flight must use the pre-tap snapshot).
- **Resolution:** Extracted `applyBodyRender(load:chainOfTrust:)` from `applyLoadedRender`. The new helper does: cache the payload, build/refresh the banner, rebuild the composition, populate the body view, install the verdict block, configure the trust graph. It does NOT touch the action region. The `.loaded` path: applyBodyRender + actionsView.configure(actions: policy result, ...) + dismissChainOverlay. The `.actionInFlight` path: applyBodyRender(predicted) + actionsView.configure(actions: lastConfiguredActions [pre-tap], inFlight: action) + mountChainOverlayIfNeeded. The `.actionFailed` path: applyBodyRender(rollback) + actionsView.configure(actions: lastConfiguredActions, inFlight: nil) + dismissChainOverlay.
- **Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift`.

**4. [Rule 3 — Blocking] DEBUG-only test seams on the VC**

- **Found during:** Task 2 RED test compile — the action-render tests need to swap in a CapturingLoadActionsView spy and force `.actionInFlight` / `.actionFailed` renders without driving the VM through a real network call.
- **Resolution:** Added 5 `#if DEBUG` `internal` test seams: `replaceActionsViewForTesting(with:)`, `applyTestState_actionInFlight(predicted:frozenChain:action:)`, `applyTestState_actionFailed(rollbackTo:frozenChain:errorCopyKey:)`, `applyTestState_loaded(load:chain:)`, `handleActionTapForTesting(action:)`. Plus 2 non-DEBUG `internal` read-only seams: `chainOverlayForTesting` (computed property) and `presentTenderSheetCallCountForTesting` (read-only `private(set)`). Release builds never compile the DEBUG seams.
- **Why not protocol-based DI / NotificationCenter:** Same as deviation 2 — the in-repo precedent (LoadDetailViewControllerSizeClassRoutingTests' `handleSizeClassChange(forceRebuild:)` seam) uses `internal` test entry points; this plan follows that precedent.
- **Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift`.

**5. [Rule 3 — Environment] iPhone 16 → iPhone 17 substitution**

- **Found during:** First test run.
- **Issue:** Plan's `<verify>` block specifies `-destination 'platform=iOS Simulator,name=iPhone 16'`. iPhone 16 is NOT installed on this host (project memory `ios-test-suite-pitfalls`).
- **Fix:** Substituted `iPhone 17`. Runner-side only; no source change.

**6. [Rule 3 — Test runner stability] `-only-testing` folder-segment → class-name only**

- **Found during:** First scoped test invocation.
- **Issue:** `-only-testing:validationLedgerTests/Loads/LoadActionsViewTests` discovers 0 tests; the XCTest runner does not parse the folder segment.
- **Fix:** Used `-only-testing:validationLedgerTests/LoadActionsViewTests` (no folder segment) throughout.

**Total deviations:** 6 — 1 Rule 1 (bug-interpretation broadening), 4 Rule 3 (blocking compile/test seam adds), 1 Rule 3 (environment). No Rule 4 (architectural) decisions needed. All documented; no scope creep.

## Threat Surface Scan

No new threat surface beyond what's already enumerated in the plan's `<threat_model>`. Specifically:

- **T-10-01 (Wrong action shown for role × status)** — mitigated by the lint-as-test `LoadDetailNoStatusSwitchTests` (zero `switch.*\.status` hits across `Features/Loads/`) + the VC's `applyLoadedRender` computing actions via `RoleLoadPolicy.availableActions(for:in:)` (single source of truth).
- **T-10-04 (Tender to unverified counterparty)** — partial mitigate. The load-level Tender button gate via `Load.tenderEligibility?.canTender == false` is live; the carrier-level picker gate ships in Plan 06 (the sheet).
- **T-10-PR-01 (Pitfall 6 in-flight against post-tap action set)** — mitigated by `lastConfiguredActions` cache + the `inFlight: LoadAction?` parameter on `configure(...)`. Test 2 of LoadDetailViewControllerActionRenderTests is the regression guard.
- **T-10-PR-02 (Pitfall 5 `in_transit` underscore leakage)** — mitigated. Test 6 of LoadActionsViewTests is the explicit regression guard.
- **T-10-PR-03 (Pitfall 1 chain overlay double-mount)** — partial mitigate (stub). Single `chainOverlay: UIView?` ref + idempotent `mountChainOverlayIfNeeded`. Plan 07 finishes the alpha-fade animation cleanup. Tests 4 + 5 lock the mount/dismount API.
- **T-09-04 view-layer lock extended** — mitigate. The `.actionFailed` arm in `render(state:)` IGNORES the `errorCopyKey` associated value (no toast rendered in this plan); the VM holds the localization key, no server text leaks to the screen.
- **T-10-PR-SC (Package legitimacy)** — accept. Phase 10 installs ZERO new packages.

No `## Threat Flags` section needed — no new server endpoints, no new auth paths, no new file access, no schema changes at trust boundaries.

## Known Stubs

Two stubs ship with this plan; both are explicitly documented and scheduled for downstream plans:

1. **`presentTenderSheet()` stub (LoadDetailViewController)** — empty body, increments `presentTenderSheetCallCountForTesting`. Plan 06 fills in the `UISheetPresentationController` that collects the carrier + respond-by deadline + (on Send) dispatches `viewModel.submit(action: .tender, body: ...)`.
2. **Chain overlay stub (`mountChainOverlayIfNeeded` / `dismissChainOverlay` + `chainOverlay: UIView?`)** — mounts a translucent `surface @ 0.6` `UIView` over the chain region; no activity indicator, no alpha-fade. Plan 07 swaps the stub for the activity-indicator + alpha-fade variant WITHOUT touching `render(state:)` — the mount/dismount API surface is locked here.

Neither stub blocks the plan's stated success criteria. The plan's `<objective>` explicitly scopes them as stubs: "Also stub the chain overlay's mount/dismount API on the VC so Plan 07 (which owns the actual overlay subview + animation) can plug in without re-entering the render dispatcher."

## TDD Gate Compliance

- ✓ Task 1: `test(10-04): add failing tests for LoadActionsView + lint + RespondBy` (RED, `e310eb3`) → `feat(10-04): implement LoadActionsView per UI-SPEC § Component Geometry` (GREEN, `dc01d21`).
- ✓ Task 2: `test(10-04): add failing tests for VC action-region wiring + chain overlay stub` (RED, `ddf8dc6`) → `feat(10-04): mount LoadActionsView; wire VC render arms; skeleton row` (GREEN, `fbf58d1`).
- No refactor commit needed — both GREEN implementations were minimal on the first pass after the Rule 1/3 fixes documented above.

## Self-Check

Verified at HEAD `fbf58d1`:

- [x] FOUND: `validationLedger/Features/Loads/Detail/LoadActionsView.swift` (461 lines)
- [x] FOUND: `validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift` (modified — actionsContainer at index 2)
- [x] FOUND: `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` (modified — render arms expanded, test seams)
- [x] FOUND: `validationLedger/Features/Loads/Detail/LoadDetailSkeletonView.swift` (modified — action-row skeleton)
- [x] FOUND: `validationLedgerTests/Loads/LoadActionsViewTests.swift`
- [x] FOUND: `validationLedgerTests/Loads/Lint/LoadDetailNoStatusSwitchTests.swift`
- [x] FOUND: `validationLedgerTests/Loads/RespondByLabelTests.swift`
- [x] FOUND: `validationLedgerTests/Loads/LoadDetailViewControllerActionRenderTests.swift`
- [x] FOUND commit `e310eb3` (Task 1 RED)
- [x] FOUND commit `dc01d21` (Task 1 GREEN)
- [x] FOUND commit `ddf8dc6` (Task 2 RED)
- [x] FOUND commit `fbf58d1` (Task 2 GREEN)
- [x] Source assertion: `grep -c 'public class LoadActionsView: UIView' validationLedger/Features/Loads/Detail/LoadActionsView.swift` = 1
- [x] Source assertion: `grep -c 'actionsContainer' validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift` = 3 (declaration + addArrangedSubview + 1 doc occurrence)
- [x] Source assertion: `grep -c 'case .actionInFlight' validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` = 1
- [x] Source assertion: `grep -c 'case .actionFailed' validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` = 1
- [x] Source assertion: `grep -c 'private var chainOverlay: UIView?' validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` = 1
- [x] Source assertion: `grep -c 'lastConfiguredActions' validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` = 5 (declaration + cache write in applyLoadedRender + 2 cache reads + 1 doc reference)
- [x] Source assertion: `grep -rnE 'switch[[:space:]]+[^{]*\.status' validationLedger/Features/Loads/ | grep -v '^[^:]*://'` = 0 hits
- [x] 18/18 LoadActionsViewTests green
- [x] 1/1 LoadDetailNoStatusSwitchTests green
- [x] 4/4 RespondByLabelTests green
- [x] 7/7 LoadDetailViewControllerActionRenderTests green
- [x] 53/53 prior-wave regression sweep green (LoadDetailViewModelActionTests + Rollback + PredictorTests + TitleResolver + AvailableActions + CompositionTests + SizeClassRoutingTests)
- [x] Whole-project `xcodebuild build` returns `BUILD SUCCEEDED`

## Self-Check: PASSED

---
*Phase: 10-per-role-tender-accept-reject*
*Plan: 04*
*Wave: 3*
*Completed: 2026-05-21*
