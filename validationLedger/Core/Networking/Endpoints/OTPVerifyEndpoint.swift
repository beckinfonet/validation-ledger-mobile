// validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift
// POST /auth/otp/verify — submit 6-digit code; return session token + role.
// Consumed by Phase 3 AUTH-02. Role drives Phase 3 SHELL-01 role-coordinator selection.
// Role values mirror validationLedger/Roles/Role.swift.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct OTPVerifyEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable {
        public let otpSessionID: String
        public let code: String  // 6-digit numeric string; M1 mock accepts "123456"
    }
    public struct Response: Decodable, Sendable {
        public let sessionToken: String
        public let role: String   // "shipper" | "broker" | "carrier" | "dispatch" | "factoring"
        public let userID: String
    }
    public let path = "/auth/otp/verify"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(otpSessionID: String, code: String) {
        self.body = RequestBody(otpSessionID: otpSessionID, code: code)
    }
}
