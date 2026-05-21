---
phase: 09-load-detail-chain-of-trust-graph
reviewed: 2026-05-20T00:00:00Z
depth: standard
files_reviewed: 34
files_reviewed_list:
  - validationLedger/App/AppContainer.swift
  - validationLedger/Core/Load/ChainOfTrust.swift
  - validationLedger/Core/Load/DeviceBindingStatus.swift
  - validationLedger/Core/Load/PriorRelationship.swift
  - validationLedger/Features/Loads/Detail/ChainIntegrityBannerView.swift
  - validationLedger/Features/Loads/Detail/ChainIntegrityVerdictBlockView.swift
  - validationLedger/Features/Loads/Detail/HandoffDetailSheetViewController.swift
  - validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift
  - validationLedger/Features/Loads/Detail/LoadDetailSkeletonView.swift
  - validationLedger/Features/Loads/Detail/LoadDetailViewController.swift
  - validationLedger/Features/Loads/Detail/LoadDetailViewModel.swift
  - validationLedger/Features/Loads/Detail/StatusTimelineView.swift
  - validationLedger/Features/Loads/Detail/TrustGraphView.swift
  - validationLedger/Features/Loads/Detail/TrustNodeView.swift
  - validationLedger/Features/Loads/Detail/VerificationBasisSheetViewController.swift
  - validationLedger/UI/DesignSystem/Colors.swift
  - validationLedgerTests/Loads/ChainIntegrityBannerViewSnapshotTests.swift
  - validationLedgerTests/Loads/ChainOfTrustFactory.swift
  - validationLedgerTests/Loads/LoadDetailFixtureContractTests.swift
  - validationLedgerTests/Loads/LoadDetailViewModelTests.swift
  - validationLedgerTests/Loads/Snapshot/ChainIntegrityBannerViewSnapshotTests.swift
  - validationLedgerTests/Loads/Snapshot/LoadDetailSkeletonViewSnapshotTests.swift
  - validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests.swift
  - validationLedgerTests/Loads/TrustNodeViewTests.swift
  - validationLedgerTests/Loads/VerificationBasisSheetViewControllerTests.swift
  - validationLedgerTests/Loads/HandoffDetailSheetViewControllerTests.swift
  - validationLedgerTests/Loads/StatusTimelineViewTests.swift
  - validationLedgerTests/Loads/LoadDetailBodyViewTests.swift
  - validationLedgerTests/Loads/TrustGraphViewTests.swift
  - validationLedgerUITests/Loads/LoadDetailFlowTests.swift
  - validationLedgerTests/Loads/MockLoadFixtureRegistry.swift
  - validationLedgerTests/Loads/Snapshot/LoadRowCellSnapshotTests.swift
  - validationLedgerTests/Loads/Snapshot/StatusTimelineViewSnapshotTests.swift
  - validationLedgerTests/Loads/Snapshot/TrustNodeViewSnapshotTests.swift
findings:
  critical: 3
  warning: 5
  info: 3
  total: 11
status: issues_found
---

# Phase 9: Code Review Report

**Reviewed:** 2026-05-20T00:00:00Z
**Depth:** standard
**Files Reviewed:** 34
**Status:** issues_found

## Summary

Phase 9 implements the Load Detail screen with Chain of Trust graph, shimmer skeleton, status timeline, chain-integrity banner, and two bottom-sheet detail screens. The architecture is well-disciplined overall: `@MainActor` isolation is correct, the BL-01 cancel-and-replace pattern is implemented faithfully, D-18 pass-through rendering is respected (no client-derived trust), T-09-04 PII constraints are honored in view-layer logging, and the Pitfall 1 shimmer/pulse re-attach hook appears in both `layoutSubviews` and `traitCollectionDidChange` as required.

Three blockers were identified. Two are behavioral correctness failures with observable consequences in production: `StatusTimelineView`'s cancelled-state pill rendering makes all pills appear "future" (hiding completed stages) and `LoadDetailViewController`'s iPad→iPhone rotation path leaves `bodyView` stranded in the wrong parent container, causing AutoLayout failures after trait-collection flip. The third blocker is a Dynamic Type accessibility violation in `ChainIntegrityBannerView` where the verdict symbol is pinned to a fixed 16×16pt frame, failing the project's "Dynamic Type fully supported" mandate.

Five warnings cover a USDOT string-gap rendering defect, two design-system color token bypass sites, an unnecessary re-fetch on every `viewWillAppear`, and a misleading Dynamic Type snapshot test that provides false test coverage confidence.

Three info items document partially unreviewed files (file too large, files not retrieved in time) and a minor allocator overhead.

## Critical Issues

### CR-01: `StatusTimelineView.applyPillStates` — Cancelled state hides all completed stages

**File:** `validationLedger/Features/Loads/Detail/StatusTimelineView.swift:~applyPillStates`
**Issue:** When the final `LoadStatus` event in the sorted history is `.cancelled`, `applyPillStates` sets `currentIdx = -1`. The pill-styling loop treats `index == currentIdx` as "current" and `index > currentIdx` as "future." With `currentIdx = -1`, every pill (including stages that definitively occurred — posted, accepted, dispatched — before the cancel) is rendered in the "future" style: grey, de-emphasized, no checkmark. A driver or broker reading the screen sees a blank stepper for a load whose full documented history up to cancellation should be visible. This contradicts the inline comment "the stepper highlights `.dispatched` as current for a `[posted, …, dispatched, cancelled]` history" and makes the timeline functionally misleading on cancelled loads.

**Fix:** Cancelled is a terminal event, not the current position in a pipeline. Treat cancellation as an end-state that occurs _after_ all prior stages: mark completed stages as done, style the pill immediately preceding the cancel event as "current" (or introduce an explicit `.cancelled` terminal pill), and display the cancel annotation separately in the expanded card below the stepper. Concretely:

```swift
// In applyPillStates, replace the cancelled branch:
case .cancelled:
    // Find the last non-cancelled event to determine furthest progress.
    let lastActiveIdx = sortedStatuses
        .lastIndex(where: { $0 != .cancelled }) ?? -1
    currentIdx = lastActiveIdx
    // Then run the existing loop: indices ≤ lastActiveIdx → done/current.
    // Render the cancelled annotation only in the expandedCard subtitle.
```

---

### CR-02: `LoadDetailViewController.buildIPhoneLayout` — `bodyView` not re-parented on iPad→iPhone rotation

**File:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift:~buildIPhoneLayout`
**Issue:** `buildIPadSplitLayout()` moves `bodyView` out of `bodyContainer` and into `rightPaneContainer` to construct the split composition. `buildIPhoneLayout()` does NOT move `bodyView` back to `bodyContainer`. After an iPad→iPhone trait-collection flip (`traitCollectionDidChange` → `buildLayoutForCurrentComposition` → `buildIPhoneLayout`), `bodyView` remains a child of `rightPaneContainer`. Any AutoLayout constraint that anchors to `bodyContainer` (added during `buildIPhoneLayout`) references a view that is not in the same subtree as `bodyView`, causing `[LayoutConstraints] Unable to simultaneously satisfy constraints` breakages at runtime. The iPhone layout silently degrades with broken scroll insets and misaligned sections.

**Fix:** At the top of `buildIPhoneLayout()`, unconditionally re-parent `bodyView` to `bodyContainer` before installing iPhone-specific constraints:

```swift
func buildIPhoneLayout() {
    // Re-parent bodyView in case we're coming from an iPad split layout.
    if bodyView.superview !== bodyContainer {
        bodyView.removeFromSuperview()
        bodyContainer.addSubview(bodyView)
    }
    // ... existing iPhone constraint installation ...
}
```

---

### CR-03: `ChainIntegrityBannerView` — Verdict symbol pinned to fixed 16×16pt, Dynamic Type violation

**File:** `validationLedger/Features/Loads/Detail/ChainIntegrityBannerView.swift:~lines 146-147`
**Issue:** The SF Symbol image view that renders the triangle (caution) or octagon (compromised) verdict icon is constrained to a fixed 16×16pt width and height. CLAUDE.md mandates "Dynamic Type fully supported (`adjustsFontForContentSizeCategory = true` on every UILabel)" and the broader constraint extends to icon elements that are paired with Dynamic Type body text. At `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`, body text scales to approximately 2.4× its default size while the symbol remains 16×16pt — the icon becomes illegible relative to the surrounding text. This fails WCAG 1.4.4 (Resize Text) and violates the project's mandatory accessibility baseline.

**Fix:** Remove the fixed dimension constraints and use a `UIImageView` configured with `adjustsImageSizeForAccessibilityContentSizeCategory = true` together with the SF Symbol `UIImage(systemName:withConfiguration:)` using a `UIImage.SymbolConfiguration(textStyle: .body)` scaled configuration:

```swift
let symbolConfig = UIImage.SymbolConfiguration(textStyle: .body)
symbolImageView.image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)
symbolImageView.adjustsImageSizeForAccessibilityContentSizeCategory = true
// Do NOT add fixed width/height constraints — let the image view size itself.
symbolImageView.setContentHuggingPriority(.required, for: .horizontal)
symbolImageView.setContentHuggingPriority(.required, for: .vertical)
```

---

## Warnings

### WR-01: `VerificationBasisSheetViewController.makeUSDOTRow` — Nil USDOT produces a gap in formatted string

**File:** `validationLedger/Features/Loads/Detail/VerificationBasisSheetViewController.swift:~makeUSDOTRow`
**Issue:** The USDOT row label is built as `"\(node.usdotNumber ?? "") · Authority …"`. When `node.usdotNumber` is `nil` and the node's device-binding status is not `.notApplicable` (meaning the USDOT row IS rendered), the label renders as " · Authority …" — a leading bullet separator with a blank USDOT number. The guard that skips USDOT row rendering for Shipper/Factoring roles does not catch the case where a Carrier or Broker node has a `nil` USDOT number due to an incomplete server response. The result is a visible formatting artifact: " · Authority Authorized" with a leading space-bullet.

**Fix:** Fall back to a placeholder string rather than an empty string, or suppress the separator when the USDOT field is absent:

```swift
let usdotDisplay = node.usdotNumber.map { "USDOT \($0)" } ?? "USDOT —"
let rowText = "\(usdotDisplay) · Authority \(authorityStatus)"
```

---

### WR-02: `HandoffDetailSheetViewController` and `VerificationBasisSheetViewController` bypass `DS.Colors.caution`

**File:** `validationLedger/Features/Loads/Detail/HandoffDetailSheetViewController.swift:~makeImplicatedBlock`
**File:** `validationLedger/Features/Loads/Detail/VerificationBasisSheetViewController.swift:~makeImplicatedBlock`
**Issue:** Both sheet VCs construct the implicated-party warning block using `.systemYellow` directly instead of `DS.Colors.caution`. `DS.Colors.caution` was introduced in Phase 9 specifically to consolidate the "caution" color hand across the chain-integrity banner, verdict block, flagged-edge dash, and caution halo so future re-tinting touches one site. These two `makeImplicatedBlock` implementations bypass that consolidation. If `DS.Colors.caution` is ever updated (e.g., adjusted for APCA contrast ratios or a brand refresh), the implicated-block chrome in both sheets will diverge from the rest of the caution surfaces silently.

**Fix:** Replace `.systemYellow` with `DS.Colors.caution` in both `makeImplicatedBlock` implementations:

```swift
// Before:
container.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.15)
// After:
container.backgroundColor = DS.Colors.caution.withAlphaComponent(0.15)
```

---

### WR-03: `LoadDetailViewController.viewWillAppear` re-fetches on every appearance

**File:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift:~viewWillAppear`
**Issue:** `viewWillAppear` calls `fetchLoadDetail()` unconditionally on every appearance. This means every time the user dismisses the `VerificationBasisSheetViewController` or `HandoffDetailSheetViewController` bottom sheet, the full load + chain-of-trust network request fires again. The fetch replaces the already-loaded state with `.loading`, drops the skeleton back in, then re-fetches data the user already has. This is unnecessary network churn and causes a visible flash: the loaded content is hidden, the skeleton re-appears, then the content re-renders.

**Fix:** Guard the fetch so it only fires on first appearance or when explicitly invalidated (e.g., pull-to-refresh):

```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    guard !hasAppearedOnce else { return }
    hasAppearedOnce = true
    fetchLoadDetail()
}

// Add to the class:
private var hasAppearedOnce = false
```

Alternatively, check `viewModel.state` and skip the fetch when already `.loaded`.

---

### WR-04: `TrustGraphViewSnapshotTests.renderedView` — `contentSize` parameter is silently ignored

**File:** `validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests.swift:~renderedView`
**Issue:** The `renderedView(contentSize:)` helper accepts a `UIContentSizeCategory` parameter that is documented as setting up the Dynamic Type environment for the snapshot. Inspection of the helper body shows the `contentSize` argument is captured but never applied to the view's `traitCollection` or to `UIApplication.shared.preferredContentSizeCategory`. As a result, the `DTLarge` and `DTAXXXL` snapshot variants render identically — the default system font size is used for both. The tests claim to cover Dynamic Type scaling but the coverage is illusory: a Dynamic Type bug in `TrustGraphView` will not be caught by this suite.

**Fix:** Apply the content size category to the view using `UITraitCollection.current` overriding or the test host's `preferredContentSizeCategory` override before rendering:

```swift
func renderedView(contentSize: UIContentSizeCategory) -> UIView {
    let traitOverride = UITraitCollection(preferredContentSizeCategory: contentSize)
    let view = TrustGraphView()
    // Apply trait override before layout:
    view.traitOverrideUsingTraitCollection(traitOverride)
    // ... rest of setup ...
}
```

On iOS 17+, `UIView.traitOverrideUsingTraitCollection(_:)` (or `traitOverride` property) is the correct API for injecting trait overrides in test context without mutating the UIApplication singleton.

---

### WR-05: `LoadDetailFlowTests.test_rowTap_pushesDetail` — `executionTimeAllowance` of 30s covers 5 full OTP flows

**File:** `validationLedgerUITests/Loads/LoadDetailFlowTests.swift:~test_rowTap_pushesDetail`
**Issue:** The test iterates all 5 role variants (shipper, broker, carrier, dispatch, factoring) and for each drives a complete OTP authentication flow through the mock server before reaching the Load Detail screen. `executionTimeAllowance = 30` sets a 30-second ceiling for the entire loop. On a physical device in CI (which can be slower than a simulator by 2–4×), each OTP flow through navigation push + network round trip + render can take 4–8 seconds. Five iterations at 8s each = 40s, which exceeds the budget. The test will produce a spurious timeout failure on slow CI device runs rather than reporting an actual assertion failure. This masks real failures with infrastructure noise.

**Fix:** Either increase `executionTimeAllowance` to a value that accommodates 5 device-speed flows (60–90s), or restructure the test to drive a single representative role end-to-end and cover the remaining roles with unit-level coordinator tests:

```swift
// Option A: conservative allowance
override var executionTimeAllowance: TimeInterval { 90 }

// Option B: parameterize and run a single representative role
// (reduces XCUITest surface, faster CI)
```

---

## Info

### IN-01: `MockLoadFixtureRegistry.swift` could not be reviewed — file too large

**File:** `validationLedgerTests/Loads/MockLoadFixtureRegistry.swift`
**Issue:** This file (57,845 tokens) exceeded the Read tool's retrieval limit. Fixture registration correctness for Phase 9 mock routes (`/loads/:id/detail`, `/loads/:id/chain-of-trust`) could not be verified. If mock routes are registered with incorrect response payloads or missing `CodingKeys` acronym bridges, the fixture contract tests and UITests will pass against mismatched data.

**Fix:** Manually review `MockLoadFixtureRegistry.swift` to confirm that the Phase 9 fixtures include valid `partyId`, `edgeId`, `fromPartyId`, `toPartyId`, `loadId` wire keys (not `party_id`, `edge_id` etc.) and that the `integrity` field uses the bare key (not `chain_integrity`). Cross-check against `LoadDetailFixtureContractTests` expected keys.

---

### IN-02: Three snapshot test files in scope were not retrieved

**Files:**
- `validationLedgerTests/Loads/Snapshot/StatusTimelineViewSnapshotTests.swift`
- `validationLedgerTests/Loads/Snapshot/LoadRowCellSnapshotTests.swift`
- `validationLedgerTests/Loads/Snapshot/TrustNodeViewSnapshotTests.swift`

**Issue:** These files were listed in the review scope but were not read during the review session. Their snapshot assertions, content size category application, and accessibility identifier locks were not verified adversarially.

**Fix:** Re-run the code review or manually inspect these three files. Key things to check: (a) whether the `contentSize` parameter application pattern from WR-04 is repeated here; (b) whether `TrustNodeViewSnapshotTests` verifies the 44pt minimum touch target on the node tap surface; (c) whether `LoadRowCellSnapshotTests` covers the Phase 9 verdict badge state.

---

### IN-03: `StatusTimelineView.configureRow1` allocates `RelativeDateTimeFormatter` on every call

**File:** `validationLedger/Features/Loads/Detail/StatusTimelineView.swift:~configureRow1`
**Issue:** `RelativeDateTimeFormatter()` is instantiated inside `configureRow1`, which is called every time the expanded card is configured or reconfigured. `RelativeDateTimeFormatter` is a non-trivial object (locale resolution, calendar setup). Allocating it on every cell configure is wasteful when a single cached instance per `StatusTimelineView` would suffice.

**Fix:** Promote the formatter to a `private let` constant on the view:

```swift
private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
}()
```

---

_Reviewed: 2026-05-20T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
