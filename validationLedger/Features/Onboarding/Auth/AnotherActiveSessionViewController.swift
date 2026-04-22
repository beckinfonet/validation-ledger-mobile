// validationLedger/Features/Onboarding/Auth/AnotherActiveSessionViewController.swift
// Phase 3 D-18/D-19/DEV-06: shown when LogoutReason.anotherActiveSession fires.
// M1 placeholder — re-KYC switch flow itself is M2+.
//
// Threat model:
//   T-03-10-03 (accept): supportEmail is a public constant; mailto: subject carries
//   no user-identifying info ("Switch device request").

import UIKit

final class AnotherActiveSessionViewController: UIViewController {

    private let supportEmail: String

    init(supportEmail: String = Environment.supportEmail) {
        self.supportEmail = supportEmail
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Already signed in"
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Another device is signed in"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = "Validation Ledger allows one active device per user. To switch devices, contact support to re-verify your identity."
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        var cfg = UIButton.Configuration.bordered()
        cfg.title = "Contact support"
        let supportButton = UIButton(configuration: cfg)
        supportButton.addTarget(self, action: #selector(contactSupport), for: .touchUpInside)
        supportButton.accessibilityIdentifier = "another-session-contact-support"

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, supportButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }

    @objc private func contactSupport() {
        guard let url = URL(string: "mailto:\(supportEmail)?subject=Switch%20device%20request") else { return }
        UIApplication.shared.open(url)
    }
}
