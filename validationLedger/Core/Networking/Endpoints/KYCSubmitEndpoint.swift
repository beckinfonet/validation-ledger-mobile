// validationLedger/Core/Networking/Endpoints/KYCSubmitEndpoint.swift
// POST /kyc/submit — D-03 thin finalizer for the Phase 5 KYC capture flow.
// By the time this endpoint is called all 6 KYC artifacts have ALREADY been committed
// to the backend via the pipelined per-artifact resumable upload (D-01 / KYCUploader).
// /kyc/submit only carries the 6 committed artifact IDs and hands the bundle off to
// review — it does NOT upload any bytes. Consumed by Phase 5 (KYC-01 Review-screen
// gated Submit; turned GREEN in plan 05-05 / 05-06).
//
// Structural template: KYCUploadCommitEndpoint (same nonisolated/Sendable + explicit
// acronym-CodingKeys discipline).

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct KYCSubmitEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable {
        /// The 6 committed artifact IDs (face, DL front/back, vehicle, trailer, plate).
        public let artifactIDs: [String]

        // Explicit CodingKeys pin the wire contract against JSONEncoder.convertToSnakeCase
        // toolchain behavior for trailing uppercase acronyms (ID). The wire key is
        // `artifact_ids`; the camelCase raw value below is the form .convertToSnakeCase
        // consumes. See OTPVerifyEndpoint.RequestBody for full rationale.
        private enum CodingKeys: String, CodingKey {
            case artifactIDs = "artifactIds"
        }
    }
    public struct Response: Decodable, Sendable {
        /// Post-submit KYC status — e.g. "under_review".
        public let overallStatus: String

        // Explicit CodingKeys: acronym bridge — see OTPRequestEndpoint.Response for rationale.
        // Raw value is camelCase (post-.convertFromSnakeCase form of wire key `overall_status`).
        private enum CodingKeys: String, CodingKey {
            case overallStatus
        }
    }
    public let path = "/kyc/submit"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(artifactIDs: [String]) {
        self.body = RequestBody(artifactIDs: artifactIDs)
    }
}
