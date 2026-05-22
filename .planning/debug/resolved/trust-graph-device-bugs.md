---
status: resolved
trigger: "Phase 9 trust-graph rendering breaks on real device for multi-node graphs (Bug A: nodes collapse to same position when >1 non-counterparty role) and for chain-compromised graphs (Bug B: large DS.Colors.destructive-pink filled square appears in canvas center on compromised chains only). Discovered during Phase 9 device UAT on 2026-05-20 after the just-resolved kyc-status-under-review-trap unblocked the role shell."
created: 2026-05-20T00:00:00Z
updated: 2026-05-20T00:00:00Z
---

## Current Focus

hypothesis: RESOLVED. The real root cause is a CONSTRAINT-PROPAGATION TIMING bug in `TrustGraphView.layoutSubviews()`, NOT the originally-suspected TAMIC=false defect (see Eliminated ELIM-6). The `contentContainer` (the zoomable view inside the inner scrollView) is sized implicitly via Auto Layout — pinned to `scrollView.frameLayoutGuide` in `setUp()` (lines 248-265). When `TrustGraphView.layoutSubviews()` fires for the first time after `configure(chainOfTrust:)`, the constraint chain `self → scrollView → contentContainer` has NOT yet propagated, so `contentContainer.bounds == (0, 0, 0, 0)` at that moment. The existing `guard canvas.width > 0 && canvas.height > 0 else { return }` then returned early — frame writes for every TrustNodeView never ran, leaving every node parked at the origin (0, 0). On compromised chains the implicated-node halo CAShapeLayer paths (set further down in the same `layoutSubviews` body) ALSO never wrote — but the halo layers themselves had been created in `configure(...)` with `fillColor = systemRed.cgColor`. The visual outcome on device was the user's report: all node tiles stacked at canvas origin (Bug A) plus an exposed bare red rounded-square mid-canvas (Bug B). Forcing `scrollView.layoutIfNeeded(); contentContainer.layoutIfNeeded()` at the top of `layoutSubviews()` flushes the constraint solver through the scroll-view's nested guides before reading the canvas — fixing both bugs in one place. Confirmed with two regression tests that fail without the fix and pass with it.
test: New `TrustGraphViewLayoutTests` (2 tests) — (1) `test_nodeFrames_areDistinctAndPositionedFromRoleSlots` asserts each of the 5 canonical TrustNodeView frames lands at a distinct non-origin position matching `canvas * iPhoneSlots[role]` within 1pt; (2) `test_compromisedHalo_isCenteredOnImplicatedNodeChrome` asserts the implicated halo's CGPath bounding-box center matches the implicated node chrome's center within 1pt. Both tests fail BEFORE the fix and pass AFTER (empirically verified via git stash + xcodebuild test).
expecting: Resolved. Device re-walk of VL-1001 / VL-1007 / VL-1009 / VL-1010 should now show distinct node tiles at slot positions, no bare pink square mid-canvas, halo correctly framing the implicated node chrome on VL-1009 and VL-1010.
next_action: Device UAT on physical iPhone — re-walk the 4 fixtures and confirm the visual remediation. Commit the fix with `fix(09):` prefix. Update phase-9-execution-closeout memory to reflect the resolved device-UAT items.

## Symptoms

expected: TrustGraphView renders each non-counterparty trust role (FACTORING, DISPATCH, CAPITAL, etc.) as a distinct tile at a distinct position on the canvas, with arrow edges connecting roles per the trust-chain topology. Compromised chains display a pulse-on-compromised halo around the flagged node (an animated CALayer pulse, NOT a static filled square). Dim-others mechanic dims non-flagged nodes. Phase 9 D-decisions cover the marquee mechanics — see phase-9-execution-closeout memory.
actual: On physical iPhone 17 / iOS 26 (DEBUG build, networkConfig=.mock, -MockKYCStatusVerified active), 4 of the 4 load-detail screens tested exhibit one or both of these bugs:
  - VL-1007 (Detroit→Indianapolis, DISPATCHED, no chain-compromised banner, 1 non-counterparty role 'Cornerstone Dispatch'): renders CORRECTLY. Single tile upper-left, arrow extending down-right. CONTROL CASE — but see ELIM-1: with hindsight this was actually all 4 nodes overlapping at (0, 0), masquerading as "one tile upper-left."
  - VL-1010 (Miami→Jacksonville, ACCEPTED, chain-compromised banner present, 2 non-counterparty roles 'Cornerstone Dispatch' + 'PhantomLine Logistics'): BUG A + BUG B. Two tiles stack at the same origin (text overlays read as scrambled "DSPATCERIE / VERIFIIED / ChaentestcineLisgisticics"). Large ~150pt pink-magenta rounded square centered in canvas with a small triangle marker on top.
  - VL-1009 (Long Beach→Phoenix, IN TRANSIT, chain-compromised banner present, 2 non-counterparty roles 'FACTORING' + 'BridgeCap Capital'): BUG A + BUG B. Same stacking overlap. ~80pt pink square present.
  - VL-1001 (Anaheim→Atlanta, DELIVERED, no chain-compromised banner, 2 non-counterparty roles 'FACTORING' + 'BridgeCap Capital' [variant]): BUG A only (no pink square, because no chain-compromised banner).
errors: No runtime crashes, no console errors visible to the tester. Both bugs are silent visual defects only.
reproduction: On a DEBUG build with networkConfig=.mock and -MockKYCStatusVerified active, navigate past KYC into the role shell, open the Loads list, then open the four load fixtures VL-1001 / VL-1007 / VL-1009 / VL-1010. VL-1007 is the clean control; the other three exhibit one or both bugs.
started: Discovered 2026-05-20 by user during Phase 9 device UAT (six device-UAT items pending per phase-9-execution-closeout memory). The Phase 9 trust-graph code shipped earlier the same day (TrustGraphView.swift + TrustNodeView.swift, mtime 08:57 UTC); the bugs are in code less than ~7 hours old. Yesterday's code-review-fix pass touched CR-02 (LoadDetailViewController iPhone-layout re-parenting) and CR-03 (ChainIntegrityBannerView Dynamic Type) — both potentially-adjacent surfaces worth checking for collateral damage. WR-04 (snapshot helper traitOverrides) was noted to require re-recorded baselines and may have masked Bug A from CI snapshot coverage.

## Eliminated

- ELIM-1: Hypothesis "VL-1007 renders correctly because it has 1 non-counterparty role" — incorrect framing. Fixture inspection (python3 walk of chain_of_trust.nodes) shows VL-1007 has 4 nodes total (shipper, broker, carrier, dispatch) — same shape as the others minus factoring. The reason VL-1007 LOOKS like one tile is that ALL FOUR nodes are collapsed to (0, 0) and the user reads the stack as "a single tile upper-left." VL-1007 is NOT a control — it's the same bug rendering with one fewer overlay.
- ELIM-2: Hypothesis "duplicate `role` in the role-slot dictionary collapses two nodes to one slot" — only partially applicable. VL-1009 has 2 brokers (so 2 nodes share role=.broker); but VL-1001 and VL-1010 each have 5 and 4 nodes respectively with NO duplicate roles, yet still exhibit Bug A. So duplicate roles are not the trigger.
- ELIM-3: Hypothesis "compromised halo branch draws a filled rect instead of an animated CALayer halo" — incorrect. The halo IS a CAShapeLayer with `fillColor = systemRed.cgColor`, and its `path` is correctly computed in `layoutSubviews` (line 570: `UIBezierPath(roundedRect: chromeFrame.insetBy(dx: -6, dy: -6), cornerRadius: 18)`) — IF `layoutSubviews` reaches that branch. The pulse animation is correctly attached in `startPulseIfNeeded()` (line 690-701). Bug B is NOT a missing-animation defect; the halo construction is correct.
- ELIM-4: Hypothesis "CR-02 LoadDetailViewController re-parenting broke trust-graph layout pass" — investigated and discarded. The trust-graph's internal layout is self-contained: scrollView pinned to self, contentContainer pinned to scrollView.frameLayoutGuide. Yesterday's CR-02 changes touched only the OUTER container hierarchy.
- ELIM-5: Hypothesis "snapshot tests would have caught this" — investigated: `UIKitSnapshot.image(of:size:)` renders to UIImage and `attach`es to the test report as an XCTAttachment for human triage. There is NO pixel-diff comparison against a baseline; the "snapshot tests" are effectively just visual-inspection artifacts. So Bug A passing CI is expected. A proper regression test must be a LAYOUT assertion (frame positions), not a pixel snapshot — which is what `TrustGraphViewLayoutTests` now provides.
- ELIM-6: Initial hypothesis "TAMIC=false on TrustNodeView prevents frame-based layout from sticking" — INCORRECT, though plausible. Investigated by flipping TAMIC to true and re-running the new regression test — frames were STILL parked at (0, 0). Adding a debug print inside `layoutSubviews()` revealed `contentContainer.bounds == (0, 0)` at the moment the guard ran — meaning frame writes never executed AT ALL. The TAMIC change was harmless (and arguably correct documentation of the intent at the call site), but it was not the actual cause. The real cause is the constraint-propagation timing — see Current Focus.

## Evidence

- timestamp: 2026-05-20T_session_phase1
  hypothesis: TAMIC=false on TrustNodeView prevents frame-based layout from sticking
  steps:
    - Read TrustGraphView.swift end-to-end (824 lines, UIKit + CALayer composition).
    - Identified the per-node placement code at TrustGraphView.swift:543-555 (layoutSubviews → `nodeView.frame = CGRect(...)`).
    - Identified the TAMIC=false at TrustGraphView.swift:319 inside `configure(chainOfTrust:)` and at TrustNodeView.swift:147 inside setUp().
    - Authored regression test `TrustGraphViewLayoutTests` asserting per-node centers match `canvas * iPhoneSlots[role]`.
    - Flipped TrustGraphView.swift:319 from `false` to `true`.
  result: Test STILL failed with every frame parked at (0, 0). Hypothesis discarded — TAMIC is not the trigger.

- timestamp: 2026-05-20T_session_phase2
  hypothesis: contentContainer.bounds is zero at the moment layoutSubviews reads it
  steps:
    - Added a debug `print` at the top of `layoutSubviews()` exposing `self.bounds`, `scrollView.bounds`, `contentContainer.bounds`, and the `nodeViews` array.
    - Re-ran TrustGraphViewLayoutTests on simulator iPhone 17.
    - Observed: `self.bounds=(0,0,393,600)` `scrollView.bounds=(0,0,393,600)` `contentContainer.bounds=(0,0,0,0)`.
    - Verified by attaching the view to a host UIWindow before layoutIfNeeded — STILL `contentContainer.bounds=(0,0,0,0)`.
    - Hypothesised: the constraint chain `self → scrollView → contentContainer` has not yet propagated through Auto Layout at the moment `self.layoutSubviews()` runs. The scroll-view's frame-layout-guide pinning is correct but unsettled.
    - Added `scrollView.layoutIfNeeded(); contentContainer.layoutIfNeeded()` at the top of `layoutSubviews()` (before reading `contentContainer.bounds`).
    - Re-ran — `contentContainer.bounds` is now `(0, 0, 393, 600)`, every node frame lands at its slot position, regression tests pass.
  result: Root cause CONFIRMED — the bug is a constraint-propagation timing issue, NOT TAMIC. Fix applied. 40 of 40 LoadDetail-touching tests pass (TrustGraphViewLayoutTests + TrustGraphViewAccessibilityTests + TrustGraphViewGestureTests + TrustGraphViewSnapshotTests + TrustNodeViewGestureTests + TrustNodeViewSnapshotTests + LoadDetailViewModelTests + ChainOfTrustDecodeTests + LoadDomainDecodeTests + LoadStateHistoryTests + PriorRelationshipDecodeTests + LoadDetailFixtureContractTests + ChainIntegrityBannerViewSnapshotTests + LoadDetailSkeletonViewSnapshotTests).

- timestamp: 2026-05-20T_session_phase3
  hypothesis: the regression tests genuinely catch the bug (not vacuously green)
  steps:
    - With the fix applied, ran `TrustGraphViewLayoutTests` — both tests pass.
    - `git stash` the fix-bearing TrustGraphView.swift to revert it.
    - Re-ran tests — both tests fail (12 XCTAssert failures across the two tests, mostly "centers within 1pt of (0,0) vs (0,0)" and "halo center does not match chrome center").
    - `git stash pop` to restore the fix.
    - Re-ran — both tests pass.
  result: Tests genuinely catch the bug. CI regression guard verified.

## Possibly-expected, not in scope

- A yellow "Limited trust mode — this device can't fully verify. Some features may be restricted." banner appears at the top of all 4 load-detail screens INCLUDING the cleanly-rendering VL-1007. Almost certainly Phase 6 App Attest failing on the dev device (no valid attestation entitlement). NOT a Phase 9 bug — Phase 6 documented fallback behavior (DCAppAttestService.featureUnsupported on non-provisioned devices). CONFIRMED out-of-scope.

## Suggested Investigation Order

1. Read TrustGraphView.swift in full to identify the rendering framework (UIKit + CALayer? CAShapeLayer? SwiftUI inside a UIHostingController? Pure CAGradientLayer?). 37 KB / 824 LOC suggests UIKit + multiple CALayer subclasses.
2. Identify the per-node placement code — search for `frame =`, `center =`, `bounds =`, NSLayoutConstraint activations, or `setPosition`. Cross-check whether the placement loop indexes correctly per non-counterparty role.
3. Open the 4 fixture files to confirm role counts: load-detail-VL-1001.json (expect 2 non-counterparty roles), VL-1007.json (expect 1), VL-1009.json (expect 2), VL-1010.json (expect 2). Confirm the rendering pattern correlates with role count.
4. For Bug B, search for "pulse", "halo", "compromised" inside TrustGraphView.swift and TrustNodeView.swift. Identify the compromised-render branch and verify whether the pulse layer is added via `addSublayer` + `add(animation, forKey:)` or whether the branch only sets a fill color without the animation.
5. Hypothesize, propose minimum fix per bug, implement, commit atomically (`fix(09):` prefix per orchestrator note), validate via the scoped serial simulator lane (NOT bare xcodebuild test per ios-test-suite-pitfalls memory).

## Resolution

root_cause: TrustGraphView.layoutSubviews() ran before the scrollView → contentContainer constraint chain had propagated, so `contentContainer.bounds` was (0, 0) at the moment the canvas was read. The `guard canvas.width > 0 ...` returned early, skipping every per-node `frame = ...` write AND every halo path write. On device the resulting layout was all node tiles stacked at (0, 0) (Bug A) and — on compromised chains — an exposed red CAShapeLayer mid-canvas with no path geometry sized against the actual chrome (Bug B). Both bugs share ONE timing root cause. Initial hypothesis (TAMIC=false on TrustNodeView) was empirically falsified during investigation phase 1 — see ELIM-6.
fix: Two coupled edits in `validationLedger/Features/Loads/Detail/TrustGraphView.swift`:
  (a) `layoutSubviews()` — added `scrollView.layoutIfNeeded(); contentContainer.layoutIfNeeded()` at the top of the method (BEFORE reading `contentContainer.bounds`) to flush the constraint solver through the scroll-view's nested layout guides. This is the LEAST-INVASIVE fix — it touches only the layout-pass entry, requires no constraint re-modelling, and keeps the existing `guard` for the (now unreachable) zero-size early return.
  (b) `configure(chainOfTrust:)` — changed `v.translatesAutoresizingMaskIntoConstraints = false` to `= true` on each TrustNodeView. Not strictly required to fix the timing bug, but documents the contract at the call site (per-node placement is frame-write driven, not constraint driven). Harmless change with intent documentation value.
verification:
  - New `TrustGraphViewLayoutTests` (2 tests) — both fail without (a) + (b), both pass with the fix.
  - All existing trust-graph tests still pass: TrustGraphViewAccessibilityTests (6), TrustGraphViewGestureTests (5), TrustGraphViewSnapshotTests (12), TrustNodeViewGestureTests (3), TrustNodeViewSnapshotTests (4) — 30 existing + 2 new = 32 total green on the trust-graph surface.
  - Broader Load + Loads + decode + skeleton suites green: 40 of 40 tests selected via scoped serial simulator lane (`-destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO`).
  - Pending: device UAT walk on physical iPhone of VL-1001 / VL-1007 / VL-1009 / VL-1010 to confirm the visual remediation. Expected: distinct node tiles at slot positions, no bare pink square, halo correctly framing implicated nodes on the compromised fixtures.
files_changed:
  - validationLedger/Features/Loads/Detail/TrustGraphView.swift (+28 / -1 — production fix + intent comments)
  - validationLedgerTests/Loads/TrustGraphViewLayoutTests.swift (new — 2 regression tests)
