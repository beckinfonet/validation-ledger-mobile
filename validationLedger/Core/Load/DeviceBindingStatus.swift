// validationLedger/Core/Load/DeviceBindingStatus.swift
// Phase 7 LOAD-02 (D-07): the device-binding facet of a TrustNode's
// verification basis. Consumed by ChainOfTrust.TrustNode (Plan 02) and
// rendered by the Phase 9 trust-graph badge.
//
// D-07: TrustNode carries TYPED verification-basis fields — not an opaque
// server-formatted fact list. The iOS UI controls presentation, the server
// supplies the typed facts. DeviceBindingStatus is one of the four such facts
// (alongside kycCompletedAt, usdotAuthorityStatus, priorRelationshipCount).
//
// Case set (closed) — chosen to mirror what the v1.0 TrustTier hardware-
// attested ladder communicates and what the Phase 9 trust-graph badge will
// render:
//   - bound       — device is registered + actively bound to the party
//                   (parallel to TrustTier.hardwareAttested on the active
//                   device for that party).
//   - unbound     — no device has ever bound for this party (parallel to
//                   TrustTier.softwareOnly / no Secure-Enclave attestation
//                   yet completed).
//   - mismatched  — a device bound previously but the current first-party
//                   session is on a different device — a fraud signal. The
//                   Phase 9 graph renders this as a caution/compromised cue.
//
// File-shape analog: validationLedger/Core/Attestation/TrustTier.swift.
// Decoder semantics: unknown wire value throws DecodingError (Swift-
// synthesized init). NOT subject to D-09's fail-closed contract — that
// applies only to VerificationState / ChainIntegrity.Verdict per the plan's
// threat-model (PLAN 07-01 threats T-07-01, T-07-02). A future
// device-binding-status superstring would surface as a loud decode failure.

import Foundation

public enum DeviceBindingStatus: String, Sendable, Decodable, CaseIterable {
    case bound
    case unbound
    case mismatched
}
