---
phase: 10-per-role-tender-accept-reject
plan: 02
subsystem: load-actions
tags: [policy, title-resolver, pure-helpers, wave-1, foundation]

dependency_graph:
  requires:
    - Phase 7 LOAD-02 — RoleLoadPolicy.actions(for:status:) (frozen truth table)
    - Phase 7 — LoadAction, LoadStatus, Role, Load value types
  provides:
    - RoleLoadPolicy.availableActions(for: Role, in: Load) -> [LoadAction]
    - LoadActionTitleResolver.title(for: LoadAction, currentStatus: LoadStatus?) -> String
    - LoadActionTitleResolver.nextStatus(from: LoadStatus) -> LoadStatus?
    - VALIDATION.md ACTION-01 named test file (RoleLoadPolicyAvailableActionsTests)
  affects:
    - Plan 10-03 (LoadDetailViewModel) — calls availableActions(for:in:)
    - Plan 10-04 (LoadActionsView) — calls title(for:currentStatus:) per render
    - Plan 10-04 lint test — title resolver in Core/Load/ keeps Features/Loads/ free of switch load.status

tech_stack:
  added: []
  patterns:
    - "public-enum namespace + static API surface (analog to RoleLoadPolicy / LoadActionPredictor)"
    - "exhaustive switch with NO default arm — future LoadStatus case fails at compile time"
    - "NSLocalizedString with English-fallback `value:` so unit tests assert English without a Localizable.strings ship"
    - "JSON-literal fixture decoded via APIClient.defaultDecoder() — mirrors LoadListEnvelopeDecodeTests.minimalLoadJSON convention"

key_files:
  created:
    - validationLedger/Core/Load/LoadActionTitleResolver.swift (167 lines)
    - validationLedgerTests/Loads/RoleLoadPolicyAvailableActionsTests.swift (215 lines)
    - validationLedgerTests/Loads/LoadActionTitleResolverTests.swift (160 lines)
  modified:
    - validationLedger/Core/Load/RoleLoadPolicy.swift (+34 lines appended; original enum body byte-identical)

decisions:
  - "XCTest folder-path syntax (`-only-testing:validationLedgerTests/Loads/<Class>`) silently selects zero tests on this project — the canonical invocation is `validationLedgerTests/<Class>` (no folder segment). Empirically confirmed during Task 1 RED."
  - "iPhone 16 simulator is NOT installed on this host (project memory); iPhone 17 is the working simulator. The plan's `iPhone 16` destination string is corrected to `iPhone 17` at run time."
  - "Plan instructed `[.post, .cancel]` for Broker × .draft but the frozen Phase 7 truth table returns `[.post]` only. The wrapper-delegation Test 1 invariant requires the wrapper to mirror the frozen table — Test 9 asserts `[.post]` (the frozen behavior) and documents the read_first text as a citation inaccuracy."

metrics:
  duration: 8m24s
  started_at: 2026-05-21T13:56:31Z
  completed_at: 2026-05-21T14:04:55Z
  tasks: 2
  commits: 4
  tests_added: 19
  tests_green: 19
  lines_added: 376  # 167 + 215 + 160 - 0 (deletions) + 34 (extension append)
---

# Phase 10 Plan 02: RoleLoadPolicy `availableActions(for:in:)` wrapper + `LoadActionTitleResolver` pure helpers — Summary

The two thin pure helpers the action region (Plan 04) will call once per render are now live: `RoleLoadPolicy.availableActions(for: Role, in: Load) -> [LoadAction]` (a same-file extension delegating to the frozen Phase 7 `actions(for:status:)`) and `LoadActionTitleResolver.title(for: LoadAction, currentStatus: LoadStatus?) -> String` (the pure title resolver that maps `.advanceStatus` against the current status to the three distinct localized button titles "Dispatch" / "Mark in transit" / "Mark delivered"). Both helpers live in `Core/Load/`, so the planned Plan 04 lint test (zero `switch load.status` in `Features/Loads/**/*ViewController.swift` and `**/*Cell.swift`) is verified passing pre-implementation.

## What landed

### Source

| File | Change | Lines |
|------|--------|-------|
| `validationLedger/Core/Load/RoleLoadPolicy.swift` | APPEND-only — new `public extension RoleLoadPolicy` with `availableActions(for:in:)`; original enum body byte-identical | +34 |
| `validationLedger/Core/Load/LoadActionTitleResolver.swift` | NEW — pure namespace, 2 static functions (`nextStatus(from:)`, `title(for:currentStatus:)`) | 167 |

### Tests

| File | Framework | Methods | Status |
|------|-----------|---------|--------|
| `validationLedgerTests/Loads/RoleLoadPolicyAvailableActionsTests.swift` | XCTest | 9 | 9/9 green |
| `validationLedgerTests/Loads/LoadActionTitleResolverTests.swift` | XCTest | 10 | 10/10 green |
| **Total** | | **19** | **19/19 green** |

## Per-action title table (Plan 04 reference)

The `LoadActionTitleResolver.title(for:currentStatus:)` resolver implements the following table, locked against UI-SPEC § Action button titles lines 270-282:

| LoadAction | Current status | Title | NSLocalizedString key |
|------------|----------------|-------|------------------------|
| `.tender` | — (ignored) | "Tender" | `loads.actions.button.tender` |
| `.accept` | — (ignored) | "Accept" | `loads.actions.button.accept` |
| `.reject` | — (ignored) | "Reject" | `loads.actions.button.reject` |
| `.cancel` | — (ignored) | "Cancel load" | `loads.actions.button.cancel` |
| `.post` | — (ignored) | "Post" | `loads.actions.button.post` |
| `.advanceStatus` | `.accepted` | "Dispatch" | `loads.actions.button.advance.dispatched` |
| `.advanceStatus` | `.dispatched` | "Mark in transit" | `loads.actions.button.advance.in_transit` |
| `.advanceStatus` | `.inTransit` | "Mark delivered" | `loads.actions.button.advance.delivered` |
| `.advanceStatus` | any other / nil | "Advance" (defensive fallback) | `loads.actions.button.advance.generic` |

`nextStatus(from:)` implements the canonical-lifecycle forward map:

| Input current status | `nextStatus(from:)` output |
|----------------------|---------------------------|
| `.accepted` | `.dispatched` |
| `.dispatched` | `.inTransit` |
| `.inTransit` | `.delivered` |
| Every other case (draft, posted, tendered, rejected, expired, delivered, cancelled, podCaptured, invoiced, funded) | `nil` |

The switch is exhaustive with NO `default:` arm — a future LoadStatus case fails at compile time (T-10-PR-02 mitigation).

## Commits (this plan)

| Hash | Type | Message |
|------|------|---------|
| `81a652a` | test | test(10-02): add failing test for RoleLoadPolicy.availableActions(for:in:) |
| `60a3ea1` | feat | feat(10-02): add RoleLoadPolicy.availableActions(for:in:) VM-facing wrapper |
| `b376c24` | test | test(10-02): add failing tests for LoadActionTitleResolver namespace |
| `752b005` | feat | feat(10-02): add LoadActionTitleResolver pure namespace in Core/Load/ |

TDD discipline: each task has paired `test:` (RED) and `feat:` (GREEN) commits.

## Done-criteria evidence

### Task 1
- ✓ All 9 tests in `RoleLoadPolicyAvailableActionsTests` green
- ✓ `grep -c 'static func availableActions(for' validationLedger/Core/Load/RoleLoadPolicy.swift` returns `1`
- ✓ The existing `actions(for:status:)` body in `RoleLoadPolicy.swift` is byte-identical to the pre-edit version (verified via `git diff 33521a4..HEAD -- validationLedger/Core/Load/RoleLoadPolicy.swift` — diff shows only an append after the original enum's closing brace)

### Task 2
- ✓ All 10 tests in `LoadActionTitleResolverTests` green
- ✓ `grep -c '^public enum LoadActionTitleResolver' validationLedger/Core/Load/LoadActionTitleResolver.swift` returns `1`
- ✓ `test -f validationLedger/Core/Load/LoadActionTitleResolver.swift && echo OK` outputs `OK` (file is in Core/Load/, not in Features/Loads/)
- ✓ `grep -nE 'switch[[:space:]]+.*\.status' validationLedger/Features/Loads/ -r` returns 0 hits (Plan 04 lint test continues to be satisfiable)

## Plan-level success criteria

- ✓ `RoleLoadPolicy.swift` gains ONE extension; the original enum body is unchanged byte-for-byte
- ✓ `LoadActionTitleResolver.swift` exists in `Core/Load/` and compiles
- ✓ Both new test files green; together they cover all `availableActions(for:in:)` cells the action region will hit + all 6 LoadAction title cases (5 simple + 1 advance with 4 status branches) + 13 `nextStatus(from:)` cases (10 + 9 = 19 new green tests)
- ✓ VALIDATION.md ACTION-01 row's named test (`RoleLoadPolicyAvailableActionsTests`) is now real and green
- ✓ No new file under `Features/Loads/` — both helpers are in `Core/Load/` so the Plan 04 lint test (zero `switch load.status` in `Features/Loads/**/*ViewController.swift` / `**/*Cell.swift`) continues to be satisfiable (verified: 0 hits)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] iPhone 17 simulator substituted for iPhone 16 in test invocations**
- **Found during:** Task 1 first test run
- **Issue:** The plan's `<automated>` block specifies `-destination 'platform=iOS Simulator,name=iPhone 16'`, but iPhone 16 is **NOT** installed on this host (project memory `ios-test-suite-pitfalls`). The plan's destination string would have failed with a simulator-not-found error.
- **Fix:** Substituted `iPhone 17` (which is installed and was already booted on the host) per the same memory's CORRECT-simulator-lane command. This is a per-host environment fix that does not change the test contract.
- **Files modified:** None (run-time-only swap in `xcodebuild` invocations)

**2. [Rule 3 — Blocking] XCTest folder-path `-only-testing` selects 0 tests on this project — canonical invocation is class-name only**
- **Found during:** Task 1 GREEN phase initial verification
- **Issue:** The plan's verify command `-only-testing:validationLedgerTests/Loads/RoleLoadPolicyAvailableActionsTests` builds successfully but reports `Executed 0 tests, with 0 failures`. The XCTest runner does not parse the folder segment (`/Loads/`) — it expects `<TARGET>/<CLASS>` form, not `<TARGET>/<FOLDER>/<CLASS>`.
- **Fix:** Re-ran with `-only-testing:validationLedgerTests/RoleLoadPolicyAvailableActionsTests` (no folder segment) → 9 tests discovered and passed. Documented this convention in the `LoadActionTitleResolverTests.swift` file header so the next executor inherits the lesson rather than re-discovering it.
- **Files modified:** None at the source level (the file paths on disk are unchanged; only the `-only-testing` argument was corrected). Recommend updating Plan 03+ `<automated>` blocks to use class-name-only form.

**3. [Rule 1 — Bug citation] `[.post, .cancel]` vs `[.post]` for Broker × .draft**
- **Found during:** Writing Test 9 in `RoleLoadPolicyAvailableActionsTests`
- **Issue:** The plan's <behavior> block for Test 9 cites `UI-SPEC line 516 (Shipper/Broker on .draft → [.post, .cancel])`, but the frozen Phase 7 `RoleLoadPolicy.actions(for:status:)` returns `[.post]` only for `(shipper|broker, .draft)` (RoleLoadPolicy.swift line 79: `case .draft: return [.post]`). The wrapper is a thin delegation — asserting `[.post, .cancel]` would falsely break Test 1's delegation invariant.
- **Fix:** Test 9 asserts the frozen behavior `[.post]` (matches the Phase 7 truth table); a documentation comment in the test method explains the citation drift. This preserves the wrapper-is-thin-delegation invariant. If `[.post, .cancel]` is in fact the intended behavior, that is a Phase 7 truth-table change, not a Plan 10-02 change.
- **Files modified:** `validationLedgerTests/Loads/RoleLoadPolicyAvailableActionsTests.swift` (Test 9 method comment)

### No architectural changes
None of these deviations required a Rule 4 architectural decision — all are environment- or citation-level corrections that preserve the plan's contract.

## Authentication gates
None — pure-Swift helpers; no network, Keychain, or external service interaction.

## Threat surface scan

No new threat surface beyond what's already enumerated in the plan's `<threat_model>`. The helpers expose no new network endpoints, no new auth paths, no new file access, no new schema. The wrapper preserves the existing Phase 7 server-enforcement boundary on every action; the title resolver produces only display strings.

No `## Threat Flags` section needed.

## Known Stubs
None. Both helpers are fully implemented; no placeholder text, no hardcoded empty returns flowing to UI, no TODO/FIXME markers.

## TDD Gate Compliance
- ✓ Task 1: `test(10-02): add failing test...` (RED, 81a652a) → `feat(10-02): add RoleLoadPolicy.availableActions...` (GREEN, 60a3ea1)
- ✓ Task 2: `test(10-02): add failing tests...` (RED, b376c24) → `feat(10-02): add LoadActionTitleResolver...` (GREEN, 752b005)
- No refactor pass needed — both implementations were minimal and idiomatic on the first GREEN pass.

## Self-Check

- ✓ `validationLedger/Core/Load/RoleLoadPolicy.swift` exists (modified — +34 lines)
- ✓ `validationLedger/Core/Load/LoadActionTitleResolver.swift` exists (created)
- ✓ `validationLedgerTests/Loads/RoleLoadPolicyAvailableActionsTests.swift` exists (created)
- ✓ `validationLedgerTests/Loads/LoadActionTitleResolverTests.swift` exists (created)
- ✓ Commit `81a652a` present in `git log --all`
- ✓ Commit `60a3ea1` present in `git log --all`
- ✓ Commit `b376c24` present in `git log --all`
- ✓ Commit `752b005` present in `git log --all`

## Self-Check: PASSED
