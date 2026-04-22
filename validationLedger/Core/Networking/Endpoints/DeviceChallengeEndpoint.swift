// validationLedger/Core/Networking/Endpoints/DeviceChallengeEndpoint.swift
// GET /device/challenge — fetch a server-generated, single-use attestation challenge.
// Consumed by Plan 03 DCAppAttestAttestationService immediately before attestKey /
// generateAssertion (D-05 challenge contract, D-08 single-use immediate-consumption).
// GET endpoint: no body — uses EmptyBody sentinel from APIEndpoint.swift.
//
// Response shape (D-05): { challenge: base64 string, expires_at: ISO8601, nonce: string }
// Mock fixture: validationLedgerTests/Networking/Fixtures/device-challenge-success.json (Plan 02).
//
// Threat mitigation T-APP-ATTEST-01 (Spoofing): client is a passive consumer of the
// server-generated challenge. No client-side caching — each fetch must be consumed
// immediately (D-08). Backend owns nonce + TTL (≤60s).

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct DeviceChallengeEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody

    public struct Response: Decodable, Sendable {
        public let challenge: String   // base64-encoded (client applies SHA-256 per D-06)
        public let expiresAt: Date     // ISO-8601 decoded via APIClient's .iso8601 strategy
        public let nonce: String

        // .convertFromSnakeCase handles expires_at → expiresAt. challenge + nonce are
        // already single-word lowercase on the wire — no CodingKeys override needed.
    }

    public let path = "/device/challenge"
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil

    public init() {}
}
