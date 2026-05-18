// validationLedger/Features/Onboarding/KYC/Capture/CapturePreviewViewController.swift
// Phase 5 Plan 05 — D-07: the per-shot Use/Retake still preview.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md hard constraint). After every
// capture a still preview is shown with "Use photo" (primary CTA — bubbles a
// confirm callback that kicks the pipelined upload and advances the coordinator)
// and "Retake" (re-opens the camera). This catches a bad shot immediately, in
// context, while the subject is still present — so the plan-06 Review screen is
// a confirm-all, not the first chance to spot a problem.
//
// The captured bytes are already persisted into the `KYCSessionStore` by the
// capture VM (Pitfall 6 — GPS-injected straight from the `AVCapturePhoto`). This
// screen does NOT re-render the upload bytes — it shows a lightweight render-only
// preview supplied by the capture VC, keeping the preview path and the upload
// path strictly distinct. Both buttons present a 44pt touch-target floor (HIG).

import UIKit

/// The per-shot Use/Retake still preview (D-07).
final class CapturePreviewViewController: UIViewController {

    /// Fired when the user taps "Use photo" — the capture VC kicks the pipelined
    /// upload (D-01) and the coordinator advances.
    var onUse: (() -> Void)?

    /// Fired when the user taps "Retake" — the capture VC re-opens the camera.
    var onRetake: (() -> Void)?

    /// A render-only preview image of the just-captured shot, if the capture VC
    /// supplied one. Never the upload byte source (the upload `Data` lives in
    /// the `KYCSessionStore`, GPS-injected — Pitfall 6).
    private let previewImage: UIImage?

    /// A description of what was captured, shown above the preview.
    private let artifactLabel: String

    // MARK: - UI components

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.headline
        label.textColor = DS.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-preview-title"
        return label
    }()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "kyc-preview-image"
        // In a `.fill` vertical stack pinned top+bottom, a UIImageView's height
        // comes ONLY from its image's intrinsic size — a nil/odd image collapses
        // it to 0 (the FaceCapture round-2 bug class — debug session
        // `kyc-flow-device-audit`). Hug at the lowest priority so the `.fill`
        // stack always expands the image view into the leftover vertical space.
        view.setContentHuggingPriority(.init(1), for: .vertical)
        view.setContentCompressionResistancePriority(.init(1), for: .vertical)
        return view
    }()

    private let useButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = NSLocalizedString(
            "kyc.preview.cta",
            value: "Use photo",
            comment: "Per-shot preview primary CTA (D-07)"
        )
        let button = UIButton(configuration: cfg)
        button.accessibilityIdentifier = "kyc-preview-use"
        return button
    }()

    private let retakeButton: UIButton = {
        var cfg = UIButton.Configuration.bordered()
        cfg.title = NSLocalizedString(
            "kyc.preview.retake",
            value: "Retake",
            comment: "Per-shot preview retake action (D-07)"
        )
        let button = UIButton(configuration: cfg)
        button.accessibilityIdentifier = "kyc-preview-retake"
        return button
    }()

    // MARK: - Init

    /// - Parameters:
    ///   - artifactLabel: a description of what was captured (the capture
    ///     screen's instruction header reads well here).
    ///   - previewImage: an optional render-only preview of the shot.
    init(artifactLabel: String, previewImage: UIImage? = nil) {
        self.artifactLabel = artifactLabel
        self.previewImage = previewImage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background

        titleLabel.text = NSLocalizedString(
            "kyc.preview.title",
            value: "Check your photo",
            comment: "Per-shot preview title (D-07)"
        )
        imageView.image = previewImage

        // The title + buttons hug their intrinsic vertical content firmly so the
        // `.fill` stack leaves them content-sized and stretches the image view
        // (debug session `kyc-flow-device-audit`).
        titleLabel.setContentHuggingPriority(.required, for: .vertical)

        let buttons = UIStackView(arrangedSubviews: [useButton, retakeButton])
        buttons.axis = .vertical
        buttons.spacing = DS.Spacing.sm
        buttons.alignment = .fill
        buttons.setContentHuggingPriority(.required, for: .vertical)

        let stack = UIStackView(arrangedSubviews: [titleLabel, imageView, buttons])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.md
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let imageMinHeight = imageView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 240
        )
        imageMinHeight.priority = .init(250)

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
            // Defense-in-depth min-height floor for the preview image — too low
            // (priority 250) to fight the encapsulated layout, mirrors the
            // FaceCapture round-3 fix (debug session `kyc-flow-device-audit`).
            imageMinHeight,
            // 44pt touch-target floor on both buttons (UI-SPEC / HIG).
            useButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            retakeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        useButton.addTarget(self, action: #selector(useTapped), for: .touchUpInside)
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func useTapped() {
        onUse?()
    }

    @objc private func retakeTapped() {
        onRetake?()
    }
}
