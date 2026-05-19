// validationLedger/Roles/Role.swift
// The 5 M1 roles per TechStack.md §4. Role is established at account creation
// (backend-assigned) and drives the root coordinator swap at SceneDelegate level (D-10).
//
// Phase 7 LOAD-02 addition: `Decodable` conformance so Role can be decoded
// from server payloads as a field on LoadParty (D-02) and TrustNode (D-07).
// Decoder semantics: an unknown wire value throws DecodingError (Swift-
// synthesized init). NOT subject to D-09's fail-closed contract — Role is a
// non-fraud-vector field (a server superstring on role would surface as a
// loud decode failure on the entire Load, exactly like LoadStatus per
// PLAN 07-01 threat T-07-03).

import Foundation

public enum Role: String, CaseIterable, Sendable, Decodable {
    case shipper
    case broker
    case carrier
    case dispatch
    case factoring
}

public extension Role {
    /// User-facing display name (uppercased first letter).
    var displayName: String {
        switch self {
        case .shipper:   return "Shipper"
        case .broker:    return "Broker"
        case .carrier:   return "Carrier"
        case .dispatch:  return "Dispatch"
        case .factoring: return "Factoring"
        }
    }
}
