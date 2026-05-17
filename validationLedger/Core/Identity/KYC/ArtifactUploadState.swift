// validationLedger/Core/Identity/KYC/ArtifactUploadState.swift
// Phase 5 Plan 02 (UPL-02 / KYC-06): per-artifact chunked-upload progress model.
//
// One ArtifactUploadState exists per KYC artifact (face / dl_front / dl_back /
// truck / trailer / plate). It is the resume cursor for the chunked-upload
// pipeline (UPL-02): `chunksAcked` advances by one after every server ack and is
// persisted immediately (Pitfall 4 — a force-quit loses at most the in-flight
// chunk, never the whole artifact). `KYCUploader` (plan 05-04) reads this on
// re-init to resume from `chunksAcked` rather than chunk 0.
//
// No in-repo analog (RESEARCH "No Analog Found") — this is a plain Codable value
// type. It reuses the SHIPPED `KYCUploadInitEndpoint.ArtifactType` for the
// artifact key; it deliberately does NOT redefine the 6-artifact vocabulary.

import Foundation

// The shipped `KYCUploadInitEndpoint.ArtifactType` is declared `Encodable` only
// (it is the request-body side of `/kyc/upload/init`). The persisted KYC models
// here need it to round-trip through `Codable`, so add `Decodable` via a
// retroactive conformance — this does NOT redefine the 6-artifact vocabulary,
// it only completes `Codable` on the single shipped enum.
extension KYCUploadInitEndpoint.ArtifactType: Decodable {}

/// Per-artifact chunked-upload progress. The resume cursor for UPL-02.
public struct ArtifactUploadState: Codable, Sendable, Equatable {

    /// The artifact this state tracks. Reuses the shipped endpoint enum — the
    /// 6-artifact vocabulary lives in exactly one place.
    public let artifactType: KYCUploadInitEndpoint.ArtifactType

    /// Server-issued upload identifier. `nil` until `POST /kyc/upload/init`
    /// succeeds for this artifact.
    public var uploadID: String?

    /// Total chunk count for the full artifact.
    public var totalChunks: Int

    /// Total artifact size in bytes.
    public var totalBytes: Int

    /// Backend-confirmed chunk size (from the `KYCUploadInitEndpoint.Response`).
    public var chunkSize: Int

    /// Resume cursor — count of chunks the server has acked (UPL-02).
    /// Persisted immediately after every ack (Pitfall 4).
    public var chunksAcked: Int

    /// Hex-encoded SHA-256 of the full artifact (`KYCUploadInitEndpoint` body).
    public var sha256: String

    /// `true` once `POST /kyc/upload/commit` has succeeded for this artifact.
    public var committed: Bool

    /// Server-issued artifact identifier — set after a successful commit.
    public var artifactID: String?

    /// `false` once the local artifact `Data` copy is deleted post-commit
    /// (D-02 footprint control). The upload state survives; the bytes do not.
    public var localDataAvailable: Bool

    public init(
        artifactType: KYCUploadInitEndpoint.ArtifactType,
        uploadID: String? = nil,
        totalChunks: Int = 0,
        totalBytes: Int = 0,
        chunkSize: Int = 0,
        chunksAcked: Int = 0,
        sha256: String = "",
        committed: Bool = false,
        artifactID: String? = nil,
        localDataAvailable: Bool = true
    ) {
        self.artifactType = artifactType
        self.uploadID = uploadID
        self.totalChunks = totalChunks
        self.totalBytes = totalBytes
        self.chunkSize = chunkSize
        self.chunksAcked = chunksAcked
        self.sha256 = sha256
        self.committed = committed
        self.artifactID = artifactID
        self.localDataAvailable = localDataAvailable
    }

    /// Deterministic per-chunk idempotency key (RESEARCH Open Question 2).
    ///
    /// The same `(uploadID, chunkIndex)` pair always yields the same string, so a
    /// retried chunk POST carries the same `Idempotency-Key` and the backend
    /// dedupes it. It is derived purely from persisted fields, so it survives a
    /// cold boot without being stored separately.
    public func idempotencyKey(forChunk index: Int) -> String {
        "\(uploadID ?? "no-upload-id").chunk.\(index)"
    }
}
