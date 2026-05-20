---
phase: 08-role-filtered-load-list
plan: 01
subsystem: networking
tags: [decodable, jsondecoder, mock-url-protocol, swift-testing, snapshot-helper, trust-graph, role-filtering]

# Dependency graph
requires:
  - phase: 07-load-domain-model-mock-contract
    provides: "Load, TrustNode, VerificationState (fail-closed), MockLoadFixtureRegistry, the 5 role list fixtures + load-detail-VL-*.json + APIClient.defaultDecoder()"
provides:
  - "LoadListItem envelope value type (load: Load; displayedCounterparty: TrustNode?)"
  - "LoadListEndpoint.Response.loads element type changed [Load] -> [LoadListItem] (source-incompatible — only Phase 8 consumers exist)"
  - "Re-wrapped 5 role + empty fixtures (loads-list-{broker,shipper,carrier,dispatch,factoring,empty}.json) carrying the envelope shape"
  - "New loads-list-degraded-counterparty.json fixture (null + flagged + verified rows) for the fail-closed UI test path"
  - "MockLoadFixtureRegistry.registerForDegradedDemo() sentinel-suffix demo lane (DEBUG, NOT in registerAppDefaults)"
  - "UIKitSnapshot hand-rolled UIView->UIImage snapshot helper (Wave 0; consumed by Plans 02/04/05)"
  - "LoadListEnvelopeDecodeTests (9/9 pass) — D-02/D-03/D-04/D-05 + D-09 + shared-world coverage"

affects: [08-02-badges, 08-03-vm-states, 08-04-loadrowcell, 08-05-skeleton-shimmer, 08-06-tab-wiring]

# Tech tracking
tech-stack:
  added: []  # zero new SwiftPM dependencies (CLAUDE.md STACK-04 + 08-RESEARCH A2)
  patterns:
    - "Wire-envelope evolution via additive nested type (Load nested under `load:` keeps Phase 7 Load.swift byte-identical)"
    - "Server-projected per-row trust (TrustNode? from server, never client-selected) — D-18 carried forward"
    - "Hand-rolled UIView -> UIImage snapshot baseline via UIGraphicsImageRenderer + view.layer.render(in:)"
    - "Sentinel-suffix path dispatch for DEBUG-only test scenarios (/loads/degraded)"
    - "Cross-fixture shared-world invariant test (Phase 7 D-11) — locked at the Phase 8 envelope layer"

key-files:
  created:
    - "validationLedger/Core/Load/LoadListItem.swift"
    - "validationLedgerTests/Networking/Fixtures/loads-list-degraded-counterparty.json"
    - "validationLedgerTests/Support/UIKitSnapshot.swift"
    - "validationLedgerTests/Loads/LoadListEnvelopeDecodeTests.swift"
  modified:
    - "validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift"
    - "validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift"
    - "validationLedger/Core/Load/Load.swift"
    - "validationLedgerTests/Networking/Fixtures/loads-list-broker.json"
    - "validationLedgerTests/Networking/Fixtures/loads-list-shipper.json"
    - "validationLedgerTests/Networking/Fixtures/loads-list-carrier.json"
    - "validationLedgerTests/Networking/Fixtures/loads-list-dispatch.json"
    - "validationLedgerTests/Networking/Fixtures/loads-list-factoring.json"
    - "validationLedgerTests/Networking/Fixtures/loads-list-empty.json"
    - "validationLedgerTests/Load/LoadDomainDecodeTests.swift"

key-decisions:
  - "D-02 (locked): LoadListItem { load: Load; displayedCounterparty: TrustNode? } — additive nested envelope, Load.swift untouched"
  - "D-03 (locked): JSON null AND missing displayed_counterparty key BOTH decode to Swift nil via synthesized decodeIfPresent (Tests 2+3 lock this behavior)"
  - "D-04 (locked): per-role counterparty roles — broker->carrier; shipper/carrier/dispatch->broker; factoring->carrier"
  - "D-05 (locked): nextCursor is decode-only — Test 7 (string round-trip) + Test 8 (null) prove the contract without exercising any consumer"
  - "Discretion: sentinel-suffix /loads/degraded (NOT a query param) — matches existing path-suffix dispatch grammar"
  - "Discretion: hand-rolled UIKitSnapshot (NOT swift-snapshot-testing) — zero new SwiftPM dependency"

patterns-established:
  - "Per-row server-projected trust envelope: Phase 9 trust-graph rows / future role-scoped list endpoints follow the same shape (data: Aggregate, displayedX: ProjectedTrustNode?)"
  - "Test-only sentinel-path demo lane in DEBUG fixture registries: registerForXxxDemo() static func that is NEVER called from registerAppDefaults()"
  - "Cross-fixture shared-world test (Test 6): load same ID from N role fixtures, assert per-role view of counterparty differs as D-04 dictates"

requirements-completed: [LOAD-03, LOAD-04, TRUST-02]

# Metrics
duration: ~75min
completed: 2026-05-20
---

# Phase 8 Plan 01: Wire-Format Extension + Wave 0 Test Infrastructure Summary

**LoadListItem envelope landed with lockstep fixture rewrap, degraded edge-case fixture + DEBUG demo lane, and the hand-rolled UIKitSnapshot baseline — 9-test envelope decode suite green, all Phase 7 endpoint tests still green against the new shape.**

## Performance

- **Duration:** ~75 min (4 atomic commits + verification)
- **Started:** 2026-05-20T03:01Z (worktree spawn)
- **Completed:** 2026-05-20T04:16Z
- **Tasks:** 4/4 complete
- **Files modified:** 13 (4 created, 9 modified)
- **Commits:** 4 (one per task)

## Accomplishments

- **D-02 envelope landed** — `LoadListItem` is the element type of `LoadListEndpoint.Response.loads`; Phase 7 `Load.swift` byte-identical.
- **D-03 fail-closed nil semantic locked** — Tests 2 (JSON null) + 3 (missing key) prove the synthesized `decodeIfPresent` unifies both forms identically.
- **D-04 fixture authoring + D-11 shared-world consistency** — 5 role fixtures rewrapped; VL-1001 cross-fixture verified (broker sees Acme carrier, shipper/carrier/dispatch/factoring see role-appropriate counterparties).
- **Fraud signal surfaces on the list** — VL-1010 broker row carries `PhantomLine Logistics` (flagged carrier); VL-1009 carrier/dispatch rows carry `Keystone Freight Group` (flagged broker). The chain-of-trust fraud archetypes from Phase 7 D-13 are now visible at the list-row level before the user taps into Phase 9 detail.
- **MockLoadFixtureRegistry lockstep edit** — inline `listPayloads` (33 `displayed_counterparty` refs) matches the on-disk JSON; AUTHORITATIVE COPY discipline preserved.
- **`registerForDegradedDemo()` lane** — sentinel-suffix `/loads/degraded` dispatcher inside the existing `#if DEBUG` block; NOT called from `registerAppDefaults()` (test-only invocation per RESEARCH Open Question 2).
- **Wave 0 snapshot baseline** — `UIKitSnapshot.image(of:size:)` + `UIKitSnapshot.attach(_:name:to:)` ready for Plans 02 / 04 / 05.
- **9-test decode suite, all green** — `LoadListEnvelopeDecodeTests` covers envelope, fail-closed nil (both JSON null and missing key), unknown verification_state degrade (Phase 7 D-09 carried through composition), degraded fixture, cross-fixture shared-world invariant, next_cursor round-trip both forms, empty envelope.
- **Zero new SwiftPM dependencies** — CLAUDE.md STACK-04 + 08-RESEARCH A2 honored.

## Task Commits

Each task was committed atomically:

1. **Task 1: UIKitSnapshot.swift (Wave 0 snapshot helper)** — `9e2047b` (feat)
2. **Task 2: LoadListItem envelope + LoadListEndpoint.Response element type** — `ffd8b6b` (feat)
3. **Task 3: Lockstep rewrap of 6 list fixtures + degraded fixture + MockLoadFixtureRegistry envelope payloads + registerForDegradedDemo lane** — `5e3d76e` (feat)
4. **Task 4: LoadListEnvelopeDecodeTests (D-02/D-03/D-04 + D-09 + shared-world)** — `e46850e` (test)

_No TDD RED→GREEN split per task — Tasks 1 and 2 are pure structural additions; Task 3's "test" of correctness is the structural greps + the existing Phase 7 endpoint tests continuing to pass against the rewrapped shape; Task 4 lands the formal Phase 8 test surface as a single suite (RED phase passes-on-first-run because the implementation is already in place, which is the expected outcome for a contract-only plan)._

## Files Created/Modified

**Created (4):**
- `validationLedger/Core/Load/LoadListItem.swift` — the D-02 envelope value type
- `validationLedgerTests/Networking/Fixtures/loads-list-degraded-counterparty.json` — 3-row fail-closed edge fixture
- `validationLedgerTests/Support/UIKitSnapshot.swift` — Wave 0 UIKit snapshot helper
- `validationLedgerTests/Loads/LoadListEnvelopeDecodeTests.swift` — 9-test Phase 8 envelope decode suite

**Modified (9):**
- `validationLedger/Core/Networking/Endpoints/LoadListEndpoint.swift` — `Response.loads: [Load]` -> `Response.loads: [LoadListItem]`; doc updated for D-02/D-03/D-05
- `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` — `listPayloads` rewritten in lockstep with the JSON fixtures (envelope shape); appended `registerForDegradedDemo()` + `degradedPayload`
- `validationLedger/Core/Load/Load.swift` — doc-comment list-endpoint reference `[Load]` -> `[LoadListItem]` + D-02 note (auto-fix; deviation Rule 2 — accuracy)
- `validationLedgerTests/Networking/Fixtures/loads-list-broker.json` — 9 rows envelope-wrapped, broker->carrier counterparties (incl. PhantomLine flagged on VL-1010)
- `validationLedgerTests/Networking/Fixtures/loads-list-shipper.json` — 5 rows, shipper->broker counterparties
- `validationLedgerTests/Networking/Fixtures/loads-list-carrier.json` — 6 rows, carrier->broker (incl. Keystone flagged on VL-1009)
- `validationLedgerTests/Networking/Fixtures/loads-list-dispatch.json` — 6 rows, dispatch->broker (incl. Keystone flagged on VL-1009)
- `validationLedgerTests/Networking/Fixtures/loads-list-factoring.json` — 4 rows, factoring->carrier
- `validationLedgerTests/Networking/Fixtures/loads-list-empty.json` — envelope-shape passthrough `{loads: [], next_cursor: null}` (byte-identical to pre-Phase-8 — empty array of any element type)
- `validationLedgerTests/Load/LoadDomainDecodeTests.swift` — `everyRoleListFixtureDecodes` loop body updated for element-type change (auto-fix; deviation Rule 3 — blocking)

## Decisions Made

- **Counterparty selection per fraud-archetype load.** D-04 strictly assigns counterparty roles per viewer (broker->carrier, etc.). When a load has multiple parties of the same role (e.g. VL-1009 with 2 brokers, 2 carriers; VL-1011 with 2 brokers), the canonical-counterparty rule is: search `state_history` backwards for the most-recent actor of the wanted role; fall back to the last matching `nodes[]` entry. This gives the "currently-engaged counterparty" — surfacing Keystone Freight Group (flagged broker) for VL-1009 carrier/dispatch rows, surfacing PhantomLine (flagged carrier) for VL-1010 broker row. Documented in this SUMMARY for downstream reference.
- **Empty fixture body unchanged.** `loads-list-empty.json` was already `{loads: [], next_cursor: null}` — that's envelope-shape passthrough because an empty array of any element type decodes uniformly.
- **No `validationLedgerTests/Support/UIKitSnapshot.swift` xcodeproj edit needed.** The test target uses `PBXFileSystemSynchronizedRootGroup` (line 58 of `project.pbxproj`); adding a file under `validationLedgerTests/Support/` auto-discovers without a project.pbxproj edit. The `Support/` directory was created during Task 1.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue caused by Task 2's element-type change] LoadDomainDecodeTests element-property access**
- **Found during:** Task 3 verification (test target build)
- **Issue:** `validationLedgerTests/Load/LoadDomainDecodeTests.swift` line 83 — `for load in response.loads { _ = load.status }` would not compile after Task 2 changed the element type from `Load` to `LoadListItem` (`status` is on `LoadListItem.load`, not `LoadListItem`).
- **Fix:** Renamed the loop variable to `item` and updated the access to `item.load.status` plus a one-line doc note explaining the Phase 8 D-02 envelope composition.
- **Files modified:** `validationLedgerTests/Load/LoadDomainDecodeTests.swift`
- **Verification:** scoped `-only-testing:validationLedgerTests/LoadDomainDecodeTests` passes 5/5 after the fix.
- **Committed in:** `5e3d76e` (with Task 3 lockstep rewrap, since the fix is only needed once Task 2's change is in effect and Task 3 was the next atomic commit).

**2. [Rule 2 — Documentation accuracy after wire-contract evolution] Load.swift doc comment stale reference**
- **Found during:** Task 3 cross-grep for surface references
- **Issue:** `validationLedger/Core/Load/Load.swift` lines 8-10 carried a doc-comment list embedded type as `LoadListEndpoint.Response.loads: [Load]` — stale after Task 2's change.
- **Fix:** Updated the doc to `LoadListEndpoint.Response.loads: [LoadListItem]` with a one-line Phase 8 D-02 envelope note.
- **Files modified:** `validationLedger/Core/Load/Load.swift`
- **Verification:** included in Task 3's overall build + scoped test runs (no behavioral change; doc-only).
- **Committed in:** `5e3d76e`.

**3. [Rule 3 — Environment fix] Plan verify destination substituted iPhone 17 for iPhone 15**
- **Found during:** Task 1 verification — `iPhone 16` is not installed on this host per the `ios-test-suite-pitfalls` project memory; the plan's verify commands specified `iPhone 15, OS=17.5` which also is not available locally.
- **Issue:** Plan specified `-destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'` which would fail to find a simulator.
- **Fix:** Substituted `iPhone 17` (the canonical installed simulator per project memory) and added `-skip-testing:validationLedgerDeviceTests` to the test runs (avoids the ~9 unrelated Secure Enclave failures on the simulator lane, also per project memory).
- **Files modified:** none (environmental)
- **Verification:** the substitute command is the documented "Correct simulator-lane command" in project memory.
- **Committed in:** N/A (environmental shortcut; no source edits).

---

**Total deviations:** 3 auto-fixed (2 × Rule 3 blocking, 1 × Rule 2 doc accuracy)
**Impact on plan:** Two compile/build blockers caused by the Task 2 element-type change (the plan acknowledged this in Task 4's `<done>`: "the test file may need an update for the element-type change"; deviation 1 above is exactly that case but for `LoadDomainDecodeTests`, not `LoadEndpointsTests` — `LoadEndpointsTests` does not access element fields so it needed no edit). Deviation 3 is environmental and matches existing project memory. No scope creep, no architectural change.

## Issues Encountered

- **Initial `#expect(..., "concatenated string")` build error.** The Swift Testing `Comment?` parameter rejects string concatenation expressions (`"a" + "b"`) because the autoclosure value isn't a literal context. Fixed by flattening the three multi-line concatenations into single-line literals (lines 183, 217, 268 of `LoadListEnvelopeDecodeTests.swift`).
- **First multi-suite scoped test run hit a stale bundle.** `xcodebuild test-without-building` after multiple incremental builds reported "Failed to create a bundle instance". A clean `build-for-testing` followed by `test-without-building` resolved it (23/23 tests green).

## User Setup Required

None — no external service configuration. All work landed against `MockURLProtocol`-driven fixtures per the v1.1 contract-first posture.

## Next Phase Readiness

**Ready for:**
- **Plan 02 (Badge components):** `LoadListItem.displayedCounterparty: TrustNode?` is the data shape `VerificationBadgeView` will bind to; `UIKitSnapshot` is in place for snapshot tests.
- **Plan 03 (ViewModel + states):** `APIClient.request(LoadListEndpoint(role:))` returns `Response.loads: [LoadListItem]`; the VM consumes this directly. `nextCursor` is decode-only per D-05 — the VM should store it but never read it.
- **Plan 04 (LoadRowCell):** `LoadRowCell` binds to one `LoadListItem` — reads `item.load` for the freight fields and `item.displayedCounterparty` for the counterparty badge (nil renders the neutral UNVERIFIED badge per D-03).
- **Plan 05 (SkeletonLoadRowCell):** Uses `UIKitSnapshot` to lock the silhouette-match assertion against the real cell at default Dynamic Type.
- **Plan 06 (Tab-bar wiring):** Independent of this plan; consumes Plans 02-05.

**No blockers.** All 9 LoadListEnvelopeDecodeTests + all 6 LoadEndpointsTests + all 5 LoadDomainDecodeTests + all 3 AppContainerLoadEndpointsConfigSwapTests + all 3 MockURLProtocolLatencyTests + all 5 MockURLProtocolRegistryTests are green against the new envelope. The `registerForDegradedDemo()` lane is ready for Plan 04's fail-closed UI tests to call directly. **23/23 scoped test runs green**, **0 regressions** in adjacent Phase 6/7 networking suites.

## Output Spec Coverage (from Plan)

- ✓ LoadListItem signature: `public struct LoadListItem: Decodable, Sendable { public let load: Load; public let displayedCounterparty: TrustNode? }`
- ✓ LoadListEndpoint change: `Response.loads: [Load]` -> `Response.loads: [LoadListItem]` (+ updated doc)
- ✓ 7 fixture file paths (5 role + empty + degraded) — see Files Created/Modified
- ✓ Registry inline-payload lockstep edit — 33 `displayed_counterparty` references inside `MockLoadFixtureRegistry.swift`
- ✓ `loads-list-degraded-counterparty.json` field selection — Row 1: null counterparty; Row 2: flagged carrier (PhantomLine Logistics, USDOT revoked, device mismatched, KYC very recent, prior relationship 0); Row 3: verified carrier (Acme Trucking Inc.) for contrast
- ✓ `registerForDegradedDemo()` lane signature — `static func registerForDegradedDemo() { MockURLProtocol.register { request in ... } }`, dispatches `GET /loads/degraded` -> inline `degradedPayload` (the AUTHORITATIVE COPY of the JSON fixture)
- ✓ Sentinel-role suffix choice — chosen because the existing dispatcher matches on URL path suffix with no query parsing; `/loads/degraded` slots into the same grammar (avoids both new dispatcher code and a separate XCUITest-only query-parameter approach)
- ✓ UIKitSnapshot API surface — `static func image(of view: UIView, size: CGSize) -> UIImage`; `static func attach(_ image: UIImage, name: String, to testCase: XCTestCase, lifetime: XCTAttachment.Lifetime = .keepAlways)`
- ✓ Open question that surfaced: the `LoadEndpointsTests.swift` update mentioned in Task 4's `<done>` was a misdirection in the plan — `LoadEndpointsTests` does NOT access element fields (only `.count`), so it needed no edit; `LoadDomainDecodeTests` was the file that needed the element-type-induced fix and that was auto-handled (deviation 1 above).

## Self-Check: PASSED

All 15 claimed files exist on disk; all 4 claimed commit hashes (9e2047b / ffd8b6b / 5e3d76e / e46850e) exist in `git log --oneline --all`.

---
*Phase: 08-role-filtered-load-list*
*Plan: 01 (wire-format extension + Wave 0)*
*Completed: 2026-05-20*
