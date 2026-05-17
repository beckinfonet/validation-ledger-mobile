// validationLedger/Features/Onboarding/KYC/KYCReviewViewController.swift
// Phase 5 Plan 06 — KYC-01 / D-03: the Review screen.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md sensitive-surface mandate; KYC
// is an identity surface). Thin view layer — the gated-Submit logic lives in
// `KYCReviewViewModel`.
//
// Layout (05-UI-SPEC "Review your photos"):
//   - heading "Review your photos"
//   - a 6-cell artifact thumbnail grid (a 2-column `UIStackView` of cells) on
//     `DS.Colors.surface` cells, each with a per-artifact upload status badge:
//       ✓ uploaded  → `DS.Colors.primary`
//       ⟳ uploading → a determinate `UIProgressView`
//       ⚠ failed    → `DS.Colors.destructive`, with inline "Retry upload" +
//                     "Retake" buttons (44pt hit area)
//   - the "Submit" primary CTA (`borderedProminent`), disabled until
//     `submitEnabled`; while disabled the helper caption explains the gate.
//
// All copy via `NSLocalizedString(_, value:)`; all spacing via `DS.Spacing`;
// `adjustsFontForContentSizeCategory = true` throughout.

import UIKit

final class KYCReviewViewController: UIViewController {

    private let viewModel: KYCReviewViewModel

    // MARK: - UI components

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.translatesAutoresizingMaskIntoConstraints = false
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

    private let headingLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.title1
        l.textColor = DS.Colors.label
        l.numberOfLines = 0
        l.adjustsFontForContentSizeCategory = true
        l.text = NSLocalizedString(
            "kyc.review.title",
            value: "Review your photos",
            comment: "KYC Review screen heading"
        )
        l.accessibilityIdentifier = "kyc-review-heading"
        return l
    }()

    /// The 6-cell grid — two columns of three rows of `ArtifactCell`s.
    private let gridStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = DS.Spacing.md
        s.alignment = .fill
        s.distribution = .fillEqually
        return s
    }()

    private let submitButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = NSLocalizedString(
            "kyc.review.submit",
            value: "Submit",
            comment: "KYC Review screen primary CTA — the D-03 gated finalizer"
        )
        let b = UIButton(configuration: cfg)
        b.isEnabled = false
        b.accessibilityIdentifier = "kyc-review-submit"
        return b
    }()

    private let helperCaption: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.labelSecondary
        l.numberOfLines = 0
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = true
        l.text = NSLocalizedString(
            "kyc.review.submit_helper",
            value: "Submit unlocks once all 6 photos finish uploading.",
            comment: "KYC Review screen — helper caption shown while Submit is disabled (D-03)"
        )
        l.accessibilityIdentifier = "kyc-review-helper"
        return l
    }()

    private let errorLabel: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.textColor = DS.Colors.destructive
        l.numberOfLines = 0
        l.textAlignment = .center
        l.adjustsFontForContentSizeCategory = true
        l.accessibilityIdentifier = "kyc-review-error"
        return l
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let i = UIActivityIndicatorView(style: .medium)
        i.hidesWhenStopped = true
        return i
    }()

    /// One `ArtifactCell` per artifact, keyed for targeted updates.
    private var cells: [KYCUploadInitEndpoint.ArtifactType: ArtifactCell] = [:]

    // MARK: - Init

    init(viewModel: KYCReviewViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString(
            "kyc.review.nav_title",
            value: "Review",
            comment: "KYC Review screen nav-bar title"
        )
        view.backgroundColor = DS.Colors.background

        buildGrid()
        layoutContent()
        wireActions()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-read the persisted session — pipelined uploads (D-01) may have
        // completed while the user was still capturing.
        viewModel.refresh()
    }

    // MARK: - Layout

    private func buildGrid() {
        // Two artifacts per row → 3 rows.
        let order = KYCReviewViewModel.artifactOrder
        for pair in stride(from: 0, to: order.count, by: 2) {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = DS.Spacing.md
            rowStack.alignment = .fill
            rowStack.distribution = .fillEqually
            for index in pair..<min(pair + 2, order.count) {
                let artifact = order[index]
                let cell = ArtifactCell(artifact: artifact)
                cell.onRetryUpload = { [weak self] in
                    Task { await self?.viewModel.retryUpload(artifactType: artifact) }
                }
                cell.onRetake = { [weak self] in
                    self?.viewModel.retake(artifactType: artifact)
                }
                cells[artifact] = cell
                rowStack.addArrangedSubview(cell)
            }
            gridStack.addArrangedSubview(rowStack)
        }
    }

    private func layoutContent() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(headingLabel)
        contentStack.addArrangedSubview(gridStack)
        contentStack.addArrangedSubview(submitButton)
        contentStack.addArrangedSubview(activityIndicator)
        contentStack.addArrangedSubview(helperCaption)
        contentStack.addArrangedSubview(errorLabel)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: guide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),

            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor, constant: DS.Spacing.lg),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: DS.Spacing.lg),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -DS.Spacing.lg),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -DS.Spacing.lg),

            submitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func wireActions() {
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
    }

    private func bindViewModel() {
        viewModel.onRowsChange = { [weak self] rows in self?.render(rows: rows) }
        viewModel.onSubmitEnabledChange = { [weak self] enabled in
            self?.applySubmitGate(enabled: enabled)
        }
        viewModel.onStateChange = { [weak self] state in self?.handle(state: state) }
        // Initial render.
        render(rows: viewModel.rows)
        applySubmitGate(enabled: viewModel.submitEnabled)
    }

    // MARK: - Actions

    @objc private func submitTapped() {
        Task { await viewModel.submit() }
    }

    // MARK: - State → UI

    private func render(rows: [KYCReviewViewModel.ArtifactRow]) {
        for row in rows {
            // Render the captured-photo thumbnail AND the status badge (debug
            // session `kyc-flow-device-audit` — the thumbnail image was never
            // wired; the cell only ever showed an empty surface-colored box).
            cells[row.artifact]?.apply(status: row.status, thumbnailData: row.thumbnailData)
        }
    }

    private func applySubmitGate(enabled: Bool) {
        submitButton.isEnabled = enabled
        // The helper caption is shown only while the gate is closed (D-03) so a
        // disabled Submit does not read as a bug.
        helperCaption.isHidden = enabled
    }

    private func handle(state: KYCReviewViewModel.State) {
        switch state {
        case .reviewing:
            errorLabel.text = ""
            activityIndicator.stopAnimating()
            submitButton.isEnabled = viewModel.submitEnabled
        case .submitting:
            errorLabel.text = ""
            activityIndicator.startAnimating()
            submitButton.isEnabled = false
        case .submitted:
            activityIndicator.stopAnimating()
            // KYCCoordinator observes onSubmitted and pushes the status screen.
        case .error(let message):
            errorLabel.text = message
            activityIndicator.stopAnimating()
            submitButton.isEnabled = viewModel.submitEnabled
        }
    }
}

// MARK: - ArtifactCell

/// One thumbnail cell in the Review grid: the artifact preview, the per-artifact
/// upload status badge, and (when failed) inline "Retry upload" + "Retake".
private final class ArtifactCell: UIView {

    let artifact: KYCUploadInitEndpoint.ArtifactType

    /// Tapped on a failed cell — re-invokes the uploader (D-03).
    var onRetryUpload: (() -> Void)?
    /// Tapped on a failed cell — re-opens that capture step (D-03).
    var onRetake: (() -> Void)?

    private let thumbnail: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.backgroundColor = DS.Colors.surface
        v.layer.cornerRadius = DS.Spacing.sm
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let label: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.headline
        l.textColor = DS.Colors.label
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 1
        return l
    }()

    private let badge: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let progressView: UIProgressView = {
        let p = UIProgressView(progressViewStyle: .default)
        p.progressTintColor = DS.Colors.primary
        p.isHidden = true
        return p
    }()

    private let statusText: UILabel = {
        let l = UILabel()
        l.font = DS.Typography.footnote
        l.numberOfLines = 0
        l.adjustsFontForContentSizeCategory = true
        return l
    }()

    private let retryButton: UIButton = {
        var cfg = UIButton.Configuration.bordered()
        cfg.title = NSLocalizedString(
            "kyc.review.retry_upload",
            value: "Retry upload",
            comment: "KYC Review screen — retry a failed artifact upload (D-03)"
        )
        let b = UIButton(configuration: cfg)
        b.isHidden = true
        return b
    }()

    private let retakeButton: UIButton = {
        var cfg = UIButton.Configuration.bordered()
        cfg.title = NSLocalizedString(
            "kyc.review.retake",
            value: "Retake",
            comment: "KYC Review screen — retake a failed artifact (D-03)"
        )
        let b = UIButton(configuration: cfg)
        b.isHidden = true
        b.tintColor = DS.Colors.primary
        return b
    }()

    private let container: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = DS.Spacing.sm
        s.alignment = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    init(artifact: KYCUploadInitEndpoint.ArtifactType) {
        self.artifact = artifact
        super.init(frame: .zero)
        backgroundColor = DS.Colors.surface
        layer.cornerRadius = DS.Spacing.sm
        accessibilityIdentifier = "kyc-review-cell-\(artifact.rawValue)"

        label.text = Self.displayName(for: artifact)

        let headerRow = UIStackView(arrangedSubviews: [label, badge])
        headerRow.axis = .horizontal
        headerRow.spacing = DS.Spacing.xs
        headerRow.alignment = .center

        let buttonRow = UIStackView(arrangedSubviews: [retryButton, retakeButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = DS.Spacing.sm
        buttonRow.distribution = .fillEqually

        container.addArrangedSubview(thumbnail)
        container.addArrangedSubview(headerRow)
        container.addArrangedSubview(progressView)
        container.addArrangedSubview(statusText)
        container.addArrangedSubview(buttonRow)
        addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: DS.Spacing.sm),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Spacing.sm),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Spacing.sm),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Spacing.sm),
            thumbnail.heightAnchor.constraint(equalToConstant: 88),
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 22),
            // 44pt touch-target floor (UI-SPEC) for the inline recovery buttons.
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            retakeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func retryTapped() { onRetryUpload?() }
    @objc private func retakeTapped() { onRetake?() }

    /// Render the captured-photo thumbnail + the per-artifact upload status
    /// badge (UI-SPEC). `thumbnailData` is the GPS-injected JPEG persisted in the
    /// `KYCSession`; `nil` once the local copy is freed post-commit (D-02), in
    /// which case a placeholder symbol is shown.
    func apply(
        status: KYCReviewViewModel.ArtifactUploadStatus,
        thumbnailData: Data?
    ) {
        if let thumbnailData, let image = UIImage(data: thumbnailData) {
            thumbnail.image = image
            thumbnail.contentMode = .scaleAspectFill
            thumbnail.tintColor = nil
        } else {
            // No local bytes (committed + freed, or not captured yet) — show a
            // neutral placeholder rather than an empty box.
            thumbnail.image = UIImage(systemName: "photo")
            thumbnail.contentMode = .center
            thumbnail.tintColor = DS.Colors.labelSecondary
        }
        switch status {
        case .uploaded:
            badge.image = UIImage(systemName: "checkmark.circle.fill")
            badge.tintColor = DS.Colors.primary
            progressView.isHidden = true
            statusText.text = NSLocalizedString(
                "kyc.review.status.uploaded",
                value: "Uploaded",
                comment: "KYC Review thumbnail badge — artifact committed"
            )
            statusText.textColor = DS.Colors.labelSecondary
            retryButton.isHidden = true
            retakeButton.isHidden = true
        case .uploading(let progress):
            badge.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            badge.tintColor = DS.Colors.labelSecondary
            progressView.isHidden = false
            progressView.setProgress(Float(progress), animated: true)
            statusText.text = NSLocalizedString(
                "kyc.review.status.uploading",
                value: "Uploading…",
                comment: "KYC Review thumbnail badge — artifact upload in progress"
            )
            statusText.textColor = DS.Colors.labelSecondary
            retryButton.isHidden = true
            retakeButton.isHidden = true
        case .failed:
            badge.image = UIImage(systemName: "exclamationmark.triangle.fill")
            badge.tintColor = DS.Colors.destructive
            progressView.isHidden = true
            statusText.text = NSLocalizedString(
                "kyc.review.status.failed",
                value: "Upload failed.",
                comment: "KYC Review thumbnail badge — artifact upload retries exhausted"
            )
            statusText.textColor = DS.Colors.destructive
            retryButton.isHidden = false
            retakeButton.isHidden = false
        case .pending:
            badge.image = UIImage(systemName: "circle.dashed")
            badge.tintColor = DS.Colors.labelSecondary
            progressView.isHidden = true
            statusText.text = NSLocalizedString(
                "kyc.review.status.pending",
                value: "Waiting to upload…",
                comment: "KYC Review thumbnail badge — artifact captured, upload not started"
            )
            statusText.textColor = DS.Colors.labelSecondary
            retryButton.isHidden = true
            retakeButton.isHidden = true
        }
    }

    private static func displayName(for artifact: KYCUploadInitEndpoint.ArtifactType) -> String {
        switch artifact {
        case .face:
            return NSLocalizedString("kyc.artifact.face", value: "Selfie",
                                     comment: "KYC artifact name — face photo")
        case .dlFront:
            return NSLocalizedString("kyc.artifact.dl_front", value: "License front",
                                     comment: "KYC artifact name — driver's license front")
        case .dlBack:
            return NSLocalizedString("kyc.artifact.dl_back", value: "License back",
                                     comment: "KYC artifact name — driver's license back")
        case .truck:
            return NSLocalizedString("kyc.artifact.truck", value: "Truck",
                                     comment: "KYC artifact name — truck photo")
        case .trailer:
            return NSLocalizedString("kyc.artifact.trailer", value: "Trailer",
                                     comment: "KYC artifact name — trailer photo")
        case .plate:
            return NSLocalizedString("kyc.artifact.plate", value: "Plate",
                                     comment: "KYC artifact name — license plate photo")
        }
    }
}
