---
phase: 09-load-detail-chain-of-trust-graph
fixed_at: 2026-05-20T18:25:00Z
review_path: .planning/phases/09-load-detail-chain-of-trust-graph/09-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 9: Code Review Fix Report

**Fixed at:** 2026-05-20T18:25:00Z
**Source review:** `.planning/phases/09-load-detail-chain-of-trust-graph/09-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 8 (3 Critical + 5 Warning; Info findings IN-01..IN-03 are deferred per `fix_scope: critical_warning`)
- Fixed: 8
- Skipped: 0

All 3 Critical findings (CR-01, CR-02, CR-03) and all 5 Warning findings (WR-01..WR-05) were applied. Verification used `xcrun swiftc -parse` (Tier 2) against an iOS 17 simulator target on every modified Swift source file — every file parsed cleanly. Several fixes are flagged below as **requires human verification** because syntax-parse alone cannot confirm semantic / behavioral correctness (CR-01 logic, WR-04 snapshot baseline impact).

## Fixed Issues

### CR-01: `StatusTimelineView.applyPillStates` — Cancelled state hid all completed stages

**Files modified:** `validationLedger/Features/Loads/Detail/StatusTimelineView.swift`
**Commit:** `6ba959e`
**Status:** fixed: requires human verification

**Applied fix:** Added a `priorPrimaryForCancelledIdx: Int?` cache on the view, populated in `configure(load:)` by walking `load.stateHistory` in reverse and recording the index in `primaryLifecycle` of the most recent non-cancelled primary status. `applyPillStates(currentStatus:)` now reads that index when `currentStatus == .cancelled` instead of falling through to `currentIdx = -1` (which had marked every primary pill as "future" — hiding the load's documented progress prior to cancellation). For other non-primary fallback paths (draft / rejected / expired / podCaptured / invoiced / funded), the -1 fallback is preserved so a malformed history still fails visibly.

**Human verification needed because:** this is a logic change that re-derives "what is the current pipeline position" on the cancelled path. The reviewer's spec says "treat cancellation as an end-state that occurs _after_ all prior stages: mark completed stages as done, style the pill immediately preceding the cancel event as 'current'." My implementation uses `applyCurrentStyle` for the last-non-cancelled primary, which matches that intent. But existing tests assert the old "all-future on cancel" behavior (per the previous code comments and the inline contract in `pickCurrentStatus`); a developer should sanity-check that no existing `StatusTimelineViewTests` / `StatusTimelineViewSnapshotTests` assertion on the cancelled path is now contradicted. The reviewer also suggested rendering the cancel annotation in the expanded-card subtitle below the stepper — this is already done via `configureRow3(currentStatus: .cancelled)` returning the "This load was cancelled." copy, so no additional changes were needed there.

---

### CR-02: `LoadDetailViewController.buildIPhoneLayout` — bodyView not re-parented on iPad→iPhone rotation

**Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift`
**Commit:** `56dd620`
**Status:** fixed

**Applied fix:** Added a `bodyView.superview !== bodyContainer` guard at the top of `buildIPhoneLayout()` that calls `bodyView.removeFromSuperview()` + `bodyContainer.addSubview(bodyView)` before installing the iPhone-specific constraints. This mirrors the symmetric re-parent that `buildIPadSplitLayout()` already performs (lines 556-559 in the original file). The fix eliminates the AutoLayout "Unable to simultaneously satisfy constraints" breakage on the iPad→iPhone trait-collection flip path, where `bodyView` was previously left stranded under `rightPaneContainer` while the iPhone constraints anchored it to `bodyContainer`.

---

### CR-03: `ChainIntegrityBannerView` — Verdict symbol pinned to fixed 16x16pt, Dynamic Type violation

**Files modified:** `validationLedger/Features/Loads/Detail/ChainIntegrityBannerView.swift`
**Commit:** `cce5070`
**Status:** fixed

**Applied fix:** Two coordinated changes:
1. Removed the `symbolView.widthAnchor.constraint(equalToConstant: 16)` and `symbolView.heightAnchor.constraint(equalToConstant: 16)` from the constraints array — the SF Symbol now sizes itself via its intrinsicContentSize.
2. Set `symbolView.adjustsImageSizeForAccessibilityContentSizeCategory = true` and constructed the symbol image with `UIImage.SymbolConfiguration(textStyle: .footnote)` so the icon tracks the same Dynamic Type text style as the surrounding label (`UIFont.preferredFont(forTextStyle: .footnote)`). Also pinned vertical content hugging + compression resistance to `.required` so the icon stays centered without stretching when the stack lays out.

This satisfies WCAG 1.4.4 (Resize Text) and the CLAUDE.md "Dynamic Type fully supported" mandate. At accessibility-tier content size categories, the icon now grows proportionally with the body text.

---

### WR-01: `VerificationBasisSheetViewController.makeUSDOTRow` — Nil USDOT produced a gap in formatted string

**Files modified:** `validationLedger/Features/Loads/Detail/VerificationBasisSheetViewController.swift`
**Commit:** `1fdfc18`
**Status:** fixed

**Applied fix:** Replaced `let usdot = node.usdotNumber ?? ""` with `node.usdotNumber ?? NSLocalizedString("loads.detail.sheet.usdot.placeholder", value: "—", comment: ...)`. The em-dash placeholder now appears in the templated copy (e.g. "USDOT — · Authority active") when a Carrier or Dispatch node has an active/suspended/revoked authority status but the `usdotNumber` itself is nil due to an incomplete server response. Prevents the leading-double-space-plus-bullet artifact ("USDOT  · Authority active") that the original empty-string fallback produced.

The new localization key follows the existing `loads.detail.sheet.usdot.*` namespace convention. M1 ships English only — no additional localization work required.

---

### WR-02: `HandoffDetailSheetViewController` and `VerificationBasisSheetViewController` bypass `DS.Colors.caution`

**Files modified:**
- `validationLedger/Features/Loads/Detail/HandoffDetailSheetViewController.swift`
- `validationLedger/Features/Loads/Detail/VerificationBasisSheetViewController.swift`

**Commit:** `3354a5c`
**Status:** fixed

**Applied fix:** Replaced `.systemYellow` with `DS.Colors.caution` in both `makeImplicatedBlock` implementations (the `tintBase` ternary). The caution branch in each VC now uses the shared design-system token introduced in Phase 9 to consolidate the chain-integrity banner, verdict block, flagged-edge dash, and caution halo. Any future re-tinting (APCA contrast bump, brand refresh) will now propagate from `DS.Colors.caution` to both implicated blocks automatically.

Note: I deliberately did NOT touch the USDOT "suspended" branch in `VerificationBasisSheetViewController.makeUSDOTRow` (line 342, `tintColor = .systemYellow`) even though it has the same pattern — the reviewer's WR-02 finding was scoped specifically to the `makeImplicatedBlock` sites in both sheet VCs. The USDOT-suspended `.systemYellow` carries an inline `(no DS.Colors.caution token yet — additive token deferred)` comment that is now stale; a follow-up cleanup can consolidate it under the same token, but it falls outside this finding's explicit scope.

---

### WR-03: `LoadDetailViewController.viewWillAppear` re-fetches on every appearance

**Files modified:** `validationLedger/Features/Loads/Detail/LoadDetailViewController.swift`
**Commit:** `c39bb00`
**Status:** fixed

**Applied fix:** Replaced the unconditional `Task { [viewModel] in await viewModel.fetchLoadDetail() }` with a `switch viewModel.state` guard. Only `.loading` and `.error` states fire the fetch; `.loaded` returns early. Sheet dismissals (verification-basis / handoff-detail) no longer churn the network or flash the skeleton over already-rendered content. Pull-to-refresh + the `.error` retry CTA remain on the unconditional `fetchLoadDetail()` path because they invoke the VM method directly, not via `viewWillAppear`.

I chose the state-based check over the "hasAppearedOnce" Bool option mentioned in the review fix suggestion because it naturally handles the error→retry→loaded→sheet-dismiss flow (after a successful retry the state is `.loaded` and subsequent appearances skip the fetch, no extra bookkeeping needed).

---

### WR-04: `TrustGraphViewSnapshotTests.renderedView` — `contentSize` parameter silently ignored

**Files modified:** `validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests.swift`
**Commit:** `3a0d222`
**Status:** fixed: requires human verification

**Applied fix:** Changed the parameter signature from `contentSize _: UIContentSizeCategory` to `contentSize: UIContentSizeCategory` and applied it via `v.traitOverrides.preferredContentSizeCategory = contentSize` before `configure(...)` + `layoutIfNeeded()`. The DTLarge vs DTAXXXL legs of the 12-fingerprint snapshot matrix now render at genuinely different Dynamic Type sizes instead of both rendering at the system default.

Note on API choice: the reviewer's fix suggestion referenced `view.traitOverrideUsingTraitCollection(traitOverride)` which is not a real iOS 17 API. The correct iOS 17 channel for view-local trait injection is `UIView.traitOverrides` (a `UITraitOverrides` collection), which is what I used. This avoids mutating the host-app singleton (`UIApplication.shared.preferredContentSizeCategory`) and keeps the override scoped to a single view subtree.

**Human verification needed because:** this is a snapshot-baseline-shifting change. The previous DTAXXXL artefacts were recorded at default size (effectively identical to DTLarge); the new artefacts will be visibly larger. Existing recorded baselines for `TrustGraph-*-DTAXXXL` will likely fail on the next snapshot-record/CI pass and need re-recording. A developer should:
1. Run the snapshot suite locally to capture new DTAXXXL baselines.
2. Confirm visually that the DTAXXXL frames render at the expected larger size + diff cleanly from DTLarge.
3. Commit the re-recorded artefacts in a follow-up commit (the existing baselines were never actually exercising DT scaling, so they should be considered initial captures, not regressions).

The same DT-application pattern probably wants to be ported to the other snapshot helpers IN-02 lists as unreviewed (`StatusTimelineViewSnapshotTests`, `LoadRowCellSnapshotTests`, `TrustNodeViewSnapshotTests`) but that is out of scope for this finding.

---

### WR-05: `LoadDetailFlowTests.test_rowTap_pushesDetail` — `executionTimeAllowance` of 30s covered 5 full OTP flows

**Files modified:** `validationLedgerUITests/Loads/LoadDetailFlowTests.swift`
**Commit:** `4463386`
**Status:** fixed

**Applied fix:** Raised `executionTimeAllowance` from 30s to 90s in `setUp()`. Chose Option A (conservative allowance) from the reviewer's two-option fix suggestion rather than Option B (parameterize to single-role) because:
- The 5-role coverage was a deliberate Plan 03 LOAD-05 acceptance criterion (test all 5 roles route to the detail VC), and the test file's docstring at line 142-145 explicitly justifies the loop shape (`XCTContext.runActivity` for per-role failure scoping).
- Other tests in this file are single-role flows and finish well under 30s; the new 90s cap only meaningfully changes the 5-role test's ceiling.
- A 90s cap on a single test is well within XCTest's "reasonable per-test cap" range and matches the reviewer's "conservative allowance" recommendation.

If physical-device CI runs ever show this test consistently approaching the 90s ceiling (rather than the 40-60s expected window), Option B (parameterize + complement with coordinator unit tests) is the natural follow-up.

---

## Skipped Issues

None — all 8 in-scope findings were applied.

---

## Verification Notes

- **Tier 1 (re-read after every edit):** confirmed for all 8 fixes.
- **Tier 2 (`xcrun swiftc -parse` against iOS 17 simulator target):** all 6 modified Swift files parsed cleanly with no errors (only the expected `using sysroot for 'MacOSX' but targeting 'iPhone'` warning, which is a host-vs-target SDK note and not a code error).
- **No test run:** per the prompt's iOS test-suite pitfall note, the full `xcodebuild test` was deliberately not invoked. Snapshot re-recording (relevant for WR-04) and behavioral regression testing should be performed by the verifier phase or the developer using the project's scoped serial simulator-lane command.

## Follow-Up Notes (Out of Scope for This Iteration)

- **IN-01 / IN-02 / IN-03:** these Info findings were deferred per `fix_scope: critical_warning`. IN-01 (large `MockLoadFixtureRegistry.swift` review gap) and IN-02 (three unreviewed snapshot test files) recommend manual file inspection rather than automated fixes; IN-03 (formatter allocator hoist in `StatusTimelineView.configureRow1`) is a micro-optimization safe to roll into a future cleanup commit.
- **USDOT-suspended `.systemYellow` (file `VerificationBasisSheetViewController.swift` line ~342):** the same DS.Colors.caution consolidation question that WR-02 flagged for `makeImplicatedBlock` also applies to this site. A follow-up cleanup can fold it into the shared token; the inline `(no DS.Colors.caution token yet — additive token deferred)` comment is now stale and should be removed at that time.

---

_Fixed: 2026-05-20T18:25:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
