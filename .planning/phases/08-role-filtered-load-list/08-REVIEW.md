---
phase: 08-role-filtered-load-list
reviewed: 2026-05-19T00:00:00Z
depth: standard
files_reviewed: 28
files_reviewed_list:
  - validationLedger/App/AppContainer.swift
  - validationLedger/App/AppCoordinator.swift
  - validationLedger/Core/Load/Load.swift
  - validationLedger/Core/Load/LoadListItem.swift
  - validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift
  - validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift
  - validationLedger/Core/Networking/Mock/MockOTPRoleFixtureRegistry.swift
  - validationLedger/Features/Loads/Cells/LoadRowCell.swift
  - validationLedger/Features/Loads/Cells/SkeletonLoadRowCell.swift
  - validationLedger/Features/Loads/LoadListViewController.swift
  - validationLedger/Features/Loads/LoadListViewModel.swift
  - validationLedger/Roles/Broker/BrokerTabBarController.swift
  - validationLedger/Roles/Carrier/CarrierTabBarController.swift
  - validationLedger/Roles/Dispatch/DispatchTabBarController.swift
  - validationLedger/Roles/Factoring/FactoringTabBarController.swift
  - validationLedger/Roles/Shipper/ShipperTabBarController.swift
  - validationLedger/UI/Components/LoadStatusBadgeView.swift
  - validationLedger/UI/Components/VerificationBadgeView.swift
  - validationLedgerTests/Load/LoadDomainDecodeTests.swift
  - validationLedgerTests/Loads/LoadListEnvelopeDecodeTests.swift
  - validationLedgerTests/Loads/LoadListViewModelTests.swift
  - validationLedgerTests/Loads/Snapshot/LoadRowCellSnapshotTests.swift
  - validationLedgerTests/Loads/Snapshot/LoadStatusBadgeViewSnapshotTests.swift
  - validationLedgerTests/Loads/Snapshot/SkeletonLoadRowCellSnapshotTests.swift
  - validationLedgerTests/Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift
  - validationLedgerTests/Support/UIKitSnapshot.swift
  - validationLedgerUITests/Loads/RoleLoadsTabSmokeTests.swift
findings:
  critical: 0
  blocker: 2
  warning: 6
  info: 4
  total: 12
status: issues_found
---

# Phase 8: Code Review Report

**Reviewed:** 2026-05-19
**Depth:** standard
**Files Reviewed:** 28
**Status:** issues_found

## Summary

Phase 8 ships the first end-to-end Loads UI for all five roles. The fail-closed
trust-signal discipline (TRUST-02, T-08-06, T-08-07) is solid and well-tested
— the `VerificationBadgeView` nil-counterparty path, the `LoadRowCell`
`prepareForReuse` reset, and the zero-PII `LoadListViewModel` logger emissions
all hold under the locked snapshot/state-machine test surface. The
`LoadListItem` Decodable contract correctly relies on synthesized
`decodeIfPresent` for the nil-counterparty fail-closed semantic.

That said, the review surfaces two BLOCKER-tier concurrency / UX defects that
are reachable without test setup:

1. `LoadListViewModel.fetchLoads()` has NO in-flight guard. `viewWillAppear`
   fires it on every tab-switch / modal-dismiss, AND pull-to-refresh fires it,
   AND the error-state retry button fires it — all in unbounded parallel
   Tasks. The "last-write-wins" race lets a stale response overwrite a
   fresher one, and can leave the refresh control spinning indefinitely.
2. The Factoring "Invoices" tab's INNER navigation bar reads "Loads" — the
   T-08-12 lock fixes only the tab-bar label, not the in-screen nav-bar
   title. The user is on the Invoices tab but the chrome above the list says
   "Loads".

Six additional Warnings cover diffable-data-source hashing fragility,
unbounded mock-handler accumulation in DEBUG, swallowed Keychain seed
errors in a UI-test path, dead-store on `invoicesTab.title`, contradictory
documentation on UILabel `text`/`attributedText` ordering, and a Factoring
fallback that constructs a bare placeholder VC under the locked
`UIBarButtonItem` accessibility identifier. Four Info-tier items capture
maintainability concerns (drift between inline JSON and test fixtures,
brittle skeleton-row height constant, `String(describing: type(of:))`
recursive walk fragility, and an off-by-one comment about `text =`/
`attributedText` order that contradicts itself).

## Blocker Issues

### BL-01: `LoadListViewModel.fetchLoads()` has no in-flight guard — multiple concurrent fetches race on `state` and `refreshControl`

**File:** `validationLedger/Features/Loads/LoadListViewModel.swift:152-187`
**Also:** `validationLedger/Features/Loads/LoadListViewController.swift:320-323, 355-364, 382-384`

**Issue:** `fetchLoads()` is `async` and mutates `self.state` based on the
result of `await apiClient.request(...)`. Three call sites in the VC fire
fresh `Task { await viewModel.fetchLoads() }` calls with NO coordination:

- `viewWillAppear(_:)` (line 322) — fires on every tab switch, modal
  dismiss, present/dismiss round-trip, and on the initial render.
- `pulledToRefresh()` (line 382) — UIRefreshControl `.valueChanged`.
- `errorRetryButton` UIAction (line 360) — error-state Try again button.

There is no `isFetching` flag, no `Task` reference for cancellation, and no
serialization. A realistic sequence:

```
t0: viewWillAppear → Task A (await apiClient...)
t10: user pulls to refresh → Task B (await apiClient...)
t100: Task A completes with response X, sets state = .loaded(X)
t150: Task B completes with response Y (stale, earlier server snapshot),
      sets state = .loaded(Y)
```

The UI now displays a stale Y over a fresher X. Worse:

```
t0: state = .loaded → user pulls to refresh → Task A
t1: refreshControl is spinning, refresh-from-loaded path → no .loading
t50: user taps the error-retry button (was visible from a prior session?)
     → Task B fires
t100: Task A succeeds → render(.loaded) → endRefreshing() in apply completion
t200: Task B succeeds → render(.loaded) again → endRefreshing() called on an
      already-ended control → no-op, but the second snapshot diff produces
      a visible row-replace animation for unchanged content
```

Also: if Task A errors AFTER Task B succeeds, the user sees the error screen
even though their most recent successful fetch was Task B.

This is a security-adjacent concern as well: a `LoadListItem` with
`displayedCounterparty: .flagged` from a fresh fetch can be silently overwritten
by an older fetch's `.verified` counterparty, briefly upgrading the on-screen
trust signal. That directly contradicts the project's "trust that cannot be
faked" core value.

**Fix:** Add an in-flight `Task` reference and either coalesce or cancel:

```swift
private var fetchTask: Task<Void, Never>?

public func fetchLoads() async {
    // Cancel-and-replace: a fresh fetch supersedes an in-flight one.
    fetchTask?.cancel()
    let task = Task { [weak self] in
        await self?.performFetch()
    }
    fetchTask = task
    await task.value
}

private func performFetch() async {
    if case .loaded = state {
        // refresh-from-loaded — no .loading transition
    } else {
        state = .loading
    }
    let response: LoadListEndpoint.Response
    do {
        response = try await apiClient.request(LoadListEndpoint(role: role))
    } catch is CancellationError {
        return  // superseded by a fresher fetch
    } catch {
        logger.error(event: LogEvent("loads_list_fetch_failed"), fields: [:])
        state = .error(message: Self.userFacingMessage(for: error))
        return
    }
    if Task.isCancelled { return }
    logger.info(event: LogEvent("loads_list_loaded"), fields: [:])
    state = response.loads.isEmpty
        ? .empty
        : .loaded(items: response.loads, nextCursor: response.nextCursor)
}
```

Alternative (coalesce): drop the new fetch if `fetchTask` is non-nil and
not finished. Cancel-and-replace better matches pull-to-refresh semantics.

---

### BL-02: Factoring "Invoices" tab shows "Loads" in the nav bar — T-08-12 only locks the tab-item title, not the in-screen title

**File:** `validationLedger/Roles/Factoring/FactoringTabBarController.swift:42-88`
**Also:** `validationLedger/Features/Loads/LoadListViewController.swift:284-288`

**Issue:** `T-08-12 / PATTERNS Q1` locks the Factoring tab label to "Invoices".
The implementation does this correctly at the tab-bar level by overriding
the outer `UINavigationController`'s `tabBarItem`. However,
`LoadListViewController.viewDidLoad` unconditionally sets:

```swift
title = NSLocalizedString("loads.list.nav_title", value: "Loads", ...)
```

This title propagates into `UINavigationController`'s navigation bar via
`navigationItem.title` fallback. So when the Factoring user is on the
"Invoices" tab, the IN-SCREEN nav-bar at the top of the loads list reads
"Loads" — directly contradicting the locked product copy that the tab bar
below carefully preserves. Worse, the assignment
`invoicesTab.title = "Invoices"` on line 52 of
`FactoringTabBarController.viewDidLoad` is dead code: it runs BEFORE the
inner LoadListViewController's own `viewDidLoad` (which fires later when the
tab is selected / the view loads), and is overwritten.

This is the kind of subtle inconsistency the T-08-12 PATTERNS lock exists to
prevent. The current XCUITest `test_factoringInvoicesTabRendersList` only
asserts that the tab-bar BUTTON exists with text "Invoices" — it doesn't
look at the nav-bar title inside the loads screen, so this defect is not
covered by the integration test.

**Fix:** Make the in-screen title role-aware. Two clean options:

(a) Pass the title through the factory:

```swift
// AppContainer.makeLoadListScreen
@MainActor
func makeLoadListScreen(role: Role) -> UIViewController {
    let title: String = (role == .factoring) ? "Invoices" : "Loads"
    let vm = LoadListViewModel(role: role, apiClient: apiClient, logger: featureLogger)
    return LoadListViewController(viewModel: vm, navTitle: title)
}
```

(b) Set the title at the call site for Factoring:

```swift
// FactoringTabBarController.viewDidLoad — after factory call
let invoicesTab = loadListScreenFactory?(role) ?? ...
invoicesTab.title = "Invoices"
// AND override inside LoadListViewController: only set title if not preset.
```

Option (a) is cleaner — it removes the dead assignment and centralizes the
role→title mapping in the composition root next to the existing T-08-12
plumbing. Whichever path is chosen, add an XCUITest assertion that
`app.navigationBars["Invoices"]` exists on the Factoring path so this lock
is genuinely covered end-to-end.

## Warnings

### WR-01: `MockLoadFixtureRegistry.registerAppDefaults()` appends handlers on every `AppContainer.init` — DEBUG handler-array leak across role swaps

**File:** `validationLedger/App/AppContainer.swift:481-487`
**Also:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift:65-76`

**Issue:** Each time `SceneDelegate.presentRoot(_:)` builds a fresh
AppContainer (per ADR 0002 abrupt-replace — and DevMenu drives this on
every role swap), the DEBUG block runs:

```swift
if case .mock = resolvedConfig, !isUITestRolePath {
    MockDefaultFixtures.registerAppDefaults()
    MockLoadFixtureRegistry.registerAppDefaults()   // APPEND-ONLY
}
```

`MockLoadFixtureRegistry.registerAppDefaults()` explicitly forbids itself
from calling `MockURLProtocol.reset()` (line 17-24 file header — would
clobber `MockDefaultFixtures`). So every role swap APPENDS another set of
handlers without ever pruning. After N swaps the global `_handlers` array
has N copies of the same three load-domain handlers (plus N copies of
MockDefaultFixtures' handlers). First-match-wins means the behavior is
correct, but:

- Memory grows linearly in role swaps (small but unbounded in a long DEBUG
  session — DevMenu role-swap is a designed flow).
- Lookup is now O(N·handlers-per-registration) per request.
- Closures capture nothing observably here, but if any future closure ever
  captures `[weak container]` it'll silently leak the dropped containers.

**Fix:** Either (a) make `MockDefaultFixtures.registerAppDefaults()` +
`MockLoadFixtureRegistry.registerAppDefaults()` idempotent (skip if already
registered for this session), or (b) gate the entire DEBUG registration on a
"first launch" flag at the SceneDelegate level so it runs ONCE per process
lifetime, not once per AppContainer. Option (b) requires SceneDelegate
changes; option (a) is local. A guard sentinel works:

```swift
private static var hasRegistered = false
static func registerAppDefaults() {
    guard !hasRegistered else { return }
    hasRegistered = true
    // ... existing register() calls
}
```

---

### WR-02: KYC UI-test seed errors are silently swallowed by a stringless logger event — failed seeds leave subsequent test in an unknown phase

**File:** `validationLedger/App/AppContainer.swift:637-642`

**Issue:** The KYC test-seed block catches Keychain `set` failures and emits
only `logger.error(event: .init("kyc_uitest_seed_failed"), fields: [:])`. No
test-side assertion checks for this — the UI test proceeds and the role
shell (or KYC gate) appears in whatever state the un-seeded Keychain
produces. The most-likely failure mode is a `Keychain` access-control
mismatch in a CI-fresh simulator, which would silently let the test land on
phone-entry instead of the role shell — and the test then fails downstream
in an unrelated assertion ("expected 'Loads' tab but got 'phone-entry-field'").

This isn't strictly a Phase 8 regression — the catch was already there
pre-Phase 8 — but Phase 8's UI test flow (`RoleLoadsTabSmokeTests`) depends
on this seed succeeding, so the lack of a hard fail is a real diagnostic
gap.

**Fix:** In DEBUG only, fatalError on seed failure so the failure is
unambiguous:

```swift
} catch {
    logger.error(event: .init("kyc_uitest_seed_failed"), fields: [:])
    fatalError("KYC UI-test seed failed: \(error) — UI test cannot proceed without seeded Keychain state")
}
```

The fatalError is acceptable here because the entire block is
`#if DEBUG`-gated and only runs when a launch arg seeds the test.

---

### WR-03: `LoadRowItem.hash(into:)` hashes only `load.id` but `==` compares more — verification-state changes trigger full delete+insert animations, never `reconfigureItems`

**File:** `validationLedger/Features/Loads/LoadListViewController.swift:119-127`
**Also:** `validationLedger/Features/Loads/LoadListViewModel.swift:224-230`

**Issue:** The diffable-data-source wrapper has:

```swift
nonisolated fileprivate struct LoadRowItem: Hashable, @unchecked Sendable {
    let item: LoadListItem
    func hash(into hasher: inout Hasher) {
        hasher.combine(item.load.id)
    }
    static func == (l: LoadRowItem, r: LoadRowItem) -> Bool {
        l.item == r.item
    }
}
```

And `LoadListItem ==` compares `load.id`, `displayedCounterparty?.partyID`,
and `displayedCounterparty?.verificationState`. The Hashable contract is
satisfied (equal items hash equal), but the diffable data source uses `==`
to decide whether an item is "the same item" between snapshots. So when the
server's next fetch reports VL-1001 with verificationState `.pending →
.verified`, the OLD item and the NEW item are NOT `==`. The data source
treats this as one delete + one insert, producing a row-replace animation
even though it's the same load. The intended `reconfigureItems` re-render
(per the file-header comment in `LoadListViewModel.swift:60-69`) never
fires because `reconfigureItems` requires the identifier to be `==`.

This is a UX bug AND a subtle trust-signal flicker — the row briefly leaves
and re-enters the visible window during the swap animation, which on a
slow scroll can read as "the row changed identity" rather than "this row's
counterparty was updated."

**Fix:** Make `LoadRowItem.==` compare only `load.id` (matching its hash),
and rely on a SEPARATE content-equality check inside the data source apply
path to drive `reconfigureItems` when the same id has a new payload:

```swift
nonisolated fileprivate struct LoadRowItem: Hashable, @unchecked Sendable {
    let item: LoadListItem
    func hash(into hasher: inout Hasher) { hasher.combine(item.load.id) }
    static func == (l: LoadRowItem, r: LoadRowItem) -> Bool {
        l.item.load.id == r.item.load.id
    }
}

// In render(.loaded):
let oldItems = dataSource.snapshot().itemIdentifiers
let newItems = items.map(LoadRowItem.init)
// Build set of ids whose payload changed (full LoadListItem equality)
let changedIDs: Set<String> = ... // diff old vs new by content
var snap = NSDiffableDataSourceSnapshot<LoadListSection, LoadRowItem>()
snap.appendSections([.main])
snap.appendItems(newItems, toSection: .main)
// reconfigure only the rows whose payload changed
let toReconfigure = newItems.filter { changedIDs.contains($0.item.load.id) }
snap.reconfigureItems(toReconfigure)
dataSource.apply(snap, animatingDifferences: true) { ... }
```

(Or accept the current behavior and rewrite the file-header comment to say
"any payload change triggers a full row-swap animation" — but that's the
opposite of what the comment claims today.)

---

### WR-04: `viewControllers?.first` fallback in `FactoringTabBarController` clobbers the avatar-affordance `accessibilityIdentifier` when `loadListScreenFactory` is nil

**File:** `validationLedger/Roles/Factoring/FactoringTabBarController.swift:50-88`

**Issue:** When `loadListScreenFactory` is `nil` (test path), the fallback
creates a bare placeholder VC via `ShipperTabBarController.makeTab(...)`:

```swift
let invoicesTab: UIViewController = loadListScreenFactory?(role)
    ?? ShipperTabBarController.makeTab(title: "Invoices", systemImage: "doc.text.magnifyingglass")
```

That fallback VC is then wrapped in a UINavigationController by
`wrapTabsWithNavAndInstallAvatar`, which installs an avatar bar button
with `accessibilityIdentifier = "nav-avatar"` on the wrapped nav's root —
which is the placeholder VC. So far OK. THEN, line 82-88 OVERWRITES the
wrapper nav's `tabBarItem`, but this replacement happens AFTER
`wrapTabsWithNavAndInstallAvatar`. That helper installed the avatar on the
INNER VC's `navigationItem.rightBarButtonItem`. The new `tabBarItem` on
the OUTER nav doesn't affect the avatar.

The actual bug here is subtler: the four other roles all route through
`ShipperTabBarController.makeLoadsTab(loadListScreenFactory:role:)`, which
sets `vc.tabBarItem = UITabBarItem(...)` AFTER the factory returns. That
hardcoded re-creation IGNORES whatever tab item the underlying VC may
already have set internally — fine because LoadListViewController doesn't
set one. But the FACT that every other tab bar uses
`makeLoadsTab(loadListScreenFactory:role:)` and Factoring DOES NOT
duplicates the role→title mapping logic in two places: `makeLoadsTab` for
4 roles, and `FactoringTabBarController.viewDidLoad` for the 5th. A future
edit to the Loads tab construction (icon swap, identifier addition) will
land in one place and not the other.

**Fix:** Extend `makeLoadsTab` to take an explicit title/image override:

```swift
static func makeLoadsTab(
    loadListScreenFactory: ((Role) -> UIViewController)?,
    role: Role,
    title: String = "Loads",
    systemImage: String = "shippingbox"
) -> UIViewController { ... }
```

Then Factoring calls `makeLoadsTab(..., role: .factoring, title: "Invoices",
systemImage: "doc.text.magnifyingglass")` and the special-case 30 lines of
override logic in `FactoringTabBarController.viewDidLoad` collapse to one
line. This also closes BL-02 cleanly because `makeLoadsTab` is the one
place title propagation can be tightened.

---

### WR-05: `LoadStatusBadgeView.apply(status:)` has two contradictory comments about `text=`/`attributedText=` ordering — both branches do the right thing, but the doc rationale is incoherent

**File:** `validationLedger/UI/Components/LoadStatusBadgeView.swift:296-313`

**Issue:** The strikethrough branch says:

```
// IMPORTANT: do NOT assign `label.text = nil` after setting
// `attributedText`. UILabel's `text` setter (even to nil) clears
// the previously-set `attributedText`, ...
```

— implying `text=` ALWAYS clobbers `attributedText`. The fall-through branch
says:

```
// Order matters: clear `attributedText` BEFORE assigning `text`
// — otherwise the prior attributedText survives a `text =` set
// in some iOS versions ...
```

— implying `attributedText` SURVIVES `text=` in some versions. These two
claims contradict each other; one of them is wrong, and the wrong one will
mis-guide the next edit. The code's defense-in-depth is fine (each branch
manages both properties cleanly), but the next person to touch this will
follow the wrong half of the doc.

**Fix:** Reconcile the comments. The correct iOS behavior (verified across
iOS 13+ via UILabel docs and OpenRadar discussions): setting `.text`
implicitly converts the string to a default-attributed NSAttributedString
and OVERWRITES `.attributedText` — so the strikethrough branch's caution
is correct, and the fall-through branch's "in some iOS versions" hedge is
the incorrect doc. Update to one consistent statement:

```swift
// UILabel's `text` setter always overwrites a previously-set `attributedText`
// (the string is converted to a default-attributed run). To get a CLEAN
// switch back from strikethrough to plain text, we set `attributedText = nil`
// AND `text = labelText` in that order — relying on either side alone leaves
// a subtle attribute leak under VoiceOver's prosody scanning.
```

---

### WR-06: `LoadListViewController.bindViewModel` never renders the VM's initial `.loading` state — first paint between `viewDidLoad` and `viewWillAppear` shows empty chrome

**File:** `validationLedger/Features/Loads/LoadListViewController.swift:366-378`
**Also:** `validationLedger/Features/Loads/LoadListViewModel.swift:103-105`

**Issue:** `LoadListViewModel.state = .loading` is the initial value in the
property declaration. Swift `didSet` does NOT fire for the initial
assignment, so `onStateChange` is never invoked with `.loading` from init.
`bindViewModel` sets the callback closure but does not pump the current
state through it. The skeleton overlay is hidden by default (its lazy
initializer sets `stack.isHidden = true`). So during the window
`[viewDidLoad finishes ... viewWillAppear fires the fetch Task ... Task
hops to MainActor and re-assigns state = .loading]`, the user sees a bare
empty `UICollectionView` with no skeleton and no content. On a slow device
or under main-actor contention this window is perceptible as a flash of
empty content.

**Fix:** After `bindViewModel`, prime the initial state once:

```swift
private func bindViewModel() {
    viewModel.onStateChange = { [weak self] state in
        MainActor.assumeIsolated { self?.render(state: state) }
    }
    // Pump the current state so the first paint shows the skeleton overlay,
    // not a bare collection view.
    render(state: viewModel.state)
}
```

This also makes the VC robust to future VMs that synchronously transition
state during construction (e.g. a cache-backed `.loaded(items:)` initial
state) — the VC will already be rendering the latest state by the time
`viewWillAppear` runs.

## Info

### IN-01: ~4,800-line `MockLoadFixtureRegistry.swift` duplicates JSON between the App target and `validationLedgerTests/.../Fixtures/`; drift is mitigated only by a comment

**File:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift:30-47`

**Issue:** The file-header rationale (lines 30-47) acknowledges that the
inline JSON literals are "AUTHORITATIVE COPY" of the test fixtures and that
a hand-edit to one MUST be paired with a hand-edit to the other. There is
no CI check that enforces this — a developer who edits
`validationLedgerTests/Networking/Fixtures/loads-list-broker.json` will get
correct test results AND a stale DEBUG demo flow. The file's own header
admits the trade-off ("the cost: the JSON content is duplicated") and
defers a fix to a Phase 8-or-later todo. Recommend adding a small drift
test now (Phase 8 owns the registry) that loads both representations and
asserts byte equality:

```swift
@Test("MockLoadFixtureRegistry inline JSON matches test fixtures (drift gate)")
func inlineJSONMatchesFixtures() throws {
    let cases = [("loads-list-broker", "broker"), ...]
    for (file, key) in cases {
        let fixture = try FixtureLoader.loadFixture(file)
        let inline = MockLoadFixtureRegistry.listPayloads[key]
        #expect(fixture == inline, "drift between fixture \(file) and inline listPayloads[\(key)]")
    }
}
```

(Needs widening `listPayloads` to `internal` for testability.)

---

### IN-02: `SkeletonLoadRowCell` overlay rows are hard-coded to 88pt — does not grow with Dynamic Type, so the silhouette becomes shorter than real rows at large sizes

**File:** `validationLedger/Features/Loads/LoadListViewController.swift:174-182`

**Issue:** The skeleton overlay's row heights are pinned with
`skel.heightAnchor.constraint(equalToConstant: 88).isActive = true`. Real
`LoadRowCell` rows grow with Dynamic Type (per the Pitfall 8 + 
`adjustsFontForContentSizeCategory = true` discipline on every label). At
XXL accessibility sizes the real rows are noticeably taller than the
silhouette, breaking the "row content arriving" perceptual hook the
skeleton-with-shimmer pattern is built around. The accompanying snapshot
test `test_skeletonSilhouetteMatchesLoadRowCellAtDefaultDynamicType` is
locked to "default Dynamic Type" specifically because larger sizes drift.

**Fix:** Use `UIFontMetrics.default.scaledValue(for: 88)` (or pick a base
row height from a static `LoadRowCell.estimatedHeight(forContentSize:)`
helper) so the silhouette grows proportionally:

```swift
let scaledHeight = UIFontMetrics.default.scaledValue(for: 88)
skel.heightAnchor.constraint(equalToConstant: scaledHeight).isActive = true
```

This is also testable — add a snapshot test at `.accessibilityXXL` once
the helper is in place.

---

### IN-03: `setEmptyStateAccessibilityIdentifier()` walks the subview tree using `String(describing: type(of:))` — fragile across iOS versions

**File:** `validationLedger/Features/Loads/LoadListViewController.swift:478-490`

**Issue:** The empty-state identifier walk keys on:

```swift
if String(describing: type(of: subview)).contains("ContentUnavailable")
```

This depends on UIKit's internal class name `UIContentUnavailableView`
remaining stable across iOS versions. If Apple renames the host (e.g. to
`_UIContentUnavailableHostingView` in iOS 19, as has happened with similar
classes in the past), the empty-state identifier silently disappears and
the corresponding XCUITest probe (`loads-list.empty-state`) silently
returns "no element exists." The Plan A1 spike VERDICT B chose this path
for the error state precisely because the walk was fragile — recommend
applying the same VERDICT B to the empty state for consistency, or at
minimum add a snapshot test that asserts the identifier resolved (so the
walk failure is loud, not silent).

**Fix:** Either (a) replace `UIContentUnavailableConfiguration.empty()`
with a hand-rolled empty-state UIStackView mirroring the error state
construction (clean, explicit identifier), or (b) add a defensive assert:

```swift
private func setEmptyStateAccessibilityIdentifier() {
    let hosts = view.recursiveSubviews.filter {
        String(describing: type(of: $0)).contains("ContentUnavailable")
    }
    assert(!hosts.isEmpty, "loads-list.empty-state walk failed — UIKit internal class renamed?")
    hosts.first?.accessibilityIdentifier = "loads-list.empty-state"
}
```

---

### IN-04: `LoadStatusBadgeView` and `VerificationBadgeView` snapshot tests rely on `firstLabelInTree()` recursive walks instead of direct `internal` exposure

**File:** `validationLedgerTests/Loads/Snapshot/LoadStatusBadgeViewSnapshotTests.swift:135-157`

**Issue:** `LoadStatusBadgeView.label` is `private`, so the snapshot test
adds a test-bundle UIView extension that walks the subview tree to find
the first UILabel. The walk works today because there's only ever one
UILabel. But the file-header for `LoadRowCell` follows a different pattern
— it makes `verificationBadge` and `statusBadge` `internal let` "so
LoadRowCellSnapshotTests can read their `accessibilityIdentifier`." Doing
the same for `LoadStatusBadgeView.label` (`internal let label = ...`)
would replace 22 lines of `firstLabelInTree()` walk with one direct
property access, AND would survive any future layout change that adds a
second UILabel for, e.g., a status sub-caption.

**Fix:** Promote `LoadStatusBadgeView.label` to `internal`, drop the
`firstLabelInTree()` extension, and access `view.label.text` directly in
the test.

---

_Reviewed: 2026-05-19_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
