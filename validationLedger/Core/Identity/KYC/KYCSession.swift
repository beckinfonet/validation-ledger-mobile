// validationLedger/Core/Identity/KYC/KYCSession.swift
// Phase 5 Plan 02 (KYC-06 / UPL-02): the Codable in-progress KYC session model.
//
// KYCSession is the whole resumable KYC flow as a value type: the un-uploaded
// artifact `Data`, the per-artifact upload cursors, and the submitted flag. It is
// persisted by `KYCSessionStore` to an `NSFileProtectionComplete`-protected file
// so the in-progress capture survives an indefinite cold boot (D-02 / KYC-06).
//
// State-holder rationale analog: `App/AppSession.swift` (05-PATTERNS.md) — a value
// type that aggregates an in-progress flow's state. KYCSession differs only in
// that it is the *persisted* unit, not an in-memory-only holder.
//
// Artifact-key convention: every dictionary is keyed by
// `KYCUploadInitEndpoint.ArtifactType.rawValue` ("face", "dl_front", "dl_back",
// "truck", "trailer", "plate") — one consistent string convention everywhere.
//
// === D-02 footprint vs. the Review thumbnail (debug: kyc-session-store-data-race) ===
// `artifactData` holds the multi-MB full-resolution identity image only until the
// artifact commits; post-commit `KYCUploader` frees those bytes (D-02 footprint
// control). `thumbnailData` holds a tiny (~150 px longest-edge) downscaled JPEG
// retained PAST commit so the Review grid can still render a thumbnail for an
// already-uploaded artifact. A few-KB thumbnail is not the full-resolution
// identity-image exposure D-02 guards — the multi-MB blob is still freed.

import Foundation

/// The in-progress KYC capture + upload flow, persisted as a single unit.
public struct KYCSession: Codable, Sendable, Equatable {

    /// When the user started this KYC flow.
    public var sessionStartedAt: Date

    /// Un-uploaded artifact bytes, keyed by `ArtifactType.rawValue`. An entry is
    /// removed once the local copy is deleted post-commit (D-02 footprint
    /// control); the matching `ArtifactUploadState` survives in `uploadStates`.
    public var artifactData: [String: Data]

    /// Small downscaled (~150 px longest edge) JPEG thumbnails, keyed by
    /// `ArtifactType.rawValue`. Written by `KYCUploader` at commit time — in the
    /// same atomic store update that frees the full `artifactData` blob — so the
    /// Review grid can render a thumbnail for an already-committed artifact whose
    /// full-resolution bytes are gone (D-02). A few-KB thumbnail is not the
    /// identity-image exposure D-02 guards.
    public var thumbnailData: [String: Data]

    /// Per-artifact upload cursors, keyed by `ArtifactType.rawValue`.
    public var uploadStates: [String: ArtifactUploadState]

    /// `true` once the final `POST /kyc/submit` has been sent (D-03).
    public var submitted: Bool

    public init(
        sessionStartedAt: Date = Date(),
        artifactData: [String: Data] = [:],
        thumbnailData: [String: Data] = [:],
        uploadStates: [String: ArtifactUploadState] = [:],
        submitted: Bool = false
    ) {
        self.sessionStartedAt = sessionStartedAt
        self.artifactData = artifactData
        self.thumbnailData = thumbnailData
        self.uploadStates = uploadStates
        self.submitted = submitted
    }

    // MARK: - Codable — forward-compatible decode

    private enum CodingKeys: String, CodingKey {
        case sessionStartedAt
        case artifactData
        case thumbnailData
        case uploadStates
        case submitted
    }

    /// Custom `init(from:)` so an OLDER on-disk session JSON written before
    /// `thumbnailData` existed still decodes — the missing key defaults to `[:]`
    /// rather than throwing `keyNotFound`. The synthesised decoder would reject a
    /// non-optional property with no value; `decodeIfPresent` makes it tolerant.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionStartedAt = try container.decode(Date.self, forKey: .sessionStartedAt)
        self.artifactData = try container.decode([String: Data].self, forKey: .artifactData)
        self.thumbnailData =
            try container.decodeIfPresent([String: Data].self, forKey: .thumbnailData) ?? [:]
        self.uploadStates =
            try container.decode([String: ArtifactUploadState].self, forKey: .uploadStates)
        self.submitted = try container.decode(Bool.self, forKey: .submitted)
    }

    // MARK: - Lookups

    /// The upload cursor for `artifact`, or `nil` if that artifact has not been
    /// started yet.
    public func state(for artifact: KYCUploadInitEndpoint.ArtifactType) -> ArtifactUploadState? {
        uploadStates[artifact.rawValue]
    }

    /// The locally-held full-resolution bytes for `artifact`, or `nil` if never
    /// captured or the local copy has been deleted post-commit (D-02).
    public func data(for artifact: KYCUploadInitEndpoint.ArtifactType) -> Data? {
        artifactData[artifact.rawValue]
    }

    /// The small downscaled thumbnail JPEG for `artifact`, or `nil` if the
    /// artifact has not committed yet (pre-commit the full bytes are still in
    /// `artifactData` and serve as the thumbnail source). Mirrors `data(for:)`.
    public func thumbnail(for artifact: KYCUploadInitEndpoint.ArtifactType) -> Data? {
        thumbnailData[artifact.rawValue]
    }
}
