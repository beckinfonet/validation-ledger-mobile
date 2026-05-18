// validationLedger/Features/Onboarding/KYC/Capture/CameraPermissionViewController.swift
// Phase 5 Plan 05 — D-21 reuse: the blocking camera-permission-denied screen.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md hard constraint). Shown when
// `AVCaptureDevice` authorization for video is denied/restricted — the user
// cannot photograph their ID or vehicle, so the capture surface is blocked.
//
// Reuses the Phase 3 GEO-permission-denied pattern (D-21): a blocking state with
// an "Open Settings" deep-link via `UIApplication.openSettingsURLString` plus a
// "Cancel" affordance. Uses `DS.Spacing` / `DS.Typography` / `DS.Colors` tokens;
// all copy via `NSLocalizedString(_, value:)`; every label sets
// `adjustsFontForContentSizeCategory = true`.

import AVFoundation
import UIKit

/// The blocking camera-permission-denied screen (D-21 pattern reuse).
final class CameraPermissionViewController: UIViewController {

    /// Fired when the user taps "Cancel".
    var onCancel: (() -> Void)?

    /// Whether the camera is currently authorized — `viewWillAppear` checks
    /// this so a user returning from Settings with permission granted can be
    /// advanced by the host.
    var onAuthorizationGranted: (() -> Void)?

    // MARK: - UI components

    private let headingLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.title1
        label.textColor = DS.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-permission-heading"
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.body
        label.textColor = DS.Colors.labelSecondary
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-permission-body"
        return label
    }()

    private let openSettingsButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = NSLocalizedString(
            "kyc.permission.open_settings",
            value: "Open Settings",
            comment: "Camera-permission-denied Open Settings action (D-21)"
        )
        let button = UIButton(configuration: cfg)
        button.accessibilityIdentifier = "kyc-permission-open-settings"
        return button
    }()

    private let cancelButton: UIButton = {
        var cfg = UIButton.Configuration.bordered()
        cfg.title = NSLocalizedString(
            "kyc.permission.cancel",
            value: "Cancel",
            comment: "Camera-permission-denied cancel action (D-21)"
        )
        let button = UIButton(configuration: cfg)
        button.accessibilityIdentifier = "kyc-permission-cancel"
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = NSLocalizedString(
            "kyc.permission.heading",
            value: "Camera access needed",
            comment: "Camera-permission-denied nav title"
        )

        headingLabel.text = NSLocalizedString(
            "kyc.permission.heading",
            value: "Camera access needed",
            comment: "Camera-permission-denied heading"
        )
        bodyLabel.text = NSLocalizedString(
            "kyc.permission.body",
            value: "Validation Ledger needs your camera to photograph your ID and vehicle. Turn it on in Settings.",
            comment: "Camera-permission-denied body copy"
        )

        let buttons = UIStackView(arrangedSubviews: [openSettingsButton, cancelButton])
        buttons.axis = .vertical
        buttons.spacing = DS.Spacing.sm
        buttons.alignment = .fill

        let stack = UIStackView(arrangedSubviews: [headingLabel, bodyLabel, buttons])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.lg
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: DS.Spacing.lg
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -DS.Spacing.lg
            ),
            // 44pt touch-target floor (UI-SPEC / HIG).
            openSettingsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        openSettingsButton.addTarget(self, action: #selector(openSettingsTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // A user who granted access in Settings and returned can be advanced.
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            onAuthorizationGranted?()
        }
    }

    // MARK: - Actions

    @objc private func openSettingsTapped() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else {
            return
        }
        UIApplication.shared.open(url)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}
