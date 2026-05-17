// validationLedger/Features/Onboarding/KYC/Capture/FaceCaptureViewController.swift
// Phase 5 Plan 05 — KYC-02 / D-04: the Vision-gated face-capture screen.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md hard constraint: camera surfaces
// are UIKit, never SwiftUI). Scaffold copied from `OTPViewController`, using
// `DS.Spacing` / `DS.Typography` / `DS.Colors` tokens (NOT the analog's raw
// `8/12/16/24/32` literals — 05-UI-SPEC contract). All copy via
// `NSLocalizedString(_, value:)`; every label sets
// `adjustsFontForContentSizeCategory = true`.
//
// === D-04 AUTO-FIRE ===
// The VC hosts the `CameraSession` preview layer behind an oval framing guide.
// The `FaceCaptureViewModel` consumes the Vision `FaceQualityGate` stream; when
// it reports the steady-hold pass the photo auto-fires — there is no shutter
// button. The guide stroke is `.white` (reduced alpha) while gates fail and
// `.systemGreen` when all pass; the live inline cue is driven by the gate's
// adjust reason (no alert).
//
// === iPad (RESEARCH Pitfall 7) ===
// The capture chrome is laid out with Auto Layout against the safe area; the
// preview connection's `videoRotationAngle` is updated on `viewWillTransition`
// — no hard-coded portrait frames, no deprecated `videoOrientation`.

import AVFoundation
import OSLog
import UIKit

/// The Vision-gated face-capture screen (KYC-02). Auto-fires on the D-04
/// steady-hold gate pass.
final class FaceCaptureViewController: UIViewController {

    private let viewModel: FaceCaptureViewModel

    // MARK: - UI components

    /// Hosts the live camera preview. Distinct from the upload path — render only.
    private let previewContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "kyc-face-preview"
        return view
    }()

    /// The oval framing guide drawn over the preview. White (reduced alpha)
    /// while gates fail; `.systemGreen` when the gate passes (UI-SPEC).
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

    /// The camera preview layer, hosted in `previewContainer`.
    private lazy var previewLayer: AVCaptureVideoPreviewLayer = viewModel.previewLayer

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

        let stack = UIStackView(arrangedSubviews: [instructionLabel, previewContainer, cueLabel])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.md
        stack.alignment = .fill
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
            // ROOT-CAUSE FIX (debug session `front-camera-preview-black`):
            // `previewContainer` is a plain `UIView` — it has no intrinsic
            // content size. As an arranged subview of a vertical `.fill`
            // UIStackView whose only sized siblings are the labels (which DO
            // have intrinsic heights), the container had NO height preference
            // and NO height constraint, so Auto Layout collapsed it to height
            // 0. `previewLayer.frame = previewContainer.bounds` then copied a
            // zero-height rect → the AVCaptureVideoPreviewLayer rendered into a
            // 0pt-tall frame → solid-black preview area. Pinning a definite 3:4
            // portrait aspect ratio gives the host view a real, device-
            // independent height so the preview layer has a visible frame.
            previewContainer.heightAnchor.constraint(
                equalTo: previewContainer.widthAnchor,
                multiplier: 4.0 / 3.0
            ),
        ])

        previewLayer.frame = previewContainer.bounds
        previewContainer.layer.addSublayer(previewLayer)
        previewContainer.layer.addSublayer(ovalGuideLayer)
        kycCameraLog.info("kyc_camera event=face_vc.viewDidLoad preview_layer_added_to=previewContainer videoGravity=\(String(describing: self.previewLayer.videoGravity), privacy: .public)")

        viewModel.onStateChange = { [weak self] state in
            self?.handle(state: state)
        }
        handle(state: .adjusting(nil))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        kycCameraLog.info("kyc_camera event=face_vc.viewWillAppear previewContainer.bounds=\(NSCoder.string(for: self.previewContainer.bounds), privacy: .public)")
        viewModel.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = previewContainer.bounds
        ovalGuideLayer.frame = previewContainer.bounds
        updateOvalPath()
        updatePreviewRotation()
        let connection = previewLayer.connection
        kycCameraLog.info("kyc_camera event=face_vc.viewDidLayoutSubviews previewContainer.bounds=\(NSCoder.string(for: self.previewContainer.bounds), privacy: .public) previewLayer.frame=\(NSCoder.string(for: self.previewLayer.frame), privacy: .public) inHierarchy=\(self.previewLayer.superlayer != nil, privacy: .public) connectionExists=\(connection != nil, privacy: .public) connectionActive=\(connection?.isActive ?? false, privacy: .public) connectionEnabled=\(connection?.isEnabled ?? false, privacy: .public)")
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

    // MARK: - State → UI

    private func handle(state: FaceCaptureViewModel.State) {
        switch state {
        case let .adjusting(reason):
            cueLabel.text = cueText(for: reason)
            setGuidePassing(false)
        case .holding:
            cueLabel.text = NSLocalizedString(
                "kyc.face.cue.hold",
                value: "Hold still",
                comment: "Face-capture steady-hold cue (D-04)"
            )
            setGuidePassing(true)
        case .capturing:
            cueLabel.text = NSLocalizedString(
                "kyc.face.cue.hold",
                value: "Hold still",
                comment: "Face-capture steady-hold cue (D-04)"
            )
            setGuidePassing(true)
        case .locationUnavailable:
            cueLabel.text = NSLocalizedString(
                "kyc.error.gps_stale",
                value: "We couldn't confirm your location. Move to an open area and try the photo again.",
                comment: "KYC GPS-stale capture error"
            )
            setGuidePassing(false)
        case .captured:
            presentPreview()
        case let .failed(message):
            cueLabel.text = message
            setGuidePassing(false)
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
        let bounds = previewContainer.bounds
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

    private func presentPreview() {
        let preview = CapturePreviewViewController(
            artifactLabel: NSLocalizedString(
                "kyc.face.instruction",
                value: "Position your face inside the oval.",
                comment: "Face-capture instruction header"
            )
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
