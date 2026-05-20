// validationLedgerTests/Load/PriorRelationshipDecodeTests.swift
// Phase 9 Plan 01 Task 3 — Decodable contract test on the new PriorRelationship
// value type (D-12, D-13, D-14).
//
// === What this suite locks ===
//   1. Clean baseline (VL-1001): every TrustNode in the chain carries 5+
//      prior_relationships entries (D-14 clean rule).
//   2. Chameleon archetype (VL-1010): the flagged carrier's
//      prior_relationships is `[]` (the marquee fraud signal — D-14 chameleon
//      rule + RESEARCH §7 line 846).
//   3. Double-broker archetype (VL-1009): the flagged broker carries ≤ 2
//      prior_relationships entries (D-14 double-broker rule).
//   4. Wire-bridge proof: synthesized JSON with `load_id` decodes to
//      `PriorRelationship.loadID` via `.convertFromSnakeCase` + the explicit
//      `case loadID = "loadId"` raw value (RESEARCH §7 Pitfall 5).
//   5. ISO-8601 Date round-trip via `APIClient.defaultDecoder()`.
//   6. Optional `counterpartyDisplayName` decodes as nil when wire key is
//      omitted (synthesized initializer + Optional handling).
//
// `.serialized` matches the ChainOfTrustDecodeTests precedent — though this
// suite doesn't touch MockURLProtocol, keeping it serialized avoids any
// surprise interaction with parallel suites that DO touch the global registry.
//
// Per T-09-02 (PII): tests use synthetic data only. Per T-09-01 (decode
// safety): Test 5 locks the optional decode behavior.

import Testing
import Foundation
@testable import validationLedger

@Suite("PriorRelationshipDecodeTests — Phase 9 D-12 / D-13", .serialized)
struct PriorRelationshipDecodeTests {

    // MARK: - Helpers

    /// Build the production decoder once per test — guarantees the suite
    /// drifts iff `APIClient.defaultDecoder()` drifts.
    private static func decoder() -> JSONDecoder {
        APIClient.defaultDecoder()
    }

    // MARK: - Test 1 — Clean baseline

    @Test("VL-1001 clean baseline — every TrustNode carries 5+ prior_relationships (D-14 clean carrier rule)")
    func cleanBaselineDecodesFivePlusPriorsOnCarrier() throws {
        let data = try FixtureLoader.loadFixture("load-detail-VL-1001")
        let response = try Self.decoder().decode(LoadDetailEndpoint.Response.self, from: data)

        let carrier = try #require(
            response.chainOfTrust.nodes.first(where: { $0.role == .carrier }),
            "VL-1001 MUST have a carrier-role node"
        )
        #expect(
            carrier.priorRelationships.count >= 5,
            "D-14 clean rule: VL-1001 carrier MUST carry 5+ priors. Got \(carrier.priorRelationships.count)"
        )
    }

    // MARK: - Test 2 — Chameleon archetype empty-array fraud signal

    @Test("VL-1010 chameleon carrier — flagged carrier's priorRelationships is [] (D-14 marquee fraud signal)")
    func chameleonCarrierDecodesEmptyPriorRelationships() throws {
        let data = try FixtureLoader.loadFixture("load-detail-VL-1010")
        let response = try Self.decoder().decode(LoadDetailEndpoint.Response.self, from: data)

        let flaggedCarrier = try #require(
            response.chainOfTrust.nodes.first(where: { $0.role == .carrier && $0.verificationState == .flagged }),
            "VL-1010 MUST have a carrier-role node with verificationState == .flagged"
        )
        #expect(
            flaggedCarrier.priorRelationships.isEmpty,
            "D-14 chameleon rule: VL-1010 flagged carrier MUST have priorRelationships == []. Got \(flaggedCarrier.priorRelationships.count) entries"
        )
    }

    // MARK: - Test 3 — Wire-bridge proof (RESEARCH §7 Pitfall 5)

    @Test("PriorRelationship decodes `load_id` wire key as loadID via .convertFromSnakeCase + explicit CodingKey raw value 'loadId' (RESEARCH §7 Pitfall 5)")
    func loadIDWireBridgeDecodesPostConversionForm() throws {
        let json = """
        {
          "load_id": "VL-1023",
          "occurred_at": "2026-02-01T09:00:00Z",
          "counterparty_role": "broker",
          "counterparty_display_name": "Acme Brokerage"
        }
        """.data(using: .utf8)!

        let result = try Self.decoder().decode(PriorRelationship.self, from: json)
        #expect(result.loadID == "VL-1023",
                "Pitfall 5: 'load_id' wire key MUST decode to the trailing-acronym 'loadID' property via 'loadId' (post-conversion) raw value")
        #expect(result.counterpartyRole == .broker)
        #expect(result.counterpartyDisplayName == "Acme Brokerage")
    }

    // MARK: - Test 4 — ISO-8601 Date round-trip

    @Test("PriorRelationship.occurredAt round-trips as ISO-8601 via APIClient.defaultDecoder()")
    func occurredAtRoundTripsAsISO8601() throws {
        let json = """
        {
          "load_id": "VL-1024",
          "occurred_at": "2026-02-01T09:00:00Z",
          "counterparty_role": "carrier",
          "counterparty_display_name": "Red Rock Carriers"
        }
        """.data(using: .utf8)!

        let result = try Self.decoder().decode(PriorRelationship.self, from: json)
        let expected = ISO8601DateFormatter().date(from: "2026-02-01T09:00:00Z")
        #expect(result.occurredAt == expected,
                "ISO-8601 decoding strategy: occurredAt MUST equal the formatter-parsed reference date")
    }

    // MARK: - Test 5 — Optional counterpartyDisplayName missing-key tolerance

    @Test("PriorRelationship.counterpartyDisplayName decodes as nil when wire key is omitted (Optional + synthesized initializer)")
    func counterpartyDisplayNameOmittedDecodesAsNil() throws {
        // No `counterparty_display_name` in the source JSON.
        let json = """
        {
          "load_id": "VL-1025",
          "occurred_at": "2026-03-04T11:30:00Z",
          "counterparty_role": "shipper"
        }
        """.data(using: .utf8)!

        let result = try Self.decoder().decode(PriorRelationship.self, from: json)
        #expect(result.counterpartyDisplayName == nil,
                "Pitfall 5: omitted optional wire key MUST decode as nil — synthesized initializer + String?")
        #expect(result.loadID == "VL-1025")
        #expect(result.counterpartyRole == .shipper)
    }

    // MARK: - Test 6 — Double-broker archetype implicated carrier count

    @Test("VL-1009 double-broker archetype — flagged broker carries ≤ 2 priors (D-14 double-broker rule)")
    func doubleBrokeredArchetypeFlaggedBrokerHasFewPriors() throws {
        let data = try FixtureLoader.loadFixture("load-detail-VL-1009")
        let response = try Self.decoder().decode(LoadDetailEndpoint.Response.self, from: data)

        let flaggedBroker = try #require(
            response.chainOfTrust.nodes.first(where: { $0.role == .broker && $0.verificationState == .flagged }),
            "VL-1009 MUST have a broker-role node with verificationState == .flagged (the re-tendering intermediary)"
        )
        #expect(
            flaggedBroker.priorRelationships.count <= 2,
            "D-14 double-broker rule: flagged intermediary broker MUST carry ≤ 2 priors. Got \(flaggedBroker.priorRelationships.count)"
        )
    }

    // MARK: - Test 7 — Factoring-fraud archetype empty-array on factoring node

    @Test("VL-1011 factoring-fraud archetype — flagged factoring node carries empty priors (D-14 collusion 'no real history' signal)")
    func factoringFraudArchetypeFlaggedFactoringHasEmptyPriors() throws {
        let data = try FixtureLoader.loadFixture("load-detail-VL-1011")
        let response = try Self.decoder().decode(LoadDetailEndpoint.Response.self, from: data)

        let flaggedFactoring = try #require(
            response.chainOfTrust.nodes.first(where: { $0.role == .factoring && $0.verificationState == .flagged }),
            "VL-1011 MUST have a factoring-role node with verificationState == .flagged"
        )
        #expect(
            flaggedFactoring.priorRelationships.isEmpty,
            "D-14 factoring-fraud rule: flagged factoring node MUST carry no priors. Got \(flaggedFactoring.priorRelationships.count) entries"
        )
    }
}
