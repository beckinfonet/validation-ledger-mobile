// validationLedger/Features/Onboarding/KYC/KYCReviewViewModel.swift
// Phase 5 Plan 06 — KYC-01 / D-03: the Review-screen gated-Submit state machine.
//
// The Review screen is the all-6-confirmed gate (D-03). Submit is a thin
// finalizer: by the time it is tapped every artifact is already committed on the
// backend via the pipelined per-artifact upload (D-01 / KYCUploader). `submit()`
// therefore fires `KYCSubmitEndpoint` exactly once, carrying the 6 server-issued
// `artifactID`s — a submitted KYC always means all artifacts are confirmed on the
// backend (threat T-05-06-01).
//
// VM contract (the OTPViewModel template — 05-PATTERNS "*ViewModel"):
//   - `@MainActor public final class`
//   - a nested `enum State: Equatable, Sendable`
//   - `state` `didSet` fires `onStateChange`
//   - `on…: ((…) -> Void)?` callbacks for coordinator plumbing
//   - initializer-DI (ARCH-04)
//
// Per-artifact upload status surface: the VM exposes the 6 artifacts' upload
// status read from `KYCSession.uploadStates`. `.uploaded` once `committed`,
// `.uploading(progress:)` while the chunk loop runs, `.failed` after the
// uploader's retries are exhausted. `KYCUploader`'s `onProgress` observer feeds
// the live `.uploading` fraction; `refresh()` re-reads the persisted store.
//
// === Session lifetime (D-02) ===
// `submit()` does NOT clear the on-disk KYC session. The session is cleared only
// once `KYCStatusEndpoint` confirms a `verified` verdict — that happens in
// `KYCStatusViewModel` (the D-02 verified-clear path). Keep the session until
// the status screen confirms.

import Foundation

@MainActor
public final class KYCReviewViewModel {

    // MARK: - Per-artifact upload status

    /// The upload status of a single KYC artifact, surfaced to the Review grid.
    public enum ArtifactUploadStatus: Equatable, Sendable {
        /// Server-acked + committed — the ✓ badge.
        case uploaded
        /// Chunk loop in progress — the determinate progress badge.
        case uploading(progress: Double)
        /// Retries exhausted — the ⚠ badge with inline Retry-upload / Retake.
        case failed
        /// Captured but not yet started uploading (or no state on disk yet).
        case pending
    }

    /// One row of the 6-cell Review grid: the artifact type + its upload status.
    public struct ArtifactRow: Equatable, Sendable {
        public let artifact: KYCUploadInitEndpoint.ArtifactType
        public var status: ArtifactUploadStatus

        public init(artifact: KYCUploadInitEndpoint.ArtifactType, status: ArtifactUploadStatus) {
            self.artifact = artifact
            self.status = status
        }
    }

    /// The 6 KYC artifacts in Review-grid display order.
    public static let artifactOrder: [KYCUploadInitEndpoint.ArtifactType] = [
        .face, .dlFront, .dlBack, .truck, .trailer, .plate
    ]

    // MARK: - State

    public enum State: Equatable, Sendable {
        /// Showing the 6-thumbnail grid; Submit gated by `submitEnabled`.
        case reviewing
        /// `submit()` in flight — `KYCSubmitEndpoint` POST running.
        case submitting
        /// `KYCSubmitEndpoint` returned — the coordinator advances to the status screen.
        case submitted
        /// `submit()` failed — the user may retry.
        case error(message: String)
    }

    public private(set) var state: State = .reviewing {
        didSet { onStateChange?(state) }
    }

    /// The current 6-row grid model. Mutating it re-fires `onRowsChange` so the
    /// Review VC can reload affected cells.
    public private(set) var rows: [ArtifactRow] = [] {
        didSet {
            onRowsChange?(rows)
            onSubmitEnabledChange?(submitEnabled)
        }
    }

    /// D-03 — Submit is enabled only when all 6 artifacts are `uploaded`
    /// (server-committed). A thin finalizer cannot fire before every artifact is
    /// confirmed on the backend (threat T-05-06-01).
    public var submitEnabled: Bool {
        rows.count == Self.artifactOrder.count
            && rows.allSatisfy { $0.status == .uploaded }
    }

    // MARK: - Callbacks

    public var onStateChange: ((State) -> Void)?
    public var onRowsChange: (([ArtifactRow]) -> Void)?
    public var onSubmitEnabledChange: ((Bool) -> Void)?

    /// Fires once `KYCSubmitEndpoint` succeeds — `KYCCoordinator` advances to the
    /// status screen (`pushStatus()`).
    public var onSubmitted: (() -> Void)?

    /// D-03 — fires when the user taps "Retake" on a failed artifact cell. The
    /// coordinator re-opens that capture step.
    public var onRetake: ((KYCUploadInitEndpoint.ArtifactType) -> Void)?

    // MARK: - Dependencies (initializer-DI per ARCH-04)

    private let apiClient: APIClient
    private let store: KYCSessionStore
    private let kycUploader: KYCUploader
    private let logger: any Logger

    public init(
        apiClient: APIClient,
        store: KYCSessionStore,
        kycUploader: KYCUploader,
        logger: any Logger
    ) {
        self.apiClient = apiClient
        self.store = store
        self.kycUploader = kycUploader
        self.logger = logger
        self.rows = Self.artifactOrder.map { ArtifactRow(artifact: $0, status: .pending) }
    }

    // MARK: - Refresh

    /// Re-read the persisted `KYCSession` and recompute every row's status.
    /// Called on `viewWillAppear` and after a retry so the grid reflects the
    /// pipelined uploads that ran while the user was still capturing (D-01).
    public func refresh() {
        let session = (try? store.loadSession()) ?? nil
        rows = Self.artifactOrder.map { artifact in
            ArtifactRow(artifact: artifact, status: Self.status(for: artifact, in: session))
        }
    }

    /// Map a persisted `ArtifactUploadState` to a Review-grid status.
    private static func status(
        for artifact: KYCUploadInitEndpoint.ArtifactType,
        in session: KYCSession?
    ) -> ArtifactUploadStatus {
        guard let uploadState = session?.state(for: artifact) else {
            return .pending
        }
        if uploadState.committed {
            return .uploaded
        }
        if uploadState.totalChunks > 0 && uploadState.chunksAcked > 0 {
            let fraction = Double(uploadState.chunksAcked) / Double(uploadState.totalChunks)
            return .uploading(progress: min(max(fraction, 0), 1))
        }
        // Started (init done) but no chunks acked yet — treat as in-progress at 0.
        if uploadState.uploadID != nil {
            return .uploading(progress: 0)
        }
        return .pending
    }

    // MARK: - Live upload-progress hook

    /// Update one artifact's row from a live `KYCUploader.onProgress` callback
    /// (D-01 pipelined upload). `fraction == 1.0` is treated as committed.
    public func updateProgress(
        for artifact: KYCUploadInitEndpoint.ArtifactType,
        fraction: Double
    ) {
        guard let index = rows.firstIndex(where: { $0.artifact == artifact }) else { return }
        let newStatus: ArtifactUploadStatus = fraction >= 1.0
            ? .uploaded
            : .uploading(progress: min(max(fraction, 0), 1))
        guard rows[index].status != newStatus else { return }
        rows[index].status = newStatus
        onRowsChange?(rows)
        onSubmitEnabledChange?(submitEnabled)
    }

    /// Mark an artifact's row failed — invoked when a pipelined upload throws
    /// after the uploader's retries are exhausted.
    public func markFailed(_ artifact: KYCUploadInitEndpoint.ArtifactType) {
        guard let index = rows.firstIndex(where: { $0.artifact == artifact }) else { return }
        guard rows[index].status != .failed else { return }
        rows[index].status = .failed
        onRowsChange?(rows)
        onSubmitEnabledChange?(submitEnabled)
    }

    // MARK: - submit() — D-03 thin finalizer

    /// Fire the final `POST /kyc/submit` ONCE, carrying the 6 committed
    /// `artifactID`s. Gated: a no-op unless all 6 artifacts are committed
    /// (`submitEnabled`). On success bubbles `onSubmitted` so the coordinator
    /// advances to the status screen. Does NOT clear the on-disk session —
    /// that is the D-02 verified-clear path in `KYCStatusViewModel`.
    public func submit() async {
        guard submitEnabled else {
            logger.warn(event: LogEvent("kyc_submit_blocked_not_all_committed"), fields: [:])
            return
        }
        guard case .reviewing = state else { return }
        state = .submitting

        // Collect the 6 server-issued artifact IDs from the committed states.
        let session = (try? store.loadSession()) ?? nil
        let artifactIDs: [String] = Self.artifactOrder.compactMap { artifact in
            session?.state(for: artifact)?.artifactID
        }
        guard artifactIDs.count == Self.artifactOrder.count else {
            // The gate said all 6 were committed but an artifactID is missing —
            // a committed artifact must carry a server ID (threat T-05-06-01).
            logger.error(
                event: LogEvent("kyc_submit_missing_artifact_id"),
                fields: [.count: artifactIDs.count]
            )
            state = .error(message: NSLocalizedString(
                "kyc.review.error.submit_failed",
                value: "We couldn't submit your verification. Try again.",
                comment: "KYC Review screen — submit failed error"
            ))
            return
        }

        do {
            _ = try await apiClient.request(KYCSubmitEndpoint(artifactIDs: artifactIDs))
            logger.info(event: LogEvent("kyc_submit_succeeded"), fields: [:])
            state = .submitted
            onSubmitted?()
        } catch {
            logger.error(
                event: LogEvent("kyc_submit_failed"),
                fields: [.event: String(describing: error)]
            )
            state = .error(message: NSLocalizedString(
                "kyc.review.error.submit_failed",
                value: "We couldn't submit your verification. Try again.",
                comment: "KYC Review screen — submit failed error"
            ))
        }
    }

    /// Reset from an `.error` back to `.reviewing` so the user can retry submit.
    public func dismissError() {
        if case .error = state { state = .reviewing }
    }

    // MARK: - Per-artifact recovery (D-03)

    /// "Retry upload" — re-invoke the uploader for a failed artifact (D-03). On
    /// success the row flips to `.uploaded`; on failure it stays `.failed`.
    public func retryUpload(artifactType: KYCUploadInitEndpoint.ArtifactType) async {
        guard let index = rows.firstIndex(where: { $0.artifact == artifactType }) else { return }
        rows[index].status = .uploading(progress: 0)
        onRowsChange?(rows)
        onSubmitEnabledChange?(submitEnabled)
        do {
            try await kycUploader.upload(artifactType: artifactType)
            logger.info(
                event: LogEvent("kyc_review_retry_upload_succeeded"),
                fields: [.event: artifactType.rawValue]
            )
        } catch {
            logger.warn(
                event: LogEvent("kyc_review_retry_upload_failed"),
                fields: [.event: artifactType.rawValue]
            )
        }
        // Re-read the store either way — a success leaves a committed state, a
        // failure leaves the pre-retry cursor.
        refresh()
        if case .uploading = rowStatus(for: artifactType) {
            // Upload threw without committing — surface the failure badge.
            markFailed(artifactType)
        }
    }

    /// "Retake" — bubble to the coordinator so it re-opens that capture step (D-03).
    public func retake(artifactType: KYCUploadInitEndpoint.ArtifactType) {
        logger.info(
            event: LogEvent("kyc_review_retake_requested"),
            fields: [.event: artifactType.rawValue]
        )
        onRetake?(artifactType)
    }

    /// The current status of one artifact's row.
    public func rowStatus(for artifact: KYCUploadInitEndpoint.ArtifactType) -> ArtifactUploadStatus {
        rows.first(where: { $0.artifact == artifact })?.status ?? .pending
    }
}
