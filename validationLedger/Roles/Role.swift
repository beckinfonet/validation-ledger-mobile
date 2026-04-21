// validationLedger/Roles/Role.swift
// The 5 M1 roles per TechStack.md §4. Role is established at account creation
// (backend-assigned) and drives the root coordinator swap at SceneDelegate level (D-10).

import Foundation

public enum Role: String, CaseIterable, Sendable {
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
