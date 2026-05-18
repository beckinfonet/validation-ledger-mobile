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

        // IN-01 (Phase 2 carryover, closed Phase 3 Plan 02):
        // APIClient sets `JSONEncoder.keyEncodingStrategy = .convertToSnakeCase`.
        // On the current Swift 5.9+/Xcode 26.4 toolchain the strategy correctly maps
        // `otpSessionID` to `otp_session_id`, but that behavior is implementation-defined
        // for trailing uppercase acronyms. Explicit CodingKeys with the camelCase raw
        // value ("otpSessionId") pin the wire contract to `otp_session_id` regardless of
        // future toolchain changes. Symmetric to the Response.CodingKeys pattern below.
        private enum CodingKeys: String, CodingKey {
            case otpSessionID = "otpSessionId"
            case code
        }
    }
    public struct Response: Decodable, Sendable {
        public let sessionToken: String
        public let role: String   // "shipper" | "broker" | "carrier" | "dispatch" | "factoring"
        public let userID: String

        // D-13 (Phase 5): the KYC status of the user returned on verify, so Phase 5 Plan 07
        // can route a returning verified user straight to the role shell and a not-yet-verified
        // user to the KYC gate. OPTIONAL with no default — the wire field is `kyc_status` but
        // pre-Phase-5 fixtures (otp-verify-success.json and role-specific shells) do not carry
        // it, so an absent/malformed value decodes to `nil`. Downstream routing (Plan 07)
        // treats `nil` as "not verified" — fail-closed to the KYC gate (threat T-05-01-01).
        public let kycStatus: String?

        // Explicit CodingKeys: acronym bridge — see OTPRequestEndpoint.Response for rationale.
        // Raw values are camelCase (post-.convertFromSnakeCase form); `kycStatus` is the
        // post-.convertFromSnakeCase form of the wire key `kyc_status`.
        private enum CodingKeys: String, CodingKey {
            case sessionToken
            case role
            case userID = "userId"
            case kycStatus
        }
    }
    public let path = "/auth/otp/verify"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(otpSessionID: String, code: String) {
        self.body = RequestBody(otpSessionID: otpSessionID, code: code)
    }
}
