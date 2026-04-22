// validationLedger/Features/Onboarding/Auth/PhoneEntryViewController.swift
// Phase 3 Plan 09 — AUTH-01 + D-26 + D-21 + D-22.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md sensitive-surface mandate).
// Thin view layer — product logic lives in PhoneEntryViewModel.
// Pattern follows NetworkConfigToggleViewController (UIStackView + Auto Layout
// via safeAreaLayoutGuide anchors + initializer-DI per ARCH-04).

import UIKit

public final class PhoneEntryViewController: UIViewController {

    private let viewModel: PhoneEntryViewModel

    // MARK: - UI components

    private let prefixLabel: UILabel = {
        let l = UILabel()
        l.text = "+1"
        l.font = .preferredFont(forTextStyle: .body)
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    private let phoneField: UITextField = {
        let f = UITextField()
        f.placeholder = "(555) 123-4567"
        f.keyboardType = .phonePad
        f.borderStyle = .roundedRect
        f.translatesAutoresizingMaskIntoConstraints = false
        f.accessibilityIdentifier = "phone-entry-field"
        return f
    }()

    private let submitButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = "Send code"
        let b = UIButton(configuration: cfg)
        b.isEnabled = false
        b.accessibilityIdentifier = "phone-entry-submit"
        return b
    }()

    private let messageLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 0
        l.textColor = .secondaryLabel
        l.font = .preferredFont(forTextStyle: .footnote)
        l.accessibilityIdentifier = "phone-entry-message"
        return l
    }()

    // MARK: - Init

    public init(viewModel: PhoneEntryViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sign in"
        view.backgroundColor = .systemBackground

        let prefixRow = UIStackView(arrangedSubviews: [prefixLabel, phoneField])
        prefixRow.axis = .horizontal
        prefixRow.spacing = 8
        prefixRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [
            prefixRow,
            submitButton,
            messageLabel
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])

        phoneField.addTarget(self, action: #selector(phoneChanged), for: .editingChanged)
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        viewModel.onStateChange = { [weak self] state in self?.handle(state: state) }
        viewModel.onSubmitEnabledChange = { [weak self] enabled in
            self?.submitButton.isEnabled = enabled
        }
    }

    // MARK: - Actions

    @objc private func phoneChanged() {
        let raw = (phoneField.text ?? "").filter { $0.isNumber }
        let digits = String(raw.prefix(10))
        viewModel.phoneDigits = digits
        phoneField.text = PhoneEntryViewModel.formatDisplay(digits)
    }

    @objc private func submitTapped() {
        Task { await viewModel.submit() }
    }

    // MARK: - State → UI

    private func handle(state: PhoneEntryViewModel.State) {
        switch state {
        case .idle:
            messageLabel.text = ""
        case .needsLocationPermission:
            messageLabel.text = "Location required to verify US-only access."
            presentSettingsAlert()
        case .verifyingLocation:
            messageLabel.text = "Verifying location…"
        case .nonUSCountry:
            pushNotAvailableInRegion()
        case .requestingOTP:
            messageLabel.text = "Sending code…"
        case .otpRequested:
            // AuthCoordinator observes onPhoneSubmitted and pushes OTPVC; no UI change here.
            messageLabel.text = ""
        case .error(let msg):
            messageLabel.text = msg
        }
    }

    // MARK: - D-21 Open-Settings alert

    private func presentSettingsAlert() {
        let alert = UIAlertController(
            title: "Location required",
            message: "Validation Ledger needs your location at sign-in to verify you're in the United States.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - D-22 non-US push

    private func pushNotAvailableInRegion() {
        let vc = NotAvailableInRegionViewController()
        navigationController?.pushViewController(vc, animated: true)
    }
}
