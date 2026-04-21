// validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift
// GET /kyc/status — poll overall KYC status + per-artifact status.
// Consumed by Phase 5 KYC-05 (status UI).
// GET endpoint: no body — uses internal EmptyBody sentinel from APIEndpoint.swift.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct KYCStatusEndpoint: APIEndpoint {
    public typealias RequestBody = EmptyBody
    public struct Response: Decodable, Sendable {
        public struct Artifact: Decodable, Sendable {
            public let artifactID: String
            public let status: String             // "pending_review" | "verified" | "rejected"
            public let rejectionReason: String?   // nullable; backend-provided controlled vocabulary
        }
        public let overallStatus: String          // "pending" | "under_review" | "verified" | "rejected"
        public let artifacts: [Artifact]
    }
    public let path = "/kyc/status"
    public let method: HTTPMethod = .get
    public let body: RequestBody? = nil

    public init() {}
}
