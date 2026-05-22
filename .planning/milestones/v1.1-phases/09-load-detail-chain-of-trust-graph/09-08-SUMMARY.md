---
phase: 09-load-detail-chain-of-trust-graph
plan: 08
subsystem: features/loads/detail
tags: [trust-04, handoff-detail-sheet, ui-sheet-presentation-controller, d-07, d-08, d-11, marquee]
requires:
  - 09-01  # TrustEdge value type + ChainIntegrity.implicatedEdgeIDs
  - 09-06  # TrustGraphView edge tap-target (EdgeCompanionView) + edgeTapped callback
  - 09-07  # cachedChainOfTrust storage + the UISheetPresentationController recipe (shared per D-08)
provides:
  - HandoffDetailSheetViewController (TRUST-04 sheet content)
  - LoadDetailViewController.presentHandoffDetailSheet wired (replaces the Plan 06 fatalError stub)
  - Second in-repo UISheetPresentationController call site — both Plan 07 + Plan 08 source-level lock on `sheet.largestUndimmedDetentIdentifier = .medium`
affects:
  - validationLedger/Features/Loads/Detail/LoadDetailViewController.swift  (sheet wiring; Pitfall 7 lock now at 2 sites)
  - validationLedger/Features/Loads/Detail/TrustGraphView.swift            (UNCHANGED — edgeTapped callback already plumbed in Plan 06)
  - validationLedger/Features/Loads/Detail/VerificationBasisSheetViewController.swift  (UNCHANGED — Plan 07 sheet stays intact)
tech-stack:
  added: []  # zero new SwiftPM deps; UISheetPresentationController + NSAttributedString are iOS-13+/17 first-party
  patterns:
    - "Second in-repo UISheetPresentationController integration — shared recipe with Plan 07 per D-08 / UI-SPEC line 472 Sheet presentation invariant"
    - "Sheet content VC composed entirely from existing Phase 8 components (VerificationBadgeView reuse on the relationship row) + Apple SF Symbols (no new visual assets)"
    - "Mixed-weight attributed-string row (.body prefix + .headline ref) tracks Dynamic Type because both weights come from preferredFont(forTextStyle:)"
    - "Edge-partition accessibility identifier on the HEADER container view (UI-SPEC line 783 left placement open; descendant placement avoids root-identifier collision)"
    - "D-11 conditional render via pure Set-membership lookup on server-supplied implicatedEdgeIDs (T-09-03 lock — parallel to Plan 07's implicatedNodeIDs lookup)"
key-files:
  created:
    - validationLedger/Features/Loads/Detail/HandoffDetailSheetViewController.swift
  modified:
    - validationLedger/Features/Loads/Detail/LoadDetailViewController.swift
    - validationLedgerTests/Loads/Snapshot/HandoffDetailSheetViewControllerSnapshotTests.swift
    - validationLedgerUITests/Loads/LoadDetailFlowTests.swift
decisions:
  - "Inlined the sheet detents recipe at the new call site rather than extracting a shared `presentAsSheet(_:)` helper (option B from the Plan 07 SUMMARY's wave-4 handoff notes). The plan's per-site Pitfall 7 grep gate (`grep -c 'sheet.largestUndimmedDetentIdentifier = .medium' LoadDetailViewController.swift == 2`) requires the lock at TWO source-level sites; extracting the helper would collapse the count to 1 and silently break the gate. The duplication is therefore load-bearing — the per-site grep is what catches any future drift on either site. The helper extraction remains the cleaner DRY refactor and is left as a future-phase concern."
  - "Edge-partition identifier (`load-detail.handoff-detail-sheet.edge.<edgeID>`) placed on the HEADER stack's accessibilityIdentifier rather than on the root view. UI-SPEC line 783 leaves placement open (`additionally so XCUITest can assert which edge's sheet opened`). Placing it on the root would collide with the sheet's primary identifier (`load-detail.handoff-detail-sheet`) — one element can only carry one identifier. The header container is the cleanest deterministic descendant target."
  - "Tender-reference row uses NSAttributedString (mixed-weight inline) rather than two labels in an HStack. Both fonts come from `DS.Typography.body` and `DS.Typography.headline` (which both wrap `UIFont.preferredFont(forTextStyle:)`), so Dynamic Type scales both portions together. The single-label approach also handles line-wrapping naturally — a long tender ref wraps onto a new line without the prefix label and ref label getting split awkwardly."
  - "VL-1005 chosen for the XCUITest (not VL-1009) — same reasoning Plan 07 documented under its `decisions` for the node-tap test. VL-1009's double-broker archetype puts two broker nodes in the SAME broker role-slot per D-06; the edge BETWEEN those two co-located nodes degenerates to a near-zero-length stroke, and the companion view's tap target collapses with it. VL-1005's two-edge chain has well-separated endpoints — deterministic tap target — while still exercising the full TRUST-04 + D-11 contract on the implicated `edge-VL-1005-broker-carrier` edge."
  - "Snapshot canvas height set to 350 pt (vs the TRUST-03 sheet's 500 pt) — UI-SPEC line 470 calls out the handoff sheet as 'naturally less dense'. The shorter canvas approximates the medium-detent representative rendering more accurately than re-using the TRUST-03 size would."
  - "Doc-comment hygiene mirroring Plan 06 SUMMARY deviation #3 and Plan 07 SUMMARY deviation #3 — the file-header and presentHandoffDetailSheet docblock both DESCRIBE the Pitfall 7 invariant without QUOTING the exact `sheet.largestUndimmedDetentIdentifier = .medium` substring, so the grep gate counts code sites only (2). Same re-phrase precedent applies to the snapshot file's `XCTSkip` doc-comment (the locked-target description avoids the literal trigger token)."
metrics:
  duration: ~25min
  completed_date: 2026-05-20
  files_created: 1
  files_modified: 3
  tests_added: 5  # 4 snapshot + 1 XCUITest method body
---

# Phase 9 Plan 08: TRUST-04 Handoff-Detail Sheet Summary

## One-Liner

Shipped TRUST-04 at full quality per CONTEXT D-07 (the ROADMAP-cited
scope-trim option is EXPLICITLY REJECTED): the modal
`HandoffDetailSheetViewController` opens on a single-tap of an
`EdgeCompanionView` (Plan 06's 28pt-band invisible hit-region), renders
the four locked sections (header → relationship-state badge row →
tender-reference row OR "No formal tender on file." informational line
→ implicated block when `edgeID ∈ implicatedEdgeIDs`), and is presented
via the SAME canonical iOS-17 `UISheetPresentationController` recipe
as Plan 07 — with `sheet.largestUndimmedDetentIdentifier = .medium`
locked at the source level on BOTH presentations.

## HandoffDetailSheetViewController Surface

```swift
public final class HandoffDetailSheetViewController: UIViewController {

    public init(edge: TrustEdge, fromNode: TrustNode, toNode: TrustNode, integrity: ChainIntegrity)
    public required init?(coder: NSCoder)            // fatalError — programmatic only
    public override func viewDidLoad()

    // Internal helpers (composeContent → 4 section builders):
    private func installScrollContainer()
    private func composeContent()
    private func makeHeader(edge: TrustEdge, fromNode: TrustNode, toNode: TrustNode) -> UIView
    private func makeRelationshipStateRow(state: VerificationState) -> UIView
    private func makeTenderReferenceRow(tenderRef: String?) -> UIView
    private func makeImplicatedBlock(integrity: ChainIntegrity) -> UIView
}
```

**Locked invariants:**

- `view.accessibilityIdentifier == "load-detail.handoff-detail-sheet"` —
  the locked sheet locator (UI-SPEC line 782).
- Header container's `accessibilityIdentifier ==
  "load-detail.handoff-detail-sheet.edge.<edgeID>"` — the partition
  locator (UI-SPEC line 783) so XCUITest can assert which edge's sheet
  opened.
- Implicated block's `accessibilityIdentifier ==
  "load-detail.handoff-detail-sheet.implicated-block"` — locked
  conditional locator (UI-SPEC line 784).
- Reuses Phase 8 `VerificationBadgeView` on the relationship-state row
  (no parallel verification-state badge implementation — TRUST-02 ramp
  lock from Phase 8).
- `T-09-03` discipline: every visual flows verbatim from server-supplied
  `TrustEdge` + `TrustNode` + `ChainIntegrity` fields. No `derive*()`
  method exists in this file.
- `T-09-04` discipline: zero `Logger` / `os_log` calls (verified by the
  negative grep gate).
- 9 `NSLocalizedString`-wrapped user-facing strings (header title, four
  per-state relationship-row templates, two tender-reference templates,
  implicated-block title).

## Section Content Rules (UI-SPEC §HandoffDetailSheetViewController)

| Section | Render rule | Source location |
| --- | --- | --- |
| Header | `.headline` "Handoff" title + `.body` "{fromRole.displayName} → {toRole.displayName}" subtitle + `.body` "{fromNode.displayName} → {toNode.displayName}" display-name line. Header container carries the edge-partition `accessibilityIdentifier`. | `makeHeader(edge:fromNode:toNode:)` |
| Relationship-state row | `VerificationBadgeView.configure(state: edge.relationshipState)` + `.body` label "Relationship: {STATE}" — STATE uppercase per Phase 8 ramp (VERIFIED / PENDING / UNVERIFIED / FLAGGED), NSLocalizedString-wrapped per state. | `makeRelationshipStateRow(state:)` |
| Tender-reference row — present | NSAttributedString "Tender reference: " (`.body`) + `tenderRef` (`.headline`) — both weights from `preferredFont(forTextStyle:)` so Dynamic Type scales both portions. | `makeTenderReferenceRow(tenderRef:)` (non-nil branch) |
| Tender-reference row — absent | Single `.body` label "No formal tender on file." — UI-SPEC line 731 informational sentence, no icon, not alarming. | `makeTenderReferenceRow(tenderRef:)` (nil branch) |
| Implicated block | Only when `integrity.implicatedEdgeIDs.contains(edge.edgeID)`; soft 0.15 tint (yellow for caution / red for compromised); icon (triangle / octagon); title "Why this handoff is flagged"; body = verbatim `integrity.reason` (T-09-03 lock). | `makeImplicatedBlock(integrity:)` |

## LoadDetailViewController Plan 06 Fatal-Error Stub Replacement

### `presentHandoffDetailSheet(for:)` body (replaced)

```swift
private func presentHandoffDetailSheet(for edgeID: String) {
    guard let chainOfTrust = cachedChainOfTrust,
          let edge = chainOfTrust.edges.first(where: { $0.edgeID == edgeID }),
          let fromNode = chainOfTrust.nodes.first(where: { $0.partyID == edge.fromPartyID }),
          let toNode = chainOfTrust.nodes.first(where: { $0.partyID == edge.toPartyID }) else {
        return  // defensive — edge or endpoints disappeared between configure and tap
    }
    let sheetVC = HandoffDetailSheetViewController(edge: edge, fromNode: fromNode, toNode: toNode, integrity: chainOfTrust.integrity)
    sheetVC.modalPresentationStyle = .pageSheet
    if let sheet = sheetVC.sheetPresentationController {
        sheet.detents = [.medium(), .large()]
        sheet.selectedDetentIdentifier = .medium
        sheet.prefersGrabberVisible = true
        sheet.largestUndimmedDetentIdentifier = .medium  // D-08 + RESEARCH §5 line 519 CRITICAL
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
    }
    present(sheetVC, animated: true)
}
```

The Plan 06 `fatalError("Plan 08 wires...")` stub is GONE — negative
grep gate `grep -c 'fatalError("Plan 08' LoadDetailViewController.swift`
returns `0`.

### Pitfall 7 lock now at TWO sites

Both Plan 07's `presentVerificationBasisSheet(for:)` and Plan 08's
`presentHandoffDetailSheet(for:)` carry:

```swift
sheet.largestUndimmedDetentIdentifier = .medium
```

at the source level. The grep gate is the source-of-truth for the
D-08 / RESEARCH §5 line 519 invariant: any future drift on EITHER site
flips the count away from 2 and trips the acceptance criterion.

## Source-Level Acceptance Gates (All Pass)

| # | Gate | Expected | Actual |
| --- | --- | --- | --- |
| 1 | `grep -c 'public final class HandoffDetailSheetViewController: UIViewController' HandoffDetailSheetViewController.swift` | 1 | 1 |
| 2 | `grep -c 'public init(edge: TrustEdge' HandoffDetailSheetViewController.swift` | 1 | 1 |
| 3 | `grep -c 'accessibilityIdentifier = "load-detail.handoff-detail-sheet"' HandoffDetailSheetViewController.swift` | ≥ 1 | 1 |
| 4 | `grep -c 'VerificationBadgeView' HandoffDetailSheetViewController.swift` (reuse lock) | ≥ 1 | 3 |
| 5 | `grep -c 'NSLocalizedString' HandoffDetailSheetViewController.swift` | ≥ 5 | 9 |
| 6 | `grep -v '^//' HandoffDetailSheetViewController.swift \| grep -cE 'Logger\|os_log'` (T-09-04) | 0 | 0 |
| 7 | `grep -c 'HandoffDetailSheetViewController(edge:' LoadDetailViewController.swift` | 1 | 1 |
| 8 | `grep -c 'fatalError("Plan 08' LoadDetailViewController.swift` (Plan 06 stub gone) | 0 | 0 |
| 9 | `grep -c 'sheet.largestUndimmedDetentIdentifier = .medium' LoadDetailViewController.swift` (D-08 / Pitfall 7 — both sites) | 2 | 2 |
| 10 | `grep -c 'XCTSkip' HandoffDetailSheetViewControllerSnapshotTests.swift` (zero stubs) | 0 | 0 |
| 11 | `grep -c 'test_edgeTap_opensHandoffSheet' LoadDetailFlowTests.swift` | ≥ 1 | 2 (one method + one doc reference) |
| 12 | `grep -c 'XCTSkip' LoadDetailFlowTests.swift` (after this plan: 2 remain — banner-a11y + outer-scroll, both Plan 10) | 2 | 2 |

## The 4 Snapshot Test Scenarios

| # | Method | Asserts |
| --- | --- | --- |
| 1 | `test_cleanEdge_rendersBasicRows` | Root identifier `load-detail.handoff-detail-sheet` present; edge-partition identifier `load-detail.handoff-detail-sheet.edge.<edgeID>` resolves on a descendant OR the root; NO implicated block present. |
| 2 | `test_cautionImplicatedEdge_rendersImplicatedBlock` | D-11 — implicated block IS rendered; container background RGBA channels match `UIColor.systemYellow.withAlphaComponent(0.15)` within ±0.05 (R / G / alpha). |
| 3 | `test_compromisedImplicatedEdge_rendersRedTintImplicatedBlock` | D-11 — implicated block rendered with red tint (R / B / alpha ±0.05); D-18 LOCK — `integrity.reason` rendered VERBATIM somewhere inside the implicated subtree (label.text exact match). |
| 4 | `test_nullTenderRef_rendersInformationalLine` | UI-SPEC line 731 — when `tenderRef == nil`, the literal sentence "No formal tender on file." MUST appear as a label.text somewhere in the subtree (informational, no icon). |

## XCUITest Fragment

```swift
// broker → loads-list → VL-1005 (caution archetype, single carrier edge)
//                    → load-detail
//                    → load-detail.trust-graph.edge.edge-VL-1005-broker-carrier (tap)
//                    → load-detail.handoff-detail-sheet (waitForExistence 3s)
//                    → load-detail.handoff-detail-sheet.implicated-block (present — D-11)
```

Multi-query edge-element fallback (`.descendants(matching: .any)
.matching(identifier:)` → `.buttons` → `.otherElements`) defends against
any future re-tagging of `EdgeCompanionView.accessibilityTraits` —
parallel to the resilient pattern Plan 07 documented for the node-tap
test.

Why VL-1005 (caution) rather than VL-1009 (compromised): same reasoning
Plan 07 documented for the node-tap test. VL-1009's double-broker chain
places TWO broker nodes in the same broker role-slot per D-06; the edge
BETWEEN them degenerates to a near-zero-length stroke and the companion
view's tap region collapses with it. VL-1005's two-edge chain has
well-separated endpoints — deterministic tap target — while still
exercising the full TRUST-04 + D-11 contract on the implicated
`edge-VL-1005-broker-carrier` edge.

## Threat-Model Status

| Threat ID | Disposition | Mitigation actually shipped |
| --- | --- | --- |
| T-09-03 | mitigate | Every row's content is driven by server-supplied `TrustEdge` + `TrustNode` + `ChainIntegrity` fields verbatim. The three lookups (`chainOfTrust.edges.first(where: edgeID)` + `nodes.first(where: fromPartyID/toPartyID)`) are pure equality tests. The implicated-block render gate is `integrity.implicatedEdgeIDs.contains(edge.edgeID)` — Set membership. Zero `derive*()` methods in `HandoffDetailSheetViewController.swift`. |
| T-09-04 | mitigate | Zero `Logger` / `os_log` / `OSLog` calls in `HandoffDetailSheetViewController.swift` (verified by negative grep gate after stripping `^//` comment lines). Tender references + party display names are server-supplied and rendered verbatim without ever being logged. Snapshot tests use only `ChainOfTrustFactory` synthetic identifiers. |
| T-09-10 | mitigate | `sheet.largestUndimmedDetentIdentifier = .medium` source-level lock at TWO call sites — Plan 07's `presentVerificationBasisSheet(for:)` and Plan 08's `presentHandoffDetailSheet(for:)`. Grep gate `== 2` in `LoadDetailViewController.swift`. Without the lock the graph behind the sheet dims at `.medium` per RESEARCH §5 Pitfall 7 — breaking the marquee posture on EITHER tap surface. |
| T-09-SC | accept | Zero new SwiftPM dependencies. `UISheetPresentationController` is iOS-17 first-party. `NSAttributedString` is Foundation. |

## Test Results

| Suite | Tests | Result |
| --- | --- | --- |
| `HandoffDetailSheetViewControllerSnapshotTests` (NEW — populated this plan) | 4 / 4 | pass (≈0.14s) |
| `LoadDetailFlowTests/test_edgeTap_opensHandoffSheet` (NEW — populated this plan) | 1 / 1 | pass (≈24.8s) |
| `LoadDetailFlowTests/test_nodeTap_opensVerificationBasisSheet` (regression — Plan 07) | 1 / 1 | pass (≈26.1s) |
| `VerificationBasisSheetViewControllerSnapshotTests` (regression — Plan 07) | 4 / 4 | pass |
| `TrustGraphViewSnapshotTests` (regression — Plan 06) | 12 / 12 | pass |
| `TrustGraphViewAccessibilityTests` (regression — Plan 06) | 6 / 6 | pass |
| `TrustGraphViewGestureTests` (regression — Plan 06) | 5 / 5 | pass |
| `TrustNodeViewSnapshotTests` (regression — Plan 06) | 4 / 4 | pass |
| `TrustNodeViewGestureTests` (regression — Plan 06) | 3 / 3 | pass |
| `LoadDetailViewModelTests` (regression — Plan 03) | 4 / 4 | pass |
| `LoadDetailSkeletonViewSnapshotTests` (regression — Plan 04) | 5 (4 + 1 skipped) | 4 pass / 1 skipped (iPad split — Plan 09) |

**Total across new + regression suites: 48 tests; 0 failures; 1 pre-existing Plan-09-deferred skip.**

## Plan 06's Sheet Stubs — Status After This Plan

Plan 06 shipped TWO fatalError stubs on `LoadDetailViewController`:

| Stub | Plan that landed | Status after Plan 08 |
| --- | --- | --- |
| `presentVerificationBasisSheet(for:)` | Plan 07 | GONE — replaced with full sheet wiring |
| `presentHandoffDetailSheet(for:)` | **Plan 08 (this plan)** | **GONE — replaced with full sheet wiring** |

Both negative grep gates pass:
- `grep -c 'fatalError("Plan 07' LoadDetailViewController.swift` == 0
- `grep -c 'fatalError("Plan 08' LoadDetailViewController.swift` == 0

The LoadDetailVC now has zero stubs related to the TRUST-03 / TRUST-04
tap surfaces. Plan 06's "louder signal" stub posture (Plan 06 SUMMARY
decision #5) has served its purpose — both downstream waves landed
without a tap-target-without-sheet wave being shipped.

## Deviations from Plan

### Auto-Fixed Issues

**1. [Rule 3 — Blocking] Plan acceptance gate `grep -c 'HandoffDetailSheetViewController(edge:' == 1` required same-line constructor form**

- **Found during:** acceptance criteria validation (post-GREEN test pass)
- **Issue:** initial implementation used a multi-line constructor form
  (`let sheetVC = HandoffDetailSheetViewController(\n    edge: edge, ...)`
  with `edge:` on the SECOND line), which is idiomatic Swift but does
  NOT match the plan's grep pattern `HandoffDetailSheetViewController(edge:`
  (same-line literal substring). Grep returned 0 instead of the expected 1.
- **Fix:** flattened the constructor call to a single line so the literal
  substring matches. Line length grows to ~115 chars but stays within the
  codebase's de-facto column limit; the per-arg readability cost is
  acceptable for the gate-satisfying grep contract. The TDD cycle still
  passes (build succeeds, all tests pass).
- **Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift`
- **Commit:** `ba1b1eb`

**2. [Rule 3 — Blocking] Plan acceptance gate `grep -c 'sheet.largestUndimmedDetentIdentifier = .medium' == 2` initially returned 3 — doc-comment leak**

- **Found during:** acceptance criteria validation
- **Issue:** initial GREEN-phase docblock on `presentHandoffDetailSheet`
  contained the verbatim substring inside a parenthetical quotation
  describing the lock (`(`sheet.largestUndimmedDetentIdentifier = .medium`,
  expected count 2)`). The grep gate matched the doc-comment alongside
  the two intended code sites, producing a count of 3.
- **Fix:** re-phrased the doc-comment to DESCRIBE the invariant ("Pitfall
  7 undimmed-detent lock at `.medium`") without QUOTING the literal
  assignment substring. Same re-phrase precedent applied by Plan 06
  SUMMARY deviation #3 and Plan 07 SUMMARY deviation #3. Code sites
  remain unchanged.
- **Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift`
- **Commit:** `ba1b1eb`

**3. [Rule 3 — Blocking] Plan acceptance gate `grep -c 'XCTSkip' HandoffDetailSheetViewControllerSnapshotTests.swift == 0` initially returned 1 — doc-comment leak**

- **Found during:** acceptance criteria validation
- **Issue:** the populated snapshot file's header doc-comment included a
  "Locked targets" line `09-08-PLAN.md Acceptance Criteria — 0 \`XCTSkip\`
  in this file.` The grep gate as-stated does not strip comments, so the
  doc-comment satisfied the substring match by itself.
- **Fix:** re-phrased the doc-comment to "zero test-method skip stubs"
  so the grep gate satisfies its plain-text contract. Same re-phrase
  precedent applied by Plan 07 SUMMARY deviation #3.
- **Files modified:** `validationLedgerTests/Loads/Snapshot/HandoffDetailSheetViewControllerSnapshotTests.swift`
- **Commit:** `ba1b1eb`

### Recorded but not auto-fixed (out of scope)

- **Wave-4 handoff Option B (extract `presentAsSheet(_:)` helper) NOT
  taken** — the plan's per-site grep gate (`sheet.largestUndimmedDetent
  Identifier = .medium == 2`) is the contract that prevented the
  helper-extraction refactor. Option A (inline at both call sites) is
  what shipped. Recorded under Open Questions for a future-phase
  coordinated refactor that updates the grep gate at the same time it
  introduces the helper. Until then, the duplication is load-bearing.
- **No `DS.Colors.caution` token introduced** (mirrors Plan 07
  Recorded-but-not-auto-fixed item) — the implicated-block caution tint
  uses raw `UIColor.systemYellow.withAlphaComponent(0.15)` matching the
  VerificationBadgeView `.pending` precedent and Plan 07's
  VerificationBasisSheetViewController implicated-block. Introducing
  the token here would orphan a coordinated naming pass — deferred for
  an explicit design-system PR.

## Open Questions

- **Wave-4 handoff Option B (shared `presentAsSheet(_:)` helper).** The
  plan's per-site grep gate `sheet.largestUndimmedDetentIdentifier =
  .medium == 2` blocks the helper-extraction refactor; if a future
  phase wants the DRY refactor, the grep gate text needs to be updated
  at the same time. The helper would be: `private func presentAsSheet
  (_ vc: UIViewController)` that applies the locked detent configuration
  (the 8 properties currently inlined twice) and calls `present(_:animated:)`.
- **Edge-partition identifier placement** (UI-SPEC line 783 left
  open). Shipped: header container's `accessibilityIdentifier`. The
  alternative is a sibling element (a sentinel UIView with `isHidden =
  false` and zero frame). The header-container approach has the
  advantage that the XCUITest doesn't need a separate sentinel; the
  disadvantage is that the header container then carries BOTH a
  partition identifier AND visible content. For v1.1 this is fine; if
  a future test needs to assert "the header container alone is
  visible" without the partition identifier interfering, the sibling-
  sentinel form may be cleaner.
- **NSAttributedString vs. two-label HStack for the tender-reference
  row.** Shipped: NSAttributedString (mixed-weight inline). The two-
  label approach would be: `[label("Tender reference:"), label(ref,
  font: .headline)]` in an HStack. The trade-off is that the HStack
  form is simpler to reason about but breaks awkwardly when the ref is
  long enough to wrap (the prefix label and ref label split onto
  separate lines). The NSAttributedString form handles wrapping
  naturally and tracks Dynamic Type on both portions. Future UI-SPEC
  refinement can revisit if the wrapping isn't ideal in any locale.
- **Tender-reference row icon.** UI-SPEC line 731 explicitly says "no
  special icon" for the absent case; the present case doesn't specify
  whether an icon should accompany the row. Shipped: no icon either
  way — keeps the row uniform regardless of presence. If product
  wants a "document" icon for the present case to make the row
  visually scannable, that's a UI-SPEC refinement, not a contract
  change.
- **Edge accessibility-label suffix on implicated edges.** Plan 06's
  D-22 contract composes per-node accessibility labels with an
  implicated suffix (`"... (implicated)"`); the edge equivalent is
  not present (the edge's `accessibilityLabel` on the companion view
  is still just "Handoff from {fromRole} to {toRole}, {state}"). If
  the VoiceOver experience needs parity with the node implicated
  suffix, that's a Plan 06 follow-up — out of scope for this plan.

## Auth Gates

None. Tests run entirely against `MockURLProtocol` fixtures + the
existing simulator-lane scheme.

## Self-Check: PASSED

- `validationLedger/Features/Loads/Detail/HandoffDetailSheetViewController.swift` — FOUND
- `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift` (modified) — FOUND
- `validationLedgerTests/Loads/Snapshot/HandoffDetailSheetViewControllerSnapshotTests.swift` (populated) — FOUND
- `validationLedgerUITests/Loads/LoadDetailFlowTests.swift` (populated) — FOUND
- `26d7277` (test RED) — FOUND
- `ba1b1eb` (feat GREEN) — FOUND

## TDD Gate Compliance

- RED: `test(09-08): add failing tests for handoff-detail sheet (TRUST-04)` — commit `26d7277`
- GREEN: `feat(09-08): implement TRUST-04 handoff-detail sheet (D-07/D-08/D-11)` — commit `ba1b1eb`

The RED commit's build deliberately failed with `error: cannot find type
'HandoffDetailSheetViewController' in scope` (verified via
`xcodebuild build-for-testing` before committing). The GREEN commit
then made the build pass and all 4 snapshot scenarios + the XCUITest
pass; the Plan 07 regression XCUITest also continued to pass.
