// validationLedger/Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift
// POST /kyc/upload/commit — finalize chunked upload; backend assembles + hands off to review.
// Consumed by Phase 5 UPL-01 (final step of each artifact upload).

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct KYCUploadCommitEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable {
        public let uploadID: String
    }
    public struct Response: Decodable, Sendable {
        public let artifactID: String
        public let status: String  // e.g., "pending_review"

        // Explicit CodingKeys: acronym bridge — see OTPRequestEndpoint.Response for rationale.
        // Raw values are camelCase (post-.convertFromSnakeCase form).
        private enum CodingKeys: String, CodingKey {
            case artifactID = "artifactId"
            case status
        }
    }
    public let path = "/kyc/upload/commit"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(uploadID: String) {
        self.body = RequestBody(uploadID: uploadID)
    }
}
