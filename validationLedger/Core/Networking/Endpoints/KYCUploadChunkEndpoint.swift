// validationLedger/Core/Networking/Endpoints/KYCUploadChunkEndpoint.swift
// POST /kyc/upload/chunk — upload one chunk of a KYC artifact.
// Consumed by Phase 5 UPL-01/UPL-02 (chunk loop + resume).
// chunkData is base64-encoded bytes; backend verifies chunkSha256 matches payload.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct KYCUploadChunkEndpoint: APIEndpoint {
    public struct RequestBody: Encodable, Sendable {
        public let uploadID: String
        public let chunkIndex: Int
        public let chunkData: String   // base64-encoded bytes
        public let chunkSha256: String // hex-encoded SHA-256 of the raw chunk bytes
    }
    public struct Response: Decodable, Sendable {
        public let ackedChunk: Int
        public let chunksAcked: Int
        public let totalChunks: Int
    }
    public let path = "/kyc/upload/chunk"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(uploadID: String, chunkIndex: Int, chunkData: String, chunkSha256: String) {
        self.body = RequestBody(
            uploadID: uploadID,
            chunkIndex: chunkIndex,
            chunkData: chunkData,
            chunkSha256: chunkSha256
        )
    }
}
