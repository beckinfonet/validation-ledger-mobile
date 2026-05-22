---
phase: 10-per-role-tender-accept-reject
fixed_at: 2026-05-21T20:06:02Z
review_path: .planning/phases/10-per-role-tender-accept-reject/10-REVIEW.md
iteration: 1
findings_in_scope: 10
fixed: 10
skipped: 0
status: all_fixed
---

# Phase 10: Code Review Fix Report

**Fixed at:** 2026-05-21T20:06:02Z
**Source review:** .planning/phases/10-per-role-tender-accept-reject/10-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 10 (2 Critical + 8 Warning; 6 Info deferred per fix_scope=critical_warning)
- Fixed: 10
- Skipped: 0

All 10 in-scope findings were addressed. WR-04 was applied jointly with
CR-01 (same function body, same commit) so the report lists 9 fix
commits covering 10 findings. One finding (WR-06) is a semantic change
to the rollback contract and is flagged for human verification — see
the "Requires human verification" note in its entry below.

## Fixed Issues

### CR-01: Tender sheet Send button doesn't re-validate the selected carrier — defense-in-depth gap

**Files modified:** `validationLedger/Features/Loads/Detail/TenderSheetViewController.swift`, `validationLedgerTests/Loads/TenderSheetViewControllerTests.swift`
**Commit:** 969f8eb
**Applied fix:** `handleSendTap()` now re-validates `selectedCarrier.verificationState == .verified` AND `resolvedDeadlineDate > Date()` BEFORE invoking `onSend`. If either guard fails, `updateSendButton()` re-syncs the UI to its computed truth and the closure bails. Added an internal test seam `forceSelectedCarrierIndexForTesting(_:)` that bypasses the delegate guard, then added Test 16 `test_handleSendTap_refusesNonVerifiedCarrier_defenseInDepth` which forces `selectedCarrierIndex` to each of the .pending/.unverified/.flagged rows and asserts `handleSendTap` STILL refuses to fire `onSend` (the T-10-04 platform-thesis defense-in-depth requirement). Test results: 16/16 (15 existing + 1 new) pass.

### CR-02: Mock action-success payload returns a hardcoded `VL-1004` load + chain for EVERY action against EVERY loadID

**Files modified:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift`, `validationLedgerTests/Loads/MockLoadFixtureRegistryActionToggleTests.swift`
**Commit:** 5d52f4d
**Applied fix:** Converted the static `actionSuccessPayload: Data` constant to a function `actionSuccessPayload(forLoadID: String) -> Data` that rewrites the canonical fixture's `"id": "VL-1004"` field to `"id": "<loadID>"` via a single literal substitution. Other VL-1004 references (reference_number, edge_id slugs) remain as harmless demo metadata — only `load.id` is read by `LoadDetailViewModel.performAction(...)` to drive the post-action `.loaded(response.load,…)` state. Updated the action-success handler call site to pass the request's loadID. Added a CR-02 regression sweep `test_actionSuccessPayload_synthesizedFromRequestedLoadID_CR02` exercising 3 distinct VL-#### loadIDs and asserting `response.load.id` mirrors the request. Enhanced `test_default_noFlags_actionRequest_returnsSuccess` to also assert `load.id == "VL-001"`. Test results: 9/9 (8 existing + 1 new) pass.

### WR-01: `MockActionFailureToggles` exposes mutable `public static var` closures with no isolation — data race surface

**Files modified:** `validationLedger/Core/Networking/Mock/MockActionFailureToggles.swift`
**Commit:** 19cbdaf
**Applied fix:** Each of the 4 `…Active: () -> Bool` toggles is now a `get`/`set` computed property backed by a `nonisolated(unsafe) private static var` closure storage. A single `toggleLock: NSLock` guards reads and writes. The public test-seam API is unchanged — tests still write `DebugActionFailureOverride.conflict409Active = { … }`. Cross-test happens-before ordering remains the test author's responsibility (documented inline). #if DEBUG-gated file, zero cost in Release. Test results: 9/9 pass.

### WR-02: `Thread.sleep(forTimeInterval:)` inside `MockURLProtocol` handler blocks the URLSession worker for 1.5s — handler-array starvation

**Files modified:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift`
**Commit:** 2b1f156
**Applied fix:** Replaced `Thread.sleep(forTimeInterval:)` in the (3d) `latencySlow` handler with a `DispatchSemaphore` whose `signal()` is scheduled via `DispatchQueue.global().asyncAfter`. The current request's URLSession worker still blocks (the handler closure MUST return synchronously to defer to the next match), but the wake-up runs on a separate global-queue thread — sibling URLSession workers on the same internal queue can proceed. The 1.5s latency contract is preserved. Test results: 9/9 pass (includes the latency timing assertion).

### WR-03: `TenderSheetViewController.configureTableView()` activates a fixed-height constraint based on a one-time `contentSize` read — Dynamic Type changes corrupt the layout

**Files modified:** `validationLedger/Features/Loads/Detail/TenderSheetViewController.swift`
**Commit:** 9448624
**Applied fix:** Added a stored `tableViewContentHeightConstraint: NSLayoutConstraint?` property. Extracted the constraint installation into a `recomputeTableContentHeightConstraint()` helper that deactivates the existing constraint, re-measures `tableView.contentSize.height`, and installs a fresh one. Overrode `traitCollectionDidChange(_:)` to invoke the helper when `preferredContentSizeCategory` changes — Dynamic Type now correctly resizes the table. The empty-directory case (contentH == 0) is preserved: no constraint installed, the `>= 64` minimum from `installLayout` keeps the table from collapsing. Test results: 20/20 (TenderSheet unit + snapshot suites) pass.

### WR-04: `TenderSheetViewController.handleSendTap()` mutates the Send button's activity indicator without serializing against the post-`.loaded`/post-`.actionFailed` parent re-render

**Files modified:** `validationLedger/Features/Loads/Detail/TenderSheetViewController.swift`, `validationLedgerTests/Loads/TenderSheetViewControllerTests.swift`
**Commit:** 969f8eb (jointly with CR-01)
**Applied fix:** Dropped the redundant inner `MainActor.run` hop. The VC is already `@MainActor` under `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, so the outer Task body runs on the main actor. The original pattern produced two writes to `sendButton.configuration` (one explicit spinner-off, one inside `updateSendButton()`) and a 1-frame flicker when `computeSendButtonState()` re-enabled Send. The new flow explicitly clears the spinner once, then defers to `updateSendButton()` for the enable/disable + helper-copy decisions.

### WR-05: `LoadDetailViewController.presentTenderSheet()` silently drops carrier-directory fetch errors — user is left thinking the tender flow froze

**Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift`
**Commit:** a8a573d
**Applied fix:** The catch arm now invokes `self.presentToastBanner(copyKey: "loads.actions.error.tender_failed")`. The toast resolves to the locked English fallback "Couldn't send tender. Try again." via `defaultEnglishFallback`. T-09-04 still holds — the rendered text comes from `NSLocalizedString` (locked), not from the thrown error's `localizedDescription`. A future plan can introduce a dedicated `loads.detail.tender.error.directory_unavailable` key; for v1.1 the existing key surfaces the failure without leaking server text. Test results: action-render 7/7 pass (one pre-existing flake in the toast double-mount test was unrelated and rooted in WR-08, since fixed).

### WR-06: `LoadDetailViewModel.submit` permits action submission from `.actionInFlight` but treats the predicted Load as the pre-tap snapshot — rollback returns the user to a never-committed state

**Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift`
**Commit:** a815c76
**Applied fix:** Added private `lastConfirmedLoad: Load?` and `lastConfirmedChain: ChainOfTrust?` storage. Both are written from `performFetch`'s terminal `.loaded` arm AND `performAction`'s success arm — i.e., every state the server has acknowledged. In `submit()`'s `.actionInFlight` arm, captured `preLoad = lastConfirmedLoad` (with a defensive bail if nil) instead of the predicted Load. `preChain = frozenChain` is preserved as-is because `frozenChain` IS the last-confirmed chain by the D-13 invariant (the chain never moves through `.actionInFlight`). The `.actionFailed` arm is unchanged because `rollbackTo` was itself derived from a server-confirmed snapshot at the previous submit's entry — restorable by induction.

**Status: fixed: requires human verification.** This is a semantic change to the rollback contract per the reviewer's "Scenario" in the finding. The existing rollback + action tests cover the canonical `.loaded → .actionInFlight → .actionFailed → .loaded` paths (15/15 + 4/4 pass) but do NOT explicitly exercise the cancel-after-tender mid-flight failure path described in the finding. A focused test for that scenario should be added in a follow-up phase to lock the rollback-to-confirmed-snapshot invariant.

### WR-07: `LoadDetailViewController.makeChainOverlayConstraints` returns stale-anchor constraints when the strip/card aren't in the hierarchy

**Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift`
**Commit:** 0ac8621
**Applied fix:** Rewrote `makeChainOverlayConstraints` for the iPhone vertical-tree path as an all-or-nothing decision instead of per-edge conditional anchors. When BOTH strip and card are mounted, pin to (strip.top, card.bottom) — the canonical case. When only one is mounted (mid-detach window), pin all 4 edges to that one view (overlay briefly smaller than ideal but CANNOT straddle the chain boundary into bodyView's actions/freight rows). When neither is mounted (transient mid-rebuild), install zero-height constraints pinned to `bodyView.topAnchor` so the overlay occupies no space until the next `.actionInFlight` render lands. The over-spanning grey-scrim-over-actions visual is now structurally impossible. Test results: 10/10 (toast-and-overlay suite) pass.

### WR-08: `LoadActionToastBannerView.scheduleAutoDismiss()` Timer closure captures `[weak self]` but the Task hop doesn't — possible retain after view removal

**Files modified:** `validationLedger/Features/Loads/Detail/LoadActionToastBannerView.swift`
**Commit:** 49a7818
**Applied fix:** Three changes: (1) `removeFromSuperview` now invalidates and nils `autoDismissTimer` BEFORE calling super.removeFromSuperview — covers paths that tear down the banner without going through `playSlideOutAndRemove` (parent VC teardown, memory-warning eviction). (2) Added `deinit { autoDismissTimer?.invalidate() }` as a catch-all. (3) The inner `Task { @MainActor in self?.… }` now uses `Task { @MainActor [weak self] in self?.… }` so the Task body holds self weakly — the iOS 18+ implicit-strong-capture hazard is avoided. Diagnosis bonus: the malloc double-free flake observed during WR-05 testing on the toast double-mount test stopped recurring after this fix landed, consistent with the Timer firing against an out-of-hierarchy view. Test results: 16/16 (unit) + 6/6 (snapshot) pass.

---

_Fixed: 2026-05-21T20:06:02Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
