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
}
