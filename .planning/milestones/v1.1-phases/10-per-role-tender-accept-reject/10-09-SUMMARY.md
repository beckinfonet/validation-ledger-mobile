---
phase: 10-per-role-tender-accept-reject
plan: 09
subsystem: testing
tags: [snapshot, xctest, uikit, regression-gate, action-bar, tender-sheet, toast-banner]

# Dependency graph
requires:
  - phase: 10-04
    provides: LoadActionsView (the view under test in the 65-cell matrix)
  - phase: 10-06
    provides: TenderSheetViewController + TenderSheetCarrierRowView (the sheet under test)
  - phase: 10-07
    provides: LoadActionToastBannerView (the toast under test)
  - phase: 10-08
    provides: predictor + rollback wiring (chain overlay sibling — verified-elsewhere)
provides:
  - 65-cell (Role × LoadStatus) action-region regression gate (UI-SPEC line 537)
  - 5-cell tenderEligibility-disabled visual lock (ACTION-04 / ACTION-07)
  - 2-cell empty-state caption locks (factoring view-only + terminal-delivered)
  - 1-cell Pitfall 5 "in transit" no-underscore visual lock
  - 3-cell situational locks (in-flight tender, future respond-by, past-due respond-by destructive color)
  - 4-cell tender sheet snapshot suite (default / verified-selected / mixed / send-in-flight)
  - 6-cell toast banner snapshot suite (one per LOCKED per-action error key)
affects: [phase-10 future plans, phase-11 onward — every UI change to LoadActionsView / TenderSheetViewController / LoadActionToastBannerView surfaces as a snapshot diff and demands an eyeball-reviewed re-record]

# Tech tracking
tech-stack:
  added: []  # Zero new SwiftPM dependencies — UIKitSnapshot is in-house, baseline I/O uses Foundation only.
  patterns:
    - "PNG-on-disk baseline + XCTAttachment dual-write: each snapshot helper attaches the rendered image to the XCTest result bundle AND writes a PNG to validationLedgerTests/__Snapshots__/<suite>/. RECORD_SNAPSHOTS=YES env var rewrites baselines; default run asserts baseline exists + non-empty. Structural XCTAssertions are the actual gate; the PNG is for human eyeball-review per Phase 9.1 D-05 precedent."
    - "Walk-up baseline directory resolver: #filePath → ../.. → __Snapshots__/<name>/. SNAPSHOT_BASELINE_DIR env var is the CI escape hatch."
    - "Fresh-allocation per cell: every snapshot test method allocates a new LoadActionsView() / TenderSheetViewController() — never reused across iterations (Pitfall 7 lock)."

key-files:
  created:
    - "validationLedgerTests/Loads/Snapshot/LoadActionBarSnapshotMatrixTests.swift (8 test methods, 76 baselines)"
    - "validationLedgerTests/Loads/Snapshot/TenderSheetViewControllerSnapshotTests.swift (4 test methods, 4 baselines)"
    - "validationLedgerTests/Loads/Snapshot/LoadActionToastBannerViewSnapshotTests.swift (6 test methods, 6 baselines)"
    - "validationLedgerTests/__Snapshots__/LoadActionBarSnapshotMatrix/ (76 PNG baselines + README.md)"
    - "validationLedgerTests/__Snapshots__/TenderSheetViewControllerSnapshot/ (4 PNG baselines)"
    - "validationLedgerTests/__Snapshots__/LoadActionToastBannerViewSnapshot/ (6 PNG baselines)"
  modified: []

key-decisions:
  - "Stay in-house — no swift-snapshot-testing dependency. The project's UIKitSnapshot helper (Phase 8 in-house) attaches images to the XCTest result bundle; this plan extends the contract by also writing PNGs to __Snapshots__/ on disk. A future pixel-diff library would require CLAUDE.md dependency approval; the structural XCTAssertions in every test method are the actual regression gate."
  - "RECORD-then-VERIFY in a single plan run — both passes execute the same structural XCTAssertions; the env-flag toggle only governs whether the on-disk PNG is rewritten. This keeps the gate atomic per the plan's intent (no temporal split between record and verify)."
  - "Test 3 / 4 / 5 of LoadActionBarSnapshotMatrixTests pass `actions: []` directly (rather than deriving via RoleLoadPolicy) — the empty-caption visual lock is the regression guard, not the policy-table delegation. The literal `[]` argument makes the test's intent explicit and matches the plan's behavior text verbatim."
  - "TenderSheetViewControllerSnapshotTests Test 4 uses a CheckedContinuation parked on a static var to capture the in-flight visual state — the `onSend` closure is async and Sendable, which prevents capturing the XCTestCase instance (non-Sendable). The parked continuation resolves after the snapshot is captured."

patterns-established:
  - "Phase 10 PNG-on-disk baseline workflow: every new snapshot suite under Loads/Snapshot/ that wants on-disk baselines copies the `baselineComparison(image:name:)` + `baselineDirectoryURL()` pair from this plan. Future plans add a new __Snapshots__/<suite>/ subdirectory and the same pair of helpers — kept inline in the test file to avoid a cross-suite shared dependency that could drift."
  - "MainActor-isolated XCTestCase for views with @MainActor configure(...): adding `@MainActor` to the test class is the project's idiom for testing main-actor-isolated UIKit views without per-method ceremony (Phase 10 LoadActionToastBannerView is the first such surface)."

requirements-completed:
  - ACTION-01
  - ACTION-04
  - ACTION-05
  - ACTION-07
  - ACTION-09

# Metrics
duration: 15min
completed: 2026-05-21
---

# Phase 10 Plan 09: 82-Baseline Snapshot Regression Gate Summary

**Landed the 65-cell (Role × LoadStatus) action-region snapshot matrix plus the 4-scenario tender sheet suite, 6-scenario toast banner suite, and 7 single-cell situational locks — 86 PNG baselines committed under `validationLedgerTests/__Snapshots__/` with both RECORD and VERIFY passes green in a single plan run, completing the VALIDATION.md § 65-Cell Snapshot Matrix Wave 4 sign-off.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-05-21T17:28:50Z
- **Completed:** 2026-05-21T17:44:12Z (approximate)
- **Tasks:** 2 of 2 complete
- **Files modified:** 3 new test files + 3 new baseline directories (86 PNGs + 1 README)

## Accomplishments

- **Phase 10 regression gate is live.** Any future plan that accidentally changes a button title, a destructive tint, the empty-state caption format, the tenderEligibility-disabled visual, the visible-but-disabled carrier row treatment, or a toast banner copy now produces a structural XCTAssertion failure AND a baseline-PNG diff for eyeball-review.
- **76 / 4 / 6 baselines** committed across the three new snapshot suites — every (Role × LoadStatus) cell of the policy table has a baseline, every LOCKED per-action error key has a baseline, and the four sheet states (default / verified-selected / mixed / send-in-flight) have baselines.
- **All 16 Phase 7-10 snapshot suites still green** in the integrated 102-test scoped run — Phase 8/9/9.1 baselines untouched.
- **Zero new SwiftPM dependencies** — UIKitSnapshot remains the only snapshot mechanism; baseline I/O uses Foundation.

## Task Commits

Each task was committed atomically:

1. **Task 1: 65-cell matrix + variants** — `77359fc` (test) — 76 baselines, RECORD + VERIFY both green
2. **Task 2: Tender sheet + toast banner suites** — `2466857` (test) — 10 baselines, RECORD + VERIFY both green

## Files Created

- `validationLedgerTests/Loads/Snapshot/LoadActionBarSnapshotMatrixTests.swift` — XCTest class, 8 test methods, 76 baselines:
  - `test_actionRegion_matrix_5roles_x_13statuses` — 65 cells (ACTION-09 regression gate)
  - `test_actionRegion_tenderEligibilityDisabled_5variants` — 5 cells (ACTION-04 / ACTION-07)
  - `test_actionRegion_emptyStateCaption_factoring` — 1 cell (UI-SPEC line 303)
  - `test_actionRegion_emptyStateCaption_terminalDelivered` — 1 cell (UI-SPEC line 304)
  - `test_actionRegion_emptyStateCaption_terminalInTransit_noUnderscore` — 1 cell (Pitfall 5 anchor)
  - `test_actionRegion_inFlight_tenderTapped` — 1 cell (UI-SPEC line 548)
  - `test_actionRegion_respondByLabel_carrierTendered_futureDeadline` — 1 cell (UI-SPEC line 323)
  - `test_actionRegion_respondByLabel_pastDue_destructiveColor` — 1 cell (UI-SPEC line 324)
- `validationLedgerTests/Loads/Snapshot/TenderSheetViewControllerSnapshotTests.swift` — XCTest class, 4 test methods, 4 baselines:
  - `test_sheet_defaultState_noCarrierSelected` (default chip = "1 day", helper = "Pick a carrier to send.")
  - `test_sheet_verifiedCarrierSelected_sendEnabled` (Pitfall 8 alpha-toggle lock)
  - `test_sheet_mixedDirectory_visibleButDisabledRows` (T-10-04 CRITICAL platform-thesis surface)
  - `test_sheet_sendInFlight_spinnerOverlay` (UI-SPEC line 454 — sheet stays visible, spinner overlays Send)
- `validationLedgerTests/Loads/Snapshot/LoadActionToastBannerViewSnapshotTests.swift` — `@MainActor` XCTest class, 6 test methods, 6 baselines:
  - One method per LoadAction case; each asserts `banner.accessibilityLabel == expectedResolvedCopy` so a key-vs-string regression surfaces
- `validationLedgerTests/__Snapshots__/LoadActionBarSnapshotMatrix/` — 76 PNG baselines + `README.md` (re-record workflow)
- `validationLedgerTests/__Snapshots__/TenderSheetViewControllerSnapshot/` — 4 PNG baselines
- `validationLedgerTests/__Snapshots__/LoadActionToastBannerViewSnapshot/` — 6 PNG baselines

## Decisions Made

- **In-house baseline workflow over a pixel-diff library.** The project's `UIKitSnapshot` helper (Phase 8) attaches images for XCTest result-bundle triage; this plan extends the pattern with an on-disk PNG + structural XCTAssertions. A pixel-diff library (`swift-snapshot-testing`) is NOT on the CLAUDE.md pre-approved shortlist; structural assertions plus eyeball review is the precedent set by Phase 9.1 D-05.
- **Both RECORD and VERIFY in the same plan run.** Per the plan's intent (no temporal split between record and verify), both passes ran in this plan; the orchestrator's automated verify is the VERIFY pass against the freshly-recorded baselines. A baseline diff in a future plan triggers an eyeball-reviewed re-record commit in the same PR as the source change.
- **`actions: []` literal in empty-state tests.** Tests 3 / 4 / 5 of `LoadActionBarSnapshotMatrixTests` pass `actions: []` directly rather than deriving via `RoleLoadPolicy.availableActions(for:in:)`. The regression guard is the empty-caption visual rendering — not the policy-table delegation (which the 65-cell matrix already covers). The literal argument matches the plan's behavior text verbatim and avoids confusion with the broker/`.inTransit` cell, where `RoleLoadPolicy` returns `[.cancel]` (not empty).
- **Static `CheckedContinuation` parking for Test 4.** `TenderSheetViewControllerSnapshotTests.test_sheet_sendInFlight_spinnerOverlay` uses a class-level `static var parkedContinuation` because the `onSend` closure is `@Sendable async` and cannot capture a `var` on the non-Sendable XCTestCase. The test parks the continuation inside `onSend`, captures the in-flight visual state on the main thread, then resumes the continuation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Tooling Block] iPhone 16 simulator not present; substituted iPhone 17**
- **Found during:** Task 1 (first RECORD-pass invocation)
- **Issue:** The plan's `<automated>` block specifies `iPhone 16`, but `xcodebuild -showdestinations` lists only `iPhone 16e` / `iPhone 17` / `iPhone 17 Pro` / etc. on this machine. iPhone 16 is not installed.
- **Fix:** Used `iPhone 17` — the project-pinned device per the `ios-test-suite-pitfalls` project memory and the historic Phase 8 / 9 snapshot-recording convention.
- **Files modified:** none (xcodebuild flag only; the plan text remains)
- **Verification:** RECORD and VERIFY passes both green on iPhone 17 simulator (iOS 26.3.1).

**2. [Rule 3 - Compile Block] `@MainActor` required on `LoadActionToastBannerViewSnapshotTests`**
- **Found during:** Task 2 (first RECORD-pass invocation for the toast suite)
- **Issue:** `LoadActionToastBannerView.configure(text:)` is `@MainActor`; calling it from a synchronous nonisolated context (an XCTestCase method) is a Swift 5.9+ concurrency error. Other Phase 10 snapshot tests (`LoadActionBarSnapshotMatrixTests`) work without the annotation because `LoadActionsView.configure(...)` is not main-actor-isolated.
- **Fix:** Added `@MainActor` to the `LoadActionToastBannerViewSnapshotTests` class declaration. All 6 test methods inherit the isolation cleanly.
- **Files modified:** `validationLedgerTests/Loads/Snapshot/LoadActionToastBannerViewSnapshotTests.swift`
- **Verification:** Build green; all 6 tests pass in both RECORD and VERIFY passes.
- **Committed in:** `2466857` (part of Task 2 commit — single test-file landing)

**3. [Rule 1 - Test Logic Bug] Test 5 originally failed (`actions` derived from policy)**
- **Found during:** Task 1 RED → first run
- **Issue:** Test 5 (`test_actionRegion_emptyStateCaption_terminalInTransit_noUnderscore`) first derived `actions` via `RoleLoadPolicy.availableActions(for: .broker, in: load(.inTransit))`, which returns `[.cancel]` (not empty) — so `LoadActionsView` rendered the `.cancel` button instead of the empty caption, and the structural assertion `caption.contains("in transit")` failed.
- **Fix:** Changed Tests 3 / 4 / 5 to pass `actions: []` literally — matches the plan's behavior text ("configure with `actions: []`") and makes the test's intent explicit. Documented in the test file's per-test header that the literal `[]` argument is the empty-state visual lock, not a policy-derivation test.
- **Files modified:** `validationLedgerTests/Loads/Snapshot/LoadActionBarSnapshotMatrixTests.swift`
- **Verification:** All 8 tests of Task 1 green on second run.

## Auth Gates

None. All work was offline — no network, no API authentication required.

## Verification

- **Per-task automated verify** (per the plan's `<verify>` blocks):
  - Task 1 RECORD pass: green, 76 PNGs written.
  - Task 1 VERIFY pass: green.
  - Task 2 RECORD pass: green, 10 PNGs written (4 sheet + 6 toast).
  - Task 2 VERIFY pass: green.
- **Plan-level integrated verify** (per the plan's `<verification>` block): all 16 snapshot suites green in the scoped re-run (102 tests passed):
  - `ChainIntegrityBannerViewSnapshotTests`: 3 tests
  - `ChainOfVouchesViewSnapshotTests`: 13 tests
  - `EveryoneOnLoadStripViewSnapshotTests`: 10 tests
  - `HandoffDetailSheetViewControllerSnapshotTests`: 4 tests
  - `LoadActionBarSnapshotMatrixTests`: 8 tests (new)
  - `LoadActionToastBannerViewSnapshotTests`: 6 tests (new)
  - `LoadDetailSkeletonViewSnapshotTests`: 5 tests
  - `LoadRowCellSnapshotTests`: 7 tests
  - `LoadStatusBadgeViewSnapshotTests`: 5 tests
  - `SkeletonLoadRowCellSnapshotTests`: 3 tests
  - `StatusTimelineViewSnapshotTests`: 8 tests
  - `TenderSheetViewControllerSnapshotTests`: 4 tests (new)
  - `TrustGraphViewSnapshotTests`: 12 tests
  - `TrustNodeViewSnapshotTests`: 4 tests
  - `VerificationBadgeViewSnapshotTests`: 6 tests
  - `VerificationBasisSheetViewControllerSnapshotTests`: 4 tests
- **Baseline counts** (`ls __Snapshots__/<suite>/*.png | wc -l`):
  - `LoadActionBarSnapshotMatrix/`: 76 (≥ 70 threshold)
  - `TenderSheetViewControllerSnapshot/`: 4
  - `LoadActionToastBannerViewSnapshot/`: 6
  - **Total: 86 PNG baselines**
- **Source assertions** (Task 1 done-list):
  - `grep -c 'for role in Role.allCases'` → 2 (≥ 1 ✓)
  - `grep -c 'LoadActionsView()'` → 10 (≥ 8 ✓)
- **Source assertions** (Task 2 done-list):
  - `grep -c 'sheetCanvasSize = CGSize(width: 393, height: 500)'` → 1 ✓ (PATTERNS.md §14 canvas-size convention preserved)
  - `grep -c 'toast-'` → 8 ≥ 6 ✓ (one attachment name per LOCKED error key)

## Known Stubs

None. All views under test are real production surfaces from prior waves.

## Threat Flags

None. The new snapshot suites do not introduce new threat surfaces; the baselines themselves are PII-free synthetic data (per the `Load.fixture` factory's synthetic strings and the Plan 05 `tender-carrier-directory.json` fixture which has its own zero-PII discipline guard in `CarrierDirectoryDecodeTests` Test 5).

## Self-Check: PASSED

- Created files exist on disk:
  - `validationLedgerTests/Loads/Snapshot/LoadActionBarSnapshotMatrixTests.swift` FOUND
  - `validationLedgerTests/Loads/Snapshot/TenderSheetViewControllerSnapshotTests.swift` FOUND
  - `validationLedgerTests/Loads/Snapshot/LoadActionToastBannerViewSnapshotTests.swift` FOUND
  - `validationLedgerTests/__Snapshots__/LoadActionBarSnapshotMatrix/README.md` FOUND
  - All 76 + 4 + 6 = 86 PNG baselines FOUND
- Commits exist on the worktree branch:
  - `77359fc` FOUND (Task 1)
  - `2466857` FOUND (Task 2)
- Plan-level acceptance criteria — all met:
  - 65-cell (Role × LoadStatus) baselines: 65 of 76 ✓
  - 5-cell tenderEligibility-disabled variant: 5 ✓
  - 2 empty-state caption baselines (+ Pitfall 5 lock): 3 ✓
  - 4 tender sheet baselines: 4 ✓
  - 6 toast banner baselines: 6 ✓
  - `LoadActionBarSnapshotMatrixTests/test_actionRegion_matrix_5roles_x_13statuses` exists and green: ✓
  - Zero PII / real-world party-carrier names in any baseline: ✓
  - Baselines directory committed to git: ✓
