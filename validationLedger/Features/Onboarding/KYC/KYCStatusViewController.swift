// validationLedger/Features/Onboarding/KYC/KYCStatusViewController.swift
// Phase 5 Plan 06 — KYC-05 / D-08..D-11: the single KYC status screen.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md sensitive-surface mandate; KYC
// is an identity surface). Thin view layer — the 4-state machine + reason-code
// mapping live in `KYCStatusViewModel`.
//
// === D-08 — one screen, two entry points ===
// This is THE status screen — reached post-submit (KYCCoordinator.pushStatus)
// and, in plan 08, from the Profile entry point. It also renders the
// "No verification in progress" empty state for the role-shell re-entry path.
//
// === D-09 — fetch-on-appear + pull-to-refresh ===
// `fetchStatus()` is called from `viewWillAppear` (fires every appearance) and
// from a `UIRefreshControl`. No background polling timers.
//
// Status-state color map (05-UI-SPEC):
//   pending      → `.secondaryLabel` text + "clock" SF Symbol
//   under_review → `.secondaryLabel` text + "hourglass" SF Symbol
//   verified     → `DS.Colors.primary` checkmark + verdict heading + "Continue"
//   rejected     → `DS.Colors.destructive` label + per-artifact reason copy in
//                  red + a per-artifact "Retake" in `DS.Colors.primary`
//
// All copy via `NSLocalizedString(_, value:)`; DS tokens throughout;
// `adjustsFontForContentSizeCategory = true`.

import UIKit

final class KYCStatusViewController: UIViewController {

    private let viewModel: KYCStatusViewModel

    // MARK: - UI components

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.alwaysBounceVertical = true
        return s
    }()

    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = DS.Spacing.lg
        s.alignment = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let refreshControl = UIRefreshControl()

    private let symbolView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 56, weight: .regular)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.accessibilityIdentifier = "kyc-status-symbol"
        return v
    }()

    private let headingLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.title1
        l.textColor = DS.Colors.label
        l.numberOfLines = 0
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = true
        l.accessibilityIdentifier = "kyc-status-heading"
        return l
    }()

    private let bodyLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.body
        l.textColor = DS.Colors.labelSecondary
        l.numberOfLines = 0
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = true
        l.accessibilityIdentifier = "kyc-status-body"
        return l
    }()

    /// Holds the per-artifact rejected rows (D-10). Hidden unless `.rejected`.
    private let rejectedListStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = DS.Spacing.md
        s.alignment = .fill
        s.isHidden = true
        return s
    }()

    private let continueButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = NSLocalizedString(
            "kyc.status.continue",
            value: "Continue",
            comment: "KYC status screen — verified-path CTA into the role shell"
        )
        let b = UIButton(configuration: cfg)
        b.isHidden = true
        b.accessibilityIdentifier = "kyc-status-continue"
        return b
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let i = UIActivityIndicatorView(style: .large)
        i.hidesWhenStopped = true
        return i
    }()

    // MARK: - Init

    init(viewModel: KYCStatusViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString(
            "kyc.status.nav_title",
            value: "Verification",
            comment: "KYC status screen nav-bar title"
        )
        view.backgroundColor = DS.Colors.background
        navigationItem.hidesBackButton = true  // terminal — no back path (D-14 mitigation)

        layoutContent()
        wireActions()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // D-09 — fetch-on-appear: fires every time the screen appears (both
        // post-submit and from a role-shell re-entry). No background polling.
        Task { await viewModel.fetchStatus() }
    }

    // MARK: - Layout

    private func layoutContent() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.refreshControl = refreshControl

        contentStack.addArrangedSubview(symbolView)
        contentStack.addArrangedSubview(headingLabel)
        contentStack.addArrangedSubview(bodyLabel)
        contentStack.addArrangedSubview(activityIndicator)
        contentStack.addArrangedSubview(rejectedListStack)
        contentStack.addArrangedSubview(continueButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: guide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),

            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor, constant: DS.Spacing.xl),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: DS.Spacing.lg),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -DS.Spacing.lg),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -DS.Spacing.xl),

            symbolView.heightAnchor.constraint(equalToConstant: 72),
            continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func wireActions() {
        // D-09 — pull-to-refresh re-fires GET /kyc/status. No polling timer.
        refreshControl.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in self?.handle(state: state) }
    }

    // MARK: - Actions

    @objc private func pulledToRefresh() {
        Task { await viewModel.fetchStatus() }
    }

    @objc private func continueTapped() {
        viewModel.continueToRoleShell()
    }

    // MARK: - State → UI

    private func handle(state: KYCStatusViewModel.State) {
        // Reset shared chrome before applying the state.
        refreshControl.endRefreshing()
        rejectedListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rejectedListStack.isHidden = true
        continueButton.isHidden = true
        activityIndicator.stopAnimating()

        switch state {
        case .loading:
            symbolView.image = nil
            headingLabel.text = ""
            bodyLabel.text = ""
            // Only spin the standalone indicator when the refresh control is not
            // already showing its own spinner.
            if !refreshControl.isRefreshing {
                activityIndicator.startAnimating()
            }

        case .pending:
            symbolView.image = UIImage(systemName: "clock")
            symbolView.tintColor = DS.Colors.labelSecondary
            headingLabel.textColor = DS.Colors.labelSecondary
            headingLabel.text = NSLocalizedString(
                "kyc.status.pending.title",
                value: "Verification pending",
                comment: "KYC status screen — pending verdict heading"
            )
            bodyLabel.text = NSLocalizedString(
                "kyc.status.pending.body",
                value: "We've received your photos. Verification will begin shortly.",
                comment: "KYC status screen — pending verdict body"
            )

        case .underReview:
            symbolView.image = UIImage(systemName: "hourglass")
            symbolView.tintColor = DS.Colors.labelSecondary
            headingLabel.textColor = DS.Colors.labelSecondary
            headingLabel.text = NSLocalizedString(
                "kyc.status.under_review.title",
                value: "Under review",
                comment: "KYC status screen — under-review verdict heading"
            )
            bodyLabel.text = NSLocalizedString(
                "kyc.status.under_review.body",
                value: "Our team is reviewing your identity. This usually takes a short while.",
                comment: "KYC status screen — under-review verdict body"
            )

        case .verified:
            symbolView.image = UIImage(systemName: "checkmark.circle.fill")
            symbolView.tintColor = DS.Colors.primary
            headingLabel.textColor = DS.Colors.primary
            headingLabel.text = NSLocalizedString(
                "kyc.status.verified.title",
                value: "You're verified",
                comment: "KYC status screen — verified verdict heading"
            )
            bodyLabel.text = NSLocalizedString(
                "kyc.status.verified.body",
                value: "Your identity is confirmed. You can start using Validation Ledger.",
                comment: "KYC status screen — verified verdict body"
            )
            bodyLabel.textColor = DS.Colors.labelSecondary
            continueButton.isHidden = false

        case .rejected(let artifacts):
            symbolView.image = UIImage(systemName: "exclamationmark.triangle.fill")
            symbolView.tintColor = DS.Colors.destructive
            headingLabel.textColor = DS.Colors.destructive
            headingLabel.text = NSLocalizedString(
                "kyc.status.rejected.title",
                value: "Some photos need a retake",
                comment: "KYC status screen — rejected verdict heading"
            )
            bodyLabel.text = NSLocalizedString(
                "kyc.status.rejected.body",
                value: "Retake the photos below. The rest of your verification is fine.",
                comment: "KYC status screen — rejected verdict body"
            )
            bodyLabel.textColor = DS.Colors.labelSecondary
            for artifact in artifacts {
                rejectedListStack.addArrangedSubview(makeRejectedRow(for: artifact))
            }
            rejectedListStack.isHidden = artifacts.isEmpty

        case .noSubmission:
            symbolView.image = UIImage(systemName: "person.crop.circle.badge.questionmark")
            symbolView.tintColor = DS.Colors.labelSecondary
            headingLabel.textColor = DS.Colors.label
            headingLabel.text = NSLocalizedString(
                "kyc.status.empty.title",
                value: "No verification in progress",
                comment: "KYC status screen — empty state heading (role-shell re-entry path)"
            )
            bodyLabel.text = NSLocalizedString(
                "kyc.status.empty.body",
                value: "Finish your KYC photos to start verification.",
                comment: "KYC status screen — empty state body"
            )
            bodyLabel.textColor = DS.Colors.labelSecondary

        case .error(let message):
            symbolView.image = UIImage(systemName: "wifi.exclamationmark")
            symbolView.tintColor = DS.Colors.destructive
            headingLabel.textColor = DS.Colors.label
            headingLabel.text = NSLocalizedString(
                "kyc.status.error.title",
                value: "Couldn't load status",
                comment: "KYC status screen — fetch error heading"
            )
            bodyLabel.text = message
            bodyLabel.textColor = DS.Colors.labelSecondary
        }
    }

    /// Build one rejected-artifact row (D-10): the artifact label, the
    /// controlled-vocabulary reason copy in red, and a "Retake" button.
    private func makeRejectedRow(for artifact: KYCStatusViewModel.RejectedArtifact) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = DS.Spacing.sm
        container.alignment = .fill
        container.layoutMargins = UIEdgeInsets(
            top: DS.Spacing.md, left: DS.Spacing.md,
            bottom: DS.Spacing.md, right: DS.Spacing.md
        )
        container.isLayoutMarginsRelativeArrangement = true
        container.backgroundColor = DS.Colors.surface
        container.layer.cornerRadius = DS.Spacing.sm
        container.accessibilityIdentifier = "kyc-status-rejected-\(artifact.artifactID)"

        let reasonLabel = UILabel()
        reasonLabel.font = DS.Typography.footnote
        reasonLabel.textColor = DS.Colors.destructive
        reasonLabel.numberOfLines = 0
        reasonLabel.adjustsFontForContentSizeCategory = true
        reasonLabel.text = artifact.reasonCopy
        container.addArrangedSubview(reasonLabel)

        // Only an artifact whose ID maps to a known type can offer re-capture.
        if let artifactType = artifact.artifactType {
            var cfg = UIButton.Configuration.bordered()
            cfg.title = NSLocalizedString(
                "kyc.status.retake",
                value: "Retake",
                comment: "KYC status screen — retake a rejected artifact (D-10)"
            )
            let retake = UIButton(configuration: cfg)
            retake.tintColor = DS.Colors.primary
            retake.accessibilityIdentifier = "kyc-status-retake-\(artifactType.rawValue)"
            retake.addAction(UIAction { [weak self] _ in
                self?.viewModel.recapture(artifactType: artifactType)
            }, for: .touchUpInside)
            retake.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            container.addArrangedSubview(retake)
        }
        return container
    }
}
