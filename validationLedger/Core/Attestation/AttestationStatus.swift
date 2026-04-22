// validationLedger/Core/Attestation/AttestationStatus.swift
// Phase 4 DEV-04 (D-09): graceful-skip contract for /device/register.
//
// Wire-format enum carried on every /device/register payload. When the value
// is not .attested, the attestationObject + attestedKeyId fields are omitted
// from the request body (see DeviceRegisterEndpoint extension — Plan 04).
//
// Wire-format contract (D-09):
//   attested | unsupported | entitlementMissing | quotaExceeded | simulatorBypass | error
//
// Raw values use Swift's default String-raw-value casing (lowercase enum
// names). The backend mock fixtures (Plan 04) match on these exact strings.
// Downstream plans (03, 04, 06, 08, 11, 12) consume this by name — do NOT
// rename cases without updating every consumer + the backend contract.

import Foundation

public enum AttestationStatus: String, Sendable, Codable {
    case attested
    case unsupported
    case entitlementMissing
    case quotaExceeded
    /// `#if DEBUG && targetEnvironment(simulator)` path — emits a fake
    /// attestationObject + `attestedKeyId = "sim-bypass-{installUUID}"` per
    /// D-10. Production builds never ship this enum case in a real network
    /// call (the simulator-bypass impl is guarded at AppContainer selection).
    case simulatorBypass
    case error
}
