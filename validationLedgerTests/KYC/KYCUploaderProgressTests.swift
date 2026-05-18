// validationLedgerTests/KYC/KYCUploaderProgressTests.swift
// Requirement: UPL-04 — visible upload progress advances per chunk ack.
// RED scaffold turned GREEN by plan 05-04.
//
// KYCUploader takes an injected `@Sendable (ArtifactType, Double) -> Void`
// progress observer. Each chunk's server ack drives one update equal to
// `chunksAcked / totalChunks` — never a byte count (Pitfall 3).

import Testing
import Foundation
@testable import validationLedger

@Suite("KYCUploader — progress advances per chunk ack (UPL-04)", .serialized)
struct KYCUploaderProgressTests {

    /// 4 chunks at 512 KB.
    private static let fourChunkBytes = 512 * 1024 * 3 + 64_000

    @Test("UPL-04: progress advances monotonically — one fraction per acked chunk")
    func progressAdvancesPerChunkAck() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let totalChunks = 4
        registerProgressBackend(totalChunks: totalChunks)

        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            KYCUploaderTestSupport.artifactData(byteCount: Self.fourChunkBytes)
        try store.persist(session)

        let updates = ProgressRecorder()
        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger(),
            onProgress: { artifact, fraction in
                updates.record(artifact: artifact, fraction: fraction)
            }
        )
        try await uploader.upload(artifactType: .face)

        let fractions = updates.fractions(for: .face)
        // One update per acked chunk: 0.25, 0.50, 0.75, 1.0.
        #expect(fractions == [0.25, 0.5, 0.75, 1.0])
        // Monotonic non-decreasing.
        #expect(fractions == fractions.sorted())
        // Reaches exactly 1.0 — derived from chunksAcked/totalChunks, not bytes.
        #expect(fractions.last == 1.0)
    }

    @Test("UPL-04: progress on resume continues from the persisted cursor, not zero")
    func progressOnResumeContinuesFromCursor() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let chunkSize = 512 * 1024
        let totalChunks = 4
        let bytes = KYCUploaderTestSupport.artifactData(byteCount: Self.fourChunkBytes)
        registerProgressBackend(totalChunks: totalChunks)

        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = bytes
        session.uploadStates[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = ArtifactUploadState(
            artifactType: .face,
            uploadID: "up-progress-resume",
            totalChunks: totalChunks,
            totalBytes: Self.fourChunkBytes,
            chunkSize: chunkSize,
            chunksAcked: 2,
            sha256: bytes.kycUploaderSHA256HexForTest
        )
        try store.persist(session)

        let updates = ProgressRecorder()
        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger(),
            onProgress: { artifact, fraction in
                updates.record(artifact: artifact, fraction: fraction)
            }
        )
        try await uploader.upload(artifactType: .face)

        // Resumes at chunk 2 — first update is 0.75, then 1.0. No 0.25 / 0.5.
        let fractions = updates.fractions(for: .face)
        #expect(fractions == [0.75, 1.0])
    }

    // MARK: - Helpers

    final class ProgressRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [KYCUploadInitEndpoint.ArtifactType: [Double]] = [:]
        func record(artifact: KYCUploadInitEndpoint.ArtifactType, fraction: Double) {
            lock.withLock { values[artifact, default: []].append(fraction) }
        }
        func fractions(for artifact: KYCUploadInitEndpoint.ArtifactType) -> [Double] {
            lock.withLock { values[artifact] ?? [] }
        }
    }

    private func registerProgressBackend(totalChunks: Int) {
        MockURLProtocol.register { request in
            guard let path = request.url?.path, request.httpMethod == "POST" else { return nil }
            switch path {
            case "/kyc/upload/init":
                return KYCUploaderTestSupport.make200(
                    #"{"upload_id":"up-progress-1","chunk_size":\#(512 * 1024)}"#, url: request.url)
            case "/kyc/upload/chunk":
                let index = KYCUploaderTestSupport.chunkIndex(from: request) ?? -1
                let acked = index + 1
                return KYCUploaderTestSupport.make200(
                    #"{"acked_chunk":\#(index),"chunks_acked":\#(acked),"total_chunks":\#(totalChunks)}"#,
                    url: request.url)
            case "/kyc/upload/commit":
                return KYCUploaderTestSupport.make200(
                    #"{"artifact_id":"artifact-progress-1","status":"pending_review"}"#, url: request.url)
            default:
                return nil
            }
        }
    }
}
