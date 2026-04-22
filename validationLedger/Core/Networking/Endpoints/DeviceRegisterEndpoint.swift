// validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift
// POST /device/register — register SE-generated device identity + attestation payload.
// Phase 2 scope: devicePublicKey (DEV-01) + authorizationPublicKey (DEV-02) + deviceFingerprint (DEV-05).
// Phase 4 DEV-04 extension: attestedKeyId + attestationObject (both optional per D-09 omission rule)
//   + attestationStatus (required, D-09 six-value enum)
//   + Response.trustTier (D-12 backend-driven trust tier).
//
// Single Phase 4 init: 6-arg payload (devicePublicKey, authorizationPublicKey, attestedKeyId,
// attestationObject, attestationStatus, fingerprint). Phase 2's 2-arg init is REPLACED — the
// full three-key contract (D-02) + attestation status (D-09) is now the wire contract.
// AppContainer wiring (Plan 06) + OTPViewModel (migrated in this plan per executor Rule 3)
// are the callers.
//
// Wire-format omission: Swift's JSONEncoder skips `Optional.none` properties entirely
// (no "null" in JSON) — this is the mechanism that delivers D-09's omission rule
// for attestedKeyId + attestationObject when attestationStatus != .attested.
// Plan 05 adds a parametrized test pinning this behavior.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct DeviceRegisterEndpoint: APIEndpoint {
    public struct DeviceFingerprintPayload: Encodable, Sendable {
        public let model: String        // e.g., "iPhone15,2"
        public let iosVersion: String   // e.g., "17.5.1"
        public let installUUID: String  // Keychain-persisted, Plan 06 DEV-05
        public init(model: String, iosVersion: String, installUUID: String) {
            self.model = model
            self.iosVersion = iosVersion
            self.installUUID = installUUID
        }

        // IN-05 (Phase 2 carryover, closed Phase 3 Plan 02):
        // Explicit CodingKeys pin the wire contract against JSONEncoder.convertToSnakeCase
        // toolchain changes for trailing uppercase acronyms (UUID).
        // See OTPVerifyEndpoint.RequestBody for full rationale.
        private enum CodingKeys: String, CodingKey {
            case model
            case iosVersion
            case installUUID = "installUuid"
        }
    }
    public struct RequestBody: Encodable, Sendable {
        public let devicePublicKey: String              // Phase 2 DEV-01 (existing) — base64 DER
        public let authorizationPublicKey: String       // Phase 4 DEV-02 — NEW on the wire per D-02
        public let attestedKeyId: String?               // Phase 4 DEV-04 — nil when attestationStatus != .attested (D-09)
        public let attestationObject: Data?             // Phase 4 DEV-04 — nil when attestationStatus != .attested (D-09)
        public let attestationStatus: AttestationStatus // Phase 4 DEV-04 — ALWAYS present (D-09)
        public let deviceFingerprint: DeviceFingerprintPayload
    }
    public struct Response: Decodable, Sendable {
        public let deviceID: String
        public let registeredAt: Date
        public let trustTier: TrustTier                 // Phase 4 DEV-04 D-12

        // Explicit CodingKeys: acronym bridge — see OTPRequestEndpoint.Response for rationale.
        // Raw values are camelCase (post-.convertFromSnakeCase form).
        private enum CodingKeys: String, CodingKey {
            case deviceID = "deviceId"
            case registeredAt
            case trustTier                              // snake_case "trust_tier" via .convertFromSnakeCase
        }
    }
    public let path = "/device/register"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    // Phase 4 DEV-04 init — full three-key payload with attestation status.
    // When attestationStatus == .attested, callers pass non-nil attestedKeyId + attestationObject.
    // When attestationStatus != .attested, callers pass nil for both (D-09 omission rule).
    public init(
        devicePublicKey: String,
        authorizationPublicKey: String,
        attestedKeyId: String?,
        attestationObject: Data?,
        attestationStatus: AttestationStatus,
        fingerprint: DeviceFingerprintPayload
    ) {
        self.body = RequestBody(
            devicePublicKey: devicePublicKey,
            authorizationPublicKey: authorizationPublicKey,
            attestedKeyId: attestedKeyId,
            attestationObject: attestationObject,
            attestationStatus: attestationStatus,
            deviceFingerprint: fingerprint
        )
    }
}
