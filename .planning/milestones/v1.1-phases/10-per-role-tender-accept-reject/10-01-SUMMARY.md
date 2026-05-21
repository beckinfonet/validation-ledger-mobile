---
phase: 10-per-role-tender-accept-reject
plan: 01
subsystem: load-domain
tags: [swift, ios, load, predictor, pure-function, value-type, mvvm, tdd, xctest]

# Dependency graph
requires:
  - phase: 07-load-domain-contract-and-mock-endpoints
    provides: Load aggregate value type, LoadStatus 13-case enum, LoadAction 6-case enum, LoadActionEndpoint.RequestBody shape, RoleLoadPolicy pure-namespace shape — all frozen contract.
provides:
  - LoadActionPredictor pure-namespace function (Load, LoadAction, LoadActionEndpoint.RequestBody?) -> Load for optimistic-UI forward prediction.
  - LoadStatus.localizedDisplayName lowercase localized string (Pitfall 5 fix — empty-state captions and a11y labels).
  - Load.with(status:respondByAt:) internal-access extension helper for value-type forward construction.
affects:
  - 10-02-PLAN — RoleLoadPolicy is consumed at the action-bar site; the predictor here is the rollback-foundation companion.
  - 10-03-PLAN — LoadDetailViewModel will call LoadActionPredictor.predict(...) on entering .actionInFlight and hold the result for D-16 rollback.
  - 10-04-PLAN — terminal empty-state caption consumes LoadStatus.localizedDisplayName at format key loads.actions.empty.terminal.format.

# Tech tracking
tech-stack:
  added: []  # No new packages, no new SwiftPM dependencies (Plan 10 RESEARCH § Package Legitimacy Audit confirms zero installs).
  patterns:
    - "Pure-namespace predictor (public enum, single @MainActor static entry) mirroring RoleLoadPolicy shape — same Core/Load/ kernel placement, same exhaustive tuple switch."
    - "Defensive bottom-arm contract: predictor trusts the policy gate; out-of-policy combinations return current unchanged (no-op) rather than crash."
    - "Synthesized memberwise init reuse: internal-access extension helper (Load.with(...)) reuses the synthesized init across the same module without widening Load's public surface."

key-files:
  created:
    - validationLedger/Core/Load/LoadActionPredictor.swift
    - validationLedgerTests/Loads/LoadActionPredictorTests.swift
    - validationLedgerTests/Loads/LoadStatusLocalizedDisplayNameTests.swift
    - validationLedgerTests/Loads/LoadWithExtensionTests.swift
  modified:
    - validationLedger/Core/Load/LoadStatus.swift  # additive extension only (localizedDisplayName)
    - validationLedger/Core/Load/Load.swift        # additive extension only (with(status:respondByAt:))

key-decisions:
  - "D-12 / D-15 / D-16 rollback foundation: forward prediction is pure value-semantic Swift — the VM holds current and predicted independently and swaps back on error with a single property assignment."
  - "Pitfall 3 lock: .tender arm reads body?.respondByAt (broker's chosen deadline on the request) — NOT current.respondByAt (nil on a pre-tap posted load). The in-flight timeline shows the chosen deadline."
  - "D-04 retender alias: (.tender, .posted), (.tender, .rejected), (.tender, .expired) collapse into one switch arm — three sources produce an identical predicted Load. No separate .retender LoadAction."
  - "Defensive bottom arm: out-of-policy combinations return current unchanged. Policy gate (RoleLoadPolicy.actions(for:status:)) is the authority; predictor trusts that gate; the no-op contains the blast radius without crashing the in-flight VM transition."
  - "Pitfall 5 lock: LoadStatus.localizedDisplayName is the SINGLE SOURCE of the lowercase display string. Exhaustive switch (no default: arm) — adding a new LoadStatus case forces compile-time update here."
  - "RESEARCH Open Question 1 resolved: Swift's synthesized internal memberwise init on Load is accessible from a same-module internal extension — no public init exposure needed; Phase 7 public surface unchanged."

patterns-established:
  - "TDD RED→GREEN split per task: tests committed first with intentional compile-failure (cannot find symbol), implementation committed second. Two TDD cycles in this plan: Task 1 (helpers) + Task 2 (predictor)."
  - "Fixture-helper pattern for predictor tests: file-private makeLoad(status:respondByAt:) synthesizes minimal Load JSON and decodes through APIClient.defaultDecoder(), mirroring LoadListEnvelopeDecodeTests' synthesized-JSON convention so the test-side decoder configuration matches production exactly."
  - "MainActor isolation for fixture helpers: any test helper that decodes a Load (or other main-actor-isolated Decodable conformance under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor) must itself be @MainActor."

requirements-completed:
  - ACTION-01
  - ACTION-02
  - ACTION-03
  - ACTION-04
  - ACTION-05
  - ACTION-06
  - ACTION-08

# Metrics
duration: ~25min
completed: 2026-05-21
---

# Phase 10 Plan 01: Action Predictor + Status Display Helper Summary

**Pure-Swift LoadActionPredictor namespace (public enum + @MainActor static entry mirroring RoleLoadPolicy shape) plus LoadStatus.localizedDisplayName lowercase helper and Load.with(status:respondByAt:) extension — the unit-testable rollback foundation Plan 03's VM consumes.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-21 (wave 1 execution; per-agent worktree)
- **Completed:** 2026-05-21
- **Tasks:** 2 (both TDD; 4 atomic commits total — RED + GREEN per task)
- **Files modified:** 6 (4 created, 2 additively extended)

## Accomplishments

- Pure `LoadActionPredictor.predict(load:action:body:) -> Load` — total over the policy-permitted (LoadAction × LoadStatus) cross-product, exhaustively covered by 10 XCTest cases including the Pitfall 3 deadline-from-body anchor, the D-04 retender alias (`.tender` on `.rejected`/`.expired`), and the T-10-PR-01 value-type purity regression lock.
- `LoadStatus.localizedDisplayName` exhaustive lowercase-space-separated localized helper across all 13 enum cases (rawValue underscores like `in_transit`/`pod_captured` never surface) — unblocks Plan 04's terminal empty-state caption (UI-SPEC line 307).
- `Load.with(status:respondByAt:)` value-type forward-construction extension via the synthesized internal memberwise init — same-module access, no widening of Load's Phase 7 public surface.
- 17/17 new XCTest cases green on the iPhone 17 simulator (scoped, non-parallel) — `LoadActionPredictorTests` (10), `LoadStatusLocalizedDisplayNameTests` (4), `LoadWithExtensionTests` (3).

## Task Commits

Each task split RED → GREEN per TDD discipline:

1. **Task 1 (RED): failing tests for LoadStatus.localizedDisplayName + Load.with(...)** — `56b7b8d` (test)
2. **Task 1 (GREEN): implement helpers** — `e4c94b0` (feat)
3. **Task 2 (RED): failing tests for LoadActionPredictor cross-product matrix** — `71cfe52` (test)
4. **Task 2 (GREEN): implement LoadActionPredictor pure predict(...)** — `7de62c0` (feat)

Plan metadata (SUMMARY.md) commit lands after this file is written.

## Files Created/Modified

- `validationLedger/Core/Load/LoadActionPredictor.swift` (135 lines, NEW) — pure-namespace `public enum LoadActionPredictor` with the single `@MainActor public static func predict(load:action:body:)` entry; tuple switch over (action, current.status); defensive bottom arm.
- `validationLedger/Core/Load/LoadStatus.swift` (163 lines total; +115 additive) — appended `public extension LoadStatus { var localizedDisplayName: String }` with exhaustive switch (no default arm), `loads.status.<spaced>` localization-key namespace, English fallback baked into `NSLocalizedString(value:)`.
- `validationLedger/Core/Load/Load.swift` (205 lines total; +42 additive) — appended internal `extension Load { func with(status:respondByAt:) -> Load }` constructing a fresh Load via the synthesized memberwise init.
- `validationLedgerTests/Loads/LoadActionPredictorTests.swift` (276 lines, NEW) — 10 XCTest cases covering Test 1–10 of the Plan <behavior> block. File-private `makeLoad(status:respondByAt:)` helper.
- `validationLedgerTests/Loads/LoadStatusLocalizedDisplayNameTests.swift` (77 lines, NEW) — 4 XCTest cases covering non-empty invariant, underscore-leakage guard, English fallback table, lowercase invariant.
- `validationLedgerTests/Loads/LoadWithExtensionTests.swift` (102 lines, NEW) — 3 XCTest cases covering field-by-field equality minus mutated fields, value-type purity, explicit nil propagation.

## (action, status) Coverage Table — LoadActionPredictor

| action          | source status                                                       | predicted status | respondByAt                |
| --------------- | ------------------------------------------------------------------- | ---------------- | -------------------------- |
| `.post`         | `.draft`                                                            | `.posted`        | `nil`                      |
| `.tender`       | `.posted` / `.rejected` / `.expired`                                | `.tendered`      | `body?.respondByAt`        |
| `.accept`       | `.tendered`                                                         | `.accepted`      | `nil` (cleared)            |
| `.reject`       | `.tendered`                                                         | `.rejected`      | `nil` (cleared; server may return .posted directly per D-04) |
| `.cancel`       | `.draft` / `.posted` / `.tendered` / `.accepted` / `.dispatched` / `.inTransit` / `.rejected` / `.expired` | `.cancelled`     | `nil` (cleared)            |
| `.advanceStatus`| `.accepted` → `.dispatched` ; `.dispatched` → `.inTransit` ; `.inTransit` → `.delivered` | next canonical step | `nil`                |
| *every other (action, source) pair* | *terminal / policy-illegal*                       | `current.status` | `current.respondByAt`      |

The last row is the defensive bottom-arm contract — policy gate should have prevented these from reaching here; predictor no-ops rather than crashes.

## Notes for Plan 03 (LoadDetailViewModel)

- **Signature is `@MainActor`**: call without `await`. The project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes this a free call from a UIKit ViewModel.
- **Pure value-type**: hold both `current` (the pre-tap Load) and `predicted` (the result of `predict(...)`) as separate properties on the in-flight state. On 200 the server's authoritative Load replaces both; on error swap back to `current`.
- **`.tender` body must carry `respondByAt`**: when constructing `LoadActionEndpoint.RequestBody` for a tender, set `respondByAt` to the deadline the broker chose — the predictor reads this field (Pitfall 3). Other actions can pass `respondByAt: nil`.
- **Policy gate is your responsibility**: call `RoleLoadPolicy.actions(for:status:)` before invoking `LoadActionPredictor.predict(...)`. The predictor will not crash on an out-of-policy call (it returns `current`), but a stray call indicates a contract bug worth a log.
- **Chain-of-trust is never predicted (D-13)**: this function returns `Load` only. Hold the unchanged `ChainOfTrust` separately through the in-flight transition; the server response carries a freshly-derived `ChainOfTrust` on success.

## Decisions Made

None beyond the plan-level decisions listed in the frontmatter `key-decisions` block. All architectural choices (predictor shape, bottom-arm semantics, helper signatures, localization key namespace) were specified by Plan 10-01's `<action>` block and 10-RESEARCH.md.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Verify command's `iPhone 16` simulator does not exist on this host**

- **Found during:** Task 1 verify (first scoped `xcodebuild test` invocation).
- **Issue:** Plan's verify-block commands target `-destination 'platform=iOS Simulator,name=iPhone 16'`. Per project memory (`ios-test-suite-pitfalls`), iPhone 16 is not installed on this host — only iPhone 17 / iPhone 17 Pro / iPhone 16e are available.
- **Fix:** Substituted `iPhone 17` for every `xcodebuild test` invocation in this plan's verify cycle. No behavior change in the code under test; the simulator name is a runner-side detail.
- **Files modified:** None (runner-side only).
- **Verification:** All 17 tests green on iPhone 17 across the three new test classes.
- **Committed in:** N/A (no source change required; documented here for the next plan author who may want to update the verify-block template).

**2. [Rule 3 — Blocking] @MainActor fixture-helper hygiene under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor**

- **Found during:** Task 2 build-for-testing compile pass.
- **Issue:** The compiler emitted "main actor-isolated conformance of 'Load' to 'Decodable' cannot be used in nonisolated context" (warning under Swift 5 mode; error under Swift 6 mode) on the `makeLoad(...)` fixture helper in `LoadActionPredictorTests` and `loadFromFixture()` in `LoadWithExtensionTests`. Under the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default, `Load`'s synthesized Decodable conformance is main-actor isolated.
- **Fix:** Annotated the fixture helpers and the `LoadWithExtensionTests` test methods with `@MainActor`. The new predictor tests are likewise `@MainActor` end-to-end so the `LoadActionPredictor.predict(...)` call site (also `@MainActor`) is satisfied without `await`.
- **Files modified:** `validationLedgerTests/Loads/LoadActionPredictorTests.swift`, `validationLedgerTests/Loads/LoadWithExtensionTests.swift`.
- **Verification:** Compile-clean (no actor-isolation warnings); all 17 tests green.
- **Committed in:** `7de62c0` (Task 2 GREEN commit — bundled because the helper hygiene surfaced once the new predictor tests adopted the same fixture-helper pattern).

---

**Total deviations:** 2 auto-fixed (both Rule 3 — Blocking).
**Impact on plan:** Both are runner-side / actor-isolation hygiene fixes with no architectural change. No scope creep — the predictor signature, the helper shape, and the test coverage match the plan verbatim. The plan's verify-block reference to `iPhone 16` should be corrected in the Phase 10 verify-block template at the next opportunity (cross-plan footnote, not a 10-01 blocker).

## Issues Encountered

- **Compiler noise from `-only-testing` mixing XCTest + Swift Testing**: per project memory, running `xcodebuild test -only-testing:<X> -only-testing:<Y>` where one is XCTest and one is Swift Testing silently drops one framework. Worked around by running scoped invocations against XCTest suites only; the broader `validationLedgerTests/Loads` Swift Testing neighbors (`LoadListEnvelopeDecodeTests`, `LoadListViewModelTests`, `LoadDetailViewModelTests`) are unaffected by this plan and have not been re-run here. They were green at HEAD before this plan and the predictor/helpers introduce no shared mutable state or wire-format changes that could regress them.

## User Setup Required

None — no external services configured, no new packages installed, no environment variables required.

## Next Phase Readiness

- **Plan 10-02 (RoleLoadPolicy + per-role action-bar wiring)**: independent of this plan; can land in parallel within Wave 1.
- **Plan 10-03 (LoadDetailViewModel rollback contract)**: ready to consume `LoadActionPredictor.predict(...)`. See "Notes for Plan 03" section above for the integration contract.
- **Plan 10-04 (terminal empty-state caption)**: ready to interpolate `LoadStatus.localizedDisplayName` at the `loads.actions.empty.terminal.format` key.
- **Verification debt**: none. All done-criteria (4 source-grep assertions + 17 test passes) verified at this commit.

## Self-Check

Verified at commit `7de62c0` (Task 2 GREEN):

- [x] FOUND: `validationLedger/Core/Load/LoadActionPredictor.swift` (135 lines)
- [x] FOUND: `validationLedger/Core/Load/LoadStatus.swift` (163 lines — additive extension appended)
- [x] FOUND: `validationLedger/Core/Load/Load.swift` (205 lines — additive extension appended)
- [x] FOUND: `validationLedgerTests/Loads/LoadActionPredictorTests.swift` (276 lines)
- [x] FOUND: `validationLedgerTests/Loads/LoadStatusLocalizedDisplayNameTests.swift` (77 lines)
- [x] FOUND: `validationLedgerTests/Loads/LoadWithExtensionTests.swift` (102 lines)
- [x] FOUND commit `56b7b8d` (Task 1 RED)
- [x] FOUND commit `e4c94b0` (Task 1 GREEN)
- [x] FOUND commit `71cfe52` (Task 2 RED)
- [x] FOUND commit `7de62c0` (Task 2 GREEN)
- [x] Source assertion: `grep -c '^public enum LoadActionPredictor'` = 1
- [x] Source assertion: `grep -nE 'body\?\.respondByAt'` returns hit on `.tender` arm (line 88)
- [x] Source assertion: `grep -c 'default:'` = 1 (only the defensive bottom arm)
- [x] Source assertion: `grep -cE 'switch.*\.status'` = 1 (single tuple switch)
- [x] 17/17 new tests green via `xcodebuild test ... -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<each>`

**Self-Check: PASSED**

---
*Phase: 10-per-role-tender-accept-reject*
*Plan: 01*
*Completed: 2026-05-21*
