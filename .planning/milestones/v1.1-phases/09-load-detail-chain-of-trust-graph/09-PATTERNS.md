# Phase 9: Load Detail & Chain-of-Trust Graph — Pattern Map

**Mapped:** 2026-05-20
**Files analyzed:** 30 (12 new screen/sheet/value-type files + 1 modified domain type + 1 modified VC + 1 modified composition root + 12 re-authored detail fixtures + 14 new test files)
**Analogs found:** 24 / 30 — 6 files (gesture choreography on UIScrollView, CAShapeLayer edge renderer, accessibility container parent, traitCollection split, sheet-presentation, gesture-test harness) have **no in-repo analog** and are listed under `## Novel Patterns`.

---

## File Classification & Closest Analog

### Production files (new + modified) under `validationLedger/`

| Phase 9 File | Role | Closest Analog | Key Pattern | Excerpt Source (file:lines) |
|---|---|---|---|---|
| `Features/Loads/Detail/LoadDetailViewController.swift` | UIViewController (state-machine, fetch-on-appear) | `Features/Loads/LoadListViewController.swift` | `init(viewModel:)` → `viewDidLoad → layoutContent / wireActions / bindViewModel` → `viewWillAppear → Task { await viewModel.fetchX() }`; `bindViewModel` uses `MainActor.assumeIsolated`; WR-06 priming pump `render(state: viewModel.state)`; subview-toggle via `isHidden` (skeleton overlay, error stack), NEVER VC swap | `LoadListViewController.swift:147-174, 312-359, 391-431, 441-568` |
| `Features/Loads/Detail/LoadDetailViewModel.swift` | @MainActor VM, 3-case state machine `.loading / .loaded / .error` | `Features/Loads/LoadListViewModel.swift` | `@MainActor public final class`; `public enum State: Equatable, Sendable`; `public private(set) var state: State = .loading { didSet { onStateChange?(state) } }`; cancel-and-replace `fetchTask`; `userFacingMessage(for:) -> String` collapses all errors to one localized copy | `LoadListViewModel.swift:73-105, 173-275` |
| `Features/Loads/Detail/TrustGraphView.swift` | Custom UIView container — hosts UIScrollView, CAShapeLayer edges, TrustNodeView children, gesture model, accessibility container | **NO IN-REPO ANALOG** — partial: SkeletonLoadRowCell's `CAShapeLayer + CABasicAnimation` lifecycle (`startShimmer()` guard + re-attach on layoutSubviews) | The `startPulseIfNeeded()` helper Phase 9 invents mirrors `SkeletonLoadRowCell.startShimmer()` line-for-line: `guard layer.animation(forKey: "x") == nil else { return }` + add. `layoutSubviews()` re-attaches identically. Edge `CAShapeLayer.path` recompute on `layoutSubviews` mirrors `shimmerLayer.frame = contentView.bounds` mechanics. | `SkeletonLoadRowCell.swift:166-198` (lifecycle); `09-RESEARCH.md §1` (canonical gesture recipe); `09-RESEARCH.md §2` (halo pulse `CABasicAnimation` block) |
| `Features/Loads/Detail/TrustNodeView.swift` | Custom UIView per-node (chrome + `VerificationBadgeView` + role label + display-name label) | `UI/Components/VerificationBadgeView.swift` + `UI/Components/LoadStatusBadgeView.swift` (composable subview pattern) | Programmatic-only `init(frame:)` → `setUp()`; `required init?(coder:)` traps with `fatalError`; `isAccessibilityElement = true`; `accessibilityTraits = .button` (vs `.staticText` on badge — see D-22); `layoutSubviews` recomputes any geometry that scales with Dynamic Type; per-state DS-token color application via private `apply(state:)` helper; **composes** an existing `VerificationBadgeView` via `addSubview` (no inheritance) | `VerificationBadgeView.swift:81-128, 137-149, 153-222` |
| `Features/Loads/Detail/ChainIntegrityBannerView.swift` | Static rendered UIView banner (yellow caution / red compromised) | `UI/LimitedTrustBannerView.swift` (THE direct file-shape twin) | `public final class … : UIView` with `isUserInteractionEnabled = false`; `accessibilityIdentifier` + localized `accessibilityLabel`; `accessibilityTraits = .staticText`; `intrinsicContentSize` override for fixed minimum height; `setUp()` body builds label + pins to leading/trailing with explicit constants (NOT DS.Spacing) | `LimitedTrustBannerView.swift:35-104` |
| `Features/Loads/Detail/StatusTimelineView.swift` | Custom UIView — 6-pill horizontal stepper + current-state expanded card | `UI/Components/LoadStatusBadgeView.swift` (pill geometry) + `LoadListViewController.errorStateView` (vertical UIStackView card) | Per-pill geometry mirrors `LoadStatusBadgeView`'s `layoutSubviews → layer.cornerRadius = bounds.height / 2`; current-card vertical stack composition mirrors `errorStateView`'s `[icon, heading, body, button]` stack with `isLayoutMarginsRelativeArrangement = true`. **Single combined `accessibilityLabel`** per D-22 (UI-SPEC line 870) collapses 6 pills into one VoiceOver element | `LoadStatusBadgeView.swift:1-60`; `LoadListViewController.swift:265-280` |
| `Features/Loads/Detail/LoadDetailBodyView.swift` | UIScrollView + vertical UIStackView body (timeline + freight rows + parties + verdict block) | `Features/Onboarding/KYC/KYCStatusViewController.swift` (scrollView + contentStack + `scrollView.frameLayoutGuide` pinning) | `private let scrollView: UIScrollView` with `alwaysBounceVertical = true`; `private let contentStack: UIStackView` with `axis = .vertical, spacing = DS.Spacing.lg, alignment = .fill`; pin contentStack leading/trailing to `scrollView.frameLayoutGuide` (NOT `contentLayoutGuide` — frame-guide for horizontal anchoring locks the width) and top/bottom to `scrollView.contentLayoutGuide`; `readableContentGuide` for iPad right pane (per UI-SPEC line 817) | `KYCStatusViewController.swift:35-50, 147-177` |
| `Features/Loads/Detail/LoadDetailSkeletonView.swift` | Custom UIView — silhouette blocks + CAGradientLayer shimmer | `Features/Loads/Cells/SkeletonLoadRowCell.swift` (THE direct shimmer template) | Verbatim re-use: `private static func makeBlock() -> UIView` factory for grey silhouette blocks; `internal let shimmerLayer: CAGradientLayer` (NOT `private` — test-reachable per the `Test_shimmerAnimationRestartsOnPrepareForReuse` precedent); `startShimmer()` guarded by `shimmerLayer.animation(forKey: "shimmer") == nil`; re-attach in BOTH `layoutSubviews()` AND a `prepareForReuse`-analog (Phase 9 has no cell-recycle; the equivalent is `traitCollectionDidChange(_:)` per RESEARCH §2 Pitfall 1) | `SkeletonLoadRowCell.swift:38-100, 167-198` |
| `Features/Loads/Detail/VerificationBasisSheetViewController.swift` | UIViewController content for `UISheetPresentationController` with `[.medium, .large]` detents | **NO IN-REPO ANALOG** for `UISheetPresentationController` — partial: `Features/Onboarding/KYC/KYCStatusViewController.swift` for the VC shape + DS-token layout | `init(viewModel:)` programmatic UIKit shape; presenter-side configures `sheet.detents = [.medium(), .large()]; sheet.prefersGrabberVisible = true; sheet.largestUndimmedDetentIdentifier = .medium` (per RESEARCH §5). Content stack composition mirrors `KYCStatusViewController`'s sectioned vertical UIStackView. Each row composes `VerificationBadgeView` for the trust-state slot (D-09 KYC + device-binding + USDOT + prior-relationships) | `KYCStatusViewController.swift:124-178` (shape); `09-RESEARCH.md §5` (sheet configuration code block) |
| `Features/Loads/Detail/HandoffDetailSheetViewController.swift` | UIViewController content for `UISheetPresentationController` (handoff/tender detail) | Same as `VerificationBasisSheetViewController.swift` above; the sheet infrastructure is shared | Same `init(viewModel:)`, same detent configuration. Content stack is smaller — relationship-state row (reuses `VerificationBadgeView.configure(state:)` on the edge's `relationshipState`) + tender ref row + optional implicated-reason block | (shared with TRUST-03 sheet) |
| `Core/Load/PriorRelationship.swift` | NEW pure-value type — `public struct … : Decodable, Sendable` | `Core/Load/ChainOfTrust.swift` (lines 79-133 for `TrustNode`, which is the structural twin: identifier-bearing value type with the trailing-acronym `loadID` `CodingKey` bridge) | `public struct PriorRelationship: Decodable, Sendable`; trailing-acronym `loadID` requires explicit case in `private enum CodingKeys: String, CodingKey { case loadID = "loadId"; case occurredAt; case counterpartyRole; case counterpartyDisplayName }`; ALL non-acronym fields rely on `.convertFromSnakeCase` from `APIClient.defaultDecoder()` per D-13 / CONTEXT line 112; the file header comment block follows the `ChainOfTrust.swift:32-49` template explaining when trailing-acronym needs the bridge and when `.convertFromSnakeCase` suffices | `ChainOfTrust.swift:32-49, 79-133` |
| `Core/Load/ChainOfTrust.swift` **(modified)** | Domain Decodable value type — Phase 9 mutation (D-12) | (self — the file is its own analog) | **MODIFY** `TrustNode.priorRelationshipCount: Int` (line 117) → `TrustNode.priorRelationships: [PriorRelationship]`; UPDATE `private enum CodingKeys` (lines 122-132) to remove `priorRelationshipCount` and rely on `.convertFromSnakeCase` for `priorRelationships` (no trailing acronym — no explicit case needed per the file's own line 47 doctrine); UPDATE the file-header doc block (line 41-44) reflecting the contract evolution | `ChainOfTrust.swift:117, 122-132, 41-44` |
| `Features/Loads/LoadListViewController.swift` **(modified)** | Phase 8 list VC — Phase 9 wires `collectionView(_:didSelectItemAt:)` to push the new detail VC | (self — the file is its own analog; tap-handler addition is additive) | Phase 9 ADDS `extension LoadListViewController: UICollectionViewDelegate { func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) { … } }` + sets `collectionView.delegate = self` inside `viewDidLoad` or `layoutContent`. The handler dereferences `dataSource.itemIdentifier(for: indexPath)?.item.load.id`, then invokes the new `loadDetailScreenFactory: (String) -> UIViewController` closure threaded from `AppContainer.makeLoadListScreen(role:)` (per CONTEXT D-08 / RESEARCH §"Composition root"), then `navigationController?.pushViewController(detailVC, animated: true)`. The closure-threading pattern mirrors the existing `kycStatusScreenFactory` precedent in `AppContainer` | `LoadListViewController.swift:147-174` (init shape); `AppContainer.swift:200-247` (factory closure threading) |
| `App/AppContainer.swift` **(modified)** | Composition root — adds `makeLoadDetailScreen(loadID:)` factory | (self — same file extended) | ADD a `@MainActor func makeLoadDetailScreen(loadID: String) -> UIViewController` mirroring `makeLoadListScreen(role:)` line-for-line: build `featureLogger = OSLogLoggerImpl(subsystem: LoggingSubsystem.app, category: "feature.loads")` (reuses the `.app` subsystem, NOT a new `.loads` case — same Phase 8 doctrine), construct `LoadDetailViewModel(loadID:apiClient:logger:)`, return `LoadDetailViewController(viewModel:)`. Also EXTEND `makeLoadListScreen(role:)` to thread the new factory closure into `LoadListViewController` (planner discretion: pass it through `LoadListViewController.init(viewModel:navTitle:detailScreenFactory:)` or via a thin `LoadDetailCoordinator`) | `AppContainer.swift:217-247` |

### Test files (Wave 0 + integration) under `validationLedgerTests/` and `validationLedgerUITests/`

| Phase 9 File | Role | Closest Analog | Key Pattern | Excerpt Source (file:lines) |
|---|---|---|---|---|
| `Loads/Snapshot/TrustGraphViewSnapshotTests.swift` | XCTest snapshot suite — 12-fingerprint matrix (3 verdicts × 2 devices × 2 Dynamic Type sizes) | `Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift` + `Loads/Snapshot/SkeletonLoadRowCellSnapshotTests.swift` | `class … : XCTestCase` (NOT Swift Testing — needs `XCTAttachment`); per-fixture configuration helper; `UIKitSnapshot.image(of: view, size:)` + `UIKitSnapshot.attach(image, name:, to: self)`; layer-geometry assertions PAIRED with image attachment (so a token regression that doesn't change pixels still fails — see UI-SPEC §Snapshot Test Posture); **lock `halo.opacity == 1.0` BEFORE rendering** so the snapshot captures the resting frame, not a mid-pulse frame | `VerificationBadgeViewSnapshotTests.swift:37-122`; `SkeletonLoadRowCellSnapshotTests.swift:20-79`; `09-RESEARCH.md §3` (the verbatim recipe block) |
| `Loads/Snapshot/TrustNodeViewSnapshotTests.swift` | XCTest snapshot suite — per-verification-state × per-role matrix (≤ 20 entries, planner trims to 4-6) | `Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift` (per-state matrix template) | One test method per state; locked-color XCTAssertEqual on backgroundColor + accessibilityLabel substring + image attach | `VerificationBadgeViewSnapshotTests.swift:48-122` |
| `Loads/Snapshot/ChainIntegrityBannerViewSnapshotTests.swift` | XCTest snapshot suite — 2 verdicts (caution + compromised; `clean` hides the banner) | `Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift` (per-state matrix) + `validationLedgerUITests/LimitedTrustBannerTests.swift` (banner-specific a11y assertions) | Two test methods (caution / compromised); each asserts background color + `accessibilityLabel.contains(reason-copy-fragment)` + image attach. The `clean` case has no snapshot — `isHidden == true` is asserted by a unit test that constructs the banner with a `.clean` verdict | `VerificationBadgeViewSnapshotTests.swift:48-122` |
| `Loads/Snapshot/StatusTimelineViewSnapshotTests.swift` | XCTest snapshot suite — 6 lifecycle states (one per primary-lifecycle current status) | `Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift` | Same per-state matrix shape; one test per `LoadStatus` primary case; assert `accessibilityLabel` contains the single-combined-string format from UI-SPEC line 870 (e.g. "Posted, Tendered, Accepted complete. Dispatched current. In transit, Delivered upcoming.") | `VerificationBadgeViewSnapshotTests.swift:48-122` |
| `Loads/Snapshot/LoadDetailSkeletonViewSnapshotTests.swift` | XCTest snapshot suite — 2 layouts (iPhone full-silhouette + iPad split-silhouette) + shimmer re-attach assertion | `Loads/Snapshot/SkeletonLoadRowCellSnapshotTests.swift` (THE direct twin) | Verbatim: rendering test attaches image; **second test** `test_shimmerAnimationRestartsOnLayoutSubviews` mirrors the existing `test_shimmerAnimationRestartsOnPrepareForReuse` — manually `shimmerLayer.removeAnimation(forKey: "shimmer")`, force layout, assert `shimmerLayer.animation(forKey: "shimmer")` is non-nil. The Phase 9 lifecycle hook is `layoutSubviews()` (NOT `prepareForReuse()` — Phase 9 has no cell-recycle); `traitCollectionDidChange(_:)` re-attach is also tested | `SkeletonLoadRowCellSnapshotTests.swift:24-112` |
| `Loads/Snapshot/VerificationBasisSheetViewControllerSnapshotTests.swift` | XCTest snapshot suite — 4 scenarios (clean × Carrier; clean × Shipper; caution-implicated × Broker; compromised-implicated × Carrier) | `Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift` (per-state matrix) | One test per scenario; configure the sheet's content view from a synthesized `TrustNode` + `ChainIntegrity` pair; render the sheet's `view` (NOT the floating presentation chrome — that's UIKit-internal) at a representative size (e.g. 393×500 pt iPhone medium-detent); image attach + DS-token color assertion on the implicated block (compromised → DS.Colors.destructive) | `VerificationBadgeViewSnapshotTests.swift:48-122` |
| `Loads/Snapshot/HandoffDetailSheetViewControllerSnapshotTests.swift` | XCTest snapshot suite — 3 scenarios (clean / caution-implicated / compromised-implicated) | Same as the TRUST-03 sheet snapshot suite above | Same shape; smaller surface (3 tests not 4) | `VerificationBadgeViewSnapshotTests.swift:48-122` |
| `Loads/TrustNodeViewGestureTests.swift` | XCTest gesture-arbitration unit tests (single-tap, double-tap, `require(toFail:)`) | **NO IN-REPO ANALOG** — Phase 8's tap surfaces are `UIControl.Event.touchUpInside` on `UIButton`, not `UITapGestureRecognizer.require(toFail:)`. Closest shape: `KYCCapturePreviewLayoutTests` (XCTest that introspects view geometry) | `class … : XCTestCase`; build a `TrustNodeView`; iterate `view.gestureRecognizers` to find the `singleTap` (`numberOfTapsRequired == 1`) and `doubleTap` (`numberOfTapsRequired == 2`); assert `singleTap.failureRequirements.contains(doubleTap)` (or use `value(forKey: "_requireFailureForGestureRecognizers")` reflection); programmatically fire each recognizer via `recognizer.state = .recognized` on a swizzled target, OR construct a `UITapGestureRecognizer` subclass with a public `fire()` hook for testing. Per RESEARCH §1 Acceptance criteria | `09-RESEARCH.md §1 lines 245-253`; closest in-repo XCTest: `KYCCapturePreviewLayoutTests.swift` |
| `Loads/TrustGraphViewGestureTests.swift` | XCTest — scroll-view zoom + recenter math; double-tap-on-empty-canvas reset; `panGestureRecognizer.minimumNumberOfTouches == 2` lock | **NO IN-REPO ANALOG** — Phase 9 establishes this pattern. Closest shape: `LoadListViewModelTests` (state-machine assertions on a constructed instance) | `class … : XCTestCase`; build `TrustGraphView`, force layout, assert `view.scrollView.panGestureRecognizer.minimumNumberOfTouches == 2` (RESEARCH §1 line 247). Programmatic zoom: `view.scrollView.zoomScale = 1.8` → call `view.scrollViewDidZoom(view.scrollView)` → assert edge `CAShapeLayer.lineWidth` rescaled to `2.0 / 1.8` (RESEARCH §2 line 318). Programmatic double-tap: invoke `view.recognizers["double-tap-reset"]` (locked via accessibilityIdentifier on the gesture's view) → assert `view.scrollView.zoomScale == fitAllNodesScale` | `09-RESEARCH.md §1 lines 245-253, §6 lines 696-705` |
| `Loads/TrustGraphViewAccessibilityTests.swift` | XCTest — `accessibilityElements` container ordering + per-node label format + edge label format + Reduce Motion + VoiceOver-disables-pinch | **NO IN-REPO ANALOG** — Phase 4's `LimitedTrustBannerTests` (XCUITest, not XCTest) only asserts banner element existence + `isHittable == false`; container traversal is novel | `class … : XCTestCase`; build `TrustGraphView` with a 5-role chain; assert `view.isAccessibilityElement == false`; assert `view.accessibilityElements?.count == 9` (5 nodes + 4 edges); assert ordering: `nodes[0..<5].role` is `[.shipper, .broker, .carrier, .dispatch, .factoring]` (D-22); assert per-node `accessibilityLabel` starts with role name + comma + display name (the format string locked in UI-SPEC line 841-845); assert per-edge label starts with "Handoff from"; toggle `UIAccessibility.isVoiceOverRunning` (via swizzled stub) → assert `view.scrollView.minimumZoomScale == view.scrollView.maximumZoomScale == 1.0`; toggle `UIAccessibility.isReduceMotionEnabled` → assert no `halo.animation(forKey: "pulse")` is attached | `09-RESEARCH.md §4 lines 437-489`; UI-SPEC lines 832-862 |
| `Loads/LoadDetailViewModelTests.swift` | Swift Testing — 3-case state machine (`.loading → .loaded → .error`) + cancel-and-replace fetch | `Loads/LoadListViewModelTests.swift` (THE direct twin — almost line-for-line analog with one fewer state) | `@Suite("LoadDetailViewModel — Phase 9 3-state machine + cancel-and-replace + zero-PII log", .serialized)`; `StateRecorder` + `RecordingLogger` helpers verbatim; tests: `loadingToLoadedOnFixture()` (drives `MockURLProtocol.registerFixture(for: LoadDetailEndpoint.self, path:method:statusCode:body:)`); `loadingToErrorOnForcedFailure()`; `cancelAndReplaceOnRapidRefetch()` (BL-01 mirror); `Test_fetchLoadsLogsZeroPIIOnSuccessAndFailure` (T-08-08 mirror) | `LoadListViewModelTests.swift:42-130` |
| `Load/PriorRelationshipDecodeTests.swift` | Swift Testing — Decodable contract test on the new value type | `Load/ChainOfTrustDecodeTests.swift` (THE direct twin — fixture-driven decode assertions through `APIClient.defaultDecoder()`) | `@Suite("PriorRelationshipDecodeTests — D-12, D-13")`; `let decoder = APIClient.defaultDecoder()` + `decoder.decode(LoadDetailEndpoint.Response.self, from: data)`; per-fixture tests: clean-baseline (VL-1001 — every node carries 5+ priors); chameleon-carrier (VL-1010 — the flagged carrier node carries 0 priors per D-14); empty array; trailing-acronym `loadId` decodes to `loadID` | `ChainOfTrustDecodeTests.swift:1-140` |
| `Networking/Fixtures/LoadDetailFixtureContractTests.swift` | Swift Testing — every `load-detail-VL-*.json` decodes through `APIClient.defaultDecoder()` AND carries the new `prior_relationships` array shape (NOT the deprecated `prior_relationship_count`) | `Load/ChainOfTrustDecodeTests.swift` (the fixture-corpus enumeration template) | `@Suite` per the existing precedent; iterate the 12 fixture names; for each: decode `LoadDetailEndpoint.Response.self`; assert every `TrustNode` exposes a non-empty (or explicitly empty for chameleon-flagged) `priorRelationships` array — the contract evolution is locked at the wire-format layer too | `ChainOfTrustDecodeTests.swift:22-92` |
| `validationLedgerUITests/LoadDetailFlowTests.swift` | XCUITest — 5-role smoke flow: tap a load row → assert detail screen renders → assert banner accessibility label contains reason on compromised | `validationLedgerUITests/Loads/RoleLoadsTabSmokeTests.swift` (THE direct twin — the Phase 8 5-role smoke flow into the Loads tab) | `final class … : XCTestCase`; `executionTimeAllowance = 30`; `continueAfterFailure = false`; `app.launchArguments = ["-MockOTPRoleForUITest", role]`; reuse `driveFullOTPFlow(app)`; then tap the FIRST `loads-list.row.VL-*` cell; assert `load-detail` accessibility identifier resolves; for VL-1009/VL-1010/VL-1011 assert the banner element `chain-integrity-banner` exists with a label containing the implicated reason; assert the verification-basis sheet `verification-basis-sheet` element appears after tapping a node | `RoleLoadsTabSmokeTests.swift:38-80` |

### Fixture re-authoring (modified) under `validationLedgerTests/Networking/Fixtures/`

| Phase 9 File | Role | Closest Analog | Key Pattern | Excerpt Source |
|---|---|---|---|---|
| `load-detail-VL-1001.json` through `load-detail-VL-1012.json` **(modified)** (12 files) | JSON fixture | (self — re-authored in place) | REMOVE `"prior_relationship_count": <Int>` (line 105, 116, 127, 138, 149 in VL-1001 — one per TrustNode); REPLACE with `"prior_relationships": [...]` (array of objects with snake_case wire keys: `load_id`, `occurred_at`, `counterparty_role`, `counterparty_display_name`). Per D-14, clean carriers carry 5+ priors; chameleon-carrier flagged node carries 0; double-broker intermediary carries 1-2; factoring-fraud factoring node carries patterned priors. | `load-detail-VL-1001.json:95-150` (the existing `nodes` array with the legacy field) |

---

## Novel Patterns (No In-Repo Analog)

These six patterns are first-of-kind in the codebase. The executor will be inventing them; planner should flag each as a build-it-from-scratch task with extra review attention.

| Novel Pattern | What the executor must invent | Sole external reference |
|---|---|---|
| **Pinch+pan+double-tap choreography on a hosted UIScrollView** | The full gesture-arbitration recipe: `scrollView.panGestureRecognizer.minimumNumberOfTouches = 2` (so the outer page scroll keeps single-finger drags), `singleTap.require(toFail: doubleTap)` on every node, `scrollViewDidZoom` resetting all edge `CAShapeLayer.lineWidth = 2.0 / zoomScale`, and the `UIScrollView.zoom(to:animated:)` recenter math for double-tap-on-node. None of these gesture-recognizer primitives are wired in the current codebase. | `09-RESEARCH.md §1` (full canonical recipe block, lines 203-230) + `§6` (fit-all-nodes-tight zoom math, lines 598-687) |
| **CAShapeLayer-as-edge-renderer** | A `CAShapeLayer` per `TrustEdge` whose `path` is a `UIBezierPath` from `fromPartyID`'s node center to `toPartyID`'s node center, recomputed in `layoutSubviews()`. `strokeColor` switches by verdict tier (yellow caution dashed, red compromised dashed, neutral grey clean). The accessibility-companion **invisible 28pt-band UIView** overlaid on each edge for tap-target compliance (44pt diagonal at every angle) is also novel — every existing `CAShapeLayer` in the repo (SkeletonLoadRowCell's `shimmerLayer`) is decorative, never tappable. | `09-RESEARCH.md §2` (CAShapeLayer pulse + line-width recompute, lines 256-333); `§1 Gotchas line 241` (28pt invisible companion view) |
| **`accessibilityElements` on a custom-rendered parent** | `TrustGraphView.isAccessibilityElement = false`; `accessibilityElements: [UIView]` ordered children = 5 (or fewer) node views + 4 edge invisible-companion views; per-child `accessibilityTraits = .button`. Every existing accessibility surface in the repo (LimitedTrustBannerView, VerificationBadgeView, SkeletonLoadRowCell) is a LEAF — they all set `isAccessibilityElement = true` with `.staticText`. There is no container-parent precedent. | `09-RESEARCH.md §4` (full recipe, lines 437-503); UI-SPEC lines 832-862 |
| **`traitCollectionDidChange(_:)` size-class branch (iPhone single column ↔ iPad split)** | `LoadDetailViewController` overrides `traitCollectionDidChange(_:)`. When `previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass`, rebuild the layout: tear down the current `UIStackView` constraints and rebuild with the iPhone vertical stack OR the iPad horizontal split (60% graph / 40% body) per UI-SPEC line 812-815. Animation: ADR 0002 abrupt — no crossfade. Preserve `UIScrollView.zoomScale` across the rebuild (CONTEXT D-03). No in-repo file branches layout on `traitCollection.horizontalSizeClass` — every existing iPad-renders-natively claim (Phase 8 LoadListVC, Phase 4 LimitedTrustBannerContainer) uses pure auto-layout with `readableContentGuide`, not a structural split. | `09-CONTEXT.md D-03`; UI-SPEC lines 807-818; no in-repo prior art |
| **`UISheetPresentationController` with `[.medium, .large]` detents** | `sheet.detents = [.medium(), .large()]; sheet.prefersGrabberVisible = true; sheet.largestUndimmedDetentIdentifier = .medium` so the graph stays visible behind the sheet at `.medium`. The CONTEXT explicitly notes "Phase 9 is the first user of `UISheetPresentationController` in the codebase — the v1.0 shell uses `UINavigationController` push + `present(_:)` of full-screen modals only." | `09-RESEARCH.md §5` (full configuration block, lines 504-575) |
| **Gesture-test harness for `UITapGestureRecognizer`** | Tests assert `singleTap.failureRequirements.contains(doubleTap)` AND fire recognizers programmatically to verify the sheet opens on single-tap-after-double-tap-fail-window but NOT on the leading edge of double-tap. No existing XCTest in the codebase introspects gesture-recognizer state; closest precedents are state-machine assertions in `LoadListViewModelTests` and view-geometry assertions in `KYCCapturePreviewLayoutTests`. | `09-RESEARCH.md §1 Acceptance lines 245-253` |

---

## Excerpts

### E1 — State-machine VC `bindViewModel` + WR-06 priming pump
**Source:** `validationLedger/Features/Loads/LoadListViewController.swift:402-431`

```swift
private func bindViewModel() {
    // The VM is @MainActor; `onStateChange` fires on the same actor as the
    // VC, so the captured closure dispatches directly to render(state:).
    viewModel.onStateChange = { [weak self] state in
        // `MainActor.assumeIsolated` is the explicit hop assertion — the
        // didSet fires from within the @MainActor isolation, so this is a
        // no-op assertion in production AND silences any compiler warning
        // a future Swift-concurrency tightening might introduce.
        MainActor.assumeIsolated {
            self?.render(state: state)
        }
    }
    // WR-06 — pump the VM's CURRENT state through the renderer once.
    // Swift `didSet` does NOT fire for the property's initial assignment
    // (`var state: State = .loading` at VM init time), so without this
    // explicit pump the skeleton overlay would stay hidden between
    // `viewDidLoad` completing and the `viewWillAppear` fetch Task's
    // first MainActor hop re-assigning `state = .loading`.
    render(state: viewModel.state)
}
```
**Used by:** `LoadDetailViewController.bindViewModel()` — identical posture; the WR-06 priming pump is mandatory for the same skeleton-on-first-paint reason.

### E2 — VM state machine + cancel-and-replace fetch
**Source:** `validationLedger/Features/Loads/LoadListViewModel.swift:73-105, 173-195`

```swift
@MainActor
public final class LoadListViewModel {
    public enum State: Equatable, Sendable {
        case loading
        case empty
        case loaded(items: [LoadListItem], nextCursor: String?)
        case error(message: String)
    }

    public private(set) var state: State = .loading {
        didSet { onStateChange?(state) }
    }
    public var onStateChange: ((State) -> Void)?
    private var fetchTask: Task<Void, Never>?

    public func fetchLoads() async {
        // BL-01 — cancel-and-replace. A fresh fetch supersedes any in-flight
        // one. The cancelled task observes `Task.isCancelled` after its
        // network hop returns and bails out BEFORE mutating `state`.
        fetchTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performFetch()
        }
        fetchTask = task
        await task.value
    }
}
```
**Used by:** `LoadDetailViewModel` — Phase 9's `enum State` is 3-case (no `.empty`); the cancel-and-replace mechanism is verbatim. The CancellationError + `Task.isCancelled` checkpoints in `performFetch` (lines 207-256 of the analog) are reused identically.

### E3 — Skeleton + shimmer lifecycle (THE strongest in-repo analog for the halo-pulse + edge-CAShapeLayer mechanics)
**Source:** `validationLedger/Features/Loads/Cells/SkeletonLoadRowCell.swift:60-100, 167-198`

```swift
/// `internal` so SkeletonLoadRowCellSnapshotTests can poll
/// `animation(forKey: "shimmer")` via `@testable import validationLedger`.
let shimmerLayer: CAGradientLayer = {
    let l = CAGradientLayer()
    l.colors = [
        UIColor.clear.cgColor,
        UIColor.white.withAlphaComponent(0.25).cgColor,
        UIColor.clear.cgColor,
    ]
    l.startPoint = CGPoint(x: 0, y: 0.5)
    l.endPoint = CGPoint(x: 1, y: 0.5)
    l.locations = [0, 0.5, 1]
    return l
}()

// MARK: - layoutSubviews — Pitfall 1: re-attach on size-class / rotation
public override func layoutSubviews() {
    super.layoutSubviews()
    shimmerLayer.frame = contentView.bounds
    startShimmer()                   // re-attach if stripped
}

public override func prepareForReuse() {
    super.prepareForReuse()
    startShimmer()                   // re-attach if stripped
}

/// Attach the shimmer keyframe animation IF it isn't already attached.
/// The guard prevents re-adding on every layout pass (which would reset
/// the animation's phase and produce a visible "stutter").
private func startShimmer() {
    guard shimmerLayer.animation(forKey: "shimmer") == nil else { return }
    let anim = CABasicAnimation(keyPath: "locations")
    anim.fromValue = [-1, -0.5, 0]
    anim.toValue = [1, 1.5, 2]
    anim.duration = 1.2
    anim.repeatCount = .infinity
    anim.isRemovedOnCompletion = false
    shimmerLayer.add(anim, forKey: "shimmer")
}
```
**Used by:** `LoadDetailSkeletonView` (verbatim re-use — shimmer same gradient + animation block) AND `TrustGraphView.startPulseIfNeeded()` for compromised-node halos (same guard pattern, different `keyPath = "opacity"`, same `repeatCount = .infinity`, same re-attach lifecycle in `layoutSubviews()` AND `traitCollectionDidChange(_:)`).

### E4 — Banner UIView file shape (the direct twin for `ChainIntegrityBannerView`)
**Source:** `validationLedger/UI/LimitedTrustBannerView.swift:35-104`

```swift
public final class LimitedTrustBannerView: UIView {
    private static let bannerHeight: CGFloat = 36.0

    private let label: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.numberOfLines = 2
        lbl.textAlignment = .center
        lbl.font = UIFont.preferredFont(forTextStyle: .footnote)
        lbl.adjustsFontForContentSizeCategory = true
        lbl.textColor = .label
        return lbl
    }()

    public override init(frame: CGRect) { super.init(frame: frame); setUp() }
    public required init?(coder: NSCoder) { super.init(coder: coder); setUp() }

    private func setUp() {
        isUserInteractionEnabled = false
        backgroundColor = UIColor.systemYellow.withAlphaComponent(0.85)

        accessibilityIdentifier = "limited-trust-banner"
        accessibilityLabel = NSLocalizedString(
            "limited_trust_banner.accessibility_label",
            value: "Limited trust mode", comment: "..."
        )
        accessibilityTraits = .staticText
        isAccessibilityElement = true

        label.text = NSLocalizedString("...", value: "...", comment: "...")

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.bannerHeight)
    }
}
```
**Used by:** `ChainIntegrityBannerView` — verbatim file shape; per-verdict color tier swaps in `setUp()` based on a `verdict: ChainIntegrity.Verdict` init parameter. `accessibilityIdentifier = "chain-integrity-banner"`; `accessibilityLabel` contains the verdict-specific reason copy. NOT `isUserInteractionEnabled = false` (D-15 banner is informational only; never tappable).

### E5 — Composable badge subview file shape (the direct twin for `TrustNodeView`)
**Source:** `validationLedger/UI/Components/VerificationBadgeView.swift:81-128, 92-97`

```swift
public override init(frame: CGRect) {
    super.init(frame: frame)
    setUp()
}

public required init?(coder: NSCoder) {
    fatalError("VerificationBadgeView is constructed programmatically only")
}

public override func layoutSubviews() {
    super.layoutSubviews()
    // Pitfall 8: recompute the pill cornerRadius on every layout pass so
    // Dynamic Type growth keeps the shape (full pill, never a slab).
    layer.cornerRadius = bounds.height / 2
}

private func setUp() {
    layer.masksToBounds = true
    isAccessibilityElement = true
    accessibilityTraits = .staticText

    let stack = UIStackView(arrangedSubviews: [symbolView, label])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = DS.Spacing.xs
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.isUserInteractionEnabled = false  // badge slot non-interactive

    addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.xs),
        stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.xs),
        stack.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.xs),
        stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Spacing.xs),
        symbolView.widthAnchor.constraint(equalTo: symbolView.heightAnchor),
    ])
}
```
**Used by:** `TrustNodeView` — composes (via `addSubview`) a `VerificationBadgeView` instance plus a role `UILabel` plus a display-name `UILabel`, all wrapped in a chrome `UIView`. Per D-22, `TrustNodeView` differs from the badge in TWO ways: `accessibilityTraits = .button` (not `.staticText`) AND attaches the `singleTap` + `doubleTap` gesture recognizers.

### E6 — Trailing-acronym CodingKeys discipline (THE template for `PriorRelationship.swift`)
**Source:** `validationLedger/Core/Load/ChainOfTrust.swift:32-49, 118-132`

```swift
// === Wire-format / CodingKeys ===
// Trailing-acronym fields require an explicit CodingKey bridge under
// `.convertFromSnakeCase` (which converts wire-key `party_id` → `partyId`,
// NOT `partyID`). The KYCStatusEndpoint precedent (private enum CodingKeys
// listing only the acronym cases) is followed here. All OTHER fields rely on
// the synthesized decoder + `.convertFromSnakeCase` and do NOT need explicit
// CodingKeys cases ...

/// Acronym bridge — see KYCStatusEndpoint.Response.Artifact for rationale.
/// `partyID` is the only trailing-acronym field; the others map cleanly
/// under `.convertFromSnakeCase`.
private enum CodingKeys: String, CodingKey {
    case partyID = "partyId"
    case role
    case displayName
    case verificationState
    case kycCompletedAt
    case deviceBindingStatus
    case usdotNumber
    case usdotAuthorityStatus
    case priorRelationshipCount        // ← Phase 9 D-12 REMOVES this case
}
```
**Used by:** `PriorRelationship.swift` (new file) — its `CodingKeys` enum carries ONLY `case loadID = "loadId"`; `occurredAt`, `counterpartyRole`, `counterpartyDisplayName` all map cleanly under `.convertFromSnakeCase` and require no explicit case. The Phase 9 modification of `ChainOfTrust.swift` REMOVES the `priorRelationshipCount` case and adds NO explicit case for the new `priorRelationships` field (no trailing acronym; `.convertFromSnakeCase` handles `prior_relationships` → `priorRelationships` cleanly).

### E7 — UIKitSnapshot hand-rolled snapshot recipe (the locked Phase 9 posture)
**Source:** `validationLedgerTests/Support/UIKitSnapshot.swift:53-86`

```swift
static func image(of view: UIView, size: CGSize) -> UIImage {
    view.bounds = CGRect(origin: .zero, size: size)
    view.layoutIfNeeded()
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        view.layer.render(in: ctx.cgContext)
    }
}

static func attach(
    _ image: UIImage,
    name: String,
    to testCase: XCTestCase,
    lifetime: XCTAttachment.Lifetime = .keepAlways
) {
    let attachment = XCTAttachment(image: image)
    attachment.name = name
    attachment.lifetime = lifetime
    testCase.add(attachment)
}
```
**Used by:** Every Phase 9 `*SnapshotTests.swift` file (7 of them). Zero new SwiftPM dependency — `swift-snapshot-testing` is explicitly REJECTED per `09-RESEARCH.md §3` "Options matrix — why hand-rolled wins."

### E8 — Snapshot test file structure (the per-state matrix template)
**Source:** `validationLedgerTests/Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift:37-122`

```swift
import XCTest
@testable import validationLedger

class VerificationBadgeViewSnapshotTests: XCTestCase {
    private static let pillSize = CGSize(width: 140, height: 28)

    func test_verifiedBadgeRendersVerifiedVisuals() {
        let view = VerificationBadgeView()
        view.configure(state: .verified)

        // Locked color ramp — UI-SPEC §Color verification table.
        XCTAssertEqual(view.backgroundColor, DS.Colors.primary,
                       "Verified badge background must be DS.Colors.primary (systemBlue).")

        let a11y = view.accessibilityLabel?.lowercased() ?? ""
        XCTAssertTrue(a11y.contains("verified"),
                      "Verified badge a11y label must contain 'verified'. Got: \(a11y)")

        let image = UIKitSnapshot.image(of: view, size: Self.pillSize)
        UIKitSnapshot.attach(image, name: "VerificationBadge-verified", to: self)
    }
    // ... 5 more per-state methods, identical shape
}
```
**Used by:** All 7 Phase 9 snapshot suites (`TrustGraphView`, `TrustNodeView`, `ChainIntegrityBannerView`, `StatusTimelineView`, `LoadDetailSkeletonView`, `VerificationBasisSheetViewController`, `HandoffDetailSheetViewController`). Per Phase 9 RESEARCH §3, every compromised-verdict snapshot test additionally asserts `halo.opacity == 1.0` BEFORE rendering (resting frame, not mid-pulse).

### E9 — Shimmer-re-attach assertion (the locked Pitfall 1 test pattern)
**Source:** `validationLedgerTests/Loads/Snapshot/SkeletonLoadRowCellSnapshotTests.swift:83-102`

```swift
func test_shimmerAnimationRestartsOnPrepareForReuse() {
    let cell = SkeletonLoadRowCell()
    cell.bounds = CGRect(origin: .zero, size: Self.rowSize)
    cell.layoutIfNeeded()

    // After init + layoutSubviews, the shimmer animation MUST be attached.
    XCTAssertNotNil(cell.shimmerLayer.animation(forKey: "shimmer"),
                    "shimmer must be attached after init + layoutIfNeeded")

    // Manually strip the animation — simulates an internal UIKit lifecycle
    // event that drops the animation (rotation, size-class change).
    cell.shimmerLayer.removeAnimation(forKey: "shimmer")
    XCTAssertNil(cell.shimmerLayer.animation(forKey: "shimmer"),
                 "precondition: animation must be cleared after removeAnimation")

    // prepareForReuse re-attaches.
    cell.prepareForReuse()
    XCTAssertNotNil(cell.shimmerLayer.animation(forKey: "shimmer"),
                    "Pitfall 1: prepareForReuse must re-attach the shimmer animation")
}
```
**Used by:** `LoadDetailSkeletonViewSnapshotTests.test_shimmerAnimationRestartsOnLayoutSubviews()` (verbatim shape, swap `prepareForReuse` → `layoutSubviews`). Also `TrustGraphViewSnapshotTests.test_pulseAnimationRestartsOnLayoutSubviews()` (swap `"shimmer"` → `"pulse"`, swap `shimmerLayer` → `haloLayers.first`).

### E10 — Fixture-decode test shape (the template for `PriorRelationshipDecodeTests` + `LoadDetailFixtureContractTests`)
**Source:** `validationLedgerTests/Load/ChainOfTrustDecodeTests.swift:22-46`

```swift
@Test("VL-1009 decodes a double-brokered chain with flagged intermediary node + flagged edge + compromised verdict (D-13a)")
func vl1009DoubleBrokered() throws {
    let decoder = APIClient.defaultDecoder()
    let data = try FixtureLoader.loadFixture("load-detail-VL-1009")
    let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

    let chain = response.chainOfTrust
    #expect(chain.integrity.verdict == .compromised, "D-13a: VL-1009 MUST have integrity.verdict == .compromised")
    #expect(
        chain.nodes.contains { $0.verificationState == .flagged },
        "D-13a: VL-1009 MUST have at least one flagged TrustNode (the intermediary broker)"
    )
    #expect(
        chain.edges.contains { $0.relationshipState == .flagged },
        "D-13a: VL-1009 MUST have at least one flagged TrustEdge (the broker→carrier re-tender)"
    )
}
```
**Used by:** `PriorRelationshipDecodeTests` — per fixture, assert `chain.nodes.allSatisfy { !$0.priorRelationships.isEmpty } || /* curated exceptions */`. `LoadDetailFixtureContractTests` enumerates all 12 fixtures and asserts the contract evolution wire-shape (no `prior_relationship_count` key remaining anywhere).

### E11 — XCUITest 5-role smoke flow (the template for `LoadDetailFlowTests`)
**Source:** `validationLedgerUITests/Loads/RoleLoadsTabSmokeTests.swift:38-80`

```swift
final class RoleLoadsTabSmokeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        executionTimeAllowance = 30
        continueAfterFailure = false
    }

    private func launch(role: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MockOTPRoleForUITest", role]
        app.launch()
        return app
    }

    private func driveFullOTPFlow(_ app: XCUIApplication) {
        let phoneField = app.textFields["phone-entry-field"]
        XCTAssertTrue(phoneField.waitForExistence(timeout: 10), "...")
        phoneField.tap(); phoneField.typeText("5551234567")
        // ... submit-enabled wait, OTP entry, verify
    }
}
```
**Used by:** `LoadDetailFlowTests` — verbatim setUp + driveFullOTPFlow; then tap a `loads-list.row.VL-1009` cell; assert `app.otherElements["load-detail"].waitForExistence(timeout: 5)`; assert `app.otherElements["chain-integrity-banner"].label.contains("compromised")` (per UI-SPEC §Copywriting banner template); tap a node element; assert `app.otherElements["verification-basis-sheet"].waitForExistence(timeout: 3)`.

### E12 — Composition-root factory closure (the template for `makeLoadDetailScreen(loadID:)`)
**Source:** `validationLedger/App/AppContainer.swift:217-247`

```swift
@MainActor
func makeLoadListScreen(role: Role) -> UIViewController {
    let featureLogger = OSLogLoggerImpl(
        subsystem: LoggingSubsystem.app,
        category: "feature.loads"
    )
    let viewModel = LoadListViewModel(
        role: role,
        apiClient: apiClient,
        logger: featureLogger
    )
    let navTitle: String = (role == .factoring) ? "Invoices" : "Loads"
    return LoadListViewController(viewModel: viewModel, navTitle: navTitle)
}
```
**Used by:** `AppContainer.makeLoadDetailScreen(loadID: String) -> UIViewController` — identical shape: `OSLogLoggerImpl(subsystem: .app, category: "feature.loads")` (REUSED — no new subsystem case per Phase 8 precedent), construct `LoadDetailViewModel(loadID:apiClient:logger:)`, return `LoadDetailViewController(viewModel:)`. The closure is then threaded into `LoadListViewController.init(...)` so the row-tap handler can invoke it without depending on the container directly.

### E13 — Coordinator strong-retain pattern
**Source:** `validationLedger/App/AppCoordinator.swift:26-44`

```swift
/// strong reference to the AuthCoordinator that owns the
/// UINavigationController installed as window.rootViewController for AppPhase.auth.
/// Without this retention the AuthCoordinator deallocates immediately after `makeRoot`
/// returns — the nav stays alive (UIKit retains it via window.rootViewController) but
/// the coordinator's `onAuthenticated` closure + `pushOTP` plumbing would be orphaned.
private var authCoordinator: AuthCoordinator?

/// strong reference to the KYCCoordinator ...
/// This was a real Phase-3 bug fixed for AuthCoordinator; do not reintroduce it.
private var kycCoordinator: KYCCoordinator?
```
**Used by:** If Phase 9 introduces `LoadDetailCoordinator` (per CONTEXT § Claude's Discretion line 111), the parent (likely `LoadListViewController` itself if push-from-list, or a new `LoadCoordinator` owned by the tab bar controller) MUST hold it in a `private var loadDetailCoordinator: LoadDetailCoordinator?` instance property. Without this retention the coordinator deallocates immediately after `push` returns. The CONTEXT explicitly notes "v1.0 precedent is coordinators (KYCCoordinator, AuthCoordinator)."

---

## Shared Patterns (apply to every relevant Phase 9 file)

### Programmatic UIKit + initializer DI (ARCH-04)
**Source:** every Phase 5/8 VC + UIView in the repo
**Apply to:** Every new VC and UIView under `Features/Loads/Detail/`
- `public override init(frame: CGRect) { super.init(frame: frame); setUp() }`
- `required init?(coder: NSCoder) { fatalError("constructed programmatically only") }`
- VC: `init(viewModel: SomeVM)` — store deps, call `super.init(nibName: nil, bundle: nil)`

### DS-token discipline
**Source:** `validationLedger/UI/DesignSystem/` (Spacing/Typography/Colors)
**Apply to:** Every spacing, font, color in Phase 9. Phase 9 adds ONE additive token: `DS.Colors.caution = .systemYellow` per RESEARCH §8 line 936. The yellow vs red verdict tier consumes `DS.Colors.caution` and `DS.Colors.destructive` respectively.

### Dynamic Type discipline
**Source:** `VerificationBadgeView.swift:73`, `LimitedTrustBannerView.swift:47`
**Apply to:** Every `UILabel` in Phase 9 sets `adjustsFontForContentSizeCategory = true`. Every SF Symbol uses `UIImage.SymbolConfiguration(pointSize: ...)` so symbols scale with Dynamic Type. The `layer.cornerRadius = bounds.height / 2` recompute in `layoutSubviews()` applies to every pill-shaped surface (status-stepper pills, the verification-badge slot inside `TrustNodeView`).

### Accessibility identifier discipline
**Source:** `LoadListViewController.swift:178-280` (the locked Phase 8 identifier namespace `loads-list.*`)
**Apply to:** Phase 9 introduces a new identifier namespace `load-detail.*`: `load-detail` (root), `load-detail.skeleton`, `load-detail.error-state`, `load-detail.error-state.retry`, `load-detail.trust-graph`, `load-detail.trust-graph.node.<partyID>`, `load-detail.trust-graph.edge.<edgeID>`, `chain-integrity-banner` (mirrors the `limited-trust-banner` precedent — top-level, not under `load-detail.*`), `load-detail.timeline`, `load-detail.body`, `verification-basis-sheet`, `handoff-detail-sheet`. The XCUITest `LoadDetailFlowTests` is the consumer; locked identifiers are PUBLIC API.

### Zero-PII discipline (T-08-08 / T-08-05)
**Source:** `LoadListViewModel.swift:225-235`
**Apply to:** Every Phase 9 logger call uses `fields: [:]` — never an error description (would render JSON byte slice with party names). The state machine's `.error(message:)` carries ONLY the localized `loads.detail.error.generic` copy — server-supplied text NEVER reaches the screen.

### 44pt touch target
**Source:** `LoadListViewController.swift:261` (the `errorRetryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)` lock)
**Apply to:** Every tappable surface — node containers (Phase 9 nodes are ≥ 44pt by chrome geometry); edge invisible-companion views (28pt band × diagonal ≥ 44pt per RESEARCH §1 Gotcha line 241); sheet rows (use `UICollectionViewListCell` defaults — already 44pt); "Try again" button (mirror the locked pattern from `errorRetryButton`).

### `.serialized` for fixture-touching test suites
**Source:** `LoadListViewModelTests.swift:42` (`@Suite("...", .serialized)`)
**Apply to:** Every Phase 9 Swift Testing suite that touches `MockURLProtocol._handlers` / `_failureHandlers`. Per the `ios-test-suite-pitfalls` project memory, parallel execution against the global registry produces ~58 false-negative 404s. Snapshot tests (XCTest) are not affected.

---

## No Analog Found

| File | Role | Reason | Fallback Reference |
|---|---|---|---|
| `Features/Loads/Detail/TrustGraphView.swift` | UIScrollView-hosted custom canvas + gesture model + CAShapeLayer edges + accessibility container | Combines THREE novel patterns at once | `09-RESEARCH.md §1, §2, §4, §6` (each section is the canonical recipe for one slice) |
| `Features/Loads/Detail/VerificationBasisSheetViewController.swift` | UISheetPresentationController content VC | First user of UISheetPresentationController in the codebase | `09-RESEARCH.md §5` |
| `Features/Loads/Detail/HandoffDetailSheetViewController.swift` | Same as above | Same | `09-RESEARCH.md §5` |
| `Loads/TrustNodeViewGestureTests.swift` | Gesture-recognizer introspection unit tests | No in-repo test introspects `UITapGestureRecognizer.require(toFail:)` chains | `09-RESEARCH.md §1 lines 245-253` |
| `Loads/TrustGraphViewGestureTests.swift` | UIScrollView zoom + recenter math tests | Same — no in-repo gesture-test prior art | `09-RESEARCH.md §6 lines 696-705` |
| `Loads/TrustGraphViewAccessibilityTests.swift` | `accessibilityElements` parent-container tests | No in-repo accessibility container test — every existing surface is a leaf | `09-RESEARCH.md §4 lines 490-503` |

---

## Metadata

**Analog search scope:**
- `validationLedger/Features/Loads/` — Phase 8 list + cells + badges (the strongest pool)
- `validationLedger/Features/Onboarding/KYC/` — Phase 5 scrollView + UIRefreshControl + state-machine VC + coordinator
- `validationLedger/Features/Onboarding/Auth/` — coordinator retain-pattern precedent
- `validationLedger/UI/` — LimitedTrustBannerView (banner shape twin) + DesignSystem tokens
- `validationLedger/UI/Components/` — VerificationBadgeView + LoadStatusBadgeView (composable subview shape)
- `validationLedger/Core/Load/` — ChainOfTrust + LoadStatus + VerificationState (Phase 7 contract + the trailing-acronym `CodingKeys` template)
- `validationLedger/Core/Networking/` — APIClient (`.convertFromSnakeCase` strategy) + Endpoints/LoadDetailEndpoint
- `validationLedger/App/` — AppContainer (composition root) + AppCoordinator (retain-pattern)
- `validationLedgerTests/Loads/` — Snapshot/* + LoadListViewModelTests
- `validationLedgerTests/Load/` — ChainOfTrustDecodeTests (the Decodable-test template)
- `validationLedgerTests/Support/` — UIKitSnapshot.swift (the locked snapshot helper)
- `validationLedgerUITests/` — Loads/RoleLoadsTabSmokeTests (the XCUITest 5-role flow template) + LimitedTrustBannerTests

**Files scanned:** ~30 Swift sources + 12 detail fixtures + 4 snapshot test files + 1 XCUITest file
**Pattern extraction date:** 2026-05-20

---

## PATTERN MAPPING COMPLETE
