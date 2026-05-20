---
phase: 9
slug: load-detail-chain-of-trust-graph
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-20
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Sourced from `09-RESEARCH.md` § Validation Architecture (Nyquist Dimension 8).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (in-tree; Swift Testing also present but Phase 9 snapshot + accessibility tests use XCTest per `UIKitSnapshot.swift` lines 5–11) |
| **Config file** | `validationLedger.xcodeproj/project.pbxproj` |
| **Quick run command** | `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:validationLedgerTests/Loads -enableCodeCoverage NO` |
| **Full suite command** | Scoped serial simulator-lane command per project memory `ios-test-suite-pitfalls.md` (bare `xcodebuild test` produces ~67 false failures; see `scripts/test-serial-simulator.sh` or equivalent established by Phase 4 CI close-out) |
| **Estimated runtime** | ~60–90 seconds (quick run, Loads scope only); ~5–8 minutes (full serial simulator lane) |

---

## Sampling Rate

- **After every task commit:** Run the quick run command **scoped to the test file the task touches** (matches Phase 8 cadence).
- **After every plan wave:** Run the full serial-simulator-lane suite.
- **Before `/gsd:verify-work`:** Full suite must be green AND every snapshot artefact attached to the test run for human visual triage.
- **Max feedback latency:** ~90 seconds (scoped run).

---

## Per-Task Verification Map

> Filled at plan-time. Each plan in this phase MUST cite the test target it adds or extends. Wave 0 (test stubs + reference fixtures) is a planning prerequisite.

| Task ID | Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | 0 | (Wave 0 fixtures + stubs) | n/a | unit | scoped XCTest | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | LOAD-05 | Row tap pushes detail VC; no PII in logs | XCUITest (smoke) | `-only-testing:validationLedgerUITests/LoadDetailFlowTests/test_rowTap_pushesDetail` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | LOAD-06 | Stepper renders 6 pills from `Load.stateHistory`; side-states NOT surfaced | Snapshot + unit | `-only-testing:validationLedgerTests/Loads/Snapshot/StatusTimelineViewSnapshotTests` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | TRUST-01 | Graph renders fixed-slot nodes + edges; fit-all-nodes-tight default zoom; pinch + double-tap | Snapshot + gesture unit | `-only-testing:validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests` + `-only-testing:validationLedgerTests/Loads/TrustGraphViewGestureTests` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | TRUST-03 | Node tap opens `VerificationBasisSheetViewController`; sheet stays at `.medium` over graph | XCUITest | `-only-testing:validationLedgerUITests/LoadDetailFlowTests/test_nodeTap_opensVerificationBasisSheet` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | TRUST-04 | Edge tap opens `HandoffDetailSheetViewController` (same surface infra) | XCUITest | `-only-testing:validationLedgerUITests/LoadDetailFlowTests/test_edgeTap_opensHandoffSheet` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | TRUST-05 | Compromised verdict renders red pulsing halo + banner + dim-others; rendered from server data only (no client derivation) | Snapshot + assertion | `-only-testing:validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests/test_compromisedVerdict_rendersExpectedFrame` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | (gesture invariant) | `singleTap.require(toFail: doubleTap)` is set on `TrustNodeView` | Unit | `-only-testing:validationLedgerTests/Loads/TrustNodeViewGestureTests/test_singleTap_requiresDoubleTapFail` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | (gesture invariant) | Inner `UIScrollView.panGestureRecognizer.minimumNumberOfTouches == 2` (outer-page scroll preserved) | Unit | `-only-testing:validationLedgerTests/Loads/TrustGraphViewGestureTests/test_innerScroll_minimumTwoTouches` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | (a11y invariant — D-22) | `TrustGraphView.isAccessibilityElement == false` + ordered `accessibilityElements` (nodes role-order, then edges fromID/toID order) | Unit | `-only-testing:validationLedgerTests/Loads/TrustGraphViewAccessibilityTests` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | (a11y invariant — D-22) | Pinch-zoom disabled while `UIAccessibility.isVoiceOverRunning` | Unit | `-only-testing:validationLedgerTests/Loads/TrustGraphViewAccessibilityTests/test_voiceOver_disablesPinchZoom` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | (decode — D-13) | `PriorRelationship` decodes correctly with `load_id` → `loadID` bridge | Unit | `-only-testing:validationLedgerTests/Loads/PriorRelationshipDecodeTests` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | (contract — D-14) | Every `load-detail-VL-*.json` fixture has `prior_relationships` (count=0 removed) | Unit | `-only-testing:validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | (no-client-trust — Phase 7 D-18 inheritance) | View layer reads `verificationState` + `chainIntegrity.verdict` verbatim, never derives them | Source assertion | `grep -E 'verificationState\s*=' validationLedger/Features/Loads/Detail/**.swift` returns no derivation site | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | — | (PII zero — CLAUDE.md) | No logger calls reference `Load.reference`, party names, or `partyID` in the view layer | Source assertion | `grep -RE 'Logger|os_log' validationLedger/Features/Loads/Detail/` returns no PII-bearing args | ❌ Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Test stubs + fixture contract tests + snapshot baseline scaffolding. Created BEFORE any feature task in Phase 9.

- [ ] `validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests.swift` — 12 reference fingerprints (3 verdicts × 2 devices × 2 Dynamic Type sizes); each fingerprint records a `snapshotFingerprint(_:identifier:)` baseline via `UIKitSnapshot` helper
- [ ] `validationLedgerTests/Loads/Snapshot/TrustNodeViewSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/Snapshot/ChainIntegrityBannerViewSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/Snapshot/StatusTimelineViewSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/Snapshot/LoadDetailSkeletonViewSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/Snapshot/VerificationBasisSheetViewControllerSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/Snapshot/HandoffDetailSheetViewControllerSnapshotTests.swift`
- [ ] `validationLedgerTests/Loads/TrustNodeViewGestureTests.swift` — `singleTap.require(toFail: doubleTap)`
- [ ] `validationLedgerTests/Loads/TrustGraphViewGestureTests.swift` — `minimumNumberOfTouches`, double-tap recenter math, VoiceOver-disables-zoom
- [ ] `validationLedgerTests/Loads/TrustGraphViewAccessibilityTests.swift` — container model + ordered elements + accessibility label composition
- [ ] `validationLedgerTests/Loads/LoadDetailViewModelTests.swift` — state machine `.loading → .loaded → .error`
- [ ] `validationLedgerTests/Loads/PriorRelationshipDecodeTests.swift` — `load_id` → `loadID` trailing-acronym CodingKey bridge
- [ ] `validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests.swift` — D-14 enforcement: every detail fixture has `prior_relationships`, no `prior_relationship_count`
- [ ] `validationLedgerUITests/LoadDetailFlowTests.swift` — 5-role smoke flow + sheet-opens assertions + outer-scroll-propagation assertion

*Wave 0 framework install: not required — XCTest, snapshot helper (`UIKitSnapshot.swift`), serial-simulator lane all in tree from Phases 4–8.*

---

## Manual-Only Verifications

> Per CONTEXT.md the chain-of-trust graph is the marquee surface; visual quality and gesture feel cannot be fully captured by snapshot diffs. The phase will produce manual-test instructions for human triage of these.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Pinch-zoom gesture feel + outer-scroll preservation | TRUST-01 (D-04) | Multi-touch + gesture-recognizer interaction quality is observation-only; snapshots can't assert "feel" | On physical iPhone 17 + iPad Air: open a detail load, single-finger drag → outer page scrolls; two-finger pinch → graph zooms; two-finger pan → graph pans; double-tap node → graph recenters & zooms; double-tap empty canvas → resets |
| Halo pulse animation on compromised node | TRUST-05 (D-15) | `CABasicAnimation` continuity across `layoutSubviews()` + trait changes — Phase 8 shimmer pattern (lines 169–198) is the precedent, but visual continuity needs eyes on it | Open a compromised-archetype fixture load on device; rotate iPad compact→regular; verify halo continues pulsing without restart artefact; lock screen, return, verify halo resumes |
| VoiceOver traversal order | TRUST-01 (D-21, D-22) | Apple's VoiceOver runtime is not fully scriptable from XCUITest | Open a flagged-archetype load with VoiceOver on; swipe right repeatedly; confirm order: pinned header → node-shipper → node-broker → node-carrier → node-dispatch → node-factoring → edges fromID/toID order → status timeline (combined element) → freight rows → integrity verdict block. Confirm VoiceOver double-tap on a node opens the sheet. Confirm pinch-zoom is suspended while VoiceOver is active. |
| iPad split layout split percentage + rotation behaviour | D-03 (PROJECT.md "iPad must render natively, not just scale") | Layout aesthetic is observational | On iPad Air: portrait → confirm single-column compact composition; rotate to landscape → confirm side-by-side ~60/40 split animates in; tap a node → confirm sheet renders as floating card (NOT full-height bottom sheet) |
| Skeleton-with-shimmer continuity | D-19 | Shimmer animation must visually match Phase 8 pattern (D-10) | Force a 2-second artificial fetch delay; open load detail; verify skeleton silhouette matches expected (pinned-header rectangle + 5 grey circles in role slots + grey edges + 3–4 grey body rows); verify horizontal shimmer sweep matches Phase 8's `SkeletonLoadRowCell` cadence |
| Dim-others treatment on compromised verdict | TRUST-05 (D-15) | The `0.6 → 1.0` non-implicated-node opacity ratio is an aesthetic decision visible only with eyes on it | Open a compromised-archetype fixture; confirm the flagged carrier node renders at full opacity while the other 4 nodes render at ~0.6 opacity |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verification or a Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without an automated verify
- [ ] Wave 0 covers all `❌ Wave 0` references in the Per-Task Verification Map
- [ ] No watch-mode flags (`-watch`, `--watch`) — every test run terminates
- [ ] Feedback latency < 90s (scoped) / < 8min (full serial lane)
- [ ] `nyquist_compliant: true` set in frontmatter after planner finalizes per-task assignments
- [ ] Manual verifications scripted into a single device-test checklist that ships with the phase summary

**Approval:** pending (planner-time signoff after PLAN.md generation)
