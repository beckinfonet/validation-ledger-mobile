// validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewController.swift
// Phase 5 Plan 05 — KYC-02: the Vision-gated face-capture screen.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md hard constraint: camera surfaces
// are UIKit, never SwiftUI). Scaffold copied from `OTPViewController`, using
// `DS.Spacing` / `DS.Typography` / `DS.Colors` tokens (NOT the analog's raw
// `8/12/16/24/32` literals — 05-UI-SPEC contract). All copy via
// `NSLocalizedString(_, value:)`; every label sets
// `adjustsFontForContentSizeCategory = true`.
//
// === MANUAL SHUTTER (debug session `kyc-upload-capture-bugs`, Issue 1b) ===
// SUPERSEDES the D-04 hands-free auto-fire. The selfie screen now carries a
// manual shutter button — the EXACT affordance the `VehicleCaptureViewController`
// plain-photo screens use (44pt touch-target floor, `kyc-face-shutter`
// accessibility id, the `.fill`-stack layout pattern). The capture fires ONLY on
// a shutter tap. The Vision quality gate is RETAINED but repurposed: it gates
// the shutter — `shutterButton.isEnabled` tracks the VM's `.readyToCapture`
// state, so the shutter unlocks only while the face-quality gate holds a steady
// `.pass` (the user still cannot shoot a bad selfie). All 6 KYC capture screens
// now use a manual shutter — see the Resolution in
// `.planning/debug/resolved/kyc-upload-capture-bugs.md`.
//
// === PREVIEW HOSTING (debug session `front-camera-preview-black`, round 4) ===
// The camera preview is hosted by a `CameraPreviewView` — a `UIView` subclass
// whose BACKING layer IS the `AVCaptureVideoPreviewLayer` (`layerClass` override).
// UIKit keeps a view's backing layer exactly `bounds`-sized at all times, so
// there is NO manual `previewLayer.frame` sync and NO 0×0 race window — the
// fragile "add the layer as a sublayer and re-sync `.frame` in
// `viewDidLayoutSubviews`" pattern (rounds 1–3) is gone. The preview view is the
// slack-absorbing arranged subview of the `.fill` stack (round-3 hugging-priority
// fix retained). The oval guide is a sibling overlay layer.
//
// === iPad (RESEARCH Pitfall 7) ===
// The capture chrome is laid out with Auto Layout against the safe area; the
// preview connection's `videoRotationAngle` is updated on `viewWillTransition`
// — no hard-coded portrait frames, no deprecated `videoOrientation`.

import AVFoundation
import OSLog
import UIKit

/// The Vision-gated face-capture screen (KYC-02). The Vision quality gate
/// enables/disables a manual shutter button (Issue 1b — supersedes the D-04
/// hands-free auto-fire).
final class FaceCaptureViewController: UIViewController {

    private let viewModel: FaceCaptureViewModel

    // MARK: - UI components

    /// Hosts the live camera preview. Its backing layer IS the
    /// `AVCaptureVideoPreviewLayer` (`CameraPreviewView.layerClass`), so the
    /// preview is always exactly this view's `bounds` with zero manual frame
    /// sync — the round-4 structural fix for the black-preview bug.
    ///
    /// Layout (round 3, retained): a vertical `.fill` `UIStackView` pinned to the
    /// safe area on BOTH ends. The preview hugs vertically at the lowest priority
    /// while the labels and shutter button hug firmly, so the `.fill` stack
    /// stretches the preview into all leftover vertical space — it cannot
    /// collapse to 0.
    private let previewView: CameraPreviewView = {
        let view = CameraPreviewView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "kyc-face-preview"
        // The labels keep the UIView default vertical hugging (250); the
        // preview hugs at the lowest possible priority so the `.fill` stack
        // always expands IT to fill the remaining height.
        view.setContentHuggingPriority(.init(1), for: .vertical)
        view.setContentCompressionResistancePriority(.init(1), for: .vertical)
        return view
    }()

    /// The oval framing guide drawn over the preview. White (reduced alpha)
    /// while gates fail; `.systemGreen` when the gate passes (UI-SPEC). Hosted on
    /// the `previewView`'s layer as a sibling sublayer of the backing preview
    /// layer — it is sized to `previewView.bounds` in `viewDidLayoutSubviews`.
    private let ovalGuideLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.white.withAlphaComponent(0.6).cgColor
        layer.lineWidth = 3
        return layer
    }()

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.title1
        label.textColor = DS.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-face-instruction"
        return label
    }()

    /// The live inline capture cue ("Center your face" / "Hold still" …) —
    /// `.footnote`, never an alert.
    private let cueLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.footnote
        label.textColor = DS.Colors.labelSecondary
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-face-cue"
        return label
    }()

    /// The manual shutter button (Issue 1b — supersedes the D-04 auto-fire).
    /// The EXACT affordance `VehicleCaptureViewController` uses: a
    /// `borderedProminent` button with a 44pt touch-target floor and a stable
    /// accessibility id. Enabled only while the VM is `.readyToCapture` — the
    /// Vision quality gate gates the shutter so a bad selfie cannot be shot.
    private let shutterButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = NSLocalizedString(
            "kyc.capture.shutter",
            value: "Take photo",
            comment: "Plain-photo capture shutter button"
        )
        let button = UIButton(configuration: cfg)
        button.accessibilityIdentifier = "kyc-face-shutter"
        return button
    }()

    /// The camera preview layer — the backing layer of `previewView`.
    private var previewLayer: AVCaptureVideoPreviewLayer { previewView.previewLayer }

    /// Guards the one-shot `final_state` diagnostic so it logs once per appear.
    private var didLogFinalState = false

    // MARK: - Init

    init(viewModel: FaceCaptureViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = NSLocalizedString(
            "kyc.start.title",
            value: "Verify identity",
            comment: "KYC nav title"
        )

        instructionLabel.text = NSLocalizedString(
            "kyc.face.instruction",
            value: "Position your face inside the oval.",
            comment: "Face-capture instruction header"
        )

        // The labels hug their intrinsic vertical content firmly so the `.fill`
        // stack never steals their height — they stay label-sized and the
        // preview view absorbs the slack (see `previewView` above).
        instructionLabel.setContentHuggingPriority(.required, for: .vertical)
        cueLabel.setContentHuggingPriority(.required, for: .vertical)

        let stack = UIStackView(arrangedSubviews: [
            instructionLabel, previewView, cueLabel, shutterButton,
        ])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.md
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: DS.Spacing.xl
            ),
            stack.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: DS.Spacing.lg
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -DS.Spacing.lg
            ),
            stack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -DS.Spacing.xl
            ),
            // 44pt touch-target floor (UI-SPEC) — mirrors VehicleCaptureVC.
            shutterButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            // ROUND-3 layout fix (retained). The `.fill` stack expands the
            // preview view into all leftover vertical space because the preview
            // hugs at the lowest priority while the labels hug at `.required`
            // and the shutter button keeps its `>= 44` floor. Defense-in-depth:
            // a min-height floor at priority 250 — too low to fight the
            // encapsulated-layout height (so it can never reintroduce a
            // breakable conflict) yet it guards against a future layout change
            // shrinking the preview to nothing.
            {
                let minHeight = previewView.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: 240
                )
                minHeight.priority = .init(250)
                return minHeight
            }(),
        ])

        // ROUND-4 structural fix. The preview layer is `previewView`'s BACKING
        // layer — UIKit keeps it exactly `bounds`-sized, so there is no
        // `previewLayer.frame` to sync and no 0×0 race. Wire the session into
        // it; the oval guide is a sibling sublayer sized in `viewDidLayoutSubviews`.
        previewView.session = viewModel.captureSession
        previewView.videoGravity = .resizeAspectFill
        previewView.layer.addSublayer(ovalGuideLayer)
        kycCameraLog.info("kyc_camera event=face_vc.viewDidLoad preview_host=CameraPreviewView(layerClass) videoGravity=\(String(describing: self.previewLayer.videoGravity), privacy: .public) sessionWired=\(self.previewLayer.session != nil, privacy: .public)")

        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)

        viewModel.onStateChange = { [weak self] state in
            self?.handle(state: state)
        }
        handle(state: .adjusting(nil))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didLogFinalState = false
        kycCameraLog.info("kyc_camera event=face_vc.viewWillAppear previewView.bounds=\(NSCoder.string(for: self.previewView.bounds), privacy: .public)")
        viewModel.start()
        scheduleFinalStateSnapshot()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // No `previewLayer.frame` sync — the preview layer IS the backing layer
        // of `previewView` and is always exactly `previewView.bounds` (round 4).
        // Only the oval-guide overlay (a sibling sublayer) needs explicit sizing.
        ovalGuideLayer.frame = previewView.bounds
        updateOvalPath()
        updatePreviewRotation()
        let connection = previewLayer.connection
        kycCameraLog.info("kyc_camera event=face_vc.viewDidLayoutSubviews previewView.bounds=\(NSCoder.string(for: self.previewView.bounds), privacy: .public) previewLayer.bounds=\(NSCoder.string(for: self.previewLayer.bounds), privacy: .public) inHierarchy=\(self.previewLayer.superlayer != nil, privacy: .public) connectionExists=\(connection != nil, privacy: .public) connectionActive=\(connection?.isActive ?? false, privacy: .public) connectionEnabled=\(connection?.isEnabled ?? false, privacy: .public)")
    }

    /// iPad rotation (RESEARCH Pitfall 7) — update the preview connection's
    /// `videoRotationAngle` so the camera preview rotates correctly. The capture
    /// chrome is Auto Layout against the safe area, so it re-flows automatically.
    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updatePreviewRotation()
        })
    }

    // MARK: - Round-4 definitive diagnostic

    /// Schedule the one-shot `kyc_camera event=final_state` snapshot ~2s after
    /// the camera-session startup is kicked. By then every layout pass has
    /// settled and `startAuthorizedSession` has run to completion — this single
    /// line is the post-settle TRUTH that disambiguates the two remaining
    /// hypotheses for the black-preview bug (debug session
    /// `front-camera-preview-black`, round 4):
    ///   - layout-still-broken: `view.bounds` / `previewView.bounds` height ≈ 0
    ///   - camera-still-broken: real non-zero sizes but no frames reach the layer
    /// It removes the round-3 ambiguity of "did the tester's console capture
    /// catch every layout pass".
    private func scheduleFinalStateSnapshot() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.didLogFinalState else { return }
            self.didLogFinalState = true
            let connection = self.previewLayer.connection
            kycCameraLog.info("""
            kyc_camera event=final_state \
            view.bounds=\(NSCoder.string(for: self.view.bounds), privacy: .public) \
            view.window=\(self.view.window != nil, privacy: .public) \
            navController=\(self.navigationController != nil, privacy: .public) \
            previewView.bounds=\(NSCoder.string(for: self.previewView.bounds), privacy: .public) \
            previewLayer.bounds=\(NSCoder.string(for: self.previewLayer.bounds), privacy: .public) \
            previewLayer.superlayer=\(self.previewLayer.superlayer != nil, privacy: .public) \
            sessionWired=\(self.previewLayer.session != nil, privacy: .public) \
            sessionRunning=\(self.previewLayer.session?.isRunning ?? false, privacy: .public) \
            connectionExists=\(connection != nil, privacy: .public) \
            connectionActive=\(connection?.isActive ?? false, privacy: .public) \
            connectionEnabled=\(connection?.isEnabled ?? false, privacy: .public)
            """)
        }
    }

    // MARK: - State → UI

    /// Drive the cue, the oval-guide stroke, and the shutter-enabled state from
    /// the VM state. Issue 1b: the shutter is enabled ONLY in `.readyToCapture`
    /// (the Vision gate holds a steady `.pass`) — every other state locks it.
    private func handle(state: FaceCaptureViewModel.State) {
        switch state {
        case let .adjusting(reason):
            cueLabel.text = cueText(for: reason)
            setGuidePassing(false)
            shutterButton.isEnabled = false
        case .readyToCapture:
            cueLabel.text = NSLocalizedString(
                "kyc.face.cue.ready",
                value: "Looks good — take the photo",
                comment: "Face-capture shutter-ready cue (Issue 1b)"
            )
            setGuidePassing(true)
            shutterButton.isEnabled = true
        case .capturing:
            cueLabel.text = NSLocalizedString(
                "kyc.face.cue.hold",
                value: "Hold still",
                comment: "Face-capture steady-hold cue"
            )
            setGuidePassing(true)
            shutterButton.isEnabled = false
        case .locationUnavailable:
            cueLabel.text = NSLocalizedString(
                "kyc.error.gps_stale",
                value: "We couldn't confirm your location. Move to an open area and try the photo again.",
                comment: "KYC GPS-stale capture error"
            )
            setGuidePassing(false)
            shutterButton.isEnabled = false
        case .captured:
            shutterButton.isEnabled = false
            presentPreview()
        case let .failed(message):
            cueLabel.text = message
            setGuidePassing(false)
            shutterButton.isEnabled = false
        }
    }

    /// The live inline cue for an adjust reason (UI-SPEC face-quality copy).
    private func cueText(for reason: FaceAdjustReason?) -> String {
        switch reason {
        case .notCentered, .none:
            return NSLocalizedString(
                "kyc.face.cue.center",
                value: "Center your face",
                comment: "Face-capture centering cue"
            )
        case .tooSmall:
            return NSLocalizedString(
                "kyc.face.cue.steady",
                value: "Hold the phone steady",
                comment: "Face-capture distance cue"
            )
        case .tooDark:
            return NSLocalizedString(
                "kyc.face.cue.light",
                value: "Move into better light",
                comment: "Face-capture lighting cue"
            )
        }
    }

    private func setGuidePassing(_ passing: Bool) {
        ovalGuideLayer.strokeColor = passing
            ? UIColor.systemGreen.cgColor
            : UIColor.white.withAlphaComponent(0.6).cgColor
    }

    private func updateOvalPath() {
        let bounds = previewView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let inset = DS.Spacing.lg
        let ovalRect = bounds.insetBy(dx: inset, dy: inset)
        ovalGuideLayer.path = UIBezierPath(ovalIn: ovalRect).cgPath
    }

    private func updatePreviewRotation() {
        guard let connection = previewLayer.connection else { return }
        // iOS 17 API — `videoRotationAngle` replaces the deprecated
        // `videoOrientation` (RESEARCH Pitfall 7). 90° = portrait.
        let angle: CGFloat
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft:    angle = 180
        case .landscapeRight:   angle = 0
        case .portraitUpsideDown: angle = 270
        default:                angle = 90
        }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    // MARK: - Actions

    /// Fire the shutter (Issue 1b) — mirrors `VehicleCaptureViewController`.
    /// The VM's `capture()` is itself guarded on `.readyToCapture`, so a tap
    /// while the gate is failing is a safe no-op.
    @objc private func shutterTapped() {
        viewModel.capture()
    }

    private func presentPreview() {
        let preview = CapturePreviewViewController(
            artifactLabel: NSLocalizedString(
                "kyc.face.instruction",
                value: "Position your face inside the oval.",
                comment: "Face-capture instruction header"
            ),
            // Render-only still from the capture VM — display path only, never
            // the upload byte source (Pitfall 6).
            previewImage: viewModel.capturedPreviewImage
        )
        preview.onUse = { [weak self] in
            self?.dismiss(animated: true) {
                self?.viewModel.confirmCapture()
            }
        }
        preview.onRetake = { [weak self] in
            self?.dismiss(animated: true) {
                self?.viewModel.resetForRetake()
            }
        }
        preview.modalPresentationStyle = .fullScreen
        present(preview, animated: true)
    }
}
