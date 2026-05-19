// validationLedger/Core/Load/USDOTAuthorityStatus.swift
// Phase 7 LOAD-02 (D-07): the USDOT-authority facet of a TrustNode's
// verification basis. Consumed by ChainOfTrust.TrustNode (Plan 02) and
// rendered by the Phase 9 trust-graph badge.
//
// D-07: TrustNode carries TYPED verification-basis fields — not an opaque
// server-formatted fact list. The iOS UI controls presentation, the server
// supplies the typed facts. USDOTAuthorityStatus is one of the four such
// facts; the companion `usdotNumber: String?` lives on TrustNode and renders
// as a tappable identity reference when present.
//
// Case set (closed):
//   - active         — USDOT operating authority is current. The default
//                      good-state for carriers and dispatch parties.
//   - revoked        — authority has been REVOKED by FMCSA. A hard fraud
//                      signal — the load detail screen renders this as a
//                      compromised cue.
//   - suspended      — authority is currently suspended (typically for
//                      insurance / safety violations). The trust-graph
//                      renders this as caution.
//   - notApplicable  — this party does not carry a USDOT number by virtue of
//                      its role (Shipper, Factoring). Wire form is
//                      "not_applicable". Renders the badge as inert rather
//                      than red/yellow.
//
// File-shape analog: validationLedger/Core/Attestation/TrustTier.swift.
// Wire-format: under .convertFromSnakeCase, the keys are converted but
// raw enum values bind 1:1 to the JSON string. `notApplicable` declares
// its explicit snake_case rawValue ("not_applicable") to match the wire form.
//
// Decoder semantics: unknown wire value throws DecodingError (Swift-
// synthesized init). NOT subject to D-09's fail-closed contract — that
// applies only to VerificationState / ChainIntegrity.Verdict (PLAN 07-01
// threats T-07-01, T-07-02). A future authority-status superstring would
// surface as a loud decode failure.

import Foundation

public enum USDOTAuthorityStatus: String, Sendable, Decodable, CaseIterable {
    case active
    case revoked
    case suspended
    case notApplicable = "not_applicable"
}
