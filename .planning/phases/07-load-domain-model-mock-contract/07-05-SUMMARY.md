---
phase: 07-load-domain-model-mock-contract
plan: 05
subsystem: testing
tags: [json-fixtures, swift-testing, apiclient-defaultdecoder, fail-closed-decode, fraud-archetypes, chain-of-trust]

requires:
  - phase: 07-load-domain-model-mock-contract/02
    provides: "Load + ChainOfTrust + TrustNode + TrustEdge + ChainIntegrity + LoadStatusEvent value types (the decode targets every fixture must satisfy)"
  - phase: 07-load-domain-model-mock-contract/03
    provides: "LoadListEndpoint.Response, LoadDetailEndpoint.Response, LoadActionEndpoint.Response (the typed Response envelopes the fixtures decode into)"
provides:
  - "12 named load-detail JSON fixtures (D-12 D-13 — the V1.1 demo-data library)"
  - "5 per-role list fixtures + 1 empty-list fixture (D-11 shared-world; byte-identical Load payloads across role files)"
  - "4 action-outcome fixtures (D-14: success, conflict-409, validation-422, server-error-500)"
  - "LoadDomainDecodeTests — 5 tests covering all 22 fixtures via APIClient.defaultDecoder()"
  - "ChainOfTrustDecodeTests — 7 tests pinning the 3 D-13 fraud archetypes + clean + Pitfall 5 cases"
  - "LoadStateHistoryTests — 4 tests pinning D-02 timeline ordering + LoadStatusEvent decode"
affects: [07-06 mock-fixture-registry, 08-load-list, 09-load-detail-trust-graph, 10-load-action-bar]

tech-stack:
  added: []
  patterns:
    - "Fixture-decode round-trip via APIClient.defaultDecoder() (any drift in .convertFromSnakeCase/.iso8601 strategy surfaces in tests)"
    - "Per-role list fixture derived from load-detail fixtures via byte-identical Load copy (D-11 shared-world enforced by Python diff)"
    - "Action error-body fixtures parsed as JSON (no typed error-body struct yet); Plan 04 forced-failure delivers them as Data on NetworkError.httpError"
    - "Hand-authored in-test JSON for out-of-order timestamp coverage (decoder MUST NOT re-sort stateHistory)"

key-files:
  created:
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1001.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1002.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1003.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1004.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1005.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1006.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1007.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1008.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1009.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1010.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1011.json
    - validationLedgerTests/Networking/Fixtures/load-detail-VL-1012.json
    - validationLedgerTests/Networking/Fixtures/loads-list-shipper.json
    - validationLedgerTests/Networking/Fixtures/loads-list-broker.json
    - validationLedgerTests/Networking/Fixtures/loads-list-carrier.json
    - validationLedgerTests/Networking/Fixtures/loads-list-dispatch.json
    - validationLedgerTests/Networking/Fixtures/loads-list-factoring.json
    - validationLedgerTests/Networking/Fixtures/loads-list-empty.json
    - validationLedgerTests/Networking/Fixtures/load-action-success.json
    - validationLedgerTests/Networking/Fixtures/load-action-conflict-409.json
    - validationLedgerTests/Networking/Fixtures/load-action-validation-422.json
    - validationLedgerTests/Networking/Fixtures/load-action-server-error-500.json
    - validationLedgerTests/Load/LoadDomainDecodeTests.swift
    - validationLedgerTests/Load/ChainOfTrustDecodeTests.swift
    - validationLedgerTests/Load/LoadStateHistoryTests.swift
  modified: []

key-decisions:
  - "VL-1005 caution verdict (Claude's Discretion per 07-CONTEXT.md): the expired-tender load with the pending/unbound target carrier carries integrity.verdict == .caution with the broker→carrier edge in relationship_state .unverified — this is the only fixture that exercises the .caution verdict, giving the test suite full coverage across .clean / .caution / .compromised. VL-1008 also carries .caution (target carrier .unverified) for the ACTION-07 hard-disable flow"
  - "Action error-body fixtures carry {error_code, message} as a JSON object (not a typed Response). Plan 04 forced-failure delivers them as the .body argument of NetworkError.httpError; LoadDomainDecodeTests Test 4 pins the wire shape (object with two string fields) so a future schema drift surfaces here"
  - "VL-1009 narrative reason mentions 're-tender'; VL-1010 mentions 'USDOT' + 'revocation'; VL-1011 mentions 'factoring' + 'invoice' + 'clawback' — matches the plan's exact substring requirements for the Phase 9 graph banner copy"
  - "Test target Resources registration achieved via Xcode 15+ synchronized-root-group (PBXFileSystemSynchronizedRootGroup at pbxproj line 58) — no manual pbxproj edits required. JSON files dropped into validationLedgerTests/Networking/Fixtures/ are automatically resourced by Xcode based on the filesystem"

patterns-established:
  - "Pattern: Per-fixture decode round-trip in a parameterized @Test loop (LoadDomainDecodeTests.everyLoadDetailFixtureDecodes iterates the 12-id static array) so a new fixture only needs to be added to the static `allLoadIDs` list to gain coverage"
  - "Pattern: Shared-world consistency (D-11) enforced by Python script that copies .load from load-detail-VL-*.json into role-list fixtures — byte-identity then checked by the decode test (any l == d). A future hand-edit to a role-list fixture that diverges from the detail fixture is caught immediately"
  - "Pattern: Hand-authored in-test JSON literal (LoadStateHistoryTests.decoderPreservesDeclaredOrder) for cases that can't be expressed via fixture file (deliberately malformed/out-of-order)"

requirements-completed: [LOAD-01, LOAD-02]

# Metrics
duration: ~1h 5m
completed: 2026-05-20
---

# Phase 7 Plan 05: Fixture Matrix + Decode Tests Summary

**22 JSON fixtures (12 named loads + 5 role lists + empty + 4 action outcomes) authored to the D-12 / D-13 / D-14 contract, validated by 16 Swift Testing tests that decode every fixture via APIClient.defaultDecoder() — delivering Roadmap SC #1 (every fixture decodes).**

## Performance

- **Duration:** ~1h 5m
- **Started:** 2026-05-19T17:18:00Z (approximate)
- **Completed:** 2026-05-20T00:23:40Z
- **Tasks:** 3
- **Files modified:** 25 (22 fixtures + 3 test suites; no source files touched)

## Accomplishments
- **Fraud-archetype fixtures are real demo data, not minimal mechanical coverage:** VL-1009 narrates a double-broker (FreightWise → Keystone re-tenders to Red Rock Carriers with the broker→broker AND broker→carrier edges both flagged; integrity.reason calls out "re-tender" by name); VL-1010 narrates a chameleon carrier (PhantomLine Logistics with USDOT 3998112 revoked, freshly KYC'd, device mismatched); VL-1011 narrates factoring fraud with a flagged factoring identity (StagePay Funding, zero prior relationships) attached to a double-brokered chain
- **D-11 shared-world byte-identity verified:** the same `load` payload appears in `load-detail-VL-1009.json` AND `loads-list-broker.json` AND `loads-list-carrier.json` AND `loads-list-dispatch.json` AND `loads-list-factoring.json` — Python diff confirms byte-identity, and the decode test asserts `any(l == d for l in b)`
- **All 16 tests pass on iPhone 17 simulator** with `xcodebuild test -parallel-testing-enabled NO` — exit code 0, `** TEST SUCCEEDED **`
- **All 3 verdict cases (.clean, .caution, .compromised) exercised by fixtures:** VL-1001/1002/1003/1006/1007/1012 (clean), VL-1005/1008 (caution), VL-1009/1010/1011 (compromised)
- **Pitfall 5 (optional-field absence) exercised by 4 distinct cases:** VL-1003 respond_by_at null + tender_eligibility null; VL-1005 in-array TrustNode kyc_completed_at null; VL-1006 chain.edges empty array; VL-1008 tender_eligibility populated with can_tender false

## Task Commits

Each task was committed atomically:

1. **Task 1: Author the 12 named load-detail JSON fixtures (D-12 + D-13)** — `7e781c3` (test)
2. **Task 2: Author the 5 per-role list fixtures + empty + 4 action-outcome fixtures (D-11, D-14)** — `d2d5115` (test)
3. **Task 3: LoadDomainDecodeTests + ChainOfTrustDecodeTests + LoadStateHistoryTests** — `e77f071` (test)

**Plan metadata commit follows this SUMMARY.**

## Files Created/Modified

### Fixtures (22 files, all under `validationLedgerTests/Networking/Fixtures/`)
- `load-detail-VL-1001.json` … `load-detail-VL-1012.json` — full LoadDetailEndpoint.Response payloads (12 files); each carries `load` + `chain_of_trust`
- `loads-list-shipper.json` (5 loads), `loads-list-broker.json` (9 loads), `loads-list-carrier.json` (6 loads), `loads-list-dispatch.json` (6 loads), `loads-list-factoring.json` (4 loads) — LoadListEndpoint.Response payloads per D-11
- `loads-list-empty.json` — empty-list mechanical fixture
- `load-action-success.json` — VL-1004 post-accept LoadActionEndpoint.Response
- `load-action-conflict-409.json` (`error_code: load.stale_state`), `load-action-validation-422.json` (`error_code: load.invalid_transition`), `load-action-server-error-500.json` (`error_code: server.internal`)

### Test suites (3 files, all under `validationLedgerTests/Load/`)
- `LoadDomainDecodeTests.swift` — 148 lines, 5 `@Test` methods covering Roadmap SC #1
- `ChainOfTrustDecodeTests.swift` — 140 lines, 7 `@Test` methods covering D-13 fraud archetypes + Pitfall 5
- `LoadStateHistoryTests.swift` — 137 lines, 4 `@Test` methods covering D-02 timeline contract

## Decisions Made

1. **VL-1005 carries verdict `.caution` (Claude's Discretion per 07-CONTEXT.md).** The expired-tender fixture was the natural carrier for the .caution verdict — the prior tender expired without response, the target carrier identity (National Link Carriers) is .pending KYC, and the broker→carrier edge is .unverified. This gives the test surface full coverage across all 3 ChainIntegrity.Verdict cases (clean / caution / compromised) without inventing a new VL- identity. VL-1008 also rides at .caution for the target-carrier-unverified ACTION-07 flow.

2. **Action error-body fixtures stay as bare JSON objects (`{error_code, message}`), not typed Responses.** The v1.0 NetworkError doesn't yet have a typed error-body struct; the mock layer (Plan 04 forced-failure) surfaces them as the `data:` argument of `NetworkError.httpError(statusCode:data:)`. LoadDomainDecodeTests Test 4 pins the wire shape with JSONSerialization so a fixture schema drift surfaces here before it surfaces as a "mystery 422 with no body" bug downstream.

3. **Test target Resources registration is automatic via Xcode 15+ synchronized-root-group.** The pbxproj uses `PBXFileSystemSynchronizedRootGroup` for `validationLedgerTests` (declared at lines 57-67 of `validationLedger.xcodeproj/project.pbxproj`). Files dropped into the test target's filesystem are automatically picked up — no manual file-reference or resource-build-phase edit required. The plan's Task 1/Task 2 acceptance criterion that grepped pbxproj for fixture filenames is not applicable to this project shape; the functional acceptance (`FixtureLoader.loadFixture` returns non-nil for every fixture) is verified by the passing tests.

4. **VL-1009 narrative `reason` contains the substring "re-tender"** (matches the plan's exact requirement that the reason text contain "broker" OR "re-tender"). VL-1010 reason contains both "USDOT" and "revocation" (exceeds the OR requirement). VL-1011 reason contains "factoring" + "invoice" + "clawback" (exceeds the OR requirement). The Phase 9 graph banner has rich, specific copy to render.

5. **`load-action-success.json` was built by deepcopy from `load-detail-VL-1004.json` + post-accept mutations** (status → accepted, respond_by_at → null, stateHistory appended with accepted event, broker→carrier edge promoted from .pending → .verified, integrity reason rewritten). The post-action chain is internally consistent — a tender that lands on a verified carrier promotes the edge.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Project shape mismatch] pbxproj acceptance criterion not applicable to synchronized-root-group projects**
- **Found during:** Task 1 (initial verification scan)
- **Issue:** Plan acceptance criteria for Tasks 1 and 2 required `grep -c "load-detail-VL-" validationLedger.xcodeproj/project.pbxproj` to return ≥24 (each fixture appearing as both a file reference and a build-phase entry). The project uses `PBXFileSystemSynchronizedRootGroup` for `validationLedgerTests` (Xcode 15+ filesystem-driven), so no file references or build-phase entries exist in the pbxproj — they're inferred from the filesystem.
- **Fix:** Did NOT edit pbxproj. Verified functional equivalence: the passing tests in Task 3 prove `FixtureLoader.loadFixture` resolves every fixture (otherwise every test would throw `FixtureLoader.Error.fixtureNotFound`).
- **Files modified:** None (the deviation is the absence of a pbxproj edit, not its presence)
- **Verification:** All 16 Task 3 tests pass on the simulator; every test reads at least one fixture via `FixtureLoader.loadFixture` and uses the data, so a missing-resource would have failed loudly.
- **Committed in:** N/A (no commit produced; this is a documented departure from the literal acceptance criterion in favour of functional equivalence)

---

**Total deviations:** 1 (Rule 3 — blocking-equivalent: the literal acceptance check would have spuriously failed on a correctly-configured project)
**Impact on plan:** Zero scope impact; the plan's intent (fixtures resolvable at runtime) is fully satisfied. The pbxproj-grep acceptance criterion was a check designed for non-synchronized-group projects.

## Issues Encountered
None — Wave 2 / Wave 3 outputs (Load aggregate types, Response envelopes, APIClient.defaultDecoder()) all composed cleanly; no decoder drift surfaced.

## Threat Surface Scan
No new threat surfaces introduced beyond the plan's `<threat_model>` (T-07-22 through T-07-26):
- T-07-22 (tampered permissive fixture) — mitigated by every fixture being git-tracked; all 22 went through this commit.
- T-07-23 (weak verification_state on archetype) — VL-1009/1010/1011 all use `flagged` on the archetype party (verified by ChainOfTrustDecodeTests). VL-1008 uses `unverified` (semantic distinction preserved per D-09).
- T-07-24 (stateHistory tampered) — LoadStateHistoryTests Test 1 asserts monotonic non-decreasing on VL-1001; Test 4 documents that the decoder does NOT re-sort, locking the server-side ordering contract.
- T-07-25 (PII in fixtures) — Realistic-but-fake business names only; no SSN/DOB/document images.
- T-07-26 (fixture missing from Resources) — Synchronized-root-group makes this structurally impossible (file on disk is in the bundle by definition); decode tests would throw `FixtureLoader.Error.fixtureNotFound` if the path was wrong.

## Known Stubs
None. Every fixture carries fully-populated payloads — TrustNode kyc_completed_at is null only on parties that have never completed KYC (semantically correct), chain.edges is empty only on the VL-1006 draft (semantically correct), respond_by_at is null only on non-tendered loads (semantically correct). No "TODO" / "placeholder" text in any fixture; no mock data wired to UI (this plan is pre-UI).

## TDD Gate Compliance
This is a `type: execute` plan (not `type: tdd`). Each task's commit is a `test(…)` commit by virtue of the work being test-fixture + test-suite authoring; no `feat(…)` commits expected.

## Self-Check: PASSED

**Files exist:**
- FOUND: validationLedgerTests/Networking/Fixtures/load-detail-VL-1001.json (and VL-1002 … VL-1012)
- FOUND: validationLedgerTests/Networking/Fixtures/loads-list-shipper.json (and broker / carrier / dispatch / factoring / empty)
- FOUND: validationLedgerTests/Networking/Fixtures/load-action-success.json (and conflict-409 / validation-422 / server-error-500)
- FOUND: validationLedgerTests/Load/LoadDomainDecodeTests.swift
- FOUND: validationLedgerTests/Load/ChainOfTrustDecodeTests.swift
- FOUND: validationLedgerTests/Load/LoadStateHistoryTests.swift

**Commits exist:**
- FOUND: 7e781c3 (Task 1)
- FOUND: d2d5115 (Task 2)
- FOUND: e77f071 (Task 3)

**Test result:** 16/16 tests pass on `xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:…` — exit code 0.

## Next Phase Readiness
Plan 07-06 (mock-fixture-registry — wires these 22 fixtures into `MockLoadFixtureRegistry` for the DEBUG tap-through) is unblocked. Phase 8 (load-list) and Phase 9 (load-detail + trust-graph) consumers can begin against this fixture set; the byte-identical Load payload across role lists + detail fixtures means a Phase 8 list-cell that taps through to Phase 9 detail sees the same data on both ends, exactly as the real backend will behave.

---
*Phase: 07-load-domain-model-mock-contract*
*Completed: 2026-05-20*
