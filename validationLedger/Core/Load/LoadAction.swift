// validationLedger/Core/Load/LoadAction.swift
// Phase 7 LOAD-02 (D-03 / D-04 / D-05): the closed set of load actions a role
// can invoke against a load.
//
// D-03: `post` moves draft → posted; `tender` acts ONLY on a posted load
//       (no direct draft → tendered path).
// D-04: there is no `retender` case. After a reject or tender expiry the load
//       returns to `posted`, which already affords `tender`. Retender = `tender`
//       invoked again. Prior rejected/expired tenders are recorded in
//       `Load.stateHistory`.
// D-05: ACTION-05 status advancement collapses to a SINGLE `advanceStatus`
//       case (not three per-transition cases). Backend derives the target
//       state as the next step in the canonical order
//       (accepted → dispatched → inTransit → delivered). Path segment is
//       "status" — the backend treats "status" as "advance by one".
//
// File-shape analog: validationLedger/Core/Attestation/TrustTier.swift +
//   validationLedger/Core/Identity/KYC/RejectionReasonCode.swift (vocabulary
//   enum). NOT Decodable: this enum is sent CLIENT-TO-SERVER via URL path
//   segments (LoadActionEndpoint composes `/loads/{id}/{pathSegment}`); it is
//   never decoded from server JSON. Closing the surface to encoding-only
//   removes the entire elevation-of-privilege class (PLAN 07-01 threat T-07-04).
//
// CaseIterable so the Plan 02 RoleLoadPolicyTests can exhaustively sweep the
// (Role × LoadStatus → [LoadAction]) policy table.

import Foundation

public enum LoadAction: String, Sendable, CaseIterable {
    case post
    case tender
    case accept
    case reject
    case cancel
    case advanceStatus
}

public extension LoadAction {
    /// The URL path segment for this action in LoadActionEndpoint
    /// (`POST /loads/{loadID}/{pathSegment}`).
    ///
    /// D-05: `advanceStatus` maps to `"status"` — the backend treats the
    /// path "status" as "advance the load to the next canonical state".
    /// All other actions use their case name verbatim.
    var pathSegment: String {
        switch self {
        case .post:           return "post"
        case .tender:         return "tender"
        case .accept:         return "accept"
        case .reject:         return "reject"
        case .cancel:         return "cancel"
        case .advanceStatus:  return "status"
        }
    }
}
