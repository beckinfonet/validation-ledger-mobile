// validationLedger/Features/Onboarding/KYC/Capture/DLFrontExtractionViewController.swift
// Phase 5 Plan 05 — KYC-03 / D-05: the read-only DL extraction confirmation.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md hard constraint). Shows the
// `DataScanner`-extracted name / DL number / expiry READ-ONLY — the user CANNOT
// hand-edit them (anti-feature A13 / threat T-05-05-01: editable identity fields
// are a fraud vector; the uploaded photo is authoritative). The fields are plain
// `UILabel`s inside a `DS.Colors.surface` container — there is NO `UITextField`
// on this screen.
//
// === D-05 FORMAT GATE ===
// On appear, `DLFieldFormatValidator` runs over the extracted fields. On a
// format failure the screen auto-prompts a rescan with the UI-SPEC "That scan
// didn't come through clearly…" copy. "Looks good" advances; "Rescan" returns to
// the scanner.

import UIKit

/// The read-only DL extraction confirmation screen (KYC-03 / D-05).
final class DLFrontExtractionViewController: UIViewController {

    /// Fired when the user confirms ("Looks good"). `KYCCoordinator` advances.
    var onConfirmed: (() -> Void)?

    /// Fired when a rescan is needed — either the user tapped "Rescan" or the
    /// format check auto-prompted one. `KYCCoordinator` returns to the scanner.
    var onRescanRequested: (() -> Void)?

    private let extraction: DLExtraction
    private let formatValidator = DLFieldFormatValidator()

    // MARK: - UI components

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.title1
        label.textColor = DS.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.accessibilityIdentifier = "kyc-extraction-title"
        return label
    }()

    /// Inline format-failure notice (D-05) — hidden unless the gate fails.
    private let formatErrorLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.footnote
        label.textColor = .systemRed
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.isHidden = true
        label.accessibilityIdentifier = "kyc-extraction-format-error"
        return label
    }()

    private let confirmButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = NSLocalizedString(
            "kyc.extraction.cta",
            value: "Looks good",
            comment: "DL extraction confirm CTA (D-05)"
        )
        let button = UIButton(configuration: cfg)
        button.accessibilityIdentifier = "kyc-extraction-confirm"
        return button
    }()

    private let rescanButton: UIButton = {
        var cfg = UIButton.Configuration.plain()
        cfg.title = NSLocalizedString(
            "kyc.extraction.rescan",
            value: "Rescan",
            comment: "DL extraction rescan action (D-05)"
        )
        let button = UIButton(configuration: cfg)
        button.accessibilityIdentifier = "kyc-extraction-rescan"
        return button
    }()

    // MARK: - Init

    init(extraction: DLExtraction) {
        self.extraction = extraction
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

        titleLabel.text = NSLocalizedString(
            "kyc.extraction.title",
            value: "Does this look right?",
            comment: "DL extraction confirmation title (D-05)"
        )
        formatErrorLabel.text = NSLocalizedString(
            "kyc.extraction.format_fail",
            value: "That scan didn't come through clearly — let's try again.",
            comment: "DL extraction format-failure copy (D-05)"
        )

        // Read-only field rows — plain labels inside a surface container. NO
        // UITextField anywhere on this screen (D-05 / threat T-05-05-01).
        let fieldsContainer = makeFieldsContainer()

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, fieldsContainer, formatErrorLabel, confirmButton, rescanButton,
        ])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.md
        stack.alignment = .fill
        stack.setCustomSpacing(DS.Spacing.xl, after: formatErrorLabel)
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
            // 44pt touch-target floor on both controls (UI-SPEC).
            confirmButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            rescanButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        rescanButton.addTarget(self, action: #selector(rescanTapped), for: .touchUpInside)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        runFormatGate()
    }

    // MARK: - D-05 format gate

    /// Run `DLFieldFormatValidator` over the extracted fields. On a failure the
    /// inline notice is shown, the confirm CTA is disabled, and a rescan is
    /// auto-prompted (D-05).
    private func runFormatGate() {
        let result = formatValidator.validate(
            name: extraction.name,
            dlNumber: extraction.dlNumber,
            expiry: extraction.expiry
        )
        if result.isValid {
            formatErrorLabel.isHidden = true
            confirmButton.isEnabled = true
        } else {
            formatErrorLabel.isHidden = false
            confirmButton.isEnabled = false
            // D-05 — auto-prompt the rescan on a format failure.
            onRescanRequested?()
        }
    }

    // MARK: - Read-only field rows

    /// A `DS.Colors.surface` container of read-only label rows. There is
    /// deliberately no editable control here (D-05 / anti-feature A13).
    private func makeFieldsContainer() -> UIView {
        let container = UIView()
        container.backgroundColor = DS.Colors.surface
        container.layer.cornerRadius = DS.Spacing.sm
        container.translatesAutoresizingMaskIntoConstraints = false

        let rows = UIStackView(arrangedSubviews: [
            makeFieldRow(
                label: NSLocalizedString(
                    "kyc.extraction.field.name",
                    value: "Name",
                    comment: "DL extraction field label"
                ),
                value: extraction.name,
                identifier: "kyc-extraction-name"
            ),
            makeFieldRow(
                label: NSLocalizedString(
                    "kyc.extraction.field.dlnumber",
                    value: "License number",
                    comment: "DL extraction field label"
                ),
                value: extraction.dlNumber,
                identifier: "kyc-extraction-dlnumber"
            ),
            makeFieldRow(
                label: NSLocalizedString(
                    "kyc.extraction.field.expiry",
                    value: "Expiration",
                    comment: "DL extraction field label"
                ),
                value: extraction.expiry,
                identifier: "kyc-extraction-expiry"
            ),
        ])
        rows.axis = .vertical
        rows.spacing = DS.Spacing.sm
        rows.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: container.topAnchor, constant: DS.Spacing.md),
            rows.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DS.Spacing.md),
            rows.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DS.Spacing.md),
            rows.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DS.Spacing.md),
        ])
        return container
    }

    /// One read-only field row: a caption label + the extracted value as a
    /// plain `UILabel` (never a `UITextField` — D-05).
    private func makeFieldRow(label: String, value: String, identifier: String) -> UIView {
        let captionLabel = UILabel()
        captionLabel.text = label
        captionLabel.font = DS.Typography.footnote
        captionLabel.textColor = DS.Colors.labelSecondary
        captionLabel.adjustsFontForContentSizeCategory = true

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = DS.Typography.body
        valueLabel.textColor = DS.Colors.label
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.numberOfLines = 0
        valueLabel.accessibilityIdentifier = identifier

        let row = UIStackView(arrangedSubviews: [captionLabel, valueLabel])
        row.axis = .vertical
        row.spacing = DS.Spacing.xs
        return row
    }

    // MARK: - Actions

    @objc private func confirmTapped() {
        onConfirmed?()
    }

    @objc private func rescanTapped() {
        onRescanRequested?()
    }
}
