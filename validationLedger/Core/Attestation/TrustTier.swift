// validationLedger/Core/Attestation/TrustTier.swift
// Phase 4 DEV-04 (D-12): backend-driven trust tier returned by /device/register
// + /device/heartbeat. Client is a passive renderer — the banner in Plan 08
// decides visibility based on whether this equals .hardwareAttested.
//
// Future tiers (attestedUnverified, revoked, ...) can be added server-side
// without client changes, subject to an `@unknown default:` update here when
// the decoder is extended to a broader closed-set enum.

import Foundation

public enum TrustTier: String, Sendable, Codable {
    case hardwareAttested
    case softwareOnly
}
