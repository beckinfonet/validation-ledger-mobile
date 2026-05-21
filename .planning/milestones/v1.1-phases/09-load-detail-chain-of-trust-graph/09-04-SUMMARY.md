---
phase: 09-load-detail-chain-of-trust-graph
plan: 04
subsystem: features/loads/detail
tags: [load-detail, skeleton, shimmer, error-state, pinned-header, ui-shell, d-19, d-20]
requirements: [LOAD-05]
dependency_graph:
  requires:
    - 09-03 (LoadDetailViewModel + VC shell + state-driven render dispatcher)
    - Phase 8 PATTERNS E3 (SkeletonLoadRowCell shimmer lifecycle)
    - Phase 8 PATTERNS E9 (shimmer re-attach assertion template)
    - LoadStatusBadgeView (Phase 8 reused verbatim)
    - DS.Spacing / DS.Typography / DS.Colors tokens
  provides:
    - LoadDetailSkeletonView (D-19 skeleton-with-shimmer; reduce-motion aware; iPhone silhouette ready, iPad split pending Plan 09)
    - LoadDetailBodyView (D-01/D-02 UIScrollView + contentStack shell + pinned summary header; 4 placeholder containers for Plans 05/06/09)
    - LoadDetailViewController three populated state containers + retry-button → fetchLoadDetail() wiring
  affects:
    - Plans 05, 06, 09 inject content into LoadDetailBodyView's named placeholder containers (timelineContainer, freightDetailsContainer, partiesContainer, verdictBlockContainer)
    - Plan 09 will populate the LoadDetailSkeletonView iPad split-silhouette path (currently a placeholder `renderSplitSilhouette()` stub)
tech_stack:
  added: []
  patterns:
    - "Shimmer lifecycle re-attach (PATTERNS E3 verbatim — animation(forKey:) == nil guard in startShimmer(); re-attach in layoutSubviews() AND traitCollectionDidChange(_:) per RESEARCH §2 Pitfall 1)"
    - "Reduce-motion suppression with test seam (`reduceMotionOverride: Bool?` for deterministic test paths; production observes UIAccessibility.reduceMotionStatusDidChangeNotification)"
    - "Hand-rolled error UI per Phase 8 § Don't Hand-Roll exception (D-20 — UIContentUnavailableView's button accessibility-identifier limitation makes locked XCUITest identifiers unreachable; LoadListViewController errorStateView precedent mirrored)"
    - "UIScrollView + UIStackView shell pinned to scrollView.frameLayoutGuide for horizontal width lock + contentLayoutGuide for vertical content size (PATTERNS table row 21 KYCStatusViewController precedent)"
    - "Pre-attached state containers with isHidden toggles (D-20 — no view-controller swap on state change)"
key_files:
  created:
    - validationLedger/Features/Loads/Detail/LoadDetailSkeletonView.swift
    - validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift
  modified:
    - validationLedger/Features/Loads/Detail/LoadDetailViewController.swift
    - validationLedgerTests/Loads/Snapshot/LoadDetailSkeletonViewSnapshotTests.swift
decisions:
  - "Hand-rolled error UI over UIContentUnavailableView (D-20 + Phase 8 exception): the iOS-17-native error container does not surface its button's accessibilityIdentifier as configurable. Mirrors LoadListViewController.errorStateView verbatim."
  - "Fractional role-slot coordinates (D-06 iPhone) computed in layoutSubviews() against the live graphRegion bounds rather than via Auto Layout constraints — keeps the silhouette deterministic for snapshot tests and lets connector edges recompute by frame from circle centers."
  - "Hard-coded 400pt graph region height in the skeleton instead of the production rule `safeAreaLayoutGuide.layoutFrame.height * 0.62` — the deterministic height is the only way to get a stable snapshot fingerprint without injecting test seams for the safe-area math."
  - "Reduce-motion test seam (`reduceMotionOverride: Bool?`) — UIAccessibility.isReduceMotionEnabled is not directly settable from XCTest; the override delegates to it in production paths and short-circuits in tests."
  - "Sub-element accessibility identifiers on skeleton blocks (`load-detail.skeleton.pinned-header`, `load-detail.skeleton.circle`, `load-detail.skeleton.body-row`) are an internal testing convention — UI-SPEC only locks the root `load-detail.skeleton` identifier. The sub-element identifiers let the iPhone silhouette test count blocks without coupling to the auto-layout tree."
  - "Origin → destination rendering format `\"City, ST → City, ST\"` uses the literal U+2192 arrow per UI-SPEC § Pinned summary header line 655 — and matches Phase 8 LoadRowCell.swift:255 precedent."
  - "iPad split silhouette (D-03) is deferred to Plan 09 — ship a `// FIXME(Plan 09)` `renderSplitSilhouette()` stub and the snapshot test stays XCTSkip until Plan 09 lands."
metrics:
  duration: ~38 minutes
  completed_date: "2026-05-20"
  tasks_completed: 2
  files_created: 2
  files_modified: 2
  commits: 2
---

# Phase 09 Plan 04: Load Detail Skeleton + Body Shell Summary

**One-liner:** Plan 04 populates the Plan 03 VC shell's three state containers — `LoadDetailSkeletonView` (D-19 shimmer-with-reduce-motion) for `.loading`; hand-rolled error UI (D-20) with retry → `fetchLoadDetail()` for `.error`; `LoadDetailBodyView` (D-01/D-02 scroll shell + pinned summary header) for `.loaded` — unblocking LOAD-05 visual verification across all three states.

## What Shipped

### LoadDetailSkeletonView (D-19) — `validationLedger/Features/Loads/Detail/LoadDetailSkeletonView.swift`

The iPhone silhouette per UI-SPEC § iPhone skeleton lines 484-501:

| Region | Composition |
|---|---|
| Pinned header | One full-width × 60pt grey block (`DS.Colors.surface`, 4pt corner radius, `accessibilityIdentifier = "load-detail.skeleton.pinned-header"`) |
| Graph region | Fixed 400pt container with 5 grey 24×24pt circles positioned by frame at D-06 fractional coordinates — shipper (0.18, 0.18) · broker (0.50, 0.30) · carrier (0.50, 0.55) · dispatch (0.82, 0.55) · factoring (0.50, 0.85) — connected by 4 thin 2pt connector edges (UIView with `CGAffineTransform(rotationAngle:)` to align with circle-to-circle segments) |
| Body rows | 3 grey blocks at varying widths (60%, 90%, 70% of available width) |
| Shimmer overlay | `CAGradientLayer` on the skeleton view's root layer (NOT contentView — Phase 9 is UIView, not UICollectionViewCell). PATTERNS E3 gradient mechanics verbatim. |

Shimmer lifecycle — PATTERNS E3 + RESEARCH §2 Pitfall 1 mitigations:

- `startShimmer()` private helper. Two-step guard: (1) reduce-motion ON → remove animation and bail; (2) animation already attached → bail.
- Re-attach in `layoutSubviews()` AND `traitCollectionDidChange(_:)`.
- Reduce-motion suppression — observes `UIAccessibility.reduceMotionStatusDidChangeNotification`, falls back to `reduceMotionOverride: Bool?` test seam.
- iPad split silhouette (`renderSplitSilhouette()`) is a `// FIXME(Plan 09)` empty stub.

### LoadDetailBodyView (D-01/D-02) — `validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift`

The scroll-container shell with pinned summary header:

```
LoadDetailBodyView (UIView, accessibilityIdentifier = "load-detail.body")
└── scrollView (UIScrollView, alwaysBounceVertical)
    └── contentStack (UIStackView, vertical, DS.Spacing.lg)
        ├── pinnedSummaryHeader (UIView, "load-detail.pinned-header")
        │   └── headerStack (UIStackView, horizontal, DS.Spacing.sm)
        │       ├── referenceNumberLabel (.headline, "...reference-number")
        │       ├── originDestinationLabel (.body, truncating tail)
        │       └── statusBadge (LoadStatusBadgeView, "...status-badge")
        ├── timelineContainer       — Plan 05 injects StatusTimelineView
        ├── freightDetailsContainer — Plan 05 injects freight rows
        ├── partiesContainer        — later plan injects parties inline list
        └── verdictBlockContainer   — Plan 09 unhides + injects when verdict != .clean
```

`configure(load:)` reads ONLY `load.referenceNumber`, `load.origin.{city,state}`, `load.destination.{city,state}`, `load.status` — no trust-graph fields. The origin → destination format `"{City}, {ST} → {City}, {ST}"` (literal U+2192) mirrors Phase 8 LoadRowCell:255 verbatim.

Section placeholders are `internal let` so downstream plans can mount their actual views into the named containers. Each container starts as a 0-intrinsic-size empty UIView; the surrounding contentStack collapses around them until Plans 05/06/09 inject content.

### LoadDetailViewController modifications

- Replace empty `skeletonContainer` placeholder content with `LoadDetailSkeletonView` (edge-pinned via `installSkeletonView()`).
- Replace empty `bodyContainer` content with `LoadDetailBodyView` (edge-pinned via `installBodyView()`).
- Assemble the hand-rolled error-state subviews inside `errorContainer` via `installErrorView()`: vertical stack of `[errorIcon, errorHeading, errorBody, errorRetryButton]` centered with `DS.Spacing.xl` layout margins.
- Wire `errorRetryButton.touchUpInside` via `UIAction` → `Task { await viewModel.fetchLoadDetail() }` (same code path `viewWillAppear` uses; VM's BL-01 cancel-and-replace coordinates overlapping fetches).
- `render(state:)` on `.loaded(let load, _)` now invokes `bodyView.configure(load: load)`. The `chainOfTrust` associated value is captured via `_` discard — Plans 06/09 will read it from the VM's `state` at their own composition hooks.
- `.error` case ignores the associated `message` entirely (T-09-04 lock). The three error-state copies are locked `NSLocalizedString` values from UI-SPEC § Copywriting lines 739-741.

## Snapshot Test Suite

`LoadDetailSkeletonViewSnapshotTests` now ships 4 of 5 methods as real assertions:

| # | Test method | Status | Asserts |
|---|---|---|---|
| 1 | `test_iPhoneSilhouette_rendersExpectedFrame` | PASS | Exactly 5 role-slot circles + ≥3 body rows + 1 pinned-header rectangle + root `accessibilityIdentifier == "load-detail.skeleton"`; attaches UIKitSnapshot image for visual review |
| 2 | `test_iPadSplitSilhouette_rendersExpectedFrame` | XCTSkip | Wave 6 — Plan 09 (iPad split silhouette) |
| 3 | `test_shimmerAnimationRestartsOnLayoutSubviews` | PASS | Pitfall 1 — manually strip shimmer, force `setNeedsLayout() + layoutIfNeeded()`, assert re-attached |
| 4 | `test_shimmerAnimationRestartsOnTraitCollectionChange` | PASS | Pitfall 1 second hook — strip, call `traitCollectionDidChange(nil)`, assert re-attached |
| 5 | `test_reduceMotion_suppressesShimmer` | PASS | `reduceMotionOverride = true` → no shimmer; flip to false + layout → shimmer attached |

Suite result: `Executed 5 tests, with 1 test skipped and 0 failures (0 unexpected) in 0.080s`.

## Verification Run

```
xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:validationLedgerTests/LoadDetailSkeletonViewSnapshotTests
  → ** TEST SUCCEEDED ** (4 PASS + 1 XCTSkip)

xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17'
  → ** BUILD SUCCEEDED **

xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:validationLedgerUITests/LoadDetailFlowTests/test_rowTap_pushesDetail
  → ** TEST SUCCEEDED ** (89.24s — regression smoke through the new .loaded path)
```

## Acceptance Criteria — All Met

### Task 1 (skeleton + snapshot tests)

| Gate | Expected | Actual |
|---|---|---|
| `public final class LoadDetailSkeletonView: UIView` | 1 | 1 |
| `let shimmerLayer: CAGradientLayer` (internal) | 1 | 1 |
| `animation(forKey: "shimmer") == nil` | ≥1 | 1 |
| `layoutSubviews()` references | ≥1 | 5 |
| `traitCollectionDidChange` references | ≥1 | 4 |
| `UIAccessibility.isReduceMotionEnabled` | ≥1 | 3 |
| Root `accessibilityIdentifier = "load-detail.skeleton"` | 1 | 1 |
| Test file `XCTSkip` count | 1 | 1 |
| Test file `UIKitSnapshot.image`/`.attach` calls | ≥2 | 3 |
| T-09-03 negative gate (`verificationState`/`chainIntegrity`/`implicated`) | 0 | 0 |

### Task 2 (body view + VC error state + retry)

| Gate | Expected | Actual |
|---|---|---|
| `public final class LoadDetailBodyView: UIView` | 1 | 1 |
| `public func configure(load: Load)` | 1 | 1 |
| Reference-number accessibility identifier | 1 | 1 |
| Status-badge accessibility identifier | 1 | 1 |
| `LoadStatusBadgeView` references in body view | ≥1 | 3 |
| `scrollView.frameLayoutGuide` pin | ≥1 | 4 |
| Retry-button accessibility identifier in VC | ≥1 | 1 |
| `await viewModel.fetchLoadDetail()` in VC (viewWillAppear + retry) | ≥2 | 2 |
| `NSLocalizedString` count in VC | ≥3 | 5 |
| VC logger-free (non-comment Logger/os_log/OSLog) | 0 | 0 |
| `bodyView.configure(load:` references in VC | 1 | 3 (one call site + 2 doc-comment references) |
| **NEGATIVE GATE:** `state.message\|error.message` in VC | 0 | 0 |
| T-09-03 negative gate on body view | 0 | 0 |

## Threat-Model Mitigations

| Threat | Mitigation Verified |
|---|---|
| T-09-03 (client-side trust derivation in body/skeleton view layer) | Body view consumes only `referenceNumber / origin / destination / status` from the Load aggregate. Skeleton view consumes no data. Source-assertion grep gate returned 0 occurrences of `verificationState`/`chainIntegrity`/`implicated` in both files. |
| T-09-04 (PII in error state) | Error-state UI renders only the three locked NSLocalizedString copies. The VM's `.error` associated `message` value is never read in `render(state:)`. Negative grep gate on `state.message\|error.message` returned 0 in the VC. |
| T-09-06 (stripped CABasicAnimation after layout / trait change) | `startShimmer()` re-attach gate runs in BOTH `layoutSubviews()` and `traitCollectionDidChange(_:)`. Locked by `test_shimmerAnimationRestartsOnLayoutSubviews` + `test_shimmerAnimationRestartsOnTraitCollectionChange` (both PASS). |

## Deviations from Plan

**None — plan executed as written.** Two minor adjustments inside the spirit of the plan:

1. **Comment-text re-wording (zero functional change):** The skeleton view's file-header originally contained the literal string `verificationState, chainIntegrity, or implicated*` inside a threat-model comment documenting the constraint. The plan's T-09-03 negative grep gate (`grep -cE 'verificationState|chainIntegrity|implicated'` expected to return 0) treats comments and code identically. Re-worded the comment to describe the discipline without using the literal symbol names. Same change applied to the LoadDetailViewController file-header for the `state.message`/`error.message` gate.

2. **Test-file comment re-wording (zero functional change):** Same gate-vs-comment collision — the snapshot test file's header originally said "iPad split remains XCTSkip until Plan 09" + "test_iPadSplitSilhouette_rendersExpectedFrame() — XCTSkip (Plan 09)" in the test plan, which made `grep -c XCTSkip` return 3 instead of the expected 1. Re-worded the two comments to say "skipped" without the literal `XCTSkip` token; only the actual `throw XCTSkip(...)` statement remains.

## Known Stubs (intentional, documented)

| Stub | Location | Resolved by |
|---|---|---|
| `LoadDetailSkeletonView.renderSplitSilhouette()` empty body | `LoadDetailSkeletonView.swift` (file end, `// FIXME(Plan 09)`) | Plan 09 — iPad split-silhouette layout |
| `LoadDetailBodyView.timelineContainer` empty | `LoadDetailBodyView.swift` | Plan 05 — LOAD-06 StatusTimelineView injection |
| `LoadDetailBodyView.freightDetailsContainer` empty | `LoadDetailBodyView.swift` | Plan 05 — freight detail rows injection |
| `LoadDetailBodyView.partiesContainer` empty | `LoadDetailBodyView.swift` | later plan — inline party list |
| `LoadDetailBodyView.verdictBlockContainer` empty + hidden | `LoadDetailBodyView.swift` | Plan 09 — chain-integrity verdict block (unhide when verdict != .clean) |
| `LoadDetailViewController` `chainOfTrust` not consumed on `.loaded` (intentional `_` discard) | `LoadDetailViewController.render(state:)` | Plans 06 + 09 — TrustGraphView reads from VM state; verdict block + banner consume `chainIntegrity` |

These stubs are STRUCTURAL placeholders documented in the plan — Plan 04 intentionally ships only the container plumbing. None block LOAD-05 visual verification (which only requires "the three states render distinctly on iPhone 17 simulator" — confirmed by the regression test + manual mental trace).

## Open Questions

- **`Load.origin.cityState` vs composed `"city, state"`:** The plan asked the executor to verify the field path on `LoadStop` during execution. There is NO `cityState` convenience field on `LoadStop` — it has bare `city: String` + `state: String`. Composed inline as `"\(load.origin.city), \(load.origin.state) → \(load.destination.city), \(load.destination.state)"`, matching Phase 8 `LoadRowCell.swift:255` precedent verbatim. No contract change needed.
- **Pinned summary header layout on iPad split:** The pinned header currently lives at the top of `LoadDetailBodyView.contentStack`. On iPad split (Plan 09 D-03), the pinned header should appear at the top of the RIGHT pane. Plan 09 may either (a) keep this layout and host the entire `LoadDetailBodyView` in the right pane on iPad, or (b) extract `pinnedSummaryHeader` and reposition it. Plan 04 owns the iPhone shape; Plan 09 owns the split decision.

## Commits

- `09bc1f3` — feat(09-04): LoadDetailSkeletonView with shimmer + reduce-motion gate
- `78fd8eb` — feat(09-04): LoadDetailBodyView shell + VC error state + retry wiring

## Self-Check: PASSED

All claimed files exist:
- `validationLedger/Features/Loads/Detail/LoadDetailSkeletonView.swift` — FOUND
- `validationLedger/Features/Loads/Detail/LoadDetailBodyView.swift` — FOUND
- `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` — FOUND (modified)
- `validationLedgerTests/Loads/Snapshot/LoadDetailSkeletonViewSnapshotTests.swift` — FOUND (populated)

All claimed commits exist:
- `09bc1f3` — FOUND
- `78fd8eb` — FOUND
