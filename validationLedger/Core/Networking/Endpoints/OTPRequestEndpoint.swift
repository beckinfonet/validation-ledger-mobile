// validationLedger/Core/Networking/Endpoints/OTPRequestEndpoint.swift
// POST /auth/otp/request — begin OTP auth flow.
// Request body: E.164 phone number. Response: otpSessionID + expiry.
// Consumed by Phase 3 AUTH-01/AUTH-02.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor so nested
// RequestBody / Response conformances to Encodable / Decodable are not main-actor-isolated —
// APIEndpoint requires RequestBody: Sendable and Response: Sendable, which rejects
// main-actor-isolated conformances.
nonisolated public struct OTPRequestEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable {
        public let phone: String  // E.164 format, backend validates
    }
    public struct Response: Decodable, Sendable {
        public let otpSessionID: String
        public let expiresInSeconds: Int
    }
    public let path = "/auth/otp/request"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(phone: String) {
        self.body = RequestBody(phone: phone)
    }
}
