// validationLedgerTests/KYC/KYCGPSUploadPayloadIntegrationTests.swift
// Phase 5 SC-1 gap closure — the GPS-into-upload-payload chained proof.
// Requirements: KYC-04 / SC-1 (simulator portion).
//
// === Why this test exists ===
// The phase verifier found SC-1 only PARTIAL: `GPSMetadataInjectorTests` proves
// the EXIF GPS round-trip in isolation, and `KYCEndToEndIntegrationTests` drives
// the full init→chunk→commit pipeline — but with SYNTHETIC (non-image, non-GPS)
// `artifactData()` bytes. Neither test chains GPS-injection → session-store
// persistence → upload chunk payload. SC-1 demands exactly that single test:
// "a unit test that round-trips a known GPS value through the pipeline and
// asserts it reaches the upload payload."
//
// This test closes that gap. It:
//   1. Injects a known CLLocation into real JPEG bytes via `GPSMetadataInjector`
//      (the FALLBACK CGImageSource/CGImageDestination path — the only one a
//      simulator can exercise without an `AVCapturePhoto`).
//   2. Persists those GPS-tagged bytes into a temp on-disk `KYCSessionStore` as
//      a `KYCSession` artifact — exactly how the capture flow seeds artifacts.
//   3. Runs the real `KYCUploader.upload(...)` against `MockURLProtocol` with
//      init/chunk/commit success fixtures.
//   4. Captures every `/kyc/upload/chunk` POST body, base64-decodes the
//      `chunk_data` field, reassembles the artifact bytes in `chunk_index` order.
//   5. Asserts the GPS EXIF dictionary read back from the REASSEMBLED upload
//      payload recovers the known lat/lon within a small epsilon — i.e. the GPS
//      metadata provably survives all the way into what the uploader transmits.
//
// `@Suite(.serialized)` is mandatory — the `@Test` mutates the global
// `MockURLProtocol` handler registry (KYCEndToEndIntegrationTests pattern).

import Testing
import Foundation
import CoreLocation
import ImageIO
import UniformTypeIdentifiers
@testable import validationLedger

@Suite("KYC GPS → upload-payload chained proof (KYC-04 / SC-1)", .serialized)
struct KYCGPSUploadPayloadIntegrationTests {

    /// Produce a small, valid JPEG `Data` with NO GPS dictionary — the clean
    /// input the GPS injector tags. Built via `CGImageDestination` so no UIImage
    /// is ever used (the UIKit decode/re-encode path strips EXIF — Pitfall 6).
    /// Mirrors `GPSMetadataInjectorTests.makeBareJPEG`.
    private func makeBareJPEG(width: Int = 64, height: Int = 64) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, cgImage, [:] as CFDictionary)
        precondition(CGImageDestinationFinalize(dest), "fixture JPEG must finalize")
        return out as Data
    }

    @Test("SC-1: a known GPS value injected at capture survives into the upload chunk payload")
    func injectedGPSReachesUploadPayload() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let injector = GPSMetadataInjector()

        // --- 1. Inject a known GPS value into real JPEG bytes ----------------
        // Chicago — a recognizable northern-/western-hemisphere coordinate, the
        // same fixed value `GPSMetadataInjectorTests` uses.
        let known = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
            altitude: 0,
            horizontalAccuracy: 12,
            verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let bareJPEG = makeBareJPEG()
        // Sanity: the clean input genuinely starts with no GPS dictionary.
        #expect(injector.readGPSDictionary(from: bareJPEG) == nil,
                "the bare fixture JPEG must carry no GPS dictionary")

        let gpsTaggedJPEG = try #require(
            injector.injectGPS(into: bareJPEG, location: known),
            "GPSMetadataInjector must produce GPS-tagged JPEG bytes"
        )
        // Sanity: the GPS tag is present in the bytes we are about to persist.
        #expect(injector.readGPSDictionary(from: gpsTaggedJPEG) != nil,
                "the GPS-tagged bytes must carry a GPS dictionary before upload")

        // --- 2. Persist the GPS-tagged bytes into a temp KYCSessionStore -----
        // Seed the artifact exactly the way the capture flow does (and the way
        // KYCEndToEndIntegrationTests seeds artifacts) — but with REAL
        // GPS-injected JPEG bytes, not the synthetic `artifactData()` helper.
        let artifact: KYCUploadInitEndpoint.ArtifactType = .face
        let store = try KYCUploaderTestSupport.makeStore()
        var session = KYCSession()
        session.artifactData[artifact.rawValue] = gpsTaggedJPEG
        try store.persist(session)

        // --- 3. Drive the real KYCUploader against MockURLProtocol -----------
        // A chunk-body-capturing mock KYC backend: init → chunk → commit. The
        // recorder keeps every chunk POST body so the test can reassemble the
        // exact bytes the uploader transmitted.
        let backend = ChunkCapturingBackend()
        backend.register()

        let uploader = KYCUploader(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        try await uploader.upload(artifactType: artifact)

        // The artifact is small enough to fit in a single 512 KB chunk; assert
        // the pipeline actually ran init → chunk → commit.
        #expect(backend.initCount == 1, "exactly one /kyc/upload/init")
        #expect(backend.commitCount == 1, "exactly one /kyc/upload/commit")
        #expect(backend.chunkCount >= 1, "at least one /kyc/upload/chunk POST")

        // --- 4. Reassemble the uploaded artifact bytes from the chunk bodies -
        // The wire body is snake_case JSON; `chunk_data` is base64 of the raw
        // chunk bytes, `chunk_index` is the ordinal. Reassemble in index order.
        let chunkBodies = backend.capturedChunkBodies
        #expect(!chunkBodies.isEmpty, "the mock backend captured the chunk POST bodies")

        var decodedChunks: [Int: Data] = [:]
        for body in chunkBodies {
            let json = try #require(
                try JSONSerialization.jsonObject(with: body) as? [String: Any],
                "every chunk POST body decodes as JSON"
            )
            let index = try #require(
                json["chunk_index"] as? Int,
                "the chunk body carries a chunk_index"
            )
            let base64 = try #require(
                json["chunk_data"] as? String,
                "the chunk body carries a base64 chunk_data field"
            )
            let chunkBytes = try #require(
                Data(base64Encoded: base64),
                "chunk_data is valid base64"
            )
            decodedChunks[index] = chunkBytes
        }

        let reassembled = decodedChunks
            .sorted { $0.key < $1.key }
            .reduce(into: Data()) { $0.append($1.value) }

        // The reassembled wire payload must be byte-identical to the GPS-tagged
        // JPEG that was persisted — the uploader transmits the artifact verbatim.
        #expect(reassembled == gpsTaggedJPEG,
                "the reassembled chunk payload equals the persisted GPS-tagged JPEG")

        // --- 5. Assert the GPS value survives into the upload payload --------
        // Read the EXIF GPS dictionary back out of the bytes the uploader
        // actually transmitted — not the original artifact, the REASSEMBLED
        // wire payload. This is the SC-1 chained assertion.
        let gps = try #require(
            injector.readGPSDictionary(from: reassembled),
            "the GPS dictionary survives into the reassembled upload payload"
        )
        let lat = try #require(
            gps[kCGImagePropertyGPSLatitude as String] as? Double,
            "the upload payload carries a GPS latitude"
        )
        let lon = try #require(
            gps[kCGImagePropertyGPSLongitude as String] as? Double,
            "the upload payload carries a GPS longitude"
        )
        let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String

        // CoreGraphics stores unsigned magnitudes + ref letters; recover the
        // known Chicago coordinate within a small epsilon.
        #expect(abs(lat - abs(known.coordinate.latitude)) < 0.0001,
                "the known latitude reaches the upload payload")
        #expect(abs(lon - abs(known.coordinate.longitude)) < 0.0001,
                "the known longitude reaches the upload payload")
        #expect(latRef == "N", "northern-hemisphere ref letter survives to the payload")
        #expect(lonRef == "W", "western-hemisphere ref letter survives to the payload")
    }

    // MARK: - Chunk-body-capturing mock KYC backend

    /// A lock-guarded `MockURLProtocol` handler that drives init → chunk →
    /// commit AND captures every `/kyc/upload/chunk` POST body so the test can
    /// reassemble the transmitted artifact bytes. Mirrors the `EndToEndBackend`
    /// pattern in `KYCEndToEndIntegrationTests`, adding chunk-body capture.
    final class ChunkCapturingBackend: @unchecked Sendable {
        private let lock = NSLock()
        private var _initCount = 0
        private var _commitCount = 0
        private var _chunkBodies: [Data] = []

        var initCount: Int { lock.withLock { _initCount } }
        var commitCount: Int { lock.withLock { _commitCount } }
        var chunkCount: Int { lock.withLock { _chunkBodies.count } }
        var capturedChunkBodies: [Data] { lock.withLock { _chunkBodies } }

        func register() {
            MockURLProtocol.register { [self] request in
                guard let path = request.url?.path else { return nil }
                switch (path, request.httpMethod) {
                case ("/kyc/upload/init", "POST"):
                    lock.withLock { _initCount += 1 }
                    let payload =
                        #"{"upload_id":"up-gps-face","chunk_size":\#(KYCUploader.defaultChunkSize)}"#
                    return KYCUploaderTestSupport.make200(payload, url: request.url)

                case ("/kyc/upload/chunk", "POST"):
                    // Capture the FULL chunk body so the test can base64-decode
                    // the `chunk_data` field and reassemble the artifact bytes.
                    let body = KYCUploaderTestSupport.bodyData(from: request)
                    let index = KYCUploaderTestSupport.chunkIndex(from: request) ?? -1
                    lock.withLock { _chunkBodies.append(body) }
                    let acked = index + 1
                    let payload =
                        #"{"acked_chunk":\#(index),"chunks_acked":\#(acked),"total_chunks":\#(acked)}"#
                    return KYCUploaderTestSupport.make200(payload, url: request.url)

                case ("/kyc/upload/commit", "POST"):
                    lock.withLock { _commitCount += 1 }
                    return KYCUploaderTestSupport.make200(
                        #"{"artifact_id":"artifact-up-gps-face","status":"pending_review"}"#,
                        url: request.url
                    )

                default:
                    return nil
                }
            }
        }
    }
}
