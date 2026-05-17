// validationLedger/Features/Onboarding/KYC/KYCStartViewController.swift
// Phase 5 Plan 05 — KYC-01: the "Let's verify your identity" intro / empty-state
// screen that opens the KYC capture flow.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md sensitive-surface mandate; KYC
// is an identity surface). Scaffold copied from `OTPViewController` but using
// `DS.Spacing` / `DS.Typography` / `DS.Colors` tokens instead of the analog's
// raw `8/12/16/24/32` literals (05-UI-SPEC contract).
//
// The "Get started" CTA callback bubbles to `KYCCoordinator.pushFaceCapture()`.

import UIKit

/// The KYC-flow intro screen — UI-SPEC "Let's verify your identity" empty state.
final class KYCStartViewController: UIViewController {

    /// Fired when the user taps "Get started". `KYCCoordinator` wires this to
    /// `pushFaceCapture()`.
    var onGetStarted: (() -> Void)?

    // MARK: - UI components

    private let headingLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.title1
        label.textColor = DS.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-start-heading"
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.body
        label.textColor = DS.Colors.labelSecondary
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-start-body"
        return label
    }()

    private let getStartedButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = NSLocalizedString(
            "kyc.start.cta",
            value: "Get started",
            comment: "KYC flow-start primary CTA"
        )
        let button = UIButton(configuration: cfg)
        button.accessibilityIdentifier = "kyc-start-cta"
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = NSLocalizedString(
            "kyc.start.title",
            value: "Verify identity",
            comment: "KYC flow-start nav title"
        )

        headingLabel.text = NSLocalizedString(
            "kyc.start.heading",
            value: "Let's verify your identity",
            comment: "KYC flow-start heading"
        )
        bodyLabel.text = NSLocalizedString(
            "kyc.start.body",
            value: "We'll take 6 quick photos: your face, both sides of your license, and your truck, trailer, and plate. It takes about 2 minutes.",
            comment: "KYC flow-start body copy"
        )

        let stack = UIStackView(arrangedSubviews: [headingLabel, bodyLabel, getStartedButton])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.lg
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        // Auto Layout against the safe area — vertically centered intro/empty
        // state; renders natively on iPhone + iPad (CLAUDE.md).
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
        ])

        getStartedButton.addTarget(self, action: #selector(getStartedTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func getStartedTapped() {
        onGetStarted?()
    }
}
