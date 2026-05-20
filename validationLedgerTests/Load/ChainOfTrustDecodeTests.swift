// validationLedgerTests/Load/ChainOfTrustDecodeTests.swift
// Phase 7 Plan 05 Task 3 — fraud-archetype + clean + caution decode coverage
// (D-08, D-13). This suite exercises the three D-13 fraud archetypes the
// platform thesis exists to render — VL-1009 (double-broker), VL-1010
// (chameleon carrier), VL-1011 (factoring fraud) — plus the clean baseline
// (VL-1001) and the Pitfall 5 optional-absence cases (VL-1005, VL-1006,
// VL-1008).
//
// Every decode routes through `APIClient.defaultDecoder()` so any drift in
// the production decoder configuration surfaces here, same as the rest of
// the Phase 7 fixture-decode test suites.
//
// Plain `@Suite` — no MockURLProtocol touch.

import Testing
import Foundation
@testable import validationLedger

@Suite("ChainOfTrustDecodeTests — fraud archetypes + clean decode (D-08, D-13)")
struct ChainOfTrustDecodeTests {

    @Test("VL-1009 decodes a double-brokered chain with flagged intermediary node + flagged edge + compromised verdict (D-13a)")
    func vl1009DoubleBrokered() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1009")
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

        let chain = response.chainOfTrust
        #expect(chain.integrity.verdict == .compromised, "D-13a: VL-1009 MUST have integrity.verdict == .compromised")
        #expect(
            chain.nodes.contains { $0.verificationState == .flagged },
            "D-13a: VL-1009 MUST have at least one flagged TrustNode (the intermediary broker)"
        )
        #expect(
            chain.edges.contains { $0.relationshipState == .flagged },
            "D-13a: VL-1009 MUST have at least one flagged TrustEdge (the broker→carrier re-tender)"
        )
        #expect(
            !chain.integrity.implicatedNodeIDs.isEmpty,
            "D-13a: VL-1009 MUST list at least one implicated node ID"
        )
        #expect(
            !chain.integrity.implicatedEdgeIDs.isEmpty,
            "D-13a: VL-1009 MUST list at least one implicated edge ID"
        )
    }

    @Test("VL-1010 decodes a chameleon-carrier chain with carrier-role flagged node + compromised verdict (D-13b)")
    func vl1010ChameleonCarrier() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1010")
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

        let chain = response.chainOfTrust
        #expect(
            chain.nodes.contains { $0.role == .carrier && $0.verificationState == .flagged },
            "D-13b: VL-1010 MUST have a carrier-role TrustNode with verificationState == .flagged"
        )
        #expect(chain.integrity.verdict == .compromised, "D-13b: VL-1010 MUST have integrity.verdict == .compromised")
    }

    @Test("VL-1011 decodes a factoring-fraud chain with factoring-role flagged node + compromised verdict (D-13c)")
    func vl1011FactoringFraud() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1011")
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

        let chain = response.chainOfTrust
        #expect(
            chain.nodes.contains { $0.role == .factoring && $0.verificationState == .flagged },
            "D-13c: VL-1011 MUST have a factoring-role TrustNode with verificationState == .flagged"
        )
        #expect(chain.integrity.verdict == .compromised, "D-13c: VL-1011 MUST have integrity.verdict == .compromised")
    }

    @Test("VL-1001 decodes a clean delivered chain — verdict .clean, no flagged nodes/edges")
    func vl1001CleanBaseline() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1001")
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

        let chain = response.chainOfTrust
        #expect(chain.integrity.verdict == .clean, "VL-1001 MUST be the clean baseline")
        #expect(
            !chain.nodes.contains { $0.verificationState == .flagged },
            "VL-1001 MUST have no flagged TrustNodes"
        )
        #expect(
            !chain.edges.contains { $0.relationshipState == .flagged },
            "VL-1001 MUST have no flagged TrustEdges"
        )
    }

    @Test("VL-1006 decodes a draft load with empty chain.edges (Pitfall 5 — empty-array-not-missing-field)")
    func vl1006EmptyEdges() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1006")
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

        #expect(
            response.chainOfTrust.edges.isEmpty,
            "Pitfall 5: VL-1006 chain.edges MUST decode as [] (empty array — NOT a missing field)"
        )
    }

    @Test("VL-1005 decodes a TrustNode with kyc_completed_at: null (Pitfall 5 — in-array optional absence)")
    func vl1005KycCompletedAtNull() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1005")
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

        #expect(
            response.chainOfTrust.nodes.contains { $0.kycCompletedAt == nil },
            "Pitfall 5: VL-1005 MUST have at least one TrustNode whose kyc_completed_at decodes to nil"
        )
    }

    @Test("VL-1008 decodes target-carrier verification_state == .unverified (drives ACTION-07 hard-disable)")
    func vl1008TenderEligibilityHardDisable() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1008")
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

        // D-09 distinction: target carrier is .unverified (not-yet-verified),
        // NOT .flagged (actively suspicious). The acceptance criterion is
        // explicit about this.
        #expect(
            response.chainOfTrust.nodes.contains { $0.role == .carrier && $0.verificationState == .unverified },
            "ACTION-07: VL-1008 target carrier MUST be .unverified (not .flagged) — D-09 semantic distinction preserved"
        )
        #expect(
            response.load.tenderEligibility?.canTender == false,
            "ACTION-07: VL-1008 MUST have tender_eligibility.can_tender == false to drive the hard-disable"
        )
        #expect(
            response.load.tenderEligibility?.disabledReason != nil,
            "ACTION-07: VL-1008 MUST carry a disabled_reason string for inline display"
        )
    }
}
