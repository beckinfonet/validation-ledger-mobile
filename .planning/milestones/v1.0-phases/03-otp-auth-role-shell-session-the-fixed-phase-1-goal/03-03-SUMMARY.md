---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
plan: 03
subsystem: identity + logging + tooling
tags: [ios, geo, compile-time-safety, swiftlint, wave-1, phase-1-followup, tdd, d-19-closed, d-23, d-24]

# Dependency graph
requires:
  - phase: 01-foundational-conventions-scaffolding
    provides: "4 SwiftLint custom rules baseline (ban_print / ban_direct_os_log / ban_userdefaults_tokens / no_cross_feature_import) + DEFERRED comment placeholder for GEO-03 rule + Logger.swift LogField enum + PIIScrubber .coordinates handler"
  - phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
    plan: 01
    provides: "validationLedgerTests/Identity/PlatformPayloadFieldTests.swift Wave 0 stub (@Test(.disabled(\"Wave 1 Plan 03 implements\")) placeholder) — filled in this plan"
provides:
  - "Phantom-typed PlatformPayloadField enum in Core/Identity/ with 4 cases (coordinate / timestamp / userIdentifier / sessionToken) — the ONLY sanctioned carrier for CLLocationCoordinate2D from the geo subsystem to networking endpoints"
  - "LogField.coordinates case PURGED from validationLedger/Core/Logging/Logger.swift — compile-time barrier: any attempt to pass a coordinate to Logger produces 'Cannot convert value of type ... to expected element type LogField'"
  - "PIIScrubber.swift structured-path switch no longer references coordinates (handler removed; switch exhaustive over the 9 remaining LogField cases). String-path regex sweep for inline lat,lon pairs retained as secondary defense."
  - "5th SwiftLint custom rule ban_raw_coordinate_literal — fires on raw `CLLocationCoordinate2D(latitude:` outside allow-list (Core/Networking/Endpoints/** + Core/Identity/Geo*/**); 0 violations on the current codebase; 1 violation fired on planted AppDelegate.swift violation (test evidence)"
  - "Phase 1 D-19 deferred item CLOSED — .swiftlint.yml DEFERRED comment block removed; 5-rule charter replaces the 4-rule charter"
  - "4 green tests in PlatformPayloadFieldTests (1 type-existence + 1 case-construct proxy + 2 source-grep invariant guards)"
affects:
  - "03-09 (PhoneEntryVM OTP payload) — can now construct PlatformPayloadField.coordinate(_:) for the device_location field in the OTP request payload; Logger-side leakage is compile-time impossible"
  - "03-08 (CountryGate / LocationProvider) — both files live in validationLedger/Core/Identity/Geo/ which is allow-listed by ban_raw_coordinate_literal; constructions of CLLocationCoordinate2D there are permitted"
  - "03-05 (APIClientRateLimit) — unaffected; 429 Retry-After path doesn't touch coordinates"
  - "M2+ tender/accept/scan endpoints — will extend PlatformPayloadField enum with additional cases as payload fields grow; no new infrastructure needed"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Phantom-typed enum per subsystem: separate type families for separate sinks (Logger takes [LogField: Any]; Networking takes PlatformPayloadField). Compile-time guarantees a value cannot cross from one sink to another by syntactic construction alone."
    - "SwiftLint allow-list via `excluded:` regex with `(a|b)` alternation — supports multi-path allow-listing on a single custom rule when `included:` isn't the right shape. Used here because the literal can appear anywhere EXCEPT the two allow-listed paths."
    - "Source-grep invariant guards in Swift Testing: @Test reads a production source file via #filePath-relative URL resolution + asserts a forbidden substring is absent. Encodes a compile-time invariant as a CI-runnable grep so the invariant survives even if the type system loses its enforcement (e.g., someone re-adds the case)."
    - "TDD RED on tooling-level rules: run the linter with the planted violation BEFORE adding the rule (expect 0 findings = current rule set is blind) → add rule → re-run (expect 1 finding on planted violation) → remove planted violation → re-run (expect 0 findings). Four-step evidence chain documented in the commit body."

key-files:
  created:
    - validationLedger/Core/Identity/PlatformPayloadField.swift
  modified:
    - validationLedger/Core/Logging/Logger.swift
    - validationLedger/Core/Logging/PIIScrubber.swift
    - validationLedgerTests/Identity/PlatformPayloadFieldTests.swift
    - validationLedgerTests/Logging/PIIScrubberTests.swift
    - .swiftlint.yml

key-decisions:
  - "Test file filled from Wave 0 stub (not created) — Plan 01 seeded PlatformPayloadFieldTests.swift with a @Test(.disabled) placeholder; this plan replaced the body with 4 real @Tests. Stub-to-plan mapping in Plan 01 held."
  - "Source-grep invariant via #filePath-relative URL — tests read Logger.swift + PIIScrubber.swift from the repo (three deleteLastPathComponent calls up from the test file) rather than trusting xcodebuild's working directory. Reuses the SoftwareKeyStoreExtendedTests.cr02IdempotentGuardPresent pattern."
  - "Deleted PIIScrubberTests.coordinatesRemoved — it asserted redaction behavior for LogField.coordinates which no longer exists post-D-23. Replaced with an explanatory comment so future readers understand why the test went away (and why the 6-category contract is now a 5-category structured + string-path regex contract)."
  - "SwiftLint rule allow-list uses `Geo[^/]*` (not `Geo`) — so `Core/Identity/Geo/` AND any future `Core/Identity/GeoLocation/` style subdirectory is allow-listed. The `*` in the plan text was interpreted as a glob wildcard; regex `[^/]*` is the accurate translation."
  - "Destination substitution (same as Plans 01 + 02): iPhone 17 Pro / iOS 26.4 because plan-specified iPhone 15 / iOS 17.5 runtime is not installed. Project deployment target is iOS 17.0 — any iOS 17+ destination is equivalent for verification. Documented as Deviation 1 (Rule 3 blocking env correction)."
  - "Pitfall 4 over-match discovered during GREEN — the regex `CLLocationCoordinate2D\\s*\\(\\s*latitude\\s*:` matched a doc comment string in PlatformPayloadField.swift that described the banned pattern verbatim. Rule 1 fix: rewrote the comment in prose (\"the canonical init-with-latitude form\") rather than complicating the regex with `#`-negative-lookbehind. Simpler fix; same enforcement."

patterns-established:
  - "Two-disjoint-type-families pattern for PII compile-time guarantees: if type A should never reach sink S, make A's carrier a NEW type family C, and have S accept a DIFFERENT type family D. Cross-sink assignment is a compile error. Documented in PlatformPayloadField.swift header as the GEO-03 pattern template."
  - "RED → GREEN four-step tooling test: (1) plant violation + run linter on baseline = 0 findings (rule doesn't exist). (2) Add rule + rerun = 1 finding on planted violation. (3) Remove planted violation + rerun = 0 findings. (4) Commit final-clean state. Evidence chain documented in commit body for future verification replay."

requirements-completed:
  - GEO-03

# Metrics
duration: 6min
completed: 2026-04-21
---

# Phase 03 Plan 03: GEO-03 Compile-Time Discipline + SwiftLint D-24 Summary

**Phantom-typed `PlatformPayloadField` enum + `LogField.coordinates` removal + 5th SwiftLint custom rule — GEO-03 is now both a compile error and a CI lint error; Phase 1 D-19 deferred item CLOSED.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-04-21 (first task commit 866d553)
- **Completed:** 2026-04-21 (metadata commit pending)
- **Tasks:** 2 / 2 (TDD: each task split into RED + GREEN atomic commits; 3 commits total — Task 1 has RED+GREEN, Task 2 has a single GREEN because the "RED" evidence was run-and-show rather than commit-and-show)
- **Files created:** 1 (PlatformPayloadField.swift)
- **Files modified:** 5 (Logger.swift, PIIScrubber.swift, PlatformPayloadFieldTests.swift, PIIScrubberTests.swift, .swiftlint.yml)

## Accomplishments

- **GEO-03 type-system invariant landed.** `public enum PlatformPayloadField: Sendable` with `case coordinate(CLLocationCoordinate2D)` + 3 other carrier cases, sited at `validationLedger/Core/Identity/PlatformPayloadField.swift`. Auto-included via Phase 1 `PBXFileSystemSynchronizedRootGroup` — zero project.pbxproj churn.
- **`LogField.coordinates` purged from `Logger.swift`.** Logger APIs take `[LogField: Any]`; PlatformPayloadField is a DIFFERENT type family. Swift's type system now makes "attach a coordinate to a Logger call" a compile error. Replaced the case with an in-source comment block so future maintainers don't re-add it.
- **PIIScrubber structured-path `.coordinates` handler removed.** Switch remains exhaustive over the 9 remaining LogField cases. String-path regex sweep (`coordsPattern = -?\d{1,3}\.\d{3,},\s*-?\d{1,3}\.\d{3,}`) retained as secondary defense per threat register T-03-03-02.
- **5th SwiftLint custom rule `ban_raw_coordinate_literal` live.** Fires on `CLLocationCoordinate2D(latitude:` outside `Core/Networking/Endpoints/**` + `Core/Identity/Geo*/**` allow-list. Current codebase: 0 violations. Planted violation evidence: rule fires with specific line+col on AppDelegate.swift.
- **Phase 1 D-19 deferred item CLOSED.** `.swiftlint.yml` DEFERRED comment block (top of file) replaced with a "Phase 1 + Phase 3 lint charter" preamble. File header now cites both D-19 (rules 1-4) and D-24 (rule 5).
- **4 new green tests** in `PlatformPayloadFieldTests.swift` (1 type-existence + 1 case-construct proxy + 2 source-grep invariant guards). `PIIScrubberTests` retains 8 of the original 9 Phase 1 tests (deleted `coordinatesRemoved` because its LogField case no longer exists).
- **Zero broader regression.** `xcodebuild build-for-testing` succeeds on all 17 existing test suites. `xcodebuild test` on PlatformPayloadFieldTests + PIIScrubberTests: `** TEST SUCCEEDED **` — 12 tests in 2 suites.
- **Requirement GEO-03 COMPLETE** per plan frontmatter `requirements: [GEO-03]`.

## Task Commits

Each task was committed atomically following TDD for the Swift half and run-and-show for the SwiftLint half. Worktree mode uses `--no-verify` per parallel-execution policy.

| Commit | Type | Task | Subject |
|--------|------|------|---------|
| `866d553` | test | 1 RED | add failing tests for PlatformPayloadField + LogField coordinate purge (D-23, GEO-03) |
| `f524966` | feat | 1 GREEN | GEO-03 compile-time disjoint-types invariant (D-23) |
| `a1be317` | chore | 2 | add 5th SwiftLint custom rule ban_raw_coordinate_literal (D-24 / Phase 1 D-19 closed) |

**Plan metadata commit:** pending (appended with SUMMARY.md via orchestrator).

## Files Created (1)

### `validationLedger/Core/Identity/PlatformPayloadField.swift` (NEW, +35 lines)

```swift
import CoreLocation
import Foundation

public enum PlatformPayloadField: Sendable {
    case coordinate(CLLocationCoordinate2D)
    case timestamp(Date)
    case userIdentifier(String)
    case sessionToken(String)
}
```

- Sibling to `DeviceFingerprint.swift` in `Core/Identity/`
- Header comment spells out the GEO-03 disjoint-type-families pattern explicitly so future engineers understand the invariant
- Per-case doc comments explain the sanctioned usage of each field

## Files Modified (5)

| Path | Change | Lines |
|------|--------|-------|
| `validationLedger/Core/Logging/Logger.swift` | Removed `case coordinates`; added explanatory comment | +3 / -1 |
| `validationLedger/Core/Logging/PIIScrubber.swift` | Removed `case .coordinates: continue` from structured-path switch; updated doc comment | +5 / -4 |
| `validationLedgerTests/Identity/PlatformPayloadFieldTests.swift` | Filled Wave 0 stub with 4 @Tests (existence + invariants) + source-grep helper | +80 / -6 |
| `validationLedgerTests/Logging/PIIScrubberTests.swift` | Deleted `coordinatesRemoved` test; replaced with explanatory comment | +5 / -5 |
| `.swiftlint.yml` | Removed Phase 1 DEFERRED comment; added 5th custom rule `ban_raw_coordinate_literal` | +17 / -7 |

## Test Results

**PlatformPayloadFieldTests — 4 passed (all new, filled from Wave 0 stub):**

```
✔ PlatformPayloadField.coordinate carries CLLocationCoordinate2D
✔ PlatformPayloadField has timestamp / userIdentifier / sessionToken cases
✔ Logger source contains NO `.coordinate` / `.latitude` / `.longitude` / `.location` LogField case
✔ No production code in Logging/ references CLLocationCoordinate2D (GEO-03 compile-time invariant)
```

**PIIScrubberTests — 8 passed (was 9; `coordinatesRemoved` deleted per D-23):**

```
✔ E.164 phone masked to first-3-last-2
✔ DL number fully redacted
✔ Full name → initial-only
✔ MC/DOT numbers fully redacted (2 arg cases)
✔ Email local-part masked
✔ String-path fallback catches inline PII
✔ String-path redacts full names (CR-02a / D-16 invariant)
✔ String-path name sweep ignores single Capitalized words
```

**Total:** 12 tests in 2 suites green. `** TEST SUCCEEDED **` (combined test run in `/tmp/vl-build-p3p3/Logs/Test/Test-validationLedger-2026.04.21_20-00-42--0700.xcresult`).

**Full test-target build:** `** TEST BUILD SUCCEEDED **` on all 17 suites; no compile regression from the LogField case removal or PIIScrubber switch change.

## SwiftLint Planted-Violation Evidence

The 5th rule was verified via a four-step run-and-show procedure (Task 2 RED / GREEN sub-phases):

### Step 1 — Baseline (4 rules active; new rule not yet added)

Planted at `validationLedger/App/AppDelegate.swift:11`:
```swift
import CoreLocation
// PLANTED VIOLATION FOR SWIFTLINT TEST — REMOVE BEFORE COMMIT (Phase 3 Plan 03 Task 2)
private let _planted = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
```

```
$ swiftlint lint --strict validationLedger/
Done linting! Found 0 violations, 0 serious in 55 files.
```

0 violations — RED confirmed: the 4 existing rules do not catch raw coordinate literals; the new rule is necessary.

### Step 2 — Rule added to `.swiftlint.yml`; planted violation still present

```
$ swiftlint lint --strict validationLedger/
Done linting! Found 1 violation, 1 serious in 55 files.
validationLedger/App/AppDelegate.swift:11:24: error: Do not construct
CLLocationCoordinate2D outside the geo subsystem Violation: Raw
CLLocationCoordinate2D literals must live in Core/Networking/Endpoints/
(payload builders) or Core/Identity/Geo*/ (the geo subsystem itself).
Wrap coordinates in PlatformPayloadField for transport.
(GEO-03 + Phase 1 D-19 deferred → Phase 3 D-24) (ban_raw_coordinate_literal)
```

Rule fires on exactly the expected line+column. GREEN confirmed: rule works.

### Step 3 — Planted violation removed; rule still active

```
$ swiftlint lint --strict validationLedger/
Done linting! Found 0 violations, 0 serious in 55 files.
```

0 violations on the clean codebase — no over-match, no false positives.

### Step 4 — Pitfall 4 over-match discovered + fixed inline

During Step 2, an initial run found 2 violations (AppDelegate.swift + PlatformPayloadField.swift). The second was a false positive: the rule's regex matched a doc-comment string in `PlatformPayloadField.swift` that described the banned pattern verbatim (`\`CLLocationCoordinate2D(latitude:)\``). Rule 1 fix applied inline: rewrote the comment in prose (`the canonical init-with-latitude form`) rather than complicating the regex with negative lookbehind. Post-fix: Step 2 shows exactly 1 violation on the planted literal, Step 3 shows 0 on clean code. Recorded as Deviation 2 below.

## Decisions Made

- **Test file was filled from Wave 0 stub, not created** — Plan 01 seeded `PlatformPayloadFieldTests.swift` with `@Test(.disabled("Wave 1 Plan 03 implements"))` placeholder. This plan replaced the body with 4 real `@Test`s. The stub-to-plan mapping from Plan 01 held exactly.
- **Source-grep invariant guards use `#filePath`-relative URL resolution** — three `deleteLastPathComponent()` calls from the test file path yield the repo root. Reuses the pattern from `SoftwareKeyStoreExtendedTests.cr02IdempotentGuardPresent` (Plan 02). xcodebuild's working directory is derived-data-scoped, not repo-root, so CWD-relative reads would fail.
- **Deleted `PIIScrubberTests.coordinatesRemoved`** — the test asserted `.coordinates` LogField redaction, which is meaningless after D-23 (the case no longer exists; the test couldn't even compile). Replaced with an explanatory comment preserving the "why" for future readers.
- **Allow-list regex uses `Geo[^/]*` (not `Geo`)** — matches `Core/Identity/Geo/` AND any future `Core/Identity/GeoLocation/` subdirectory. The `*` in the plan text is a glob wildcard; `[^/]*` is its regex translation.
- **Destination substitution** (same as Plans 01 + 02): `iPhone 17 Pro / iOS 26.4` because plan-specified `iPhone 15 / iOS 17.5` runtime is not installed; project deployment target is iOS 17.0 so any iOS 17+ simulator is equivalent. Documented as Deviation 1 (Rule 3 blocking env correction).
- **SwiftLint binary resolution** — used the SwiftPM-managed `.build/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint` (0.63.2, pinned in Package.swift per Phase 1) rather than a globally-installed `swiftlint`. The plan's `swiftlint lint ...` shorthand was resolved to the in-repo binary.
- **`xcodebuild` auto-shuffles `project.pbxproj`** (same behavior as Plans 01 + 02). Reverted with `git checkout --` before commit per parallel-execution policy "Do NOT commit auto-generated pbxproj changes unless your plan explicitly requires pbxproj edits." This plan does not.
- **Task 2 "RED commit" was elided** because the RED state is a runtime lint invocation, not a source-file state. Instead, the Task 2 GREEN commit body documents the four-step evidence chain (baseline-0-violations → rule-added-1-violation → violation-removed-0-violations) with exact CLI output. This mirrors Plan 02 Task 2's "unexpected GREEN in RED phase" handling — acceptable for tooling-rule TDD.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking Env Correction] Substituted `iPhone 17 Pro / iOS 26.4` for plan-specified `iPhone 15 / iOS 17.5` destination**
- **Found during:** Task 1 RED `xcodebuild build-for-testing` invocation.
- **Issue:** `xcrun simctl list devices available` shows no `iPhone 15 / iOS 17.5` runtime installed. Installed: iOS 15.2, 18.0–18.4, 26.2, 26.4. Project Xcode SDK is 26.4 per `CLAUDE.md`; deployment target is iOS 17.0 per `validationLedger.xcodeproj/project.pbxproj`.
- **Fix:** All `xcodebuild test` / `build-for-testing` runs used `-destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'`. iOS 17.0 deployment target makes any iOS 17+ destination equivalent.
- **Files modified:** None (CLI invocation only).
- **Verification:** `** TEST SUCCEEDED **` / `** TEST BUILD SUCCEEDED **` on all runs.
- **Committed in:** N/A — no source change.

**2. [Rule 1 — Pitfall 4 Bug] SwiftLint rule regex over-matched a doc comment in `PlatformPayloadField.swift`**
- **Found during:** Task 2 Step 2 first `swiftlint lint` run after adding the rule.
- **Issue:** The regex `CLLocationCoordinate2D\s*\(\s*latitude\s*:` matched a doc-comment string that described the banned pattern verbatim: `// that raw \`CLLocationCoordinate2D(latitude:)\` literals may only appear inside`. Result: 2 violations instead of the expected 1 (planted + comment false positive).
- **Fix:** Rewrote the doc comment in prose (`the canonical init-with-latitude form`) rather than complicating the regex with negative lookbehind. Simpler fix; same enforcement scope. The file's type + API are unchanged.
- **Files modified:** `validationLedger/Core/Identity/PlatformPayloadField.swift` (comment-only; diff +2 / -3).
- **Verification:** Post-fix Step 2 run shows exactly 1 violation (the planted literal at AppDelegate.swift:11:24). Step 3 run on clean code shows 0.
- **Committed in:** `a1be317` (Task 2 GREEN — same commit as the rule itself).

---

**Total deviations:** 2 auto-fixed (1 blocking env correction, 1 Pitfall 4 over-match bug).
**Impact on plan:** No scope change. All plan `success_criteria` checkboxes + `must_haves.truths` + `must_haves.artifacts` `contains` patterns satisfied as written.

## TDD Gate Compliance

Plan frontmatter does not have `type: tdd`, but both tasks have `tdd="true"`. Gate sequence for each task:

| Task | RED commit | GREEN commit | Notes |
|------|-----------|--------------|-------|
| 1 (PlatformPayloadField + LogField purge) | `866d553` (test) | `f524966` (feat) | RED confirmed failing: 4 compile errors `cannot find 'PlatformPayloadField' in scope` on lines 41, 55, 56, 57 of PlatformPayloadFieldTests.swift. GREEN: all 4 tests pass + full test-build succeeds. |
| 2 (SwiftLint rule + D-19 closure) | N/A (run-and-show; see below) | `a1be317` (chore) | RED state is runtime lint output, not a source file. Evidence chain documented in commit body: baseline 0 violations (rule missing) → add rule, 1 violation on planted literal → remove planted, 0 violations clean. Tooling-rule TDD variant. |

`git log --oneline` verifies chronological order of RED → GREEN for Task 1. Task 2 elides the RED commit because the "failing state" is a lint invocation output, not a file; equivalent evidence is in the commit body. No TDD gate violations.

## Known Stubs

**None introduced by this plan.** Plan 01's Wave 0 stub `PlatformPayloadFieldTests.swift` is now filled with 4 real `@Test`s — removed from the pending-stub ledger. The 11 other Wave 0 stubs remain intact and traceable to their owning plans per Plan 01's Stub-to-Plan Mapping.

## Threat Flags

Per plan `<threat_model>`: three Phase 3-03 threats, all `mitigate` disposition, all three mitigations landed:

| Threat ID | Component | Mitigation landed? | Evidence |
|-----------|-----------|---------------------|----------|
| T-03-03-01 | Coordinate leaked into Logger.log call | YES (compile-time) | `LogField` has no coordinate case; `PlatformPayloadField` is a different type family. Enforced by Swift's type system. Source-grep test `loggerSourceHasNoCoordinateCase` locks the invariant. |
| T-03-03-02 | Coord string-formatted into `.event` LogField value | YES (secondary) | Phase 1 PIIScrubber `coordsPattern` regex retained in `scrubString`; 8 PIIScrubber tests still pass. Secondary defense; primary is compile-time. |
| T-03-03-03 | Future engineer adds `.coordinate` case to LogField "for analytics" | YES (lint) | `ban_raw_coordinate_literal` rule fires on raw construction outside allow-list. Even if LogField regains a case, no non-geo/non-endpoint call site can construct the value without lint failing. Evidence: planted violation in AppDelegate.swift:11 detected with specific line+col; Pitfall 4 over-match guarded by the regex's `latitude\s*:` anchor. |

**No new threat surface introduced.** Changes are: (a) removing a case from an existing enum (reduces attack surface), (b) adding a new carrier enum used only by geo → networking, (c) adding a SwiftLint rule (build-tooling, not runtime). No new network endpoints, no file access, no schema change. No threat flags.

## Issues Encountered

- **SwiftLint regex matched a doc comment in `PlatformPayloadField.swift`.** The initial comment described the banned pattern verbatim (a common doc-hygiene instinct) — which made the regex match the comment as a real violation. Rewrote the comment in prose instead. Documented in Deviation 2 / Pattern 4 above. The bug is worth noting because any future engineer who documents the rule's pattern in prose-with-literal-example will re-trigger it. Mitigation: the rule's comment block in `.swiftlint.yml` itself has to be careful; it currently cites the pattern only with escape sequences (`'CLLocationCoordinate2D\s*\(\s*latitude\s*:'` in YAML quoted-string form), which does not match because of the `\s` backslashes.

## User Setup Required

None. No external services, no secrets, no dashboard changes. All work is source + test + tooling-config edits verifiable via `xcodebuild test` + `swiftlint lint --strict`.

## Next Phase Readiness

- **Plan 07 (Logout / SensitiveAction / Auth401) proceeds unchanged** — no coordinate handling in its scope; the new PlatformPayloadField type is unused there.
- **Plan 08 (LocationProvider + CountryGate)** will be the first production consumer of `CLLocationCoordinate2D(latitude:)`. Its source directory `validationLedger/Core/Identity/Geo/` is allow-listed by the rule; no lint violations expected. When Plan 08 ships, re-run `swiftlint lint --strict validationLedger/` to confirm the allow-list does not over-match at the boundary between `Core/Identity/` and `Core/Identity/Geo/` (the current rule's `Geo[^/]*` regex is anchored and tested only by reading).
- **Plan 09 (PhoneEntryVM OTP payload)** is the first consumer of `PlatformPayloadField.coordinate(_:)`. The D-27 7-step orchestration step 1 (`POST /otp/request`) will take a `PlatformPayloadField.coordinate(_:)` constructed from a CountryGate-validated `CLLocation`. Type-safety guarantees that the value cannot flow into the logging subsystem even by accident.
- **Future endpoint payload additions** (tender/accept/scan at M2+) should add new cases to `PlatformPayloadField` as needed. The enum is designed to grow. Allow-list the endpoint file's directory if it's a new path.
- **Downstream verifier should check:** all 6 grep assertions in the plan's `<verify>` section pass (`test -f` PlatformPayloadField.swift; `grep -q "case coordinate(CLLocationCoordinate2D)"`; `! grep -q "case coordinates" Logger.swift`; `! grep -q "CLLocationCoordinate2D" Logger.swift`; `! grep -q "CLLocationCoordinate2D" PIIScrubber.swift`; plus `swiftlint lint --strict` exit-0 + the specific `xcodebuild test` for PlatformPayloadFieldTests + PIIScrubberTests). All confirmed locally; all green.
- **PROJECT.md candidate update:** Phase 1 D-19 can be moved from "Active → Pre-Phase-3 required fixes" to "Validated — Phase 3 closed GEO-03 SwiftLint rule." Orchestrator will handle this at phase transition; not touched here per executor scope.

## Self-Check

Files claimed created:

- `validationLedger/Core/Identity/PlatformPayloadField.swift` — FOUND (35 lines; 4 cases; `case coordinate(CLLocationCoordinate2D)` present)

Files claimed modified:

- `validationLedger/Core/Logging/Logger.swift` — FOUND (0 matches for `case coordinates`, 0 matches for `CLLocationCoordinate2D`)
- `validationLedger/Core/Logging/PIIScrubber.swift` — FOUND (0 matches for `CLLocationCoordinate2D`, 0 matches for `case .coordinates`)
- `validationLedgerTests/Identity/PlatformPayloadFieldTests.swift` — FOUND (4 `@Test` declarations + source-grep helper)
- `validationLedgerTests/Logging/PIIScrubberTests.swift` — FOUND (8 `@Test` declarations after `coordinatesRemoved` deletion)
- `.swiftlint.yml` — FOUND (1 match for `ban_raw_coordinate_literal:`, 1 match for `CLLocationCoordinate2D`, 1 match for `Core/Networking/Endpoints|Core/Identity/Geo`, 0 matches for `DEFERRED to Phase 3`)

Commits claimed made:

- `866d553` (Task 1 RED) — FOUND in `git log`
- `f524966` (Task 1 GREEN) — FOUND in `git log`
- `a1be317` (Task 2 GREEN / D-24) — FOUND in `git log`

Plan `<verification>` block — all 6 criteria:

| # | Check | Result |
|---|-------|--------|
| 1 | PlatformPayloadField.swift exists with 4 cases | PASS (4 cases; `case coordinate(CLLocationCoordinate2D)` present) |
| 2 | LogField has no coordinate case | PASS (`! grep -E "case (coordinates?|latitude|longitude|location)"` on Logger.swift) |
| 3a | PIIScrubber has no `CLLocationCoordinate2D` | PASS |
| 3b | PIIScrubber has no `case .coordinates` | PASS |
| 4 | `.swiftlint.yml` contains 5th rule | PASS (1 match for `ban_raw_coordinate_literal:`) |
| 5 | `swiftlint lint --strict validationLedger/` exit 0 | PASS (0 violations, 0 serious in 55 files) |
| 6 | `xcodebuild test -only-testing:...PlatformPayloadFieldTests -only-testing:...PIIScrubberTests` | PASS (`** TEST SUCCEEDED **`; 12 tests in 2 suites) |

Plan `<success_criteria>` block — all 8 criteria:

- [x] PlatformPayloadField file present with `case coordinate(CLLocationCoordinate2D)`
- [x] LogField has no coordinate-shaped case
- [x] PIIScrubber doesn't reference CLLocationCoordinate2D and doesn't switch on `.coordinates`
- [x] PIIScrubberTests (8 of 9 Phase 1 tests retained; `coordinatesRemoved` intentionally deleted per D-23) all pass
- [x] PlatformPayloadFieldTests (4 new tests) all pass
- [x] SwiftLint rule fires on planted violation (manual verification during Step 2C)
- [x] `swiftlint lint --strict validationLedger/` returns 0 violations
- [x] Phase 1 DEFERRED comment block removed from `.swiftlint.yml`

## Self-Check: PASSED

---
*Phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal*
*Completed: 2026-04-21*
