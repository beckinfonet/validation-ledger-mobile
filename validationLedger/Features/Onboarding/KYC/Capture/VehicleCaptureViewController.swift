// validationLedger/Features/Onboarding/KYC/Capture/VehicleCaptureViewController.swift
// Phase 5 Plan 05 — KYC-04: the plain-photo vehicle-capture screen.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md hard constraint). ONE VC reused
// for truck / trailer / plate, parameterized by the `VehicleCaptureViewModel`'s
// artifact type + instruction header. A plain framed-photo capture with a
// shutter button; GPS is injected at capture time exactly as the face path.
//
// Scaffold copied from `OTPViewController`, using `DS.Spacing` / `DS.Typography`
// / `DS.Colors` tokens (NOT raw literals — 05-UI-SPEC). All copy via
// `NSLocalizedString(_, value:)`; every label sets
// `adjustsFontForContentSizeCategory = true`. The shutter button presents a 44pt
// touch-target floor (UI-SPEC). iPad: Auto Layout against the safe area; the
// preview `videoRotationAngle` is updated on `viewWillTransition` (Pitfall 7).

import AVFoundation
import OSLog
import UIKit

/// The plain-photo capture screen reused for truck / trailer / plate (KYC-04).
///
/// Not `final` — `DLBackCaptureViewController` subclasses it so the DL back
/// (D-06 — a plain framed photo) reuses this identical still-capture screen
/// while remaining a distinct named type in the KYC-01 push chain.
class VehicleCaptureViewController: UIViewController {

    private let viewModel: VehicleCaptureViewModel

    // MARK: - UI components

    private let previewContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "kyc-vehicle-preview"
        return view
    }()

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.title1
        label.textColor = DS.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-vehicle-instruction"
        return label
    }()

    private let cueLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.footnote
        label.textColor = DS.Colors.labelSecondary
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-vehicle-cue"
        return label
    }()

    private let shutterButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = NSLocalizedString(
            "kyc.capture.shutter",
            value: "Take photo",
            comment: "Plain-photo capture shutter button"
        )
        let button = UIButton(configuration: cfg)
        button.accessibilityIdentifier = "kyc-vehicle-shutter"
        return button
    }()

    private lazy var previewLayer: AVCaptureVideoPreviewLayer = viewModel.previewLayer

    // MARK: - Init

    init(viewModel: VehicleCaptureViewModel) {
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

        instructionLabel.text = viewModel.instructionText

        let stack = UIStackView(arrangedSubviews: [
            instructionLabel, previewContainer, cueLabel, shutterButton,
        ])
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
            // 44pt touch-target floor (UI-SPEC).
            shutterButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            // ROOT-CAUSE FIX (debug session `front-camera-preview-black`):
            // `previewContainer` is a plain `UIView` with no intrinsic content
            // size. In this vertical `.fill` UIStackView its only sized
            // siblings (labels + shutter button) have intrinsic heights, so the
            // container had NO height preference and NO height constraint —
            // Auto Layout collapsed it to height 0. `previewLayer.frame =
            // previewContainer.bounds` then copied a zero-height rect → the
            // AVCaptureVideoPreviewLayer rendered into a 0pt-tall frame → solid-
            // black preview area. A definite 3:4 portrait aspect ratio gives
            // the host view a real height so the preview layer is visible.
            previewContainer.heightAnchor.constraint(
                equalTo: previewContainer.widthAnchor,
                multiplier: 4.0 / 3.0
            ),
        ])

        previewLayer.frame = previewContainer.bounds
        previewContainer.layer.addSublayer(previewLayer)
        kycCameraLog.info("kyc_camera event=vehicle_vc.viewDidLoad preview_layer_added_to=previewContainer videoGravity=\(String(describing: self.previewLayer.videoGravity), privacy: .public)")

        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)

        viewModel.onStateChange = { [weak self] state in
            self?.handle(state: state)
        }
        handle(state: .ready)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        kycCameraLog.info("kyc_camera event=vehicle_vc.viewWillAppear previewContainer.bounds=\(NSCoder.string(for: self.previewContainer.bounds), privacy: .public)")
        viewModel.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = previewContainer.bounds
        updatePreviewRotation()
        let connection = previewLayer.connection
        kycCameraLog.info("kyc_camera event=vehicle_vc.viewDidLayoutSubviews previewContainer.bounds=\(NSCoder.string(for: self.previewContainer.bounds), privacy: .public) previewLayer.frame=\(NSCoder.string(for: self.previewLayer.frame), privacy: .public) inHierarchy=\(self.previewLayer.superlayer != nil, privacy: .public) connectionExists=\(connection != nil, privacy: .public) connectionActive=\(connection?.isActive ?? false, privacy: .public) connectionEnabled=\(connection?.isEnabled ?? false, privacy: .public)")
    }

    /// iPad rotation (RESEARCH Pitfall 7).
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

    private func handle(state: VehicleCaptureViewModel.State) {
        switch state {
        case .ready:
            cueLabel.text = ""
            shutterButton.isEnabled = true
        case .capturing:
            cueLabel.text = ""
            shutterButton.isEnabled = false
        case .locationUnavailable:
            cueLabel.text = NSLocalizedString(
                "kyc.error.gps_stale",
                value: "We couldn't confirm your location. Move to an open area and try the photo again.",
                comment: "KYC GPS-stale capture error"
            )
            shutterButton.isEnabled = true
        case .captured:
            presentPreview()
        case let .failed(message):
            cueLabel.text = message
            shutterButton.isEnabled = false
        }
    }

    // MARK: - Actions

    @objc private func shutterTapped() {
        viewModel.capture()
    }

    private func updatePreviewRotation() {
        guard let connection = previewLayer.connection else { return }
        // iOS 17 API — `videoRotationAngle` replaces deprecated `videoOrientation`.
        let angle: CGFloat
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft:      angle = 180
        case .landscapeRight:     angle = 0
        case .portraitUpsideDown: angle = 270
        default:                  angle = 90
        }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func presentPreview() {
        let preview = CapturePreviewViewController(artifactLabel: viewModel.instructionText)
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
