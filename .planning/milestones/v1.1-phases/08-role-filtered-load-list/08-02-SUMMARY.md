---
phase: 08-role-filtered-load-list
plan: 02
subsystem: ui-components
tags: [verification-badge, status-badge, trust-02, fail-closed, snapshot-tests, dynamic-type, xctest]

# Dependency graph
requires:
  - phase: 08-role-filtered-load-list
    plan: 01
    provides: "LoadListItem envelope, displayedCounterparty: TrustNode?, UIKitSnapshot helper"
provides:
  - "VerificationBadgeView (TRUST-02 reusable 4-state pill) — public surface { init(frame:), configure(state:), configure(stateOrNil:), layoutSubviews }"
  - "LoadStatusBadgeView (13-state informational pill) — public surface { init(frame:), configure(status:), layoutSubviews }"
  - "Wave-1 XCTest snapshot precedent (XCTest, NOT Swift Testing) for Plans 04/05 to follow"
  - "validationLedger/UI/Components/ as the canonical reusable-view-component directory (NEW)"
  - "validationLedgerTests/Loads/Snapshot/ as the canonical snapshot-test directory (NEW)"

affects:
  - "08-04-loadrowcell — composes both badges, mirrors their geometry"
  - "09-* (chain-of-trust graph nodes — reuse VerificationBadgeView per TRUST-02)"
  - "10-* (disabled-tender inline reason — reuse VerificationBadgeView)"

# Tech tracking
tech-stack:
  added: []  # zero new SwiftPM dependencies (CLAUDE.md STACK-04)
  patterns:
    - "Render-from-input UIView component (no Combine, no async, no internal state beyond last configure())"
    - "Pill geometry with layoutSubviews-recomputed cornerRadius = bounds.height/2 (Pitfall 8 — Dynamic Type lock)"
    - "Per-state NSLocalizedString discipline on BOTH label.text AND accessibilityLabel"
    - "Fail-closed nil overload (configure(stateOrNil:)) — security primitive, not a convenience"
    - "Test-only private extension on a production view (statusBadgeLabelText / statusBadgeAttributedText) to assert rendered text without leaking the private `label` ivar"
    - "XCTest (not Swift Testing) for snapshot suites — XCTAttachment requires XCTestCase.add(_:)"

key-files:
  created:
    - "validationLedger/UI/Components/VerificationBadgeView.swift"
    - "validationLedger/UI/Components/LoadStatusBadgeView.swift"
    - "validationLedgerTests/Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift"
    - "validationLedgerTests/Loads/Snapshot/LoadStatusBadgeViewSnapshotTests.swift"
  modified: []

key-decisions:
  - "XCTest (not Swift Testing) for snapshot suites — UIKitSnapshot.attach requires XCTestCase.add(_:); Plans 04/05 follow precedent."
  - "LoadStatusBadgeView is label-only (no SF Symbol slot) per UI-SPEC §Color status table — VerificationBadgeView's icon slot is the visual differentiator."
  - "Documented exceptions to 'DS tokens only' policy lock the locked color ramp: .systemYellow on .pending, .tertiarySystemFill / .systemGray5 / .systemGray6 as system-managed neutrals."
  - "Strikethrough rendering (terminal-error tones) uses NSAttributedString.strikethroughStyle — and the implementation MUST NOT assign 'label.text = nil' after 'label.attributedText = ...' because UILabel's text-setter (even to nil) strips attributedText (Rule 1 bug discovered + fixed in this plan)."

requirements-completed: [TRUST-02, LOAD-04]

threat-mitigations:
  - id: T-08-05
    status: mitigated
    where: "Both badge views are PII-FREE (pure render-from-input; accessibilityLabel uses ONLY localized strings; no party names, no IDs, no load numbers)."
  - id: T-08-06
    status: mitigated
    where: "VerificationBadgeView.accessibilityLabel for .unverified / nil paths is the literal 'Counterparty not verified'. Two snapshot tests (test_unverifiedBadgeRendersUnverifiedVisuals + test_nilCounterpartyRendersUnverifiedFailClosed) assert the 'not' prefix discipline; the substring 'verified' without the 'not' prefix is the VoiceOver-trust-leak the threat model forbids."

# Metrics
duration: ~11min
completed: 2026-05-20
---

# Phase 8 Plan 02: VerificationBadgeView + LoadStatusBadgeView Summary

**Two reusable view-layer components landed under `validationLedger/UI/Components/` with full snapshot test coverage (11/11 green) — the TRUST-02 4-state verification pill (with the D-03 fail-closed nil overload) and the 13-state informational status pill (with the locked 3-tone ramp + terminal-error strikethrough). One Rule 1 bug (UILabel text-setter silently strips attributedText) was discovered via Task 3's strikethrough test and fixed inline.**

## Performance

- **Duration:** ~11 min (3 atomic commits + verification)
- **Started:** 2026-05-20T04:24Z (worktree spawn)
- **Completed:** 2026-05-20T04:35Z
- **Tasks:** 3/3 complete
- **Files created:** 4 (2 component sources + 2 snapshot test suites)
- **Files modified:** 0 production / 0 test (clean additive plan)
- **Commits:** 3 (one per task)

## Accomplishments

- **VerificationBadgeView (TRUST-02) landed** — single `UIView` subclass, 4 `VerificationState` cases mapped to the UI-SPEC locked color ramp. Public surface is `configure(state:)` and `configure(stateOrNil:)` — the latter is the D-03 fail-closed entry point that turns server-projected `nil` into the `.unverified` visual + accessibilityLabel `"Counterparty not verified"`. Pure render-from-input (no Combine, no async). Phase 9 + 10 reuse this directly.
- **LoadStatusBadgeView landed** — single `UIView` subclass, exhaustive switch over all 13 `LoadStatus` cases mapped to the UI-SPEC 3-tone informational ramp (pre-life / in-progress / done / terminal-error). Terminal-error tones (`.rejected`, `.expired`, `.cancelled`) render via `NSAttributedString` with `.strikethroughStyle = .single`. NEVER reuses `DS.Colors.primary` or `DS.Colors.destructive` — the snapshot test loops every case to lock the ramp isolation.
- **Dynamic Type discipline (Pitfall 8) locked** — both badges recompute `layer.cornerRadius = bounds.height / 2` in `layoutSubviews()`. `test_pillCornerRadiusRecomputesOnLayout` asserts the recomputation at two heights (40 → 20, 60 → 30) so a future edit that drops the override surfaces immediately.
- **Fail-closed VoiceOver discipline (T-08-06) locked by TWO tests** — `test_unverifiedBadgeRendersUnverifiedVisuals` and `test_nilCounterpartyRendersUnverifiedFailClosed` both assert the accessibilityLabel contains "not verified" (literal substring) AND defensively assert it never reads as bare "verified" without the "not" prefix. The combination prevents future edits from accidentally rewording to a copy that VoiceOver users could mis-hear as trust.
- **Status badge ramp isolation lock** — `test_statusBadgeNeverReusesVerificationRampColors` loops every `LoadStatus.allCases` case and asserts neither `DS.Colors.primary` nor `DS.Colors.destructive` is the resolved background. This protects the "informational ramp ≠ security primitive" invariant from future regression.
- **XCTAttachment baselines wired** — every snapshot test attaches its rendered `UIImage` via `UIKitSnapshot.attach(_:name:to:)`. The artefacts survive into the CI test report so visual review can spot drift on top of the structural assertions.
- **Rule 1 bug caught + fixed** — Task 3's `test_cancelledStatusRendersTerminalErrorWithStrikethrough` test FAILED on first run because `label.text = nil` (set after `label.attributedText = ...`) silently strips the attributedText payload. Removed the redundant `text = nil` line; documented the UILabel quirk inline.
- **Zero new SwiftPM dependencies** — CLAUDE.md STACK-04 honored.

## Task Commits

Each task was committed atomically:

1. **Task 1: VerificationBadgeView — TRUST-02 4-state pill + fail-closed nil** — `3bc9f37` (feat)
2. **Task 2: LoadStatusBadgeView — 13-state informational pill (3-tone ramp)** — `3933c76` (feat)
3. **Task 3: badge snapshot suites + Rule 1 fix to LoadStatusBadgeView strikethrough** — `9e9411b` (test)

## VerificationBadgeView Locked Surface

### Public API
```swift
public final class VerificationBadgeView: UIView {
    public override init(frame: CGRect)
    public required init?(coder: NSCoder) // fatalError — programmatic only
    public override func layoutSubviews()  // recomputes cornerRadius = bounds.height/2
    public func configure(state: VerificationState)
    public func configure(stateOrNil state: VerificationState?)  // nil → .unverified (D-03)
}
```

### Locked per-state accessibility labels (the 5 paths)

| Path                                     | accessibilityLabel               | Symbol                          | Background              | Foreground       |
|------------------------------------------|----------------------------------|---------------------------------|-------------------------|------------------|
| `configure(state: .verified)`            | `Counterparty verified`          | `checkmark.seal.fill`           | `DS.Colors.primary`     | `.white`         |
| `configure(state: .pending)`             | `Counterparty verification pending` | `clock.fill`                  | `.systemYellow`         | `.label`         |
| `configure(state: .unverified)`          | `Counterparty not verified`      | `questionmark.circle.fill`      | `.tertiarySystemFill`   | `.secondaryLabel` |
| `configure(state: .flagged)`             | `Counterparty flagged`           | `exclamationmark.triangle.fill` | `DS.Colors.destructive` | `.white`         |
| `configure(stateOrNil: nil)`             | `Counterparty not verified` ← **identical to .unverified, FAIL-CLOSED** | `questionmark.circle.fill` | `.tertiarySystemFill` | `.secondaryLabel` |

### Documented color exceptions (NOT raw-literal violations)

- `.systemYellow` on `.pending` — mirrors `LimitedTrustBannerView`'s caution semantic.
- `.tertiarySystemFill` on `.unverified` — system-managed NEUTRAL grey (non-chromatic).
- Documented in the file header so future contributors know these aren't accidental.

## LoadStatusBadgeView Locked Surface

### Public API
```swift
public final class LoadStatusBadgeView: UIView {
    public override init(frame: CGRect)
    public required init?(coder: NSCoder)
    public override func layoutSubviews()
    public func configure(status: LoadStatus)  // exhaustive over 13 cases
}
```

### 3-tone tier table (UI-SPEC §Color status table)

| Tier               | LoadStatus cases                                         | Background           | Foreground         | Label rendering            |
|--------------------|----------------------------------------------------------|----------------------|--------------------|----------------------------|
| Pre-life           | `.draft`                                                 | `.systemGray6`       | `.secondaryLabel`  | plain `text`               |
| In-progress (5)    | `.posted`, `.tendered`, `.accepted`, `.dispatched`, `.inTransit` | `.tertiarySystemFill` | `.label`         | plain `text`               |
| Done (4)           | `.delivered`, `.podCaptured`, `.invoiced`, `.funded`     | `.systemGray5`       | `.secondaryLabel`  | plain `text`               |
| Terminal-error (3) | `.rejected`, `.expired`, `.cancelled`                    | `.systemGray5`       | `.secondaryLabel`  | `NSAttributedString` + `.strikethroughStyle = .single` |

### Locked uppercase labels (UI-SPEC §Copywriting Contract)

`DRAFT / POSTED / TENDERED / ACCEPTED / DISPATCHED / IN TRANSIT / DELIVERED / REJECTED / EXPIRED / CANCELLED / POD CAPTURED / INVOICED / FUNDED` — 13 cases, each its own `NSLocalizedString` key with prefix `status_badge.*`.

### Strikethrough rendering discipline

For `.rejected / .expired / .cancelled`:
- Assign `label.attributedText = NSAttributedString(string:, attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: foregroundColor])`.
- Do NOT assign `label.text = nil` afterwards — UILabel's text setter (even to nil) strips attributedText (Rule 1 bug caught in this plan).

For the other 10 cases:
- Clear `label.attributedText = nil` FIRST (defends against cell recycling), then assign `label.text = labelText`.

## XCTest vs Swift Testing — Decision

**The snapshot suites use XCTest (not Swift Testing).** Rationale:

- `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)` to surface the rendered image into the CI artefact bundle.
- Swift Testing as of iOS 17 / Xcode 26.4 does not expose an equivalent attachment surface.
- Documented in BOTH snapshot test files' header comments + this Summary so **Plans 04 and 05 follow the same precedent** (snapshot tests = XCTest, non-snapshot tests = Swift Testing).
- 08-PATTERNS.md §10 already telegraphs this choice; the planner confirmed via the build.

Non-snapshot tests in Phase 8 (envelope decode, ViewModel state-machine) continue to use Swift Testing per STACK-03.

## Test Surface (11 tests, all green)

### VerificationBadgeViewSnapshotTests (6 tests)
| # | Test | Locks |
|---|------|-------|
| 1 | `test_verifiedBadgeRendersVerifiedVisuals` | `DS.Colors.primary` + "verified" a11y substring |
| 2 | `test_pendingBadgeRendersPendingVisuals` | `.systemYellow` + "pending" a11y substring |
| 3 | `test_unverifiedBadgeRendersUnverifiedVisuals` | `.tertiarySystemFill` + literal "not verified" + T-08-06 negative assertion |
| 4 | `test_flaggedBadgeRendersFlaggedVisuals` | `DS.Colors.destructive` + "flagged" a11y substring |
| 5 | `test_nilCounterpartyRendersUnverifiedFailClosed` | D-03 + T-08-06 (nil renders identical to .unverified, fail-closed) |
| 6 | `test_pillCornerRadiusRecomputesOnLayout` | Pitfall 8 — recomputes at two heights (40 → 20, 60 → 30) |

### LoadStatusBadgeViewSnapshotTests (5 tests)
| # | Test | Locks |
|---|------|-------|
| 1 | `test_draftStatusRendersPreLifeTone` | `.systemGray6` + label "DRAFT" |
| 2 | `test_inTransitStatusRendersInProgressTone` | `.tertiarySystemFill` + label "IN TRANSIT" |
| 3 | `test_deliveredStatusRendersDoneTone` | `.systemGray5` + label "DELIVERED" |
| 4 | `test_cancelledStatusRendersTerminalErrorWithStrikethrough` | `.systemGray5` + `NSAttributedString` `.strikethroughStyle = .single` + Pitfall 7 spelling |
| 5 | `test_statusBadgeNeverReusesVerificationRampColors` | Loop over `LoadStatus.allCases` — neither primary nor destructive on any case |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] LoadStatusBadgeView strikethrough silently stripped at runtime**
- **Found during:** Task 3 (`test_cancelledStatusRendersTerminalErrorWithStrikethrough` failed on first run with `statusBadgeAttributedText == nil`)
- **Issue:** In `apply(status:)`, after setting `label.attributedText = NSAttributedString(string:attributes:)` for terminal-error tones, the next line `label.text = nil` was clearing the attributed payload. UILabel's `text` setter (even when set to nil) wipes any previously-set `attributedText` — a subtle UIKit quirk that's easy to miss.
- **Fix:** Removed the `label.text = nil` line. Setting `attributedText` is sufficient; `label.text` returns the plain-string view of the attributed payload automatically. Added inline doc comments at both the terminal-error and non-terminal branches explaining the UILabel ordering trap.
- **Files modified:** `validationLedger/UI/Components/LoadStatusBadgeView.swift`
- **Verification:** Re-ran scoped suite — 11/11 green.
- **Committed in:** `9e9411b` (with Task 3 — the fix and the test that caught it ship together).

**2. [Rule 4 — Discretionary, low-impact wording adjustment] LoadStatusBadgeView doc-comment ramp-isolation note**
- **Found during:** Task 2 done-criterion grep
- **Issue:** Plan's `<done>` criterion required `grep -c 'DS.Colors.primary\|DS.Colors.destructive' validationLedger/UI/Components/LoadStatusBadgeView.swift == 0`. The initial draft satisfied the spirit (no token USE in code) but the doc-comment block warning about the prohibition literally named the tokens, returning grep count = 1.
- **Decision:** Rule 4 is over-reach here — this is a discretionary wording adjustment, not an architectural change. Rewrote the doc-comment to describe the prohibition without verbatim token names ("the blue/red tokens used by VerificationBadgeView") so the literal grep returns 0 while the warning remains.
- **Files modified:** `validationLedger/UI/Components/LoadStatusBadgeView.swift` (doc-comment only, no behavior change)
- **Verification:** Re-grepped → 0; re-built → green.
- **Committed in:** `3933c76` (part of the Task 2 initial commit — caught before the commit was made).

**3. [Rule 3 — Blocking grep mismatch on test class declaration] `final class` vs `class`**
- **Found during:** Task 3 done-criterion grep
- **Issue:** Plan's `<done>` greps required `^class VerificationBadgeViewSnapshotTests: XCTestCase` (no `final`). Initial draft declared each class as `final class` (idiomatic Swift for closed types). Plan's literal grep returned 0.
- **Decision:** XCTestCase subclasses don't benefit from `final` in this codebase (no subclassing patterns in test bundle), so dropping `final` is a no-op cost. Changed both to `class` to satisfy the literal done-criterion grep without affecting behavior.
- **Files modified:** both new snapshot test files (declaration line only)
- **Verification:** Both greps returned 1; suite re-ran → 11/11 green.
- **Committed in:** `9e9411b` (part of the Task 3 initial commit — caught before the commit was made).

**4. [Rule 3 — Environment substitution] iPhone 15 → iPhone 17 simulator destination**
- **Found during:** Task 1 verification command preparation
- **Issue:** Plan's `<verify>` blocks specified `'platform=iOS Simulator,name=iPhone 15,OS=17.5'`. This simulator is not installed on the local host (per `ios-test-suite-pitfalls` project memory + `<test_environment>` block in this prompt — iPhone 16 also not installed; iPhone 17 is the canonical local lane).
- **Fix:** Substituted `iPhone 17` and dropped the explicit `OS=` pin (defaults to the installed simulator's OS). Added `-skip-testing:validationLedgerDeviceTests` per the standing project memory.
- **Files modified:** none (environmental shortcut)
- **Committed in:** N/A (environmental shortcut; no source edits)

---

**Total deviations:** 4 (1 × Rule 1 bug discovered + fixed, 2 × Rule 3 grep-shape adjustments, 1 × Rule 3 environmental substitution). No scope creep; no architectural changes; the threat model and UI-SPEC color ramps are unchanged.

## Issues Encountered

- **UILabel.text-setter side-effect.** The Rule 1 bug above is the classic UIKit gotcha — `UILabel.text` documentation says "Assigning a new value to this property also replaces the value of the `attributedText` property" — which applies even when the new value is `nil`. The pattern `label.attributedText = NSAttributedString(...); label.text = nil` silently strips the attributedText. The fix is to ONLY assign `attributedText` (UIKit auto-derives `text` as the plain-string projection) — or, when switching back to a plain string, clear `attributedText = nil` FIRST then assign `text`. Both branches of `apply(status:)` now follow the safe ordering and are doc-commented.
- **First scoped test invocation timing.** The first `xcodebuild test` after the Task 1+2 commits took ~58s wall-clock because Xcode rebuilt the test bundle from scratch; subsequent invocations took ~34s. No flakes.

## User Setup Required

None — pure component work + tests, all against the existing simulator + test infrastructure.

## Next Phase Readiness

**Ready for:**
- **Plan 04 (LoadRowCell):** Composes both badges via `VerificationBadgeView()` + `LoadStatusBadgeView()` in the cell's `init(frame:)`; calls `configure(stateOrNil: item.displayedCounterparty?.verificationState)` on the verification badge (D-03 fail-closed nil flows directly into the badge surface) and `configure(status: item.load.status)` on the status badge.
- **Plan 05 (SkeletonLoadRowCell):** Will produce a silhouette match against the real cell — the two badge slot sizes are now locked (default Dynamic Type renders both at ~footnote height + DS.Spacing.xs padding).
- **Plan 06 (UI smoke test):** Will assert `loads-list.row.{loadID}.verification-badge` and `loads-list.row.{loadID}.status-badge` accessibilityIdentifiers — those identifiers will be set by the cell (Plan 04), not by the badges themselves. The badges set their `accessibilityLabel` (per case); the cell sets the row-scoped `accessibilityIdentifier` on each subview.
- **Phase 9 chain-of-trust graph nodes:** Will reuse `VerificationBadgeView` directly per TRUST-02 — the same `configure(state:)` entry point works.

**No blockers.** 11/11 scoped snapshot tests green. Build clean on the iPhone 17 simulator lane. Zero impact on adjacent test surfaces (no shared code paths modified; Plan 01's envelope tests already independently green).

## Open Questions

- **POD CAPTURED truncation at narrow widths.** UI-SPEC does not currently mandate a width-adaptive label-folding behavior (e.g. shrinking "POD CAPTURED" to "POD" when the row's badge slot can't fit). The label uses `setContentCompressionResistancePriority(.required, for: .vertical)` (vertical only — horizontal compression is allowed) so the label can scale-to-fit horizontally on narrow rows. If product wants explicit folding, that's a UI-SPEC amendment and a follow-up plan; not currently in scope.
- **No-symbol vs symbol-slot for LoadStatusBadgeView.** The plan called for "label-only OR mirror VerificationBadgeView's symbol slot with `UIImage?`". I chose label-only (UI-SPEC §Color status table is explicit). Reserved the additive seam: the internal layout is a `UIStackView` with one arranged subview (the label), so a future symbol-slot upgrade is a one-line `stack.insertArrangedSubview(_:at:)` away.

## Output Spec Coverage (from Plan §output)

- ✓ **VerificationBadgeView public surface** — see "VerificationBadgeView Locked Surface" section above (init, configure(state:), configure(stateOrNil:), layoutSubviews).
- ✓ **Locked accessibilityLabel strings for each of the 5 paths** — 4-state table + nil-overload row.
- ✓ **Documented color exceptions** — `.systemYellow` on `.pending` and `.tertiarySystemFill` on `.unverified` called out with rationale.
- ✓ **LoadStatusBadgeView public surface** — see "LoadStatusBadgeView Locked Surface" section above.
- ✓ **3-tone tier table** — explicit mapping of every LoadStatus case to background + foreground + label rendering.
- ✓ **Strikethrough discipline** — both the NSAttributedString.strikethroughStyle setup AND the UILabel ordering trap (the Rule 1 fix) called out.
- ✓ **XCTest-vs-Swift-Testing decision** — surfaced as an explicit decision so Plans 04/05 follow precedent. See "XCTest vs Swift Testing — Decision" section.
- ✓ **Open questions** — see "Open Questions" section (POD CAPTURED width-adaptive folding; symbol-slot for status badge — both deferred).

## Self-Check: PASSED

All 4 claimed files exist on disk:
- `validationLedger/UI/Components/VerificationBadgeView.swift` — FOUND
- `validationLedger/UI/Components/LoadStatusBadgeView.swift` — FOUND
- `validationLedgerTests/Loads/Snapshot/VerificationBadgeViewSnapshotTests.swift` — FOUND
- `validationLedgerTests/Loads/Snapshot/LoadStatusBadgeViewSnapshotTests.swift` — FOUND

All 3 claimed commit hashes exist in `git log`:
- `3bc9f37` (Task 1: VerificationBadgeView) — FOUND
- `3933c76` (Task 2: LoadStatusBadgeView) — FOUND
- `9e9411b` (Task 3: snapshot suites + Rule 1 fix) — FOUND

Test verification: 11/11 scoped snapshot tests passed on iPhone 17 simulator lane in 0.13s (Wave 1 test budget extremely small, well under the plan's implicit perf envelope).

---
*Phase: 08-role-filtered-load-list*
*Plan: 02 (VerificationBadgeView + LoadStatusBadgeView + snapshot suites)*
*Completed: 2026-05-20*
