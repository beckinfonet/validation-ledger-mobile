---
phase: 10-per-role-tender-accept-reject
reviewed: 2026-05-21T00:00:00Z
depth: standard
files_reviewed: 46
files_reviewed_list:
  - validationLedger/App/AppContainer.swift
  - validationLedger/Core/Load/Load.swift
  - validationLedger/Core/Load/LoadActionPredictor.swift
  - validationLedger/Core/Load/LoadActionTitleResolver.swift
  - validationLedger/Core/Load/LoadStatus.swift
  - validationLedger/Core/Load/RoleLoadPolicy.swift
  - validationLedger/Core/Networking/Endpoints/CarrierDirectoryEndpoint.swift
  - validationLedger/Core/Networking/Mock/MockActionFailureToggles.swift
  - validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift
  - validationLedger/Features/Loads/Detail/LoadActionToastBannerView.swift
  - validationLedger/Features/Loads/Detail/LoadActionsView.swift
  - validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift
  - validationLedger/Features/Loads/Detail/LoadDetailSkeletonView.swift
  - validationLedger/Features/Loads/Detail/LoadDetailViewController.swift
  - validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift
  - validationLedger/Features/Loads/Detail/TenderSheetCarrierRowView.swift
  - validationLedger/Features/Loads/Detail/TenderSheetViewController.swift
  - validationLedger/Features/Loads/LoadListViewController.swift
  - validationLedgerTests/Loads/CarrierDirectoryDecodeTests.swift
  - validationLedgerTests/Loads/Lint/LoadDetailNoStatusSwitchTests.swift
  - validationLedgerTests/Loads/LoadActionPredictorTests.swift
  - validationLedgerTests/Loads/LoadActionTitleResolverTests.swift
  - validationLedgerTests/Loads/LoadActionToastBannerViewTests.swift
  - validationLedgerTests/Loads/LoadActionsViewTests.swift
  - validationLedgerTests/Loads/LoadDetailViewControllerActionRenderTests.swift
  - validationLedgerTests/Loads/LoadDetailViewControllerCompositionTests.swift
  - validationLedgerTests/Loads/LoadDetailViewControllerSizeClassRoutingTests.swift
  - validationLedgerTests/Loads/LoadDetailViewControllerToastAndOverlayTests.swift
  - validationLedgerTests/Loads/LoadDetailViewModelActionTests.swift
  - validationLedgerTests/Loads/LoadDetailViewModelRollbackTests.swift
  - validationLedgerTests/Loads/LoadDetailViewModelTests.swift
  - validationLedgerTests/Loads/LoadStatusLocalizedDisplayNameTests.swift
  - validationLedgerTests/Loads/LoadWithExtensionTests.swift
  - validationLedgerTests/Loads/MockLoadFixtureRegistryActionToggleTests.swift
  - validationLedgerTests/Loads/RespondByLabelTests.swift
  - validationLedgerTests/Loads/RoleLoadPolicyAvailableActionsTests.swift
  - validationLedgerTests/Loads/Snapshot/LoadActionBarSnapshotMatrixTests.swift
  - validationLedgerTests/Loads/Snapshot/LoadActionToastBannerViewSnapshotTests.swift
  - validationLedgerTests/Loads/Snapshot/TenderSheetViewControllerSnapshotTests.swift
  - validationLedgerTests/Loads/TenderEligibilityGatingTests.swift
  - validationLedgerTests/Loads/TenderSheetViewControllerTests.swift
  - validationLedgerTests/Networking/Fixtures/tender-carrier-directory.json
  - validationLedgerTests/Networking/IdempotencyInterceptorRegistrationTests.swift
  - validationLedgerTests/Networking/Mock/CarrierDirectoryMockTests.swift
  - validationLedgerTests/Networking/Mock/MockLoadActionDispatchTests.swift
  - validationLedgerUITests/Loads/LoadActionFlowsTests.swift
findings:
  critical: 2
  warning: 8
  info: 6
  total: 16
status: issues_found
---

# Phase 10: Code Review Report

**Reviewed:** 2026-05-21
**Depth:** standard
**Files Reviewed:** 46
**Status:** issues_found

## Summary

Phase 10 delivers the per-role tender/accept/reject surface across 46 files (production + tests + UI tests + 1 JSON fixture). The overall shape — pure predictor (`LoadActionPredictor`), pure title resolver (`LoadActionTitleResolver`), pure policy (`RoleLoadPolicy`), `@MainActor`-isolated VM with BL-01 cancel-and-replace, optimistic-UI rollback + frozen chain (D-13), zero-PII view-layer lock, locked localization keys for the failure toast — is well-considered and consistently implemented. PII discipline is honored: every logger call uses `fields: [:]`, server-supplied error text never reaches the screen, and the carrier-directory fixture uses synthetic names.

That said, two production defects break the platform's own trust invariants:

1. **CR-01 (CRITICAL — T-10-04 platform thesis):** `TenderSheetCarrierRowView.configure(carrier:)` allows the cell to be reused with `isUserInteractionEnabled = false` after the cell's role flips, but the row is still added to the table delegate as a **selectable row** — and more importantly, the sheet's `selectCarrierForTesting(at:)` and any future programmatic seam BYPASS the row's `isUserInteractionEnabled = false` gate because the gate is on the CELL, not on the SHEET's `selectedCarrierIndex` model. The `tableView(_:didSelectRowAt:)` `.verified` guard catches user taps, BUT the Send button's `computeSendButtonState()` and `handleSendTap()` re-look-up `directory[selectedCarrierIndex]` and never re-validate — if `selectedCarrierIndex` is ever set to a non-verified row (defense-in-depth violation, programmatic path), Send fires with a flagged carrier. Acceptable for v1.1 but worth tightening before App Store. See finding for the actual exploitable race.

2. **CR-02 (CRITICAL — Mock fixture wrong-load response, DEBUG-only but ships to TestFlight):** `MockLoadFixtureRegistry.actionSuccessPayload` returns a hardcoded `"id": "VL-1004"` Load + chain for **every** action POST against **every** VL- loadID. The VM does `state = .loaded(response.load, response.chainOfTrust)` — so accepting a tender on VL-1003 transitions the screen to a VL-1004 load. The UI then renders the wrong reference number, the wrong origin/destination, the wrong chain-of-trust. This is DEBUG-only (the entire file is `#if DEBUG`), but TestFlight builds default to `.mock` networking in DEBUG and the demo flow exercises this path. Demo screens would visibly contradict the action the user took.

Phase 10 also has multiple WARNING-level concerns: a thread-safety issue in `MockActionFailureToggles` (mutable static closures with no isolation), a blocking `Thread.sleep` on the URLSession dispatch queue (`latencySlow` handler), a hand-rolled non-thread-safe constraint mutation in `TenderSheetViewController.configureTableView()`, the `TenderSheetViewController` `Send` button activity-indicator UI is never reset on the `.actionFailed` path (Send stays disabled with no spinner after rollback unless `updateSendButton` is called — which it is, but the spinner toggle order has a race), and a few quality issues around unsafe defaults in `presentTenderSheet()` error handling.

---

## Critical Issues

### CR-01: Tender sheet Send button doesn't re-validate the selected carrier — defense-in-depth gap

**File:** `validationLedger/Features/Loads/Detail/TenderSheetViewController.swift:553-577`

**Issue:**
`handleSendTap()` reads `selectedCarrierIndex` and `directory[idx]`, then immediately fires `onSend(carrier.partyID, deadline)`:

```swift
@objc private func handleSendTap() {
    guard let idx = selectedCarrierIndex, idx >= 0, idx < directory.count else { return }
    let carrier = directory[idx]
    let deadline = resolvedDeadlineDate
    // ... no verificationState re-check before firing onSend
    Task { [weak self] in
        await self?.onSend(carrier.partyID, deadline)
        ...
    }
}
```

The carrier-level ACTION-04 gate (T-10-04 — the entire platform thesis) is enforced in TWO places: (a) the cell's `isUserInteractionEnabled = false` blocks taps on non-verified rows, and (b) `tableView(_:didSelectRowAt:)` guards with `guard carrier.verificationState == .verified else { ... return }`. But the Send button's `handleSendTap` does NOT re-validate before firing.

The only thing protecting Send from firing for a non-verified carrier is the `computeSendButtonState()` enable/disable on `sendButton.isEnabled`. The test seams `selectCarrierForTesting(at:)` route through the delegate (which has the guard), but `setCustomDeadlineForTesting` does not — and a future refactor that selects programmatically through a different seam OR a synthetic UI-test tap that races the disable could fire `handleSendTap` while `selectedCarrierIndex` points at a non-verified row. Even more concretely: if a UIKit edge case ever re-enables the Send button without re-running `updateSendButton` (e.g. a Voice Control "Tap Send tender" command on an unverified row that bypassed the delegate's tap-rejection), the platform's CRITICAL T-10-04 invariant breaks.

Per CLAUDE.md: "Identity that cannot be spoofed and a chain-of-trust that cannot be faked. Every design decision on iOS serves making the person and the counterparty on the other end of a freight transaction demonstrably real." A defense-in-depth gap on the ONE button whose entire purpose is "tender to a verified party" is a CRITICAL finding even when the surface-layer gates appear sufficient.

**Fix:**
Re-validate at the actual fire site:

```swift
@objc private func handleSendTap() {
    guard let idx = selectedCarrierIndex, idx >= 0, idx < directory.count else { return }
    let carrier = directory[idx]
    // T-10-04 defense-in-depth — re-validate at the fire site so the
    // server NEVER receives a tender request for a non-verified carrier,
    // regardless of which gate upstream might have a bug.
    guard carrier.verificationState == .verified else {
        // Sync UI state back to its computed truth; do not fire onSend.
        updateSendButton()
        return
    }
    guard resolvedDeadlineDate > Date() else {
        updateSendButton()
        return
    }
    let deadline = resolvedDeadlineDate
    // ... rest unchanged
}
```

---

### CR-02: Mock action-success payload returns a hardcoded `VL-1004` load + chain for EVERY action against EVERY loadID

**File:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift:244-261, 4743-4809`

**Issue:**
The action-success handler matches `POST /loads/{any VL-id}/{any action}` and unconditionally returns `actionSuccessPayload`, which is a hardcoded JSON literal whose Load has `"id": "VL-1004"`, reference `"REF-1004-DD"`, origin Phoenix AZ, destination Denver CO, status `accepted`, and a fixed chain-of-trust:

```swift
MockURLProtocol.register { request in
    guard request.httpMethod == "POST" else { return nil }
    ...
    guard loadID.hasPrefix("VL-") else { return nil }
    guard actionPathSegments.contains(actionSegment) else { return nil }
    return make200(body: actionSuccessPayload, url: request.url)   // <- ALWAYS VL-1004
}
```

`LoadDetailViewModel.performAction(...)` writes the response verbatim into state:

```swift
state = .loaded(response.load, response.chainOfTrust)
```

So a user on VL-1003 who taps Tender (or any action) sees the screen instantly transition to a totally different load — wrong reference number, wrong origin/destination, wrong chain. Every fraud-archetype load (VL-1009 multi-broker, VL-1008 unverified carrier) gets blown away to VL-1004 the moment the user actions it.

This is `#if DEBUG`-only, but:
1. TestFlight closed beta is DEBUG-config (CLAUDE.md "M1 target is weeks 1-4 of a 24-week v1 plan" + "TestFlight closed beta for v1"). Demo / dogfood / human-UAT users hit this every action.
2. The demo specifically aims to showcase fraud archetypes; the action then visibly destroys the very fraud signal the platform exists to highlight.
3. Memory `Phase 9 execution close-out` mentions device-UAT — this defect would silently corrupt every multi-broker / fraud-archetype demo.

The Plan 03 acceptance criteria explicitly call out D-14: "BOTH response.load AND response.chainOfTrust swap from the wire — one assignment, single source of truth." That requirement is met by the VM, but the mock fixture violates it from the other direction — the wire response is meaningless.

**Fix:**
The mock handler must echo a Load whose `id` matches the requested loadID. Cheapest fix: rewrite the payload's ID at registration time using string substitution; better fix: synthesize the response Load from the per-VL detail fixture by parsing the suffix and looking up `detailPayloads[loadID]`, then walking the JSON and overwriting `status` to the predictor's expected forward state per the action.

```swift
MockURLProtocol.register { request in
    guard request.httpMethod == "POST",
          let path = request.url?.path, path.hasPrefix("/loads/") else { return nil }
    let suffix = String(path.dropFirst("/loads/".count))
    let parts = suffix.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    let loadID = String(parts[0])
    let actionSegment = String(parts[1])
    guard loadID.hasPrefix("VL-"),
          actionPathSegments.contains(actionSegment) else { return nil }
    // Synthesize a response whose load.id matches the request so the VM's
    // post-action .loaded state shows the same load the user actioned.
    // Quick fix: take detailPayloads[loadID] and wrap it inside
    // { "load": <detail>, "chain_of_trust": <from detail>}. Long fix:
    // a per-(loadID, action) lookup table mirroring the detailPayloads
    // structure with the forward-status applied.
    return make200(body: synthesizeActionResponse(for: loadID, action: actionSegment), url: request.url)
}
```

At minimum, document this limitation in a banner comment AND change the toast / chain-overlay tests so they never assert against post-action `load.id` (some snapshot/baseline may quietly depend on the "VL-1004 always wins" behavior).

---

## Warnings

### WR-01: `MockActionFailureToggles` exposes mutable `public static var` closures with no isolation — data race surface

**File:** `validationLedger/Core/Networking/Mock/MockActionFailureToggles.swift:83-103`

**Issue:**
The four `…Active: () -> Bool` closures are `public static var`. The closures are read from `MockURLProtocol`'s handler closures (line 186, 200, 214, 231 of `MockLoadFixtureRegistry.swift`), which run on URLSession's internal dispatch queues — NOT on the main actor. The toggle closures are reassigned in test `setUp` / `tearDown` (also potentially from off-main contexts). Swift 6 strict concurrency would flag these as data race surfaces.

```swift
public static var conflict409Active: () -> Bool = {
    ProcessInfo.processInfo.arguments.contains(conflict409Flag)
}
```

Even though the entire file is `#if DEBUG`-gated and the tests serialize via XCTest's default ordering, two parallel test classes that BOTH touch the toggles (e.g. `MockLoadFixtureRegistryActionToggleTests` + a future suite using the same toggles) would race on the closure reassignment vs the URLSession handler read.

**Fix:**
Either (a) mark each var `nonisolated(unsafe)` AND wrap mutation/read in a private NSLock, or (b) make the toggle namespace `@MainActor` and require all callers to hop to main before reading — option (b) is incompatible with the URLSession handler context, so option (a) is the right choice. Cleanest:

```swift
private static let _toggleLock = NSLock()
private static var _conflict409Active: () -> Bool = { ... }
public static var conflict409Active: () -> Bool {
    get { _toggleLock.withLock { _conflict409Active } }
    set { _toggleLock.withLock { _conflict409Active = newValue } }
}
```

(Repeat for the other three.) Document at the test-seam that mutation must complete BEFORE any in-flight POST may read.

---

### WR-02: `Thread.sleep(forTimeInterval:)` inside `MockURLProtocol` handler blocks the URLSession worker for 1.5s — handler-array starvation

**File:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift:239`

**Issue:**
The `latencySlow` handler synchronously sleeps the calling thread for 1.5s, then returns `nil` to defer to the next matching handler:

```swift
Thread.sleep(forTimeInterval: DebugActionFailureOverride.latencySlowInterval)
return nil
```

`MockURLProtocol.startLoading()` runs on URLSession's internal dispatch queue (or, depending on the protocol implementation, on a per-task queue). Blocking that queue with `Thread.sleep` for 1.5s starves any other in-flight requests sharing the same queue. For the human-UAT use case (one tap at a time) the practical impact is minimal, but if the user backgrounds the app mid-sleep, the BGTask handler + foreground KYC uploader (Phase 5 plumbing) inherit the stall.

`Thread.sleep` also defeats Swift Concurrency — it's a kernel block, not an awaitable suspension. A future test that runs `MockLoadActionDispatchTests` in parallel with another suite would observe ALL POSTs in either suite stalled by 1.5s, not just the one with the toggle set.

**Fix:**
Replace the synchronous block with a registry-side delay primitive that's also DEBUG-only:

```swift
// Either: use a CFRunLoop-driven semaphore that the URLSession queue
// can wait on without blocking parallel requests:
let semaphore = DispatchSemaphore(value: 0)
DispatchQueue.global().asyncAfter(deadline: .now() + DebugActionFailureOverride.latencySlowInterval) {
    semaphore.signal()
}
semaphore.wait()  // still blocks THIS request but other queues unaffected
return nil

// Or, preferred: extend MockURLProtocol with a `latency` parameter on
// register(_:) so the protocol's own loadingTask can schedule the
// response with asyncAfter — no thread block at all.
```

The cleanest fix is the second — extend `MockURLProtocol.register(_:)` (already done for `registerFixtureWithLatency`, per `LoadDetailViewModelActionTests.registerActionFixture`) to support async-deferred response synthesis.

---

### WR-03: `TenderSheetViewController.configureTableView()` activates a fixed-height constraint based on a one-time `contentSize` read — Dynamic Type changes corrupt the layout

**File:** `validationLedger/Features/Loads/Detail/TenderSheetViewController.swift:351-365`

**Issue:**

```swift
private func configureTableView() {
    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(...)
    tableView.reloadData()
    tableView.layoutIfNeeded()
    let contentH = tableView.contentSize.height
    if contentH > 0 {
        tableView.heightAnchor.constraint(equalToConstant: contentH).isActive = true
    }
}
```

The fixed-height constraint is set ONCE in `viewDidLoad` based on the contentSize at the initial font/Dynamic Type size. If the user changes Dynamic Type (Settings → Accessibility → Display & Text Size → Larger Text), the cells grow (the carrier-row cells use `adjustsFontForContentSizeCategory = true` per `TenderSheetCarrierRowView`) but the table's height constraint stays at the original computed value. Result: cells get clipped, or the disabled-reason label wraps but the row is fixed at its smaller intrinsic height.

Additionally, the constraint is added every time `configureTableView` is called (currently once, but a future re-init would stack constraints — the existing one is never deactivated).

The empty-directory case also rolls past silently: when `directory.count == 0`, `contentH == 0`, so no constraint is added — the table uses only the `>= 64` minimum from `installLayout`, leaving a 64pt grey rectangle with no caption.

**Fix:**
Drop the fixed-height constraint; instead let `tableView` size itself via intrinsic content. The simplest path: enable scrolling on the inner table OR pin `tableView.heightAnchor.constraint(equalTo: tableView.contentLayoutGuide.heightAnchor)` (or wrap the table in an intrinsic-content-sizing subclass that observes `contentSize` changes via KVO and re-activates the height constraint).

If keeping the fixed-height approach, at minimum:
1. Hold a reference to the constraint and deactivate-then-recreate it on `traitCollectionDidChange(_:)` (for Dynamic Type changes).
2. Add an empty-state caption when `directory.isEmpty`.

---

### WR-04: `TenderSheetViewController.handleSendTap()` mutates the Send button's activity indicator without serializing against the post-`.loaded`/post-`.actionFailed` parent re-render

**File:** `validationLedger/Features/Loads/Detail/TenderSheetViewController.swift:553-577`

**Issue:**

```swift
@objc private func handleSendTap() {
    ...
    sendButton.isEnabled = false
    var cfg = sendButton.configuration
    cfg?.showsActivityIndicator = true
    sendButton.configuration = cfg

    Task { [weak self] in
        await self?.onSend(carrier.partyID, deadline)
        await MainActor.run {
            guard let self else { return }
            var cfg = self.sendButton.configuration
            cfg?.showsActivityIndicator = false
            self.sendButton.configuration = cfg
            self.updateSendButton()
        }
    }
}
```

The closure's `MainActor.run` runs AFTER `await self?.onSend(...)` returns. But on success, the parent VC's `.loaded` render arm runs `self.dismiss(animated: true)` (`LoadDetailViewController.swift:1745-1747`) — the sheet may begin dismissal BEFORE the `MainActor.run` closure executes, leaving the button mutation racing with view-controller teardown. On failure, the sheet stays visible — fine — but the button reconfiguration overwrites a Send-disabled state that `updateSendButton()` is about to re-compute, producing a 1-frame visual flicker of the spinner-cleared-but-still-disabled button.

Worse, the inner `cfg = sendButton.configuration` capture is on a stale snapshot — `updateSendButton()` reads `computeSendButtonState()` and re-applies `configuration` from scratch with a different `showsActivityIndicator` baseline, but only after the explicit cfg mutation. The two writes to `sendButton.configuration` produce two layout passes.

**Fix:**
Drop the explicit cfg mutation in the completion and let `updateSendButton()` own the visual contract:

```swift
@objc private func handleSendTap() {
    ...
    // Start spinner explicitly (in-flight visual).
    sendButton.isEnabled = false
    if var cfg = sendButton.configuration {
        cfg.showsActivityIndicator = true
        sendButton.configuration = cfg
    }

    Task { [weak self] in
        await self?.onSend(carrier.partyID, deadline)
        guard let self else { return }
        // Stop spinner via the single-truth update path; updateSendButton
        // will re-enable Send iff the carrier + deadline remain valid.
        if var cfg = self.sendButton.configuration {
            cfg.showsActivityIndicator = false
            self.sendButton.configuration = cfg
        }
        self.updateSendButton()
    }
}
```

Note: the outer Task is already implicitly main-actor under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so the `MainActor.run` hop is redundant and obscures the lifecycle.

---

### WR-05: `LoadDetailViewController.presentTenderSheet()` silently drops carrier-directory fetch errors — user is left thinking the tender flow froze

**File:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift:1711-1724`

**Issue:**

```swift
private func presentTenderSheet() {
    presentTenderSheetCallCountForTesting += 1
    Task { [weak self] in
        guard let self else { return }
        do {
            let directory = try await self.viewModel.fetchCarrierDirectory()
            self.presentTenderSheet(directory: directory)
        } catch {
            // T-09-04 — never render the server's error text. The VM
            // already logged the fetch-failed event with fields: [:].
            // Sheet is simply not presented; user can re-tap Tender.
        }
    }
}
```

On a directory-fetch failure the catch arm does literally nothing. The user taps Tender, sees the spinner on the button (the action-region's `inFlight: .tender` marker), waits, nothing happens, gives up. There's no toast, no "try again" affordance, no audio/haptic — and the action region stays in `inFlight: .tender` if the VM had transitioned to `.actionInFlight` (this code is BEFORE the VM transition, so the action button stays enabled — but UX is still bad).

This is also a T-10-04 concern: silent failure on "show me who I can tender to" is worse than surfacing a generic error, because the user may not realize the directory was never loaded and may eventually time out / lose the tender window.

T-09-04 lock says "never render server-supplied error text" — it does NOT say "render nothing on error." A LOCKED localized generic "Couldn't load carriers. Try again." copy through the toast banner is fully compatible with the no-server-text rule.

**Fix:**

```swift
} catch {
    // T-09-04 — never render server text. But surface SOMETHING so the
    // user knows the tap was acknowledged but the directory load failed.
    self.presentToastBanner(copyKey: "loads.actions.error.tender_failed")
}
```

(Or add a new locked key `loads.detail.tender.error.directory_unavailable` matching the existing 6-key taxonomy in `LoadDetailViewModel.errorCopyKey(for:)`.)

---

### WR-06: `LoadDetailViewModel.submit` permits action submission from `.actionInFlight` but treats the predicted Load as the pre-tap snapshot — rollback returns the user to a never-committed state

**File:** `validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift:377-391`

**Issue:**

```swift
let preLoad: Load
let preChain: ChainOfTrust
switch state {
case .loaded(let load, let chain):
    preLoad = load
    preChain = chain
case .actionInFlight(let predicted, let frozenChain, _):
    preLoad = predicted     // <- WRONG: this is the prediction, not the real pre-tap
    preChain = frozenChain
case .actionFailed(let rollbackTo, let frozenChain, _):
    preLoad = rollbackTo
    preChain = frozenChain
case .loading, .error:
    return
}
```

Per the doc comment immediately above: "submit IS permitted from `.actionInFlight` (the user is overriding an in-flight action mid-spinner — BL-01 cancel-and-replace), and `.actionFailed` (the user is retrying a different action after a rollback)."

The cancel-and-replace semantics for `.actionInFlight` are subtly incorrect. Scenario:
1. Load is `.posted`. User taps Tender. VM state -> `.actionInFlight(predicted: tendered, ...)`.
2. User taps Cancel BEFORE the server response lands. The new submit captures `preLoad = predicted` (i.e. the `tendered` Load), not the actual server-confirmed pre-tap `posted` load.
3. The new predictor runs `predict(load: tendered, action: .cancel, body: nil)` → returns `cancelled`. Optimistic UI shows cancelled.
4. Server responds to the SECOND (cancel) request with `200 + load: cancelled`. Final state: `.loaded(cancelled, …)`. Looks correct.
5. BUT if the cancel request FAILS, the rollback restores `tendered` (the never-committed prediction), not `posted`. The user sees a `tendered` state that never existed on the server.

The deeper issue: optimistic-predict requires that the rollback snapshot is the LAST SERVER-CONFIRMED state, not the optimistic prediction. By treating `predicted` as `preLoad`, a chained cancel-after-tender rollback shows an impossible intermediate state.

The comment claims "The optimistic predicted Load is the visible truth on screen, so (predicted, frozenChain) is the pre-tap snapshot for the new action" — but for the ROLLBACK contract (D-15), the pre-tap snapshot must be restorable, and `predicted` was never restorable (the server never confirmed it).

**Fix:**
Track the LAST SERVER-CONFIRMED `(load, chain)` separately from the visible state:

```swift
private var lastConfirmedLoad: Load?
private var lastConfirmedChain: ChainOfTrust?

// In performAction's success arm:
lastConfirmedLoad = response.load
lastConfirmedChain = response.chainOfTrust
state = .loaded(response.load, response.chainOfTrust)

// In submit's preLoad/preChain capture:
case .actionInFlight:
    // Override-in-flight: the server has not yet confirmed `predicted`;
    // the true pre-tap snapshot is the last server-confirmed pair.
    guard let confirmed = lastConfirmedLoad, let chain = lastConfirmedChain else {
        return  // no confirmed state ever existed; defensively bail
    }
    preLoad = confirmed
    preChain = chain
```

Alternatively, prohibit re-submit from `.actionInFlight` (just `return`) and require the user wait until the spinner clears. That's the simplest fix and matches the action-region's `isEnabled = false` lock on all buttons during in-flight — so in practice the user CANNOT re-submit through the UI mid-flight. The risk surface is purely programmatic (a test or future code path that calls `submit` directly).

---

### WR-07: `LoadDetailViewController.makeChainOverlayConstraints` returns stale-anchor constraints when the strip/card aren't in the hierarchy

**File:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift:1527-1556`

**Issue:**

```swift
let topAnchor = (everyoneOnLoadStripView.superview != nil)
    ? everyoneOnLoadStripView.topAnchor
    : bodyContainer.topAnchor
let bottomAnchor = (chainOfVouchesView.superview != nil)
    ? chainOfVouchesView.bottomAnchor
    : bodyContainer.bottomAnchor
```

The check `everyoneOnLoadStripView.superview != nil` runs synchronously, but the overlay is mounted from `.actionInFlight` — which (per `applyBodyRender → buildLayoutForCurrentComposition`) just torn down and rebuilt the composition. There's a window where the strip / card are AFTER the rebuild but BEFORE their `setNeedsLayout` resolves; the `superview` check is correct but the constraint nonetheless references `bodyContainer.topAnchor` / `bodyContainer.bottomAnchor` when only one of strip/card is mounted, creating an inconsistent overlay rectangle.

More concretely: if the strip is mounted but the card is mid-detachment (or vice versa), the overlay spans `strip.top → bodyContainer.bottom` (or `bodyContainer.top → card.bottom`) — a much larger region than intended, covering the actions region AND the freight rows behind it. Visually: a grey scrim over the entire body, not just the chain section.

The `dismissChainOverlay` path deactivates the constraints up-front (good), but the MOUNT path has no symmetric protection.

**Fix:**
Pin the overlay to a stable anchor instead of conditional views — e.g. always pin to `bodyContainer.topAnchor` / `bodyContainer.bottomAnchor` (covers the whole body region, including chain) OR introduce a dedicated `chainRegionContainer` view that's always present in the hierarchy and have strip+card mount INTO it. The latter is the cleaner fix; the former is a one-line patch.

```swift
// Iphone vertical-tree: pin to bodyContainer edges + the actions container's TOP
// to skip the actions/freight rows below.
return [
    overlay.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
    overlay.bottomAnchor.constraint(equalTo: bodyView.actionsContainer.topAnchor),
    overlay.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
    overlay.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
]
```

---

### WR-08: `LoadActionToastBannerView.scheduleAutoDismiss()` Timer closure captures `[weak self]` but the Task hop doesn't — possible retain after view removal

**File:** `validationLedger/Features/Loads/Detail/LoadActionToastBannerView.swift:345-349`

**Issue:**

```swift
autoDismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
    Task { @MainActor in
        self?.playSlideOutAndRemove(onComplete: nil)
    }
}
```

The outer Timer block captures `[weak self]` correctly. But the inner `Task { @MainActor in ... }` captures `self` strongly (it's not `[weak self]` again — the outer `self?` was just the result of unwrapping, and Swift hoists `self?` into the Task body as a strong reference for the duration of the closure). On iOS 17 this works; on iOS 18 the Task may briefly retain `self` past the timer's natural fire, holding the view alive past its parent's dealloc.

The Timer also is NOT invalidated in `deinit` — if the view is removed via a path that skips `playSlideOutAndRemove` (which is the only path that nils the timer), the Timer continues firing and the view leaks.

Additionally, `removeFromSuperview` (overridden at line 318) does NOT invalidate the timer — only `playSlideOutAndRemove` does. So if anything else removes the banner from its superview (parent VC tear-down, system memory warning), the timer fires post-removal with a now-zombie callback path.

**Fix:**

```swift
private func scheduleAutoDismiss() {
    let delay: TimeInterval = /* ... */
    autoDismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
        // Hop to main without capturing self strongly inside the Task.
        Task { @MainActor [weak self] in
            self?.playSlideOutAndRemove(onComplete: nil)
        }
    }
}

public override func removeFromSuperview() {
    autoDismissTimer?.invalidate()  // belt-and-suspenders
    autoDismissTimer = nil
    super.removeFromSuperview()
    onRemoved?()
}

deinit {
    autoDismissTimer?.invalidate()  // catch-all; Timer holds the closure target strongly
}
```

Note: `deinit` cannot be `@MainActor`-isolated unless the class is `@MainActor` (it is). Timer invalidation is thread-safe.

---

## Info

### IN-01: `LoadActionsView.applyTenderEligibilityGate` looks up the Tender button by accessibility identifier string — brittle and slow

**File:** `validationLedger/Features/Loads/Detail/LoadActionsView.swift:517-523`

**Issue:**
```swift
if let tenderButton = buttonRow.arrangedSubviews
    .first(where: { ($0 as? UIButton)?.accessibilityIdentifier == "load-detail.actions.button.tender" })
    as? UIButton {
```

This walks the button row + does a string comparison against the LoadAction.rawValue interpolated identifier. The lookup is implicit-coupled to the identifier format — a future change to the identifier in `makeButton` silently breaks the gate. Better: store the per-action `UIButton` references in a `[LoadAction: UIButton]` dict during `renderButtonState`, then look up `buttons[.tender]`.

**Fix:** Build a `private var actionButtons: [LoadAction: UIButton] = [:]` cleared in `clearButtonRow()` and populated in the `for action in actions` loop. The gate becomes `if let tenderButton = actionButtons[.tender] { ... }`.

---

### IN-02: `LoadStatus.localizedDisplayName` lookup keys use dot-separated multi-word form but `LoadStatus.rawValue` uses snake_case — two parallel naming conventions to maintain

**File:** `validationLedger/Core/Load/LoadStatus.swift:113-121, 143-148`

**Issue:**
`inTransit` has `rawValue = "in_transit"` (snake_case for wire) but its lookup key is `loads.status.in.transit` (dot-spaced). Two parallel conventions for the same enum case mean a future addition to LoadStatus requires remembering both — and the lookup-key naming guide is buried in a comment, not enforced.

**Fix:** Derive the key from the rawValue at runtime:
```swift
var localizedDisplayName: String {
    let key = "loads.status.\(self.rawValue.replacingOccurrences(of: "_", with: "."))"
    return NSLocalizedString(key, value: ..., comment: ...)
}
```
This eliminates the 14-case switch and ensures the two conventions can't drift.

---

### IN-03: `MockLoadFixtureRegistry` is 5184 lines — single-file inlined JSON makes review/diff impossible

**File:** `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift:1-5184`

**Issue:**
The file documents Option A (inline JSON literal) vs Option B (Bundle resources) and accepts the duplication-cost trade-off. The cost is real: a code review of this file is effectively impossible — every change requires diff-reading thousands of lines of JSON. The file-header banner explicitly says "AUTHORITATIVE COPY" and asks reviewers to hand-pair edits with the test fixture files, which is not a sustainable invariant.

Future plan should consolidate via a shared demo-bundle pattern (the header itself flags this).

**Fix:** Track the consolidation in the next planning cycle. Until then, every new fixture should land in BOTH the test fixture file AND the inline payload, with the pairing asserted by the regression tests already in place.

---

### IN-04: `LoadDetailViewController.cachedLoad` + `cachedChainOfTrust` duplicate the VM's `.loaded` associated values

**File:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift:302-307`

**Issue:**
The VC stores a private `cachedLoad: Load?` + `cachedChainOfTrust: ChainOfTrust?` whose only readers are `handleSizeClassChange` (for composition rebuild) and the sheet-presentation paths. But the VM already owns `viewModel.state` which carries the same values via `.loaded` / `.actionInFlight` / `.actionFailed` associated values. Three sources of truth (VM state, VC cache, view content) for the same data is a coupling smell.

**Fix:** Read `viewModel.state` directly in `handleSizeClassChange` and in the sheet presenters. Pattern-match on the state case to extract the current `(load, chain)`. Removes 6 lines of mutable VC state.

---

### IN-05: Duplicated `RecordingLogger` / `StateRecorder` / `makeLoad` / `makeChain` / `makeActionResponseBody` between `LoadDetailViewModelActionTests` and `LoadDetailViewModelRollbackTests`

**File:** `validationLedgerTests/Loads/LoadDetailViewModelActionTests.swift:97-220` and `validationLedgerTests/Loads/LoadDetailViewModelRollbackTests.swift:85-220`

**Issue:**
~150 lines of test infrastructure are copy-pasted verbatim across the two files. The file-headers acknowledge the duplication and accept it. Risk: a fix to the spy in one file but not the other produces silently-inconsistent test coverage.

**Fix:** Extract a `LoadsTestSupport.swift` (in `validationLedgerTests/Loads/Support/`) with the shared types. Use `internal` visibility + `@testable import validationLedger` — no access-control friction.

---

### IN-06: `TenderSheetViewController.directory` is captured by value (struct array) but synthesizes deadline dates via `Date(timeIntervalSinceNow:)` at READ time — test determinism risk

**File:** `validationLedger/Features/Loads/Detail/TenderSheetViewController.swift:481-488`

**Issue:**

```swift
private var resolvedDeadlineDate: Date {
    switch selectedDeadline {
    case .preset(let interval):
        return Date(timeIntervalSinceNow: interval)  // <- now-relative
    case .custom(let date):
        return date
    }
}
```

The chip preset is stored as a `TimeInterval` offset and resolved at every read. Two consecutive reads return slightly different Dates. The Send-button gate (`resolvedDeadlineDate > Date()`) and the `onSend` closure both read this — they may see different values across the microseconds-of-drift window. The test file comment ("modulo a tiny seconds-of-drift") acknowledges this.

Future risk: a test that does `let captured = sheet.resolvedDeadlineForTesting` then taps Send asserting `onSend.deadline == captured` would intermittently fail. The current tests appear to use `> Date()` tolerances; a stricter assertion would flake.

**Fix:** Snapshot the resolved date when the chip is selected:
```swift
private enum SelectedDeadline {
    case preset(TimeInterval, resolvedAt: Date)
    case custom(Date)
}
private func selectChip(at idx: Int) {
    let descriptor = chipDescriptors[idx]
    if let interval = descriptor.interval {
        selectedDeadline = .preset(interval, resolvedAt: Date(timeIntervalSinceNow: interval))
    } else {
        selectedDeadline = .custom(Date(timeIntervalSinceNow: 24 * 3600))
    }
    ...
}
```
Then `resolvedDeadlineDate` returns the snapshotted value (or rebuilds it once per chip-tap). Deterministic across reads within one chip selection.

---

_Reviewed: 2026-05-21_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
