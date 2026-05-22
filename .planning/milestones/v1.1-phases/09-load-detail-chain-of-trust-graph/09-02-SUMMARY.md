---
phase: 09-load-detail-chain-of-trust-graph
plan: 02
subsystem: testing
tags:
  - testing
  - wave-0
  - snapshot
  - xcuitest
  - swift-testing
  - contract-gate
  - tdd
dependency_graph:
  requires:
    - Phase 7 LoadDetailEndpoint.Response (typed decode target)
    - Phase 7 ChainOfTrust + TrustNode (current Swift surface)
    - Phase 8 UIKitSnapshot.image(of:size:) + attach(_:name:to:)
    - Phase 8 LoadListViewModelTests (StateRecorder + RecordingLogger templates)
    - Phase 8 RoleLoadsTabSmokeTests (driveFullOTPFlow XCUITest helper)
  provides:
    - 12 empty test-file shells (XCTSkip-stubbed) — every Phase 9 plan can cite the locked `-only-testing:` path without resolution errors
    - 1 fully-implemented contract gate (LoadDetailFixtureContractTests.swift) — gates Plan 01's D-14 fixture re-authoring
    - The locked Wave 0 file inventory per 09-VALIDATION.md lines 67-81
  affects:
    - Phase 9 Plans 03-10 (every feature plan adds @Test / func test_* methods to these existing shells; never creates new files)
    - Phase 9 Plan 01 (RED-state contract gate forces fixture + ChainOfTrust.swift mutation to land together)
tech_stack:
  added:
    - none
  patterns:
    - "XCTSkip-stubbed shell methods compile + report `skipped` (exit code 0)"
    - "Raw-JSON-based contract gate via JSONSerialization — compiles against both pre- and post-Plan-01 ChainOfTrust surfaces"
    - "Swift Testing @Suite(.serialized) for fixture-touching suites (LoadDetailViewModelTests, LoadDetailFixtureContractTests)"
    - "XCTest for snapshot/gesture/a11y suites (UIKitSnapshot needs XCTestCase.add(_:))"
    - "XCUITest (no @testable) for end-to-end smoke flow"
key_files:
  created:
    - validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests.swift
    - validationLedgerTests/Loads/Snapshot/TrustNodeViewSnapshotTests.swift
    - validationLedgerTests/Loads/Snapshot/ChainIntegrityBannerViewSnapshotTests.swift
    - validationLedgerTests/Loads/Snapshot/StatusTimelineViewSnapshotTests.swift
    - validationLedgerTests/Loads/Snapshot/LoadDetailSkeletonViewSnapshotTests.swift
    - validationLedgerTests/Loads/Snapshot/VerificationBasisSheetViewControllerSnapshotTests.swift
    - validationLedgerTests/Loads/Snapshot/HandoffDetailSheetViewControllerSnapshotTests.swift
    - validationLedgerTests/Loads/TrustNodeViewGestureTests.swift
    - validationLedgerTests/Loads/TrustGraphViewGestureTests.swift
    - validationLedgerTests/Loads/TrustGraphViewAccessibilityTests.swift
    - validationLedgerTests/Loads/LoadDetailViewModelTests.swift
    - validationLedgerUITests/Loads/LoadDetailFlowTests.swift
    - validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests.swift
  modified: []
decisions:
  - "Contract test uses raw-JSON inspection (JSONSerialization + String.contains) — NOT typed Swift property access on `priorRelationships` — so the file compiles against the current ChainOfTrust.swift surface in Plan 02's worktree while still failing loud against the wire shape Plan 01 must produce. Raw-JSON gating is also a strictly stronger contract gate than typed access (it catches a regression even if a legacy Swift alias is accidentally kept)."
  - "Every shell test body is `throw XCTSkip(...)` — XCTest reports `skipped` with exit code 0, so the scoped `-only-testing:` invocations cited in 09-VALIDATION.md Per-Task Verification Map all resolve."
  - "LoadDetailViewModelTests Swift Testing methods are empty (no body) instead of XCTSkip-bearing — `@Test` empty-body methods report `passed` (Swift Testing has no skip-stub primitive equivalent to XCTSkip in the same one-liner form). Plan 03 will replace each body with real assertions."
metrics:
  duration: ~35min
  completed: 2026-05-20
---

# Phase 9 Plan 02: Wave 0 Test File Shells + LoadDetailFixtureContractTests Summary

## One-liner

Ship every test file Phase 9 Plans 03-10 will extend: 12 XCTSkip-stubbed shells (snapshot + gesture + a11y + ViewModel + XCUITest) plus the fully-implemented `LoadDetailFixtureContractTests.swift` D-14 contract gate that intentionally fails RED in Plan 02's worktree until Plan 01's fixture re-authoring merges.

## What Shipped

### Task 1 — 12 Wave 0 test-file shells (commit `14bf29d`)

Every file in `<files_modified>` lines 8-20 of `09-02-PLAN.md`, all compiling against the current production surface, every method body either `throw XCTSkip(...)` (XCTest files) or empty (Swift Testing). Each shell ships with a file-header doc-block citing the VALIDATION.md Wave 0 line + the closest in-repo analog per PATTERNS.md.

| # | Shell path | Method signatures | Populated by |
|---|---|---|---|
| 1 | `validationLedgerTests/Loads/Snapshot/TrustGraphViewSnapshotTests.swift` | 12 (3 verdicts × 2 devices × 2 Dynamic Type sizes) | **Plan 06** |
| 2 | `validationLedgerTests/Loads/Snapshot/TrustNodeViewSnapshotTests.swift` | 4 (verifiedCarrier, flaggedCarrier compromised, pendingBroker, unverifiedShipper) | **Plan 06** |
| 3 | `validationLedgerTests/Loads/Snapshot/ChainIntegrityBannerViewSnapshotTests.swift` | 3 (caution snapshot, compromised snapshot, clean isHidden unit test) | **Plan 09** |
| 4 | `validationLedgerTests/Loads/Snapshot/StatusTimelineViewSnapshotTests.swift` | 7 (6 lifecycle states + cancelled terminal card) | **Plan 05** |
| 5 | `validationLedgerTests/Loads/Snapshot/LoadDetailSkeletonViewSnapshotTests.swift` | 3 (iPhone silhouette, iPad split silhouette, shimmer re-attach on layoutSubviews — Pitfall 1) | **Plan 04** |
| 6 | `validationLedgerTests/Loads/Snapshot/VerificationBasisSheetViewControllerSnapshotTests.swift` | 4 (cleanCarrier, cleanShipper, cautionImplicatedBroker, compromisedImplicatedCarrier) | **Plan 07** |
| 7 | `validationLedgerTests/Loads/Snapshot/HandoffDetailSheetViewControllerSnapshotTests.swift` | 3 (cleanEdge, cautionImplicatedEdge, compromisedImplicatedEdge) | **Plan 08** |
| 8 | `validationLedgerTests/Loads/TrustNodeViewGestureTests.swift` | 3 (singleTap.require(toFail: doubleTap); doubleTap NOT opens sheet; singleTap opens sheet after fail window) | **Plan 06** |
| 9 | `validationLedgerTests/Loads/TrustGraphViewGestureTests.swift` | 4 (innerScroll minimumNumberOfTouches==2; doubleTapOnNode zoom 1.8; doubleTapOnEmpty resets; VoiceOver disables pinch) | **Plan 06** |
| 10 | `validationLedgerTests/Loads/TrustGraphViewAccessibilityTests.swift` | 6 (isAccessibilityElement==false; accessibilityElements ordered; node label template; implicated suffix; VoiceOver disables zoom; Reduce Motion suspends pulse) | **Plan 06** |
| 11 | `validationLedgerTests/Loads/LoadDetailViewModelTests.swift` | 4 Swift Testing `@Test` methods (loadingToLoaded, loadingToError, cancelAndReplace BL-01, zero-PII log) — `@Suite(.serialized)` | **Plan 03** |
| 12 | `validationLedgerUITests/Loads/LoadDetailFlowTests.swift` | 5 (rowTap pushesDetail; nodeTap opens sheet; edgeTap opens sheet; compromised banner a11y label; single-finger scroll propagates) | **Plan 03** + **Plan 10** |

**Verify command run** — `xcodebuild test -only-testing:validationLedgerTests/{each Loads shell suite + LoadDetailFlowTests}` — **`** TEST SUCCEEDED **`** with `Executed 49 tests, with 49 tests skipped` (the 11 XCTest shells) + 4 Swift Testing `@Test` passes (the empty Swift Testing methods report `passed`).

**XCTSkip count by file:**

| File | XCTSkip count |
|---|---:|
| TrustGraphViewSnapshotTests.swift | 12 |
| TrustNodeViewSnapshotTests.swift | 4 |
| ChainIntegrityBannerViewSnapshotTests.swift | 3 |
| StatusTimelineViewSnapshotTests.swift | 7 |
| LoadDetailSkeletonViewSnapshotTests.swift | 3 |
| VerificationBasisSheetViewControllerSnapshotTests.swift | 4 |
| HandoffDetailSheetViewControllerSnapshotTests.swift | 3 |
| TrustNodeViewGestureTests.swift | 3 |
| TrustGraphViewGestureTests.swift | 4 |
| TrustGraphViewAccessibilityTests.swift | 6 |
| LoadDetailViewModelTests.swift | 0 (Swift Testing — empty `@Test` bodies pass) |
| LoadDetailFlowTests.swift (XCUITest) | 5 |
| **LoadDetailFixtureContractTests.swift** | **0 (NOT a stub — fully implemented)** |

### Task 2 — `LoadDetailFixtureContractTests.swift` D-14 contract gate (commit `ac44723`)

Fully-implemented Swift Testing suite — 7 `@Test` methods, `.serialized`, zero `XCTSkip`. Implementation deliberately uses raw-JSON inspection via `JSONSerialization` + `String.contains(_:)` so the file compiles against the **current** `ChainOfTrust.swift` surface (pre-Plan-01 mutation) while still failing loud against the wire shape Plan 01 must produce. The single `decoder.decode(LoadDetailEndpoint.Response.self, from:)` call in Test 1 wires the typed contract gate end-to-end.

| `@Test` method | Archetype gated | Plan-01 expectation |
|---|---|---|
| `everyFixtureDecodesUnderDefaultDecoder()` | All 12 fixtures (Plan 01 `ChainOfTrust.swift` mutation + fixture re-authoring) | every fixture decodes successfully through `APIClient.defaultDecoder()` as `LoadDetailEndpoint.Response` |
| `legacyWireKeyAbsentFromEveryFixture()` | D-12 negative gate (the literal `prior_relationship_count` key removed) | every fixture's raw JSON has zero occurrences of the legacy snake_case wire key |
| `everyTrustNodeCarriesPriorRelationshipsKey()` | D-14 positive presence gate | every TrustNode in every fixture has a `prior_relationships` JSON array key (possibly empty) |
| `cleanBaselineCarrierCarriesFivePlusPriorRelationships()` | D-14 clean rule (VL-1001) | the carrier node carries 5+ priorRelationships entries |
| `doubleBrokerArchetypeFlaggedCarrierCarriesTwoOrFewerPriorRelationships()` | D-14 double-broker rule (VL-1009) | the flagged carrier carries ≤ 2 priorRelationships |
| `chameleonArchetypeFlaggedCarrierCarriesEmptyPriorRelationships()` | D-14 chameleon rule (VL-1010) | the flagged carrier carries EXACTLY 0 priorRelationships (the marquee fraud signal) |
| `factoringFraudArchetypeFactoringNodeCarriesNonEmptyPriorRelationships()` | D-14 factoring-fraud rule (VL-1011) | the factoring node carries > 0 priorRelationships (curated collusion pattern) |

**Verify command run** — `xcodebuild test -only-testing:validationLedgerTests/LoadDetailFixtureContractTests` — **`** TEST FAILED **`** (expected RED state).

Failure breakdown at RED commit:
- Test 1 (decode) passed (pre-Plan-01 fixtures still match the pre-Plan-01 Swift surface).
- Test 2 (negative gate) failed 12 times — one issue per fixture (every fixture still carries the legacy key).
- Test 3 (positive gate) failed 24 times — every TrustNode in every fixture is missing `prior_relationships`.
- Tests 4-7 (archetype rules) recorded Issues because the relevant nodes have no matching `prior_relationships` array.

**This RED is the intentional cross-plan gate** — Plan 01 brings the GREEN state by merging in the same wave (re-authored fixtures + the `ChainOfTrust.swift` mutation).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Bookkeeping] Reduced `prior_relationship_count` occurrences in `LoadDetailFixtureContractTests.swift` from 5 → 1**

- **Found during:** Task 2 source-level acceptance criteria audit.
- **Issue:** First-draft file had the literal legacy key string in 5 places (header comment, MARK comment, @Test name, the `String.contains(_:)` argument, the failure-message string). The plan's acceptance criterion specifies `grep -c 'prior_relationship_count' ... returns 1` — exactly one occurrence (the actual gate's `String.contains` argument).
- **Fix:** Removed the literal key string from the file header, MARK comment, @Test name, and failure-message string. Replaced narrative references with the hyphenated phrase `prior-relationship-count` (which has no `_count` suffix and is grep-distinct) or with generic phrases like "legacy wire key". The `!rawJSON.contains("prior_relationship_count")` line is the SOLE occurrence — the gate behaviour is unchanged.
- **Files modified:** `validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests.swift`
- **Commit:** `ac44723` (the same RED commit; the fix landed before the commit because the audit ran during file authoring, not after a commit).

No other deviations — plan executed exactly as written.

## Known Stubs

The 12 Wave 0 shells are stubs by design — they exist to give Plans 03-10 a stable test-file inventory that scoped `-only-testing:` commands can address from day one. Plan 02's `must_haves.truths` line 2 explicitly states:

> "Every feature plan (03-09) has an existing test file to extend rather than create — Wave 0 ships the empty XCTestCase shells so per-task verification commands resolve from day one"

Each shell file's header comment names the downstream plan that fills it in. The shells are NOT a contract-gating debt; they are infrastructure scaffolding. **Not flagged as a stub-risk** — Plans 03-10 own the `@Test` / `func test_*` insertion work.

## Self-Check: PASSED

- All 13 source files exist at their declared paths (verified by `ls`).
- Both commits exist in git history (`14bf29d` Task 1, `ac44723` Task 2).
- `validationLedger.xcodeproj/project.pbxproj` is byte-identical (no manual file refs; `PBXFileSystemSynchronizedRootGroup` auto-discovers).
- `grep -c 'import SnapshotTesting' validationLedgerTests/Loads/Snapshot/*.swift` returns 0 (negative gate — Phase 8 D-09 SwiftPM lock honoured).
- `grep -c '@testable import validationLedger' validationLedgerUITests/Loads/LoadDetailFlowTests.swift` returns 0 (UI test correctly does NOT use `@testable`).
- `grep -c '@Test' validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests.swift` returns 7 (≥ 7 — pass).
- `grep -c '@Suite.*\.serialized' validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests.swift` returns 1 (pass).
- `grep -c 'XCTSkip' validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests.swift` returns 0 (negative gate — contract test is NOT a stub).
- `grep -c 'prior_relationship_count' validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests.swift` returns 1 (the single `String.contains(_:)` argument — pass).
- `grep -c 'priorRelationships' validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests.swift` returns 19 (≥ 4 — pass).
- Scoped `xcodebuild test` runs:
  - 11 `Loads/{Snapshot,*GestureTests,*AccessibilityTests,LoadDetailViewModelTests}` shells + the LoadDetailFlowTests UI shell → `** TEST SUCCEEDED **`, exit 0 (49 skipped + 4 Swift Testing passes).
  - `LoadDetailFixtureContractTests` → `** TEST FAILED **` exit (the intentional RED gate; passes after Plan 01 merge).

## Open Questions

1. **PBXFileSystemSynchronizedRootGroup auto-discovery on the simulator-lane CI** — the project uses synchronized file groups (`grep -c PBXFileSystemSynchronizedRootGroup validationLedger.xcodeproj/project.pbxproj` returns 6), and `xcodebuild build-for-testing` on the local iPhone 17 simulator picked up every new file without an explicit "Add Files" step. The new `validationLedgerTests/Loads/Snapshot/` subfolder already existed (Phase 8 created it), but the contract test introduces a Swift file in `validationLedgerTests/Networking/Fixtures/` for the first time (previously Fixtures held only `.json`). The local lane works; the device-CI lane (`docs/ci.md`'s physical-device runner) is unverified for this case — flagging as a follow-up check for whichever Wave 1 plan first runs CI against `main` after the wave merge. **Likely fine** because the same group covers all swift sources under `validationLedgerTests/`, but worth a single `git push` smoke check before relying on Wave 1+ green CI.

2. **Order of merge for cross-plan gating** — Plan 02's `LoadDetailFixtureContractTests` will FAIL on `main` after Plan 02 alone merges (the orchestrator interleaves wave merges). If Plan 02 merges before Plan 01, the `main` branch ships RED for whatever period elapses until Plan 01 merges. Recommendation: the wave orchestrator should merge Plan 01 first OR atomically batch both wave-1 plans into a single merge commit. Not a Plan 02 deliverable; documenting for the orchestrator's awareness.
