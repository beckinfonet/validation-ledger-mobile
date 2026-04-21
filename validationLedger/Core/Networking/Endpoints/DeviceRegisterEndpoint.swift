// validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift
// POST /device/register — register Secure-Enclave-generated device public key + fingerprint.
// Consumed by Phase 3 (post-OTP-verify) + Phase 4 (App Attest augmentation, DEV-04).
// Phase 2 scope: devicePublicKey (DEV-01) + deviceFingerprint (DEV-05).
// Phase 4 will ADD an optional attestation field — that's a non-breaking Decodable extension.

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
    }
    public struct RequestBody: Encodable, Sendable {
        public let devicePublicKey: String  // base64-encoded DER, from SecureEnclaveKeyStore (Plan 06)
        public let deviceFingerprint: DeviceFingerprintPayload
    }
    public struct Response: Decodable, Sendable {
        public let deviceID: String
        public let registeredAt: Date
    }
    public let path = "/device/register"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(devicePublicKey: String, fingerprint: DeviceFingerprintPayload) {
        self.body = RequestBody(devicePublicKey: devicePublicKey, deviceFingerprint: fingerprint)
    }
}
