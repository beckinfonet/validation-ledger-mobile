// validationLedger/Core/Networking/Endpoints/KYCUploadInitEndpoint.swift
// POST /kyc/upload/init — begin chunked upload; backend returns uploadID + serverChunkSize.
// Consumed by Phase 5 UPL-01 (KYCUploader.startUpload).
// Chunk size default per UPL-01: 512 KB; backend can override via serverChunkSize in Response.

import Foundation

// `nonisolated` required under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — see
// APIEndpoint.swift for rationale.
nonisolated public struct KYCUploadInitEndpoint: APIEndpoint {
    public enum ArtifactType: String, Encodable, Sendable {
        case face
        case dlFront = "dl_front"
        case dlBack = "dl_back"
        case truck
        case trailer
        case plate
    }
    public struct RequestBody: Encodable, Sendable {
        public let artifactType: ArtifactType
        public let totalChunks: Int
        public let totalBytes: Int
        public let sha256: String  // hex-encoded full-artifact hash
    }
    public struct Response: Decodable, Sendable {
        public let uploadID: String
        public let chunkSize: Int
    }
    public let path = "/kyc/upload/init"
    public let method: HTTPMethod = .post
    public let body: RequestBody?

    public init(artifactType: ArtifactType, totalChunks: Int, totalBytes: Int, sha256: String) {
        self.body = RequestBody(
            artifactType: artifactType,
            totalChunks: totalChunks,
            totalBytes: totalBytes,
            sha256: sha256
        )
    }
}
