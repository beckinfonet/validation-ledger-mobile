// validationLedgerTests/Loads/ChainOfTrustFactory.swift
//
// Phase 9 Plan 06 — shared in-memory ChainOfTrust factory for Trust*View
// tests. Constructs a canonical 5-node clean chain (shipper → broker →
// carrier → dispatch fork + carrier → factoring) with synthetic identifiers.
//
// Constructed in-memory via the compiler-synthesized memberwise initializers
// on TrustNode / TrustEdge / ChainIntegrity (accessible to the test target
// via `@testable import validationLedger`) — same approach as
// LoadRowCellSnapshotTests.makeItem(...) precedent.
//
// === T-09-04 (PII) ===
// Every party uses synthetic VL-9xxx-style identifiers and a "Synthetic <Role>"
// displayName — no real freight reference numbers, no real party names.

import Foundation
@testable import validationLedger

enum ChainOfTrustFactory {

    /// Returns a 5-node chain (one party per Role, in role order) with
    /// 4 edges drawn shipper → broker → carrier → (dispatch + factoring).
    /// The verdict + implicated sets are caller-supplied so the same
    /// helper drives the clean / caution / compromised matrix tests.
    static func fiveNodeClean(
        verdict: ChainIntegrity.Verdict = .clean,
        implicatedNodeIDs: [String] = [],
        implicatedEdgeIDs: [String] = []
    ) -> ChainOfTrust {
        let nodes: [TrustNode] = [
            TrustNode(
                partyID: "party-shipper",
                role: .shipper,
                displayName: "Synthetic Shipper",
                verificationState: .verified,
                kycCompletedAt: Date(timeIntervalSince1970: 1_780_000_000),
                deviceBindingStatus: .bound,
                usdotNumber: nil,
                usdotAuthorityStatus: .notApplicable,
                priorRelationships: []
            ),
            TrustNode(
                partyID: "party-broker",
                role: .broker,
                displayName: "Synthetic Broker",
                verificationState: .verified,
                kycCompletedAt: Date(timeIntervalSince1970: 1_780_000_000),
                deviceBindingStatus: .bound,
                usdotNumber: nil,
                usdotAuthorityStatus: .notApplicable,
                priorRelationships: []
            ),
            TrustNode(
                partyID: "party-carrier",
                role: .carrier,
                displayName: "Synthetic Carrier",
                verificationState: implicatedNodeIDs.contains("party-carrier") ? .flagged : .verified,
                kycCompletedAt: Date(timeIntervalSince1970: 1_780_000_000),
                deviceBindingStatus: .bound,
                usdotNumber: "1234567",
                usdotAuthorityStatus: .active,
                priorRelationships: []
            ),
            TrustNode(
                partyID: "party-dispatch",
                role: .dispatch,
                displayName: "Synthetic Dispatch",
                verificationState: .verified,
                kycCompletedAt: Date(timeIntervalSince1970: 1_780_000_000),
                deviceBindingStatus: .bound,
                usdotNumber: "7654321",
                usdotAuthorityStatus: .active,
                priorRelationships: []
            ),
            TrustNode(
                partyID: "party-factoring",
                role: .factoring,
                displayName: "Synthetic Factoring",
                verificationState: .verified,
                kycCompletedAt: Date(timeIntervalSince1970: 1_780_000_000),
                deviceBindingStatus: .bound,
                usdotNumber: nil,
                usdotAuthorityStatus: .notApplicable,
                priorRelationships: []
            ),
        ]

        let edges: [TrustEdge] = [
            TrustEdge(edgeID: "edge-shipper-broker",
                      fromPartyID: "party-shipper", toPartyID: "party-broker",
                      relationshipState: .verified, tenderRef: nil),
            TrustEdge(edgeID: "edge-broker-carrier",
                      fromPartyID: "party-broker", toPartyID: "party-carrier",
                      relationshipState: .verified, tenderRef: nil),
            TrustEdge(edgeID: "edge-carrier-dispatch",
                      fromPartyID: "party-carrier", toPartyID: "party-dispatch",
                      relationshipState: .verified, tenderRef: nil),
            TrustEdge(edgeID: "edge-carrier-factoring",
                      fromPartyID: "party-carrier", toPartyID: "party-factoring",
                      relationshipState: .verified, tenderRef: nil),
        ]

        let reason: String
        switch verdict {
        case .clean: reason = ""
        case .caution: reason = "Synthetic caution reason for snapshot."
        case .compromised: reason = "Synthetic compromise reason for snapshot."
        }

        let integrity = ChainIntegrity(
            verdict: verdict,
            reason: reason,
            implicatedNodeIDs: implicatedNodeIDs,
            implicatedEdgeIDs: implicatedEdgeIDs
        )

        return ChainOfTrust(nodes: nodes, edges: edges, integrity: integrity)
    }

    // ============================================================
    // Phase 9.1 Plan 03 — five representative chain fixtures
    // ============================================================
    //
    // Used by EveryoneOnLoadStripViewTests + EveryoneOnLoadStripViewSnapshotTests
    // to assert R2 (chip count = de-duplicated role set in canonical order),
    // D-10 (multi-node most-suspicious-wins), R6 (3-field composed a11y
    // labels), and the 5-fixture × 2-width snapshot matrix.
    //
    // Node counts:
    //   - VL-1001: 5 distinct roles (SHP, BRK, CAR, DSP, FCT)         — 5 chips
    //   - VL-1003: 2 distinct roles (SHP, BRK)                          — 2 chips
    //   - VL-1005: 3 distinct roles (SHP, BRK, CAR pending)             — 3 chips
    //   - VL-1007: 4 distinct roles (SHP, BRK, CAR, DSP)                — 4 chips
    //   - VL-1009: 6 nodes / 5 distinct roles — two brokers (one flagged,
    //              one verified) collapse into ONE BRK chip whose status
    //              is the most-suspicious .flagged                       — 5 chips
    //
    // Display names mirror the load-detail-VL-*.json fixture corpus so the
    // strip tests assert against the SAME synthetic party names the production
    // mock path uses (NOT a parallel hand-coded set that could drift).
    // PII discipline (T-09.1-02): every party name is synthetic — no real
    // freight reference numbers, no real party names.

    /// VL-1001 — 5 distinct roles, all verified. Clean integrity.
    /// The fully-populated chain — every role present, every party verified.
    static func vl1001_fiveRolesClean() -> ChainOfTrust {
        let nodes: [TrustNode] = [
            makeNode(partyID: "party-shipper-pacificgoods",   role: .shipper,   displayName: "Pacific Goods LLC",      state: .verified, usdotNumber: nil,         usdotAuth: .notApplicable),
            makeNode(partyID: "party-broker-freightwise",     role: .broker,    displayName: "FreightWise Brokerage", state: .verified, usdotNumber: nil,         usdotAuth: .notApplicable),
            makeNode(partyID: "party-carrier-acme",           role: .carrier,   displayName: "Acme Trucking Inc.",    state: .verified, usdotNumber: "1234567",  usdotAuth: .active),
            makeNode(partyID: "party-dispatch-overland",      role: .dispatch,  displayName: "Overland Dispatch",     state: .verified, usdotNumber: "7654321",  usdotAuth: .active),
            makeNode(partyID: "party-factoring-bridgecap",    role: .factoring, displayName: "BridgeCap Capital",     state: .verified, usdotNumber: nil,         usdotAuth: .notApplicable),
        ]
        return ChainOfTrust(
            nodes: nodes,
            edges: [],  // EveryoneOnLoadStripView reads only nodes[].role / .verificationState / .displayName; edges are unused here.
            integrity: ChainIntegrity(verdict: .clean, reason: "All parties verified; KYC current; carrier authority active; no fraud signals detected.", implicatedNodeIDs: [], implicatedEdgeIDs: [])
        )
    }

    /// VL-1003 — 2 distinct roles (SHP, BRK). Clean integrity.
    /// The earliest-stage chain — awaiting tender; only shipper + broker on it.
    static func vl1003_twoRolesClean() -> ChainOfTrust {
        let nodes: [TrustNode] = [
            makeNode(partyID: "party-shipper-easternfoods",  role: .shipper, displayName: "Eastern Foods Distributing", state: .verified, usdotNumber: nil, usdotAuth: .notApplicable),
            makeNode(partyID: "party-broker-freightwise",    role: .broker,  displayName: "FreightWise Brokerage",     state: .verified, usdotNumber: nil, usdotAuth: .notApplicable),
        ]
        return ChainOfTrust(
            nodes: nodes,
            edges: [],
            integrity: ChainIntegrity(verdict: .clean, reason: "Awaiting tender; shipper and broker verified.", implicatedNodeIDs: [], implicatedEdgeIDs: [])
        )
    }

    /// VL-1005 — 3 distinct roles (SHP, BRK, CAR-pending). Caution integrity.
    /// Carrier is pending KYC — exercises the strip's per-chip state mapping
    /// across mixed verification states (not all .verified).
    static func vl1005_threeRolesClean() -> ChainOfTrust {
        let nodes: [TrustNode] = [
            makeNode(partyID: "party-shipper-easternfoods", role: .shipper, displayName: "Eastern Foods Distributing", state: .verified, usdotNumber: nil,        usdotAuth: .notApplicable),
            makeNode(partyID: "party-broker-freightwise",   role: .broker,  displayName: "FreightWise Brokerage",     state: .verified, usdotNumber: nil,        usdotAuth: .notApplicable),
            makeNode(partyID: "party-carrier-nationallink", role: .carrier, displayName: "National Link Carriers",    state: .pending,  usdotNumber: "9876543", usdotAuth: .active),
        ]
        return ChainOfTrust(
            nodes: nodes,
            edges: [],
            integrity: ChainIntegrity(verdict: .caution, reason: "Prior tender expired without response from target carrier; KYC pending.", implicatedNodeIDs: [], implicatedEdgeIDs: [])
        )
    }

    /// VL-1007 — 4 distinct roles (SHP, BRK, CAR, DSP). Clean integrity.
    /// Short-haul dispatch confirmed — no factoring party on the chain.
    static func vl1007_fourRolesClean() -> ChainOfTrust {
        let nodes: [TrustNode] = [
            makeNode(partyID: "party-shipper-globalexports", role: .shipper,  displayName: "Global Exports Co.",   state: .verified, usdotNumber: nil,        usdotAuth: .notApplicable),
            makeNode(partyID: "party-broker-sunbelt",        role: .broker,   displayName: "Sunbelt Logistics",   state: .verified, usdotNumber: nil,        usdotAuth: .notApplicable),
            makeNode(partyID: "party-carrier-redrock",       role: .carrier,  displayName: "Red Rock Carriers",   state: .verified, usdotNumber: "2468013", usdotAuth: .active),
            makeNode(partyID: "party-dispatch-cornerstone",  role: .dispatch, displayName: "Cornerstone Dispatch", state: .verified, usdotNumber: "1357924", usdotAuth: .active),
        ]
        return ChainOfTrust(
            nodes: nodes,
            edges: [],
            integrity: ChainIntegrity(verdict: .clean, reason: "Short-haul dispatch confirmed; all parties verified.", implicatedNodeIDs: [], implicatedEdgeIDs: [])
        )
    }

    /// VL-1009 — 6 nodes / 5 distinct roles. Compromised integrity.
    ///
    /// THE multi-broker fixture that exercises D-10 most-suspicious-wins
    /// (RESEARCH §Open Q1):
    ///   - 2 brokers: FreightWise (.verified) + Keystone (.flagged)
    ///   - 5 distinct roles → 5 chips
    ///   - The collapsed BRK chip's status MUST be .flagged
    ///     (`.flagged > .verified` per the suspicion ordering).
    ///   - The collapsed BRK chip's 3-field composed a11y label MUST be
    ///     "Broker, multiple parties, flagged" (B1 planner-default
    ///     multi-node displayName + most-suspicious-wins spoken state).
    ///
    /// Chameleon-broker fraud archetype per the platform thesis: the role
    /// is suspect, not just one party.
    static func vl1009_sixNodesTwoBrokersCompromised() -> ChainOfTrust {
        let nodes: [TrustNode] = [
            makeNode(partyID: "party-shipper-globalexports",  role: .shipper,   displayName: "Global Exports Co.",        state: .verified, usdotNumber: nil,         usdotAuth: .notApplicable),
            // Two brokers — one verified, one flagged. The collapse rule
            // MUST pick .flagged as the chip state (most-suspicious wins).
            makeNode(partyID: "party-broker-freightwise",     role: .broker,    displayName: "FreightWise Brokerage",    state: .verified, usdotNumber: nil,         usdotAuth: .notApplicable),
            makeNode(partyID: "party-broker-keystone",        role: .broker,    displayName: "Keystone Freight Group",   state: .flagged,  usdotNumber: nil,         usdotAuth: .notApplicable),
            makeNode(partyID: "party-carrier-redrock",        role: .carrier,   displayName: "Red Rock Carriers",        state: .verified, usdotNumber: "2468013",  usdotAuth: .active),
            makeNode(partyID: "party-dispatch-overland",      role: .dispatch,  displayName: "Overland Dispatch",        state: .verified, usdotNumber: "7654321",  usdotAuth: .active),
            makeNode(partyID: "party-factoring-bridgecap",    role: .factoring, displayName: "BridgeCap Capital",        state: .verified, usdotNumber: nil,         usdotAuth: .notApplicable),
        ]
        return ChainOfTrust(
            nodes: nodes,
            edges: [],
            integrity: ChainIntegrity(
                verdict: .compromised,
                reason: "Intermediary broker re-tendered to a downstream carrier without the original broker's authorization — classic double-broker pattern.",
                implicatedNodeIDs: ["party-broker-keystone"],
                implicatedEdgeIDs: []
            )
        )
    }

    // MARK: - Internal helpers

    /// Single-line TrustNode constructor used by the 5 Phase 9.1 factories.
    /// Defaults match the original `fiveNodeClean(...)` factory's values
    /// (bound device, fixed KYC timestamp, empty priorRelationships) since
    /// EveryoneOnLoadStripView consumes only role / verificationState /
    /// displayName.
    private static func makeNode(
        partyID: String,
        role: Role,
        displayName: String,
        state: VerificationState,
        usdotNumber: String?,
        usdotAuth: USDOTAuthorityStatus
    ) -> TrustNode {
        TrustNode(
            partyID: partyID,
            role: role,
            displayName: displayName,
            verificationState: state,
            kycCompletedAt: Date(timeIntervalSince1970: 1_780_000_000),
            deviceBindingStatus: .bound,
            usdotNumber: usdotNumber,
            usdotAuthorityStatus: usdotAuth,
            priorRelationships: []
        )
    }
}
