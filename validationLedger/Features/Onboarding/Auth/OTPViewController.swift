// validationLedger/Features/Onboarding/Auth/OTPViewController.swift
// Phase 3 Plan 09 — AUTH-02 + AUTH-03 + D-02 + D-27.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md sensitive-surface mandate).
// Thin view layer — product logic lives in OTPViewModel.
//
// Key state-to-UI mappings:
//   .idle / .verifying / .settingUp  → Verify button + progress text
//   .rateLimited(remaining)          → countdown label + Verify button disabled
//   .registerFailed                  → Retry button revealed
//   .error(message)                  → inline error label

import UIKit

public final class OTPViewController: UIViewController {

    private let viewModel: OTPViewModel

    // MARK: - UI components

    private let codeField: UITextField = {
        let f = UITextField()
        f.placeholder = "123456"
        f.keyboardType = .numberPad
        f.borderStyle = .roundedRect
        f.translatesAutoresizingMaskIntoConstraints = false
        f.accessibilityIdentifier = "otp-field"
        return f
    }()

    private let verifyButton: UIButton = {
        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = "Verify"
        let b = UIButton(configuration: cfg)
        b.isEnabled = false
        b.accessibilityIdentifier = "otp-verify"
        return b
    }()

    private let countdownLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .footnote)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.accessibilityIdentifier = "otp-countdown"
        return l
    }()

    private let progressLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .footnote)
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        l.accessibilityIdentifier = "otp-progress"
        return l
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let i = UIActivityIndicatorView(style: .medium)
        i.hidesWhenStopped = true
        return i
    }()

    private let retryButton: UIButton = {
        var cfg = UIButton.Configuration.bordered()
        cfg.title = "Retry device setup"
        let b = UIButton(configuration: cfg)
        b.isHidden = true
        b.accessibilityIdentifier = "otp-retry"
        return b
    }()

    private let errorLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 0
        l.textColor = .systemRed
        l.font = .preferredFont(forTextStyle: .footnote)
        l.accessibilityIdentifier = "otp-error"
        return l
    }()

    // MARK: - Init

    public init(viewModel: OTPViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Enter code"
        view.backgroundColor = .systemBackground

        let stack = UIStackView(arrangedSubviews: [
            codeField,
            verifyButton,
            countdownLabel,
            activityIndicator,
            progressLabel,
            retryButton,
            errorLabel
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])

        codeField.addTarget(self, action: #selector(codeChanged), for: .editingChanged)
        verifyButton.addTarget(self, action: #selector(verifyTapped), for: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        viewModel.onStateChange = { [weak self] state in self?.handle(state: state) }
        viewModel.onVerifyEnabledChange = { [weak self] enabled in
            self?.verifyButton.isEnabled = enabled
        }
    }

    // MARK: - Actions

    @objc private func codeChanged() {
        let raw = (codeField.text ?? "").filter { $0.isNumber }
        let digits = String(raw.prefix(6))
        viewModel.code = digits
        if codeField.text != digits {
            codeField.text = digits
        }
    }

    @objc private func verifyTapped() {
        Task { await viewModel.verify() }
    }

    @objc private func retryTapped() {
        Task { await viewModel.retryRegister() }
    }

    // MARK: - State → UI

    private func handle(state: OTPViewModel.State) {
        switch state {
        case .idle:
            countdownLabel.text = ""
            progressLabel.text = ""
            errorLabel.text = ""
            retryButton.isHidden = true
            activityIndicator.stopAnimating()
        case .verifying:
            countdownLabel.text = ""
            progressLabel.text = "Verifying…"
            errorLabel.text = ""
            retryButton.isHidden = true
            activityIndicator.startAnimating()
        case .settingUp(let progress, let total):
            countdownLabel.text = ""
            progressLabel.text = "Setting up your account (\(progress)/\(total))…"
            errorLabel.text = ""
            retryButton.isHidden = true
            activityIndicator.startAnimating()
        case .rateLimited(let remaining):
            countdownLabel.text = "Try again in \(remaining)s"
            progressLabel.text = ""
            errorLabel.text = ""
            retryButton.isHidden = true
            activityIndicator.stopAnimating()
        case .registerFailed:
            countdownLabel.text = ""
            progressLabel.text = ""
            errorLabel.text = "Device setup failed. Try again."
            retryButton.isHidden = false
            activityIndicator.stopAnimating()
        case .error(let msg):
            countdownLabel.text = ""
            progressLabel.text = ""
            errorLabel.text = msg
            retryButton.isHidden = true
            activityIndicator.stopAnimating()
        case .success:
            // AuthCoordinator observes onAuthenticated and root-swaps; no UI change here.
            activityIndicator.stopAnimating()
        }
    }
}
