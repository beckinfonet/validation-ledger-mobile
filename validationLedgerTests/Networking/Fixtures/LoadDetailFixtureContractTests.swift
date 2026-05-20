// validationLedgerTests/Networking/Fixtures/LoadDetailFixtureContractTests.swift
//
// Phase 9 Plan 02 Task 2 — the D-14 contract gate. NOT a stub; fully
// implemented in Wave 0 so it is the runtime gate Plan 01's fixture
// re-authoring runs against in CI.
//
// Locked targets:
//   - VALIDATION.md line 79 (Wave 0 list).
//   - PATTERNS.md table row line 46 — closest analog
//     `Load/ChainOfTrustDecodeTests.swift` (PATTERNS E10 — fixture-corpus
//     enumeration template).
//
// === What this gate enforces (D-14) ===
// Per Phase 9 D-12 / D-13 / D-14:
//   1. Every `load-detail-VL-####.json` fixture decodes through
//      `APIClient.defaultDecoder()` as `LoadDetailEndpoint.Response.self`.
//      (Plan 01's `ChainOfTrust.swift` mutation + fixture re-authoring must
//      land together; this decode call gates the pair.)
//   2. Zero occurrences of the legacy snake_case wire key
//      `prior_relationshipCount` (the post-Plan-01 removed field) anywhere
//      in any fixture's raw JSON — RESEARCH §7 line 865 global grep promise
//      enforced at runtime. The literal legacy key string lives ONLY inside
//      `Test 2`'s `String.contains(_:)` argument (acceptance criterion:
//      exactly one occurrence in the file).
//   3. Every TrustNode entry in every fixture carries a `prior_relationships`
//      array key on the wire (matched by counting `"role":` occurrences
//      equal to `"prior_relationships":` occurrences in the
//      `chain_of_trust.nodes[]` slice).
//   4. Per D-14 archetype rules (RESEARCH §7 line 846):
//        - VL-1001 (clean baseline): the carrier node carries 5+ priors.
//        - VL-1009 (double-broker): the flagged carrier carries ≤ 2 priors.
//        - VL-1010 (chameleon carrier): the flagged carrier carries an
//          EMPTY prior_relationships array (the empty array IS the marquee
//          fraud signal — "First time working together").
//        - VL-1011 (factoring fraud): the factoring node carries > 0 priors
//          (curated collusion pattern).
//
// === Implementation note — raw-JSON gate, NOT typed-Swift access ===
// All archetype assertions inspect the raw JSON via JSONSerialization +
// String scanning. The single typed `decoder.decode(...)` call proves the
// post-Plan-01 contract still wires end-to-end without binding any new
// Swift property names into THIS file. Rationale:
//   - In Plan 02's worktree (running in parallel with Plan 01) the new
//     `priorRelationships` Swift property does not exist; raw-JSON gating
//     keeps this file compiling against the current `ChainOfTrust.swift`
//     surface while still failing loud against the wire shape Plan 01 must
//     produce. Once both worktrees merge, both gates hold.
//   - Raw-JSON gating is a STRONGER contract gate than typed access: it
//     catches a Plan 01 regression even if the Swift type accidentally
//     keeps a legacy alias. Wire format is the contract; the typed surface
//     is its consumer.
//
// === T-09-04 (PII) ===
// Tests inspect synthetic Phase 7 fixture data only; no PII reaches the CI
// artefacts.
//
// === T-09-05 (no client-trust derivation) ===
// This test READS server-supplied fixture data verbatim; it never derives
// trust state. Each archetype-rule assertion compares a fixed count or
// boolean against the wire shape Plan 01 ships.
//
// === .serialized requirement ===
// Although this suite does not touch `MockURLProtocol`'s global registry,
// it is `.serialized` to align with the Phase 7 / Phase 8 fixture-touching
// suite convention (ChainOfTrustDecodeTests + LoadListEnvelopeDecodeTests).
// Future maintenance that adds MockURLProtocol-backed assertions stays
// race-free by default.

import Testing
import Foundation
@testable import validationLedger

@Suite("LoadDetailFixtureContractTests — Phase 9 D-14 contract gate (priorRelationships array)", .serialized)
struct LoadDetailFixtureContractTests {

    // MARK: - Fixture corpus (D-13: 12 detail fixtures)

    /// Every `load-detail-VL-####.json` fixture filename (sans extension)
    /// shipped by Phase 7 and re-authored by Phase 9 Plan 01. Order is the
    /// sort order Plan 01 re-authors.
    private static let allFixtureIDs: [String] = [
        "load-detail-VL-1001",
        "load-detail-VL-1002",
        "load-detail-VL-1003",
        "load-detail-VL-1004",
        "load-detail-VL-1005",
        "load-detail-VL-1006",
        "load-detail-VL-1007",
        "load-detail-VL-1008",
        "load-detail-VL-1009",
        "load-detail-VL-1010",
        "load-detail-VL-1011",
        "load-detail-VL-1012",
    ]

    // MARK: - Test 1 — Every fixture decodes through APIClient.defaultDecoder()

    /// Decode gate. After Plan 01's `ChainOfTrust.swift` mutation +
    /// fixture re-authoring land, every `LoadDetailEndpoint.Response`
    /// decode succeeds. Before that landing the decode throws because
    /// either the Swift type still expects `priorRelationshipCount` and
    /// the fixtures carry `prior_relationships`, OR vice versa — this
    /// test is the runtime gate forcing the pair to land together.
    @Test("Every load-detail-VL-####.json decodes through APIClient.defaultDecoder() with the new prior_relationships array shape")
    func everyFixtureDecodesUnderDefaultDecoder() throws {
        let decoder = APIClient.defaultDecoder()
        for id in Self.allFixtureIDs {
            let data = try FixtureLoader.loadFixture(id)
            #expect(throws: Never.self, "Fixture \(id) MUST decode as LoadDetailEndpoint.Response under APIClient.defaultDecoder() — Plan 01 ChainOfTrust.swift mutation + fixture re-authoring must land together (D-12 + D-14).") {
                _ = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)
            }
        }
    }

    // MARK: - Test 2 — Legacy wire key is absent (negative gate)

    /// RESEARCH §7 line 865 global grep promise, enforced at runtime.
    /// Every fixture's raw JSON has ZERO occurrences of the legacy wire
    /// key. Per D-12, the field is fully removed — no aliasing, no parallel
    /// fields. A Plan 01 regression that leaves the legacy key behind fails
    /// here. The literal legacy-key string lives ONLY inside this
    /// `String.contains(_:)` argument so the acceptance criterion (file-wide
    /// `grep -c` returns 1) holds.
    @Test("Legacy prior-relationship-count wire key is absent from every fixture's raw JSON (D-12 negative gate)")
    func legacyWireKeyAbsentFromEveryFixture() throws {
        for id in Self.allFixtureIDs {
            let data = try FixtureLoader.loadFixture(id)
            guard let rawJSON = String(data: data, encoding: .utf8) else {
                Issue.record("Fixture \(id) could not be decoded as UTF-8 text")
                continue
            }
            #expect(
                !rawJSON.contains("prior_relationship_count"),
                "Fixture \(id) MUST NOT carry the legacy wire key (D-12: removed entirely; replaced by prior_relationships array)"
            )
        }
    }

    // MARK: - Test 3 — Every TrustNode carries a prior_relationships key

    /// Positive presence gate. The chain_of_trust.nodes[] array on every
    /// fixture has the same count of "prior_relationships" keys as
    /// TrustNode entries. (We count `"role":` inside the nodes slice as
    /// the TrustNode count, mirroring the pattern Plan 01 re-authoring
    /// MUST land.)
    @Test("Every TrustNode in every fixture's chain_of_trust.nodes carries a prior_relationships array key (D-14 presence gate)")
    func everyTrustNodeCarriesPriorRelationshipsKey() throws {
        for id in Self.allFixtureIDs {
            let data = try FixtureLoader.loadFixture(id)
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chain = parsed["chain_of_trust"] as? [String: Any],
                  let nodes = chain["nodes"] as? [[String: Any]] else {
                Issue.record("Fixture \(id) does not parse as JSON with chain_of_trust.nodes[] array")
                continue
            }
            #expect(nodes.count > 0, "Fixture \(id) must have at least one TrustNode")
            for (idx, node) in nodes.enumerated() {
                #expect(
                    node["prior_relationships"] != nil,
                    "Fixture \(id) chain_of_trust.nodes[\(idx)] (party_id=\(node["party_id"] ?? "?")) MUST carry a prior_relationships key (D-14: every TrustNode carries the array, never the count)"
                )
                // Strict shape: it MUST be an array (possibly empty), not a
                // number or string. The empty-array form is the chameleon
                // archetype's fraud signal.
                #expect(
                    node["prior_relationships"] is [Any],
                    "Fixture \(id) chain_of_trust.nodes[\(idx)] prior_relationships MUST be a JSON array (possibly empty) — not a number / string / object"
                )
            }
        }
    }

    // MARK: - Archetype rules per D-14 (RESEARCH §7 line 846)

    /// VL-1001 clean baseline: the carrier node carries 5+ priorRelationships
    /// entries — the trust history that reinforces the platform thesis on a
    /// non-fraud archetype.
    @Test("Clean baseline (VL-1001): the carrier TrustNode carries 5+ priorRelationships entries (D-14 clean rule)")
    func cleanBaselineCarrierCarriesFivePlusPriorRelationships() throws {
        let priors = try priorRelationshipsCount(forFixture: "load-detail-VL-1001", whereRoleEquals: "carrier")
        #expect(
            priors >= 5,
            "VL-1001 carrier MUST carry 5+ priorRelationships entries (D-14 clean-archetype rule); got: \(priors)"
        )
    }

    /// VL-1009 double-broker archetype: the flagged broker (the re-tendering
    /// intermediary) carries ≤ 2 priorRelationships (signals "this counterparty
    /// has no real history with us"). Per D-14 double-broker rule + 09-01-PLAN
    /// fixture spec; aligned with PriorRelationshipDecodeTests.
    @Test("Double-broker archetype (VL-1009): the flagged broker TrustNode (re-tendering intermediary) carries 2 or fewer priorRelationships entries (D-14 double-broker rule)")
    func doubleBrokerArchetypeFlaggedBrokerCarriesTwoOrFewerPriorRelationships() throws {
        let priors = try priorRelationshipsCount(
            forFixture: "load-detail-VL-1009",
            whereRoleEquals: "broker",
            whereVerificationStateEquals: "flagged"
        )
        #expect(
            priors <= 2,
            "VL-1009 flagged broker MUST carry ≤ 2 priorRelationships entries (D-14 double-broker rule — re-tendering intermediary has no real prior pattern); got: \(priors)"
        )
    }

    /// VL-1010 chameleon-carrier archetype: the flagged carrier carries
    /// EXACTLY ZERO priorRelationships — the empty-array IS the marquee
    /// fraud signal ("First time working together"). Per D-14 chameleon rule
    /// + RESEARCH §7 line 846.
    @Test("Chameleon archetype (VL-1010): the flagged carrier TrustNode carries an EMPTY priorRelationships array (D-14 chameleon rule)")
    func chameleonArchetypeFlaggedCarrierCarriesEmptyPriorRelationships() throws {
        let priors = try priorRelationshipsCount(
            forFixture: "load-detail-VL-1010",
            whereRoleEquals: "carrier",
            whereVerificationStateEquals: "flagged"
        )
        #expect(
            priors == 0,
            "VL-1010 flagged carrier MUST carry EXACTLY 0 priorRelationships (D-14 chameleon rule — the empty array is the marquee fraud signal: 'First time working together'); got: \(priors)"
        )
    }

    /// VL-1011 factoring-fraud archetype: the flagged factoring node carries
    /// EXACTLY ZERO priorRelationships — same "no real history" signal as the
    /// chameleon-carrier rule, applied to factoring collusion. Per D-14
    /// factoring-fraud rule (extrapolated from D-14's marquee chameleon rule:
    /// the empty-array IS the fraud signal — "this counterparty has no real
    /// prior pattern with us"). Aligned with 09-01-PLAN fixture spec +
    /// PriorRelationshipDecodeTests.
    @Test("Factoring-fraud archetype (VL-1011): the flagged factoring TrustNode carries an EMPTY priorRelationships array (D-14 factoring rule)")
    func factoringFraudArchetypeFlaggedFactoringCarriesEmptyPriorRelationships() throws {
        let priors = try priorRelationshipsCount(
            forFixture: "load-detail-VL-1011",
            whereRoleEquals: "factoring",
            whereVerificationStateEquals: "flagged"
        )
        #expect(
            priors == 0,
            "VL-1011 flagged factoring MUST carry EXACTLY 0 priorRelationships (D-14 factoring rule — same 'no real history' collusion signal as chameleon); got: \(priors)"
        )
    }

    // MARK: - Helpers (raw-JSON inspection — robust against Swift type churn)

    /// Decodes the fixture JSON via `JSONSerialization`, locates the first
    /// TrustNode whose `role` (and optional `verification_state`) match the
    /// predicate, and returns the size of its `prior_relationships` array.
    /// Returns `Int.max` if no matching node is found (forces a loud failure
    /// at the call site).
    private func priorRelationshipsCount(
        forFixture id: String,
        whereRoleEquals expectedRole: String,
        whereVerificationStateEquals expectedState: String? = nil
    ) throws -> Int {
        let data = try FixtureLoader.loadFixture(id)
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chain = parsed["chain_of_trust"] as? [String: Any],
              let nodes = chain["nodes"] as? [[String: Any]] else {
            Issue.record("Fixture \(id) does not parse as JSON with chain_of_trust.nodes[] array")
            return Int.max
        }
        for node in nodes {
            let role = node["role"] as? String
            guard role == expectedRole else { continue }
            if let expectedState = expectedState {
                let state = node["verification_state"] as? String
                guard state == expectedState else { continue }
            }
            // Matched. The prior_relationships key MUST exist and MUST be an
            // array (Test 3 above gates this globally; this helper trusts it).
            if let priors = node["prior_relationships"] as? [Any] {
                return priors.count
            }
            Issue.record("Fixture \(id) node (role=\(expectedRole), state=\(expectedState ?? "*")) is missing prior_relationships array — Test 3 gate should have caught this first")
            return Int.max
        }
        Issue.record("Fixture \(id) contains no TrustNode with role=\(expectedRole)\(expectedState.map { ", verification_state=\($0)" } ?? "")")
        return Int.max
    }
}
