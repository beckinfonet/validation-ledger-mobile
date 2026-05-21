---
phase: 10-per-role-tender-accept-reject
plan: 05
subsystem: networking/mock-data-layer
tags: [endpoint, mock-fixture, tender-sheet, carrier-directory, phase-10, plan-05]
requires:
  - validationLedger/Core/Load/ChainOfTrust.swift  # TrustNode (Phase 7 frozen type)
  - validationLedger/Core/Networking/APIEndpoint.swift  # APIEndpoint + EmptyBody + HTTPMethod
  - validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift  # existing handler registration
  - validationLedger/Core/Networking/APIClient.swift  # defaultDecoder()
provides:
  - CarrierDirectoryEndpoint (GET /carriers/directory, no body)
  - CarrierDirectoryEndpoint.Response { carriers: [TrustNode] }
  - validationLedgerTests/Networking/Fixtures/tender-carrier-directory.json
  - MockLoadFixtureRegistry.tenderCarrierDirectoryPayload (inline Data; mirrors the fixture)
  - MockLoadFixtureRegistry handler (4th in registerAppDefaults; GET /carriers/directory)
affects:
  - Plan 06 (tender sheet) — directly consumes CarrierDirectoryEndpoint as the picker source
  - Phase 7 mock-registry contract — additive change; existing 3 handlers (5 with DEBUG toggles) unchanged
tech-stack:
  added: []  # NO new packages / NO new domain types
  patterns:
    - APIEndpoint conformance for GET-no-body (LoadListEndpoint precedent)
    - MockURLProtocol.register closure handler with disjoint-path-namespace guard
    - Inline raw-string Data(#"""…"""#.utf8) payload literal mirroring a fixture file
key-files:
  created:
    - validationLedger/Core/Networking/Endpoints/CarrierDirectoryEndpoint.swift
    - validationLedgerTests/Networking/Fixtures/tender-carrier-directory.json
    - validationLedgerTests/Loads/CarrierDirectoryDecodeTests.swift
    - validationLedgerTests/Networking/Mock/CarrierDirectoryMockTests.swift
  modified:
    - validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift  # +1 handler, +1 payload constant; existing handlers untouched
decisions:
  - D-07 directory source — dedicated endpoint, NOT ChainOfTrust.nodes (a .posted load has no carrier yet on the happy path)
  - Envelope shape { carriers: [TrustNode] } mirrors LoadListEndpoint precedent
  - Inline JSON payload in registry (Option A) — DEBUG App bundle independent of the test bundle; manual-sync convention guarded by CarrierDirectoryMockTests Test 5
  - 7 carriers (mid-range of 6-8); 2× .verified / 2× .pending / 1× .unverified / 2× .flagged for visual coverage of "disabled-with-reason"
  - Chameleon Cargo LLC + Phantom Express are the .flagged anchors cross-referencing Phase 7 D-13 fraud archetypes (Specifics line 263-265)
metrics:
  duration: ~70 minutes
  completed: 2026-05-21T16:00:23Z
  tasks: 2 (both TDD: RED + GREEN)
  tests_added: 12 (7 decode + 5 mock)
  files_created: 4
  files_modified: 1
---

# Phase 10 Plan 05: Carrier Directory Endpoint + Mock Handler + Fixture Summary

**One-liner:** Adds the `GET /carriers/directory` typed endpoint, the 7-carrier synthetic demo fixture spanning all 4 `VerificationState` cases (including the Chameleon Cargo fraud archetype as the `.flagged` anchor), and the `MockURLProtocol` handler that returns the directory under DEBUG — wiring the data source the Plan 06 tender-sheet picker (ACTION-04 enforcement gate) will consume.

## What Shipped

### 1. `CarrierDirectoryEndpoint` (NEW)

```swift
nonisolated public struct CarrierDirectoryEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody
    public struct Response: Decodable, Sendable {
        public let carriers: [TrustNode]
    }
    public let path: String = "/carriers/directory"
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil
    public init() {}
}
```

- File-shape analog: `LoadListEndpoint.swift` (envelope GET endpoint precedent).
- `Response.carriers: [TrustNode]` — reuses the existing Phase 7 frozen `TrustNode` type. **No new domain type was introduced.**
- `nonisolated` conformance required under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — same constraint Phase 7 endpoints satisfy.

### 2. The 7-carrier fixture roster

| #  | partyID                       | displayName              | verificationState | deviceBindingStatus | usdotAuthorityStatus | Why                                                       |
| -- | ----------------------------- | ------------------------ | ----------------- | ------------------- | -------------------- | --------------------------------------------------------- |
| 1  | `party-carrier-acme`          | Acme Logistics Inc.      | **verified**      | bound               | active               | KYC + active USDOT; the picker's happy-path target        |
| 2  | `party-carrier-northwind`     | Northwind Freight Co.    | **verified**      | bound               | active               | Second .verified — picker shows multiple selectable rows  |
| 3  | `party-carrier-cascadia`      | Cascadia Cartage         | **pending**       | unbound             | active               | KYC in progress; demonstrates disabled-with-reason        |
| 4  | `party-carrier-summit`        | Summit Routing LLC       | **pending**       | unbound             | active               | Second .pending; no USDOT number                          |
| 5  | `party-carrier-anonymous`     | Anonymous Hauling        | **unverified**    | unbound             | not_applicable       | No KYC, no USDOT — least-trusted disabled row             |
| 6  | `party-carrier-chameleon`     | Chameleon Cargo LLC      | **flagged**       | mismatched          | revoked              | **Fraud-archetype anchor** (Specifics line 264, Phase 7 D-13) |
| 7  | `party-carrier-phantom`       | Phantom Express          | **flagged**       | mismatched          | suspended            | Second .flagged — disabled-with-reason has multiple rows  |

All 7 names are **synthetic** — T-10-04 (T-08-04 inheritance) zero-PII discipline. CarrierDirectoryDecodeTests Test 5 enforces this via a real-world brand allowlist guard.

### 3. The inline-in-registry payload convention

`MockLoadFixtureRegistry.tenderCarrierDirectoryPayload` is a `Data(#"""…"""#.utf8)` constant whose JSON content mirrors `validationLedgerTests/Networking/Fixtures/tender-carrier-directory.json` **byte-faithfully**. The convention exists because the DEBUG App bundle must remain independent of the test bundle's fixture files (the existing `MockLoadFixtureRegistry` file-header invariant, applied to every prior payload constant).

**A future fixture edit MUST update both files in lockstep.** `CarrierDirectoryMockTests Test 5` is the regression guard — it decodes the fixture file directly, then drives a request through `MockURLProtocol`, and asserts the partyID order + count + state set match exactly. Drift between the two will turn this test red.

### 4. The 4th MockURLProtocol handler

Inserted in `MockLoadFixtureRegistry.registerAppDefaults()` **after** the action-success handler. The path namespace (`/carriers/directory`) is **disjoint** from the existing `/loads/*` handlers, so registration order does not affect shadowing — the structural defense (T-10-PR-02 mitigation) is the exact `request.url?.path == "/carriers/directory"` guard, not the registration order.

```swift
// (4) Phase 10 D-07 (Plan 05) — Carrier directory handler.
MockURLProtocol.register { request in
    guard request.httpMethod == "GET" else { return nil }
    guard request.url?.path == "/carriers/directory" else { return nil }
    return make200(body: tenderCarrierDirectoryPayload, url: request.url)
}
```

The existing 3 handlers (per-role list, per-VL detail, action-success) + the 4 Phase 10 D-19 DEBUG failure-injection toggles are **unchanged**.

## Tests Added

| Suite                              | Test                                                           | What it locks                                                                       |
| ---------------------------------- | -------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `CarrierDirectoryDecodeTests`      | Test 1: fixture decodes via defaultDecoder, 6-8 carriers       | Fixture-decoder contract integrity                                                  |
|                                    | Test 2: ALL 4 VerificationState cases present                  | D-07 product-surface requirement                                                    |
|                                    | Test 3: at least one .flagged Chameleon carrier                | Specifics line 264 fraud-archetype anchor                                           |
|                                    | Test 4: every entry's role == .carrier                         | Schema-shape guard (no role pollution)                                              |
|                                    | Test 5: no real-world brand substrings                         | T-10-04 zero-PII allowlist                                                          |
|                                    | Test 6: at least one .verified carrier                         | Happy-path Send unblocked                                                           |
|                                    | Test 7: endpoint exposes GET /carriers/directory               | Endpoint contract                                                                   |
| `CarrierDirectoryMockTests`        | Test 1: apiClient request returns decoded directory            | End-to-end MockURLProtocol → APIClient → typed response                             |
|                                    | Test 2: does NOT shadow GET /loads/{id}                        | T-10-PR-02 non-shadow invariant (detail)                                            |
|                                    | Test 3: does NOT shadow GET /loads/{role}                      | T-10-PR-02 non-shadow invariant (list)                                              |
|                                    | Test 4: does NOT shadow POST /loads/{id}/{action}              | T-10-PR-02 non-shadow invariant (action; httpMethod guard)                          |
|                                    | Test 5: inline payload matches fixture (sync guard)            | T-10-PR-01 manual-sync regression guard                                             |

**Total:** 12 new tests, all green.

**Sibling regression check:** `MockLoadFixtureRegistryActionToggleTests` (8 tests) + `MockLoadActionDispatchTests` (5 tests) — all still green; the additive handler did not break the Phase 7 / Phase 10 D-19 contracts.

## Notes for Plan 06 (TenderSheetViewController)

When wiring the picker data source:

1. **Request the endpoint** when the sheet is presented:
   ```swift
   let directoryResponse = try await apiClient.request(CarrierDirectoryEndpoint())
   let carriers: [TrustNode] = directoryResponse.carriers
   ```

2. **Pass the carriers into the sheet VC's initializer** per the RESEARCH Open Question 4 shape (`10-PATTERNS.md` §5):
   ```swift
   TenderSheetViewController(
       directory: directoryResponse.carriers,
       onSend: { … },
       onCancel: { … }
   )
   ```

3. **Per-row enablement** reads from `TrustNode.verificationState`:
   - `.verified` → row enabled
   - `.pending` / `.unverified` / `.flagged` → row visible but **disabled** with a reason line (UI-SPEC line 444; the platform-thesis "I cannot tender to this party" UX moment in Specifics line 263)

4. **Picker row composition** (UI-SPEC line 444): `RoleAvatarView(.tree)` + `displayName` + `VerificationBadgeView` (rendering `verificationState`) + the verification-reason line for non-verified rows.

5. **The Chameleon Cargo `.flagged` row IS the platform thesis** — it must visibly demonstrate the fraud-archetype rendering the first time any broker opens the picker (Specifics line 263-265). Do not silently hide flagged carriers from the list.

## Deviations from Plan

- **Plan note:** the plan's `<read_first>` for Task 1 cites "the project's GET-no-body type; if it's `Never` or a different idiom, match the LoadListEndpoint precedent verbatim." Verified `LoadListEndpoint` uses `typealias RequestBody = EmptyBody` + `let body: RequestBody? = nil`. The new endpoint mirrors this exactly.
- **Plan note:** the plan's `<read_first>` for Task 2 was written against the **Wave-2 base** ("existing 3 handlers at lines 128-167"). The actual base for Wave 4 already includes Plan 10-08's additions (4 DEBUG failure-injection handlers + `resetForTestOnly`). The handler was registered **after** the action-success handler (now line ~261, not 167); the disjoint-path-namespace makes registration order non-load-bearing. Captured in the new handler's inline comment.
- **Fixture format:** chose a top-level `_comment` field to embed the fixture-header comment inside the JSON (the synthesized decoder ignores unknown keys, so this is safe and survives any JSON tooling — including the inline registry-payload literal). The plan offered "above-JSON comment OR `_comment` field"; `_comment` was picked because raw JSON files cannot carry pre-document line comments without a different file format.
- **No Rules 1-4 deviations.** No bugs auto-fixed, no critical functionality added beyond what the plan specified, no architectural changes.

## Known Stubs

None. This plan ships the actual data layer — no placeholder views, no TODO-tagged data sources. Plan 06 (tender sheet) consumes this directly.

## Self-Check

**Files exist:**
<!-- evidence -->
- `validationLedger/Core/Networking/Endpoints/CarrierDirectoryEndpoint.swift` — FOUND
- `validationLedgerTests/Networking/Fixtures/tender-carrier-directory.json` — FOUND
- `validationLedgerTests/Loads/CarrierDirectoryDecodeTests.swift` — FOUND
- `validationLedgerTests/Networking/Mock/CarrierDirectoryMockTests.swift` — FOUND
- `validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift` — MODIFIED (verified by grep above: `tenderCarrierDirectoryPayload` count = 4; `/carriers/directory` count = 2)

**Commits exist (`git log --oneline`):**
- `b9919ea` test(10-05): add failing CarrierDirectoryDecodeTests (RED) — FOUND
- `94d9d55` feat(10-05): add CarrierDirectoryEndpoint + 7-carrier fixture (GREEN) — FOUND
- `185c71c` test(10-05): add failing CarrierDirectoryMockTests (RED) — FOUND
- `16863ec` feat(10-05): register /carriers/directory mock handler + inline payload (GREEN) — FOUND

**Tests:**
- 7/7 CarrierDirectoryDecodeTests — GREEN
- 5/5 CarrierDirectoryMockTests — GREEN
- 8/8 MockLoadFixtureRegistryActionToggleTests — GREEN (regression check)
- 5/5 MockLoadActionDispatchTests — GREEN (regression check)

## Self-Check: PASSED
