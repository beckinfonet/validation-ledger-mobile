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

import Foundation

/// The in-progress KYC capture + upload flow, persisted as a single unit.
public struct KYCSession: Codable, Sendable, Equatable {

    /// When the user started this KYC flow.
    public var sessionStartedAt: Date

    /// Un-uploaded artifact bytes, keyed by `ArtifactType.rawValue`. An entry is
    /// removed once the local copy is deleted post-commit (D-02 footprint
    /// control); the matching `ArtifactUploadState` survives in `uploadStates`.
    public var artifactData: [String: Data]

    /// Per-artifact upload cursors, keyed by `ArtifactType.rawValue`.
    public var uploadStates: [String: ArtifactUploadState]

    /// `true` once the final `POST /kyc/submit` has been sent (D-03).
    public var submitted: Bool

    public init(
        sessionStartedAt: Date = Date(),
        artifactData: [String: Data] = [:],
        uploadStates: [String: ArtifactUploadState] = [:],
        submitted: Bool = false
    ) {
        self.sessionStartedAt = sessionStartedAt
        self.artifactData = artifactData
        self.uploadStates = uploadStates
        self.submitted = submitted
    }

    /// The upload cursor for `artifact`, or `nil` if that artifact has not been
    /// started yet.
    public func state(for artifact: KYCUploadInitEndpoint.ArtifactType) -> ArtifactUploadState? {
        uploadStates[artifact.rawValue]
    }

    /// The locally-held bytes for `artifact`, or `nil` if never captured or the
    /// local copy has been deleted post-commit (D-02).
    public func data(for artifact: KYCUploadInitEndpoint.ArtifactType) -> Data? {
        artifactData[artifact.rawValue]
    }
}
