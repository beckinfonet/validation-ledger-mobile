// validationLedger/Features/Onboarding/KYC/KYCStatusViewModel.swift
// Phase 5 Plan 06 — KYC-05 / D-08..D-11: the 4-state KYC status state machine.
//
// The status screen is a SINGLE screen (D-08) reached post-submit and — in plan
// 08 — from the Profile entry point. It renders the four backend verdicts:
// Pending / Under Review / Verified / Rejected.
//
// VM contract (the OTPViewModel template — 05-PATTERNS "*ViewModel"):
//   - `@MainActor public final class`
//   - a nested `enum State: Equatable, Sendable`
//   - `state` `didSet` fires `onStateChange`
//   - `on…` callbacks for coordinator plumbing
//   - initializer-DI (ARCH-04)
//
// === D-09 — fetch-on-appear + pull-to-refresh, NO background polling ===
// `fetchStatus()` is called from `KYCStatusViewController.viewWillAppear` and on
// pull-to-refresh. There is no `Timer`. The shipped `RetryInterceptor` (NET-05)
// already retries GETs — the fetch needs no new retry loop.
//
// === D-10/D-11 — controlled-vocabulary rejection copy ===
// Each rejected artifact's `rejectionReason` is a backend CODE string. It is
// mapped through `RejectionReasonCode.copy(for:)` to a finalized localized
// sentence; an unknown/future code degrades to the generic copy — the raw code
// never reaches the UI (threat T-05-06-02). Verified artifacts stay verified;
// only the rejected ones offer re-capture.
//
// === D-02 — verified-clear path ===
// On a `verified` verdict the VM clears the on-disk KYC session via
// `store.clearSession()` — the in-progress session is no longer needed once KYC
// is fully verified. (`KYCReviewViewModel.submit()` deliberately does NOT clear
// it; the clear happens here, once the backend confirms.)

import Foundation

@MainActor
public final class KYCStatusViewModel {

    // MARK: - Overall status (RESEARCH "KYC status state machine")

    /// The four backend KYC verdicts. `String`-raw so the wire `overall_status`
    /// decodes directly; `under_review` is the only non-identity raw value.
    public enum KYCOverallStatus: String, Decodable, Sendable, CaseIterable {
        case pending
        case underReview = "under_review"
        case verified
        case rejected

        /// Map an arbitrary backend string to a known verdict, or `nil` if the
        /// backend sent something outside the controlled set.
        static func from(_ raw: String) -> KYCOverallStatus? {
            KYCOverallStatus(rawValue: raw)
        }
    }

    /// One rejected artifact surfaced to the status screen (D-10). Carries the
    /// artifact ID, the resolved (localized, controlled-vocabulary) reason
    /// sentence, and — when the ID maps to a known artifact type — the type so
    /// the screen can offer targeted re-capture.
    public struct RejectedArtifact: Equatable, Sendable {
        public let artifactID: String
        public let reasonCopy: String
        public let artifactType: KYCUploadInitEndpoint.ArtifactType?

        public init(
            artifactID: String,
            reasonCopy: String,
            artifactType: KYCUploadInitEndpoint.ArtifactType?
        ) {
            self.artifactID = artifactID
            self.reasonCopy = reasonCopy
            self.artifactType = artifactType
        }
    }

    // MARK: - State

    public enum State: Equatable, Sendable {
        /// `fetchStatus()` in flight.
        case loading
        /// `overall_status == pending`.
        case pending
        /// `overall_status == under_review`.
        case underReview
        /// `overall_status == verified` — the role-shell "Continue" CTA shows.
        case verified
        /// `overall_status == rejected` — per-artifact reason copy + re-capture.
        case rejected(artifacts: [RejectedArtifact])
        /// No KYC submission yet — the role-shell re-entry empty state (D-08).
        case noSubmission
        /// The fetch failed.
        case error(message: String)
    }

    public private(set) var state: State = .loading {
        didSet { onStateChange?(state) }
    }

    // MARK: - Callbacks

    public var onStateChange: ((State) -> Void)?

    /// Fires when the user taps "Continue" on the verified screen — route into
    /// the role shell. `KYCCoordinator` bubbles this to `AppCoordinator`.
    public var onVerified: (() -> Void)?

    /// D-10 — fires when the user taps "Retake" on a rejected artifact row. The
    /// coordinator re-opens just that capture step; verified artifacts are left
    /// untouched.
    public var onRecapture: ((KYCUploadInitEndpoint.ArtifactType) -> Void)?

    // MARK: - Dependencies (initializer-DI per ARCH-04)

    private let apiClient: APIClient
    private let store: KYCSessionStore
    /// Phase 6 D6-08 (WARNING-1): the Keychain hand-off for the cached KYC
    /// status. `fetchStatus()` refreshes `.kycStatus` after a successful
    /// `GET /kyc/status` so the fail-closed cold-boot `SessionRestoreProbe`
    /// routes on current truth instead of a stale cached value.
    private let keychain: KeychainStore
    private let logger: any Logger

    public init(
        apiClient: APIClient,
        store: KYCSessionStore,
        keychain: KeychainStore,
        logger: any Logger
    ) {
        self.apiClient = apiClient
        self.store = store
        self.keychain = keychain
        self.logger = logger
    }

    // MARK: - fetchStatus() — D-09 fetch-on-appear

    /// Fetch `GET /kyc/status` and map the verdict to a `State`. Called from
    /// `viewWillAppear` and pull-to-refresh (D-09) — there is no polling timer.
    public func fetchStatus() async {
        state = .loading
        let response: KYCStatusEndpoint.Response
        do {
            response = try await apiClient.request(KYCStatusEndpoint())
        } catch {
            logger.error(
                event: LogEvent("kyc_status_fetch_failed"),
                fields: [.event: String(describing: error)]
            )
            state = .error(message: NSLocalizedString(
                "kyc.status.error",
                value: "We couldn't load your verification status. Pull down to try again.",
                comment: "KYC status screen — fetch failed error"
            ))
            return
        }
        refreshCachedKYCStatus(response.overallStatus)
        state = mapState(from: response)
    }

    /// Phase 6 D6-08 (WARNING-1): cache the fresh `overall_status` to Keychain
    /// `.kycStatus` after a successful `GET /kyc/status`.
    ///
    /// Mirrors `OTPViewModel`'s `.kycStatus` write EXACTLY — same key, same
    /// `.afterFirstUnlockThisDeviceOnly` accessibility (Pattern C) — so the
    /// fail-closed cold-boot `SessionRestoreProbe` (D-13) routes on current
    /// truth instead of a stale value. This is a CORRECTNESS fix, NOT a
    /// relaxation: the probe still fails CLOSED on any non-"verified"/absent
    /// value; D6-08 only ensures the cached value is fresh. The routing logic
    /// is unchanged.
    ///
    /// A Keychain-write failure must NOT break the status fetch — degrade
    /// gracefully (log + continue). The status string is a controlled-vocabulary
    /// value (no PII), so the failure log carries only the event name.
    private func refreshCachedKYCStatus(_ overallStatus: String) {
        do {
            try keychain.set(
                Data(overallStatus.utf8),
                for: .kycStatus,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        } catch {
            logger.warn(
                event: LogEvent("kyc_status_keychain_refresh_failed"),
                fields: [:]
            )
        }
    }

    /// Pure mapping from a `KYCStatusEndpoint.Response` to a `State`. Separated
    /// so the simulator suite can drive it directly from the 4 fixtures.
    func mapState(from response: KYCStatusEndpoint.Response) -> State {
        guard let verdict = KYCOverallStatus.from(response.overallStatus) else {
            // An unrecognized overall status is not trusted as a verdict —
            // surface it as the no-submission empty state rather than guess.
            logger.warn(
                event: LogEvent("kyc_status_unknown_overall_status"),
                fields: [.event: response.overallStatus]
            )
            return .noSubmission
        }
        switch verdict {
        case .pending:
            return .pending
        case .underReview:
            return .underReview
        case .verified:
            // D-02 — the in-progress KYC session is no longer needed once KYC
            // is fully verified. Clear it now (the verified-clear path).
            do {
                try store.clearSession()
                logger.info(event: LogEvent("kyc_session_cleared_on_verified"), fields: [:])
            } catch {
                logger.warn(
                    event: LogEvent("kyc_session_clear_failed"),
                    fields: [.event: String(describing: error)]
                )
            }
            return .verified
        case .rejected:
            let rejected = response.artifacts
                .filter { $0.status == "rejected" }
                .map { artifact -> RejectedArtifact in
                    // D-11 — map the backend code through the controlled
                    // vocabulary; an unknown code degrades to generic copy.
                    let copy = RejectionReasonCode.copy(for: artifact.rejectionReason ?? "")
                    return RejectedArtifact(
                        artifactID: artifact.artifactID,
                        reasonCopy: copy,
                        artifactType: Self.artifactType(forID: artifact.artifactID)
                    )
                }
            return .rejected(artifacts: rejected)
        }
    }

    /// "Continue" tapped on the verified screen — route into the role shell.
    public func continueToRoleShell() {
        guard case .verified = state else { return }
        onVerified?()
    }

    /// "Retake" tapped on a rejected artifact row — re-open just that capture
    /// step (D-10). Verified artifacts are left untouched.
    public func recapture(artifactType: KYCUploadInitEndpoint.ArtifactType) {
        logger.info(
            event: LogEvent("kyc_status_recapture_requested"),
            fields: [.event: artifactType.rawValue]
        )
        onRecapture?(artifactType)
    }

    // MARK: - Artifact-ID → type heuristic

    /// Best-effort map from a server `artifactID` to a `ArtifactType`, so a
    /// rejected row can offer targeted re-capture. The backend ID embeds the
    /// artifact kind (e.g. `art-dl-front-002`); an unrecognized shape returns
    /// `nil` and the row simply has no Retake target.
    nonisolated static func artifactType(forID artifactID: String) -> KYCUploadInitEndpoint.ArtifactType? {
        let lowered = artifactID.lowercased()
        // Order matters — "dl-front"/"dl-back" must be checked before "dl".
        if lowered.contains("dl-front") || lowered.contains("dl_front") { return .dlFront }
        if lowered.contains("dl-back") || lowered.contains("dl_back") { return .dlBack }
        if lowered.contains("face") { return .face }
        if lowered.contains("trailer") { return .trailer }
        if lowered.contains("plate") { return .plate }
        if lowered.contains("truck") || lowered.contains("vehicle") { return .truck }
        return nil
    }
}
