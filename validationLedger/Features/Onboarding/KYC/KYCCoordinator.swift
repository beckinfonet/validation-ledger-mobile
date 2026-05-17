// validationLedger/Features/Onboarding/KYC/KYCCoordinator.swift
// Phase 5 Plan 05 — KYC-01: the KYC capture-flow coordinator.
//
// Structural template: Features/Onboarding/Auth/AuthCoordinator.swift (the EXACT
// shape — `@MainActor final class`, a `let rootViewController` that is a
// `UINavigationController`, callback `var`s, `private let nav` + `private let
// container`, an `init(container:)` that builds the root VC + wires the first
// callback, and `private func push…` methods that wire the next callback before
// `nav.pushViewController`).
//
// === RETENTION RULE (RESEARCH Pitfall 6 — MUST) ===
// `AppCoordinator` MUST hold this coordinator in a strong instance property
// (mirroring `private var authCoordinator: AuthCoordinator?`). A `KYCCoordinator`
// created as a local `let` deallocates immediately after `makeRoot` returns —
// the nav stays alive (UIKit retains it via `window.rootViewController`) but the
// `onKYCSubmitted` / `onSignOut` plumbing and every `push…` closure are orphaned.
// This was a real Phase-3 bug fixed for `AuthCoordinator`; do not reintroduce it.
//
// === FLOW (KYC-01) ===
// KYCStartViewController → face → DL front scan → DL front extraction confirm →
// DL back → truck → trailer → plate → review. Each capture step advances ONLY
// after the per-shot Use/Retake confirm (D-07). The review/status screens land
// in plan 06 — `pushReview()` is a stub here that plan 06 fills in.
//
// === D-01 PIPELINED UPLOAD ===
// On each artifact's capture-confirm the coordinator kicks
// `Task { await container.kycUploader.upload(artifactType:) }` — the upload runs
// while the user keeps shooting the remaining artifacts.
//
// === D-14 SIGN-OUT ===
// The nav chrome carries a sign-out bar-button on EVERY capture screen. Tapping
// it shows the UI-SPEC destructive "Sign out of Validation Ledger?" confirmation;
// on confirm it calls `onSignOut?()` (plan 07 wires that to
// `LogoutService.logout(reason: .userInitiated)`). The partial KYC session
// persists on disk (D-02) and resumes next login.

import UIKit

/// The ordered KYC capture steps (KYC-01). The `KYCFlowSequencer` advances
/// through these in order; `review` is the terminal step plan 06 fills in.
public enum KYCFlowStep: Int, CaseIterable, Equatable, Sendable {
    case start
    case face
    case dlFront
    case dlFrontExtraction
    case dlBack
    case truck
    case trailer
    case plate
    case review

    /// The next step after `self`, or `nil` when `self` is the terminal step.
    var next: KYCFlowStep? {
        KYCFlowStep(rawValue: rawValue + 1)
    }

    /// The KYC artifact captured at this step, or `nil` for the non-capture
    /// steps (`start`, `dlFrontExtraction`, `review`). `dlFrontExtraction` is a
    /// confirmation screen, not a capture — the DL-front artifact is captured at
    /// `dlFront`.
    var artifact: KYCUploadInitEndpoint.ArtifactType? {
        switch self {
        case .face:    return .face
        case .dlFront: return .dlFront
        case .dlBack:  return .dlBack
        case .truck:   return .truck
        case .trailer: return .trailer
        case .plate:   return .plate
        case .start, .dlFrontExtraction, .review:
            return nil
        }
    }
}

/// Pure, simulator-testable sequencer for the KYC capture flow (KYC-01).
///
/// Separated from `KYCCoordinator` so the flow-state ordering — and the rule
/// that an artifact's pipelined upload (D-01) is kicked exactly once per
/// capture-confirm — is exercised without UIKit or a camera. `KYCCoordinator`
/// owns one of these and drives the actual `nav.pushViewController`.
public struct KYCFlowSequencer {

    /// The step currently presented.
    public private(set) var current: KYCFlowStep = .start

    /// Artifacts whose pipelined upload (D-01) has been kicked, in kick order.
    public private(set) var uploadsKicked: [KYCUploadInitEndpoint.ArtifactType] = []

    public init() {}

    /// `true` once the flow has reached the terminal `review` step.
    public var reachedReview: Bool { current == .review }

    /// Advance to the next step. When the step just completed captured an
    /// artifact, its pipelined upload is recorded as kicked (D-01).
    ///
    /// - Returns: the step now current after advancing, or `nil` if already at
    ///   the terminal `review` step.
    @discardableResult
    public mutating func advance() -> KYCFlowStep? {
        guard let next = current.next else { return nil }
        if let artifact = current.artifact {
            uploadsKicked.append(artifact)
        }
        current = next
        return current
    }
}

/// Coordinates the 6-artifact KYC capture flow (KYC-01). Owns the
/// `UINavigationController`, the `GeoContext` fresh-fix cache, and the D-14
/// sign-out affordance. Mirrors `AuthCoordinator`.
@MainActor
final class KYCCoordinator {

    /// The `UINavigationController` installed as `window.rootViewController`
    /// for `AppPhase.kyc`.
    let rootViewController: UIViewController

    /// Bubbles to `AppCoordinator` once the final `POST /kyc/submit` completes
    /// (plan 06 calls this from the review screen). `AppCoordinator` root-swaps
    /// to the role shell.
    var onKYCSubmitted: (() -> Void)?

    /// D-14 — bubbles to `AppCoordinator` when the user confirms sign-out.
    /// Plan 07 wires this to `LogoutService.logout(reason: .userInitiated)`.
    var onSignOut: (() -> Void)?

    private let nav: UINavigationController
    private let container: AppContainer

    /// The fresh-`CLLocation` cache for capture-time GPS injection (KYC-04 /
    /// Pitfall 5). `refresh()` is kicked at flow start so a fresh fix is cached
    /// before the first capture.
    private let geoContext: GeoContext

    /// The pure flow sequencer — the KYC-01 step ordering + D-01 upload-kick
    /// bookkeeping. Tests exercise `KYCFlowSequencer` directly.
    private var sequencer = KYCFlowSequencer()

    init(container: AppContainer) {
        self.container = container
        self.geoContext = container.geoContext

        let startVC = KYCStartViewController()
        let nav = UINavigationController(rootViewController: startVC)
        self.nav = nav
        self.rootViewController = nav

        // Kick a fresh location fix at flow start so the first capture has a
        // <30s / <100m fix cached (RESEARCH Pitfall 5).
        Task { try? await geoContext.refresh() }

        // D-14 — the sign-out affordance on the start screen's nav chrome.
        installSignOutItem(on: startVC)

        startVC.onGetStarted = { [weak self] in
            self?.pushFaceCapture()
        }
    }

    // MARK: - D-14 sign-out chrome

    /// Install the D-14 sign-out bar-button on `vc`'s nav chrome. Called for
    /// every capture screen so the user is never trapped inside the KYC gate.
    private func installSignOutItem(on vc: UIViewController) {
        let item = UIBarButtonItem(
            title: NSLocalizedString(
                "kyc.signout.button",
                value: "Sign out",
                comment: "KYC nav-chrome sign-out affordance (D-14)"
            ),
            style: .plain,
            target: self,
            action: #selector(signOutTapped)
        )
        item.accessibilityIdentifier = "kyc-signout"
        vc.navigationItem.rightBarButtonItem = item
    }

    @objc private func signOutTapped() {
        let alert = UIAlertController(
            title: NSLocalizedString(
                "kyc.signout.confirm.title",
                value: "Sign out of Validation Ledger?",
                comment: "KYC sign-out confirmation title (D-14)"
            ),
            message: NSLocalizedString(
                "kyc.signout.confirm.body",
                value: "Your photos are saved on this device and will resume next time you sign in.",
                comment: "KYC sign-out confirmation body (D-14)"
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString(
                "kyc.signout.confirm.action",
                value: "Sign out",
                comment: "KYC sign-out confirmation destructive action (D-14)"
            ),
            style: .destructive,
            handler: { [weak self] _ in self?.onSignOut?() }
        ))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString(
                "kyc.signout.confirm.cancel",
                value: "Stay",
                comment: "KYC sign-out confirmation cancel action (D-14)"
            ),
            style: .cancel
        ))
        nav.present(alert, animated: true)
    }

    // MARK: - D-01 pipelined upload

    /// Kick the pipelined background upload for `artifact` (D-01). Called on
    /// each capture-confirm — the chunk loop runs while the user keeps shooting.
    private func kickUpload(for artifact: KYCUploadInitEndpoint.ArtifactType) {
        let uploader = container.kycUploader
        Task {
            do {
                try await uploader.upload(artifactType: artifact)
            } catch {
                // A failed upload is recoverable from the plan-06 review screen
                // ("Retry upload"); it must not block the capture flow.
                container.logger.warn(
                    event: LogEvent("kyc_pipelined_upload_failed"),
                    fields: [.event: artifact.rawValue]
                )
            }
        }
    }

    /// Record an artifact capture-confirm: advance the flow sequencer and kick
    /// the pipelined upload (D-01). Returns the step now current.
    @discardableResult
    private func confirmCapture() -> KYCFlowStep? {
        let completed = sequencer.current
        let now = sequencer.advance()
        if let artifact = completed.artifact {
            kickUpload(for: artifact)
        }
        return now
    }

    // MARK: - Navigation (KYC-01 push chain — D-07 advances per Use/Retake confirm)

    /// Step 1 — face capture (KYC-02 / D-04).
    private func pushFaceCapture() {
        let viewModel = FaceCaptureViewModel(
            cameraSession: AVFoundationCameraSession(),
            faceQualityGate: VisionFaceQualityGate(),
            geoContext: geoContext,
            gpsInjector: GPSMetadataInjector(),
            sessionStore: container.kycSessionStore,
            logger: container.logger
        )
        let vc = FaceCaptureViewController(viewModel: viewModel)
        installSignOutItem(on: vc)
        viewModel.onCaptureConfirmed = { [weak self] in
            self?.confirmCapture()
            self?.pushDLFrontScan()
        }
        nav.pushViewController(vc, animated: true)
    }

    /// Step 2 — DL front DataScanner OCR (KYC-03).
    private func pushDLFrontScan() {
        let vc = DLFrontScanViewController()
        installSignOutItem(on: vc)
        vc.onScanComplete = { [weak self] extraction in
            self?.pushDLFrontExtraction(extraction)
        }
        nav.pushViewController(vc, animated: true)
    }

    /// Step 3 — read-only DL extraction confirmation (KYC-03 / D-05).
    private func pushDLFrontExtraction(_ extraction: DLExtraction) {
        let vc = DLFrontExtractionViewController(extraction: extraction)
        installSignOutItem(on: vc)
        vc.onConfirmed = { [weak self] in
            self?.confirmCapture()
            self?.pushDLBack()
        }
        vc.onRescanRequested = { [weak self] in
            self?.nav.popViewController(animated: true)
        }
        nav.pushViewController(vc, animated: true)
    }

    /// Step 4 — DL back plain framed photo (KYC-04 / D-06 — no barcode scan).
    private func pushDLBack() {
        let viewModel = VehicleCaptureViewModel(
            artifactType: .dlBack,
            cameraSession: AVFoundationCameraSession(),
            geoContext: geoContext,
            gpsInjector: GPSMetadataInjector(),
            sessionStore: container.kycSessionStore,
            logger: container.logger
        )
        let vc = DLBackCaptureViewController(viewModel: viewModel)
        installSignOutItem(on: vc)
        viewModel.onCaptureConfirmed = { [weak self] in
            self?.confirmCapture()
            self?.pushTruck()
        }
        nav.pushViewController(vc, animated: true)
    }

    /// Step 5 — truck photo (KYC-04).
    private func pushTruck() {
        let vc = makeVehicleCapture(artifact: .truck) { [weak self] in
            self?.confirmCapture()
            self?.pushTrailer()
        }
        nav.pushViewController(vc, animated: true)
    }

    /// Step 6 — trailer photo (KYC-04).
    private func pushTrailer() {
        let vc = makeVehicleCapture(artifact: .trailer) { [weak self] in
            self?.confirmCapture()
            self?.pushPlate()
        }
        nav.pushViewController(vc, animated: true)
    }

    /// Step 7 — license-plate photo (KYC-04).
    private func pushPlate() {
        let vc = makeVehicleCapture(artifact: .plate) { [weak self] in
            self?.confirmCapture()
            self?.pushReview()
        }
        nav.pushViewController(vc, animated: true)
    }

    /// Step 8 — the Review screen (KYC-01 / D-03). Builds the
    /// `KYCReviewViewModel` + `KYCReviewViewController`: the 6-thumbnail grid
    /// with the all-6-committed gated Submit. `onSubmitted` advances to the
    /// status screen; `onRetake` re-opens the matching capture step.
    private func pushReview() {
        container.logger.info(
            event: LogEvent("kyc_flow_reached_review"),
            fields: [:]
        )
        let viewModel = KYCReviewViewModel(
            apiClient: container.apiClient,
            store: container.kycSessionStore,
            kycUploader: container.kycUploader,
            logger: container.logger
        )
        let vc = KYCReviewViewController(viewModel: viewModel)
        installSignOutItem(on: vc)
        viewModel.onSubmitted = { [weak self] in
            self?.pushStatus()
        }
        viewModel.onRetake = { [weak self] artifact in
            self?.reopenCapture(for: artifact)
        }
        nav.pushViewController(vc, animated: true)
    }

    /// Step 9 — the KYC status screen (KYC-05 / D-08). Builds the
    /// `KYCStatusViewModel` + `KYCStatusViewController`: the 4-state verdict
    /// screen with fetch-on-appear + pull-to-refresh (D-09) and per-artifact
    /// re-capture of rejected artifacts (D-10). `onVerified` fires when the user
    /// taps the verified "Continue" CTA — it bubbles to `AppCoordinator`
    /// (`onKYCSubmitted`), which root-swaps to the role shell (plan 07).
    private func pushStatus() {
        let viewModel = KYCStatusViewModel(
            apiClient: container.apiClient,
            store: container.kycSessionStore,
            logger: container.logger
        )
        let vc = KYCStatusViewController(viewModel: viewModel)
        installSignOutItem(on: vc)
        viewModel.onVerified = { [weak self] in
            self?.onKYCSubmitted?()
        }
        viewModel.onRecapture = { [weak self] artifact in
            self?.reopenCapture(for: artifact)
        }
        nav.pushViewController(vc, animated: true)
    }

    /// Re-open the capture step for a single artifact (D-03 Review-screen Retake
    /// and D-10 status-screen rejected-artifact Retake). Verified/other
    /// artifacts are left untouched — only the named capture step is re-pushed.
    private func reopenCapture(for artifact: KYCUploadInitEndpoint.ArtifactType) {
        container.logger.info(
            event: LogEvent("kyc_recapture_pushed"),
            fields: [.event: artifact.rawValue]
        )
        switch artifact {
        case .face:
            pushFaceCapture()
        case .dlFront:
            pushDLFrontScan()
        case .dlBack:
            pushDLBack()
        case .truck:
            nav.pushViewController(
                makeVehicleCapture(artifact: .truck) { [weak self] in
                    self?.kickUpload(for: .truck)
                    self?.nav.popViewController(animated: true)
                }, animated: true)
        case .trailer:
            nav.pushViewController(
                makeVehicleCapture(artifact: .trailer) { [weak self] in
                    self?.kickUpload(for: .trailer)
                    self?.nav.popViewController(animated: true)
                }, animated: true)
        case .plate:
            nav.pushViewController(
                makeVehicleCapture(artifact: .plate) { [weak self] in
                    self?.kickUpload(for: .plate)
                    self?.nav.popViewController(animated: true)
                }, animated: true)
        }
    }

    // MARK: - Helpers

    /// Build a `VehicleCaptureViewController` parameterized by artifact type
    /// (DL-back / truck / trailer / plate all share the plain-photo screen).
    private func makeVehicleCapture(
        artifact: KYCUploadInitEndpoint.ArtifactType,
        onConfirm: @escaping () -> Void
    ) -> VehicleCaptureViewController {
        let viewModel = VehicleCaptureViewModel(
            artifactType: artifact,
            cameraSession: AVFoundationCameraSession(),
            geoContext: geoContext,
            gpsInjector: GPSMetadataInjector(),
            sessionStore: container.kycSessionStore,
            logger: container.logger
        )
        let vc = VehicleCaptureViewController(viewModel: viewModel)
        installSignOutItem(on: vc)
        viewModel.onCaptureConfirmed = onConfirm
        return vc
    }
}
