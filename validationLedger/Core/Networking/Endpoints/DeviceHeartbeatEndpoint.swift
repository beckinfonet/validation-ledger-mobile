// validationLedger/Core/Networking/Endpoints/DeviceHeartbeatEndpoint.swift
// POST /device/heartbeat — assertion-backed session heartbeat (D-07 cadence).
// Fired on cold-boot re-login (piggybacking SessionRestoreProbe.restored) + on
// didBecomeActive when lastHeartbeatAt > 24h old (Plan 07 SceneDelegate extension).
//
// Request shape (D-07): { session_token, attested_key_id, assertion (base64 at wire) }
// Response shape (D-12): { heartbeat_accepted_at, trust_tier }
//
// Idempotency: IdempotencyInterceptor (NET-04) injects Idempotency-Key: UUID()
// automatically for POST. Each heartbeat gets a fresh key (not a retry) — backend
// dedupes by Idempotency-Key (04-RESEARCH Pattern 3).
//
// Mock fixtures:
//   - validationLedgerTests/Networking/Fixtures/device-heartbeat-success.json (happy path)
//   - validationLedgerTests/Networking/Fixtures/device-heartbeat-attestation-invalid.json
//     (D-04 backend-driven re-attest trigger)

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct DeviceHeartbeatEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable {
        public let sessionToken: String
        public let attestedKeyId: String
        public let assertion: Data  // JSONEncoder base64-encodes Data by default

        // Rely on APIClient's .convertToSnakeCase:
        //   sessionToken → session_token, attestedKeyId → attested_key_id, assertion → assertion.
        // Wire-format assertions pinned in Plan 05 EndpointEncodingTests.
    }

    public struct Response: Decodable, Sendable {
        public let heartbeatAcceptedAt: Date  // ISO-8601 via APIClient's .iso8601 strategy
        public let trustTier: TrustTier

        // Rely on .convertFromSnakeCase:
        //   heartbeat_accepted_at → heartbeatAcceptedAt, trust_tier → trustTier.
    }

    public let path = "/device/heartbeat"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(sessionToken: String, attestedKeyId: String, assertion: Data) {
        self.body = RequestBody(
            sessionToken: sessionToken,
            attestedKeyId: attestedKeyId,
            assertion: assertion
        )
    }
}
