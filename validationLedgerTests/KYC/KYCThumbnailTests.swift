// validationLedgerTests/KYC/KYCThumbnailTests.swift
// Debug session: kyc-session-store-data-race (SECONDARY decision).
//
// Proves the post-commit Review-thumbnail invariant: after `KYCUploader` commits
// an artifact and frees its multi-MB full-resolution bytes (D-02 footprint
// control), the session STILL carries a small, renderable `thumbnailData` entry
// for that artifact — so the Review grid can show a thumbnail for an
// already-uploaded artifact.
//
// Also covers the `KYCThumbnail` downscale helper directly and the
// forward-compatible `KYCSession` decode (an older session JSON without the
// `thumbnailData` key still decodes, defaulting to `[:]`).
//
// Drives the SHIPPED init/chunk/commit endpoints through the real APIClient +
// MockURLProtocol (reusing KYCUploaderTestSupport). `.serialized` because the
// suite mutates the global MockURLProtocol handler registry. Run with
// `-parallel-testing-enabled NO`.

import Testing
import Foundation
import UIKit
@testable import validationLedger

@Suite("KYC Review thumbnail — post-commit retention (debug: kyc-session-store-data-race)", .serialized)
struct KYCThumbnailTests {

    // MARK: - Fixtures

    /// A real, decodable JPEG of `side`×`side` pixels — large enough that the
    /// downscale to ~150 px is a genuine reduction. `KYCThumbnail` needs a real
    /// image (`CGImageSource` must decode it); synthetic byte runs are not images.
    private static func sampleJPEG(side: Int = 1_200) -> Data {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side / 2, height: side / 2))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    /// Register a happy-path KYC backend: one init → N chunk acks → one commit.
    private func registerHappyPathBackend(
        recorder: KYCUploaderTestSupport.BackendRecorder,
        totalChunks: Int
    ) {
        MockURLProtocol.register { request in
            guard let path = request.url?.path, request.httpMethod == "POST" else { return nil }
            switch path {
            case "/kyc/upload/init":
                recorder.recordInit()
                return KYCUploaderTestSupport.make200(
                    #"{"upload_id":"up-thumb-1","chunk_size":524288}"#, url: request.url)
            case "/kyc/upload/chunk":
                let index = KYCUploaderTestSupport.chunkIndex(from: request) ?? -1
                recorder.recordChunkAttempt(index, key: nil)
                recorder.recordChunkSuccess(index)
                let acked = index + 1
                return KYCUploaderTestSupport.make200(
                    #"{"acked_chunk":\#(index),"chunks_acked":\#(acked),"total_chunks":\#(totalChunks)}"#,
                    url: request.url)
            case "/kyc/upload/commit":
                recorder.recordCommit()
                return KYCUploaderTestSupport.make200(
                    #"{"artifact_id":"artifact-thumb-1","status":"pending_review"}"#,
                    url: request.url)
            default:
                return nil
            }
        }
    }

    // MARK: - The core invariant

    /// After a full upload+commit, the multi-MB `artifactData` blob is freed
    /// (D-02) BUT a small, renderable `thumbnailData` entry survives — the
    /// SECONDARY decision of debug session `kyc-session-store-data-race`.
    @Test("a committed artifact keeps a renderable thumbnail after its full bytes are freed")
    func committedArtifactRetainsRenderableThumbnail() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        // The 1200×1200 JPEG is well over one 512 KB chunk — its chunk count is
        // computed from the real encoded size; the backend acks each in turn.
        let fullImage = Self.sampleJPEG(side: 1_200)
        let chunkCount = max(1, (fullImage.count + 524_287) / 524_288)
        registerHappyPathBackend(recorder: recorder, totalChunks: chunkCount)

        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = fullImage
        try store.persist(session)

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        try await uploader.upload(artifactType: .face)

        let after = try #require(try store.loadSession())

        // D-02 — the multi-MB full-resolution bytes are gone.
        #expect(after.data(for: .face) == nil,
                "the full-resolution artifact bytes must be freed post-commit (D-02)")
        #expect(after.state(for: .face)?.localDataAvailable == false)
        #expect(after.state(for: .face)?.committed == true)

        // SECONDARY — a thumbnail survives, and it decodes to a real image.
        let thumbBytes = try #require(after.thumbnail(for: .face),
                                      "a committed artifact must keep a Review thumbnail")
        let thumbImage = try #require(UIImage(data: thumbBytes),
                                      "the retained thumbnail must decode to a renderable image")
        #expect(max(thumbImage.size.width, thumbImage.size.height)
                    <= CGFloat(KYCThumbnail.maxPixelSize) + 1,
                "the thumbnail must be downscaled to ~150 px on its longest edge")
        // The few-KB thumbnail is far smaller than the full image — D-02 intent
        // (no multi-MB identity image on disk) is preserved.
        #expect(thumbBytes.count < fullImage.count / 4,
                "the thumbnail must be a small fraction of the full image")
    }

    /// The Review VM renders the post-commit thumbnail: after a full pipelined
    /// upload, `refresh()` populates the face row's `thumbnailData` from the
    /// retained `KYCSession.thumbnailData` even though `artifactData` is gone.
    @Test("KYCReviewViewModel.refresh surfaces the post-commit thumbnail")
    @MainActor
    func reviewModelSurfacesPostCommitThumbnail() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let recorder = KYCUploaderTestSupport.BackendRecorder()
        let fullImage = Self.sampleJPEG(side: 1_000)
        let chunkCount = max(1, (fullImage.count + 524_287) / 524_288)
        registerHappyPathBackend(recorder: recorder, totalChunks: chunkCount)

        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] = fullImage
        try store.persist(session)

        let apiClient = KYCUploaderTestSupport.makeClient()
        let uploader = KYCUploader(
            apiClient: apiClient, store: store, logger: KYCUploaderTestSupport.makeLogger())
        try await uploader.upload(artifactType: .face)

        let viewModel = KYCReviewViewModel(
            apiClient: apiClient, store: store, kycUploader: uploader,
            logger: KYCUploaderTestSupport.makeLogger())
        viewModel.refresh()

        let faceRow = try #require(viewModel.rows.first { $0.artifact == .face })
        #expect(faceRow.status == .uploaded)
        let rowThumb = try #require(faceRow.thumbnailData,
                                    "the committed face row must carry a thumbnail to render")
        #expect(UIImage(data: rowThumb) != nil, "the row thumbnail must be a renderable image")
    }

    // MARK: - The downscale helper

    @Test("KYCThumbnail downscales a real image to a small JPEG within the pixel cap")
    func downscaleProducesSmallJPEG() throws {
        let full = Self.sampleJPEG(side: 2_000)
        let thumb = try #require(KYCThumbnail.downscaledJPEG(from: full))
        let image = try #require(UIImage(data: thumb))
        #expect(max(image.size.width, image.size.height)
                    <= CGFloat(KYCThumbnail.maxPixelSize) + 1)
        #expect(thumb.count < full.count, "the thumbnail must be smaller than the source")
    }

    @Test("KYCThumbnail returns nil for a non-image blob rather than crashing")
    func downscaleNonImageReturnsNil() {
        // The commit path must never crash on a corrupt / non-image artifact —
        // a synthetic byte run is not a decodable image.
        let notAnImage = Data(repeating: 0x7F, count: 4_096)
        #expect(KYCThumbnail.downscaledJPEG(from: notAnImage) == nil)
    }

    // MARK: - Forward-compatible decode

    /// A session JSON written before `thumbnailData` existed must still decode —
    /// the missing key defaults to `[:]`, not a `keyNotFound` throw.
    @Test("an older session JSON without thumbnailData still decodes (defaults to [:])")
    func legacySessionJSONDecodesWithoutThumbnailKey() throws {
        // A hand-built legacy payload: every KYCSession key EXCEPT thumbnailData.
        let legacyJSON = """
        {
          "sessionStartedAt": 700000000,
          "artifactData": {},
          "uploadStates": {},
          "submitted": false
        }
        """
        let decoded = try JSONDecoder().decode(KYCSession.self, from: Data(legacyJSON.utf8))
        #expect(decoded.thumbnailData.isEmpty,
                "a session decoded without the thumbnailData key must default to [:]")
        #expect(decoded.thumbnail(for: .face) == nil)
        #expect(decoded.submitted == false)
    }

    /// A round-trip with `thumbnailData` populated preserves it.
    @Test("thumbnailData round-trips through Codable")
    func thumbnailDataRoundTrips() throws {
        var session = KYCSession()
        session.thumbnailData[KYCUploadInitEndpoint.ArtifactType.face.rawValue] =
            Data([0x01, 0x02, 0x03])
        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(KYCSession.self, from: encoded)
        #expect(decoded.thumbnail(for: .face) == Data([0x01, 0x02, 0x03]))
    }
}
