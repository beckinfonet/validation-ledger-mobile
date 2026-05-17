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
//
// === PREVIEW HOSTING (debug session `front-camera-preview-black`, round 4) ===
// The camera preview is hosted by a `CameraPreviewView` — a `UIView` subclass
// whose BACKING layer IS the `AVCaptureVideoPreviewLayer` (`layerClass` override).
// UIKit keeps a view's backing layer exactly `bounds`-sized, so there is NO
// manual `previewLayer.frame` sync and NO 0×0 race — the fragile add-as-sublayer
// pattern of rounds 1–3 is gone. The preview view is the slack-absorbing
// arranged subview of the `.fill` stack (round-3 hugging-priority fix retained).

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

    /// Hosts the live camera preview. Its backing layer IS the
    /// `AVCaptureVideoPreviewLayer` (`CameraPreviewView.layerClass`), so the
    /// preview is always exactly this view's `bounds` with zero manual frame
    /// sync — the round-4 structural fix for the black-preview bug. Render-only
    /// (Pitfall 6).
    ///
    /// Layout (round 3, retained): a vertical `.fill` `UIStackView` pinned to the
    /// safe area on BOTH ends. The preview hugs vertically at the lowest priority
    /// while the labels and shutter button hug firmly, so the `.fill` stack
    /// stretches the preview into the leftover vertical space — it cannot
    /// collapse to 0.
    private let previewView: CameraPreviewView = {
        let view = CameraPreviewView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "kyc-vehicle-preview"
        // Hug at the lowest possible priority so the `.fill` stack always
        // expands the preview (rather than a label/button) to fill the height.
        view.setContentHuggingPriority(.init(1), for: .vertical)
        view.setContentCompressionResistancePriority(.init(1), for: .vertical)
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

    /// The camera preview layer — the backing layer of `previewView`.
    private var previewLayer: AVCaptureVideoPreviewLayer { previewView.previewLayer }

    /// Guards the one-shot `final_state` diagnostic so it logs once per appear.
    private var didLogFinalState = false

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

        // The labels hug their intrinsic vertical content firmly so the `.fill`
        // stack leaves them label-sized and stretches the preview instead.
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
            // 44pt touch-target floor (UI-SPEC).
            shutterButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            // ROUND-3 layout fix (retained). The `.fill` stack expands the
            // preview view into the leftover vertical space because the preview
            // hugs at the lowest priority while the labels hug at `.required`
            // and the shutter button keeps its `>= 44` floor. Defense-in-depth:
            // a min-height floor at priority 250 — too low to reintroduce a
            // breakable conflict, yet guards against a future layout shrink.
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
        // `previewLayer.frame` to sync and no 0×0 race. Wire the session in.
        previewView.session = viewModel.captureSession
        previewView.videoGravity = .resizeAspectFill
        kycCameraLog.info("kyc_camera event=vehicle_vc.viewDidLoad preview_host=CameraPreviewView(layerClass) videoGravity=\(String(describing: self.previewLayer.videoGravity), privacy: .public) sessionWired=\(self.previewLayer.session != nil, privacy: .public)")

        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)

        viewModel.onStateChange = { [weak self] state in
            self?.handle(state: state)
        }
        handle(state: .ready)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didLogFinalState = false
        kycCameraLog.info("kyc_camera event=vehicle_vc.viewWillAppear previewView.bounds=\(NSCoder.string(for: self.previewView.bounds), privacy: .public)")
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
        updatePreviewRotation()
        let connection = previewLayer.connection
        kycCameraLog.info("kyc_camera event=vehicle_vc.viewDidLayoutSubviews previewView.bounds=\(NSCoder.string(for: self.previewView.bounds), privacy: .public) previewLayer.bounds=\(NSCoder.string(for: self.previewLayer.bounds), privacy: .public) inHierarchy=\(self.previewLayer.superlayer != nil, privacy: .public) connectionExists=\(connection != nil, privacy: .public) connectionActive=\(connection?.isActive ?? false, privacy: .public) connectionEnabled=\(connection?.isEnabled ?? false, privacy: .public)")
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

    // MARK: - Round-4 definitive diagnostic

    /// Schedule the one-shot `kyc_camera event=final_state` snapshot ~2s after
    /// the camera-session startup is kicked — the post-settle TRUTH that
    /// disambiguates layout-still-broken vs camera-still-broken for the
    /// black-preview bug (debug session `front-camera-preview-black`, round 4).
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
        let preview = CapturePreviewViewController(
            artifactLabel: viewModel.instructionText,
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
