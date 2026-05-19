// validationLedger/Core/Load/LoadStatus.swift
// Phase 7 LOAD-02 (D-01): the full-lifecycle load status enum.
//
// D-01: 13 cases covering the canonical primary path
//   draft → posted → tendered → accepted → dispatched → inTransit → delivered
// plus side-states (rejected, expired, cancelled) and the post-delivery cases
// (podCaptured, invoiced, funded). The post-delivery trio renders read-only in
// v1.1 (factoring's list + post-delivery loads) — interactive transitions into
// them land in M3/post-v1.1. Locking the closed set now means zero enum churn
// when transitions are added.
//
// File-shape analog: validationLedger/Core/Attestation/TrustTier.swift.
// Wire-format: under JSONDecoder().keyDecodingStrategy = .convertFromSnakeCase
// (APIClient.defaultDecoder()), single-word cases pass through automatically.
// Multi-word cases declare explicit snake_case rawValues so the wire form
// (e.g. "in_transit", "pod_captured") decodes deterministically — the
// .convertFromSnakeCase strategy converts JSON KEYS, not VALUES; raw enum
// values bind 1:1 to the JSON string regardless of strategy.
//
// Decoder semantics: unknown wire value throws DecodingError per Swift's
// synthesized init(from:). This is distinct from D-09's fail-closed contract
// (which applies ONLY to VerificationState and ChainIntegrity.Verdict):
// an unknown LoadStatus is a server superstring on a non-fraud-vector field
// — the entire Load fails to decode loudly, surfacing the contract bug.
// See PLAN 07-01 threat T-07-03.

import Foundation

public enum LoadStatus: String, Sendable, Decodable, CaseIterable {
    // Primary lifecycle path
    case draft
    case posted
    case tendered
    case accepted
    case dispatched
    case inTransit = "in_transit"
    case delivered

    // Side-states
    case rejected
    case expired
    case cancelled

    // Post-delivery (display-only in v1.1; transitions land post-v1.1)
    case podCaptured = "pod_captured"
    case invoiced
    case funded
}
