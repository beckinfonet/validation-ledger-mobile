// validationLedger/Features/Profile/ProfileViewController.swift
// Phase 3 D-03 / AUTH-04: presented modally from each role's tab bar avatar
// affordance (Plan 11 wires the avatar). M1 surface = a Log out button;
// future M2+ adds account settings + KYC status.
//
// Threat model:
//   T-03-10-02 (mitigate): LogoutService.logout is AWAITED before dismiss;
//   notification posts as the LAST step in LogoutService (Pitfall 3). Observers
//   see fully-cleared state; Profile dismisses only after teardown completes.

import UIKit

final class ProfileViewController: UIViewController {

    private let logoutService: any LogoutService

    init(logoutService: any LogoutService) {
        self.logoutService = logoutService
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissSelf)
        )

        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = "Log out"
        cfg.baseBackgroundColor = .systemRed
        let logoutButton = UIButton(configuration: cfg)
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
        logoutButton.accessibilityIdentifier = "profile-logout"
        logoutButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(logoutButton)
        NSLayoutConstraint.activate([
            logoutButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            logoutButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            logoutButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }

    @objc private func dismissSelf() { dismiss(animated: true) }

    @objc private func logoutTapped() {
        // SceneDelegate observer (Plan 11) handles the .sessionDidInvalidate Notification
        // → roots-swap to .auth. We just kick the LogoutService funnel and dismiss.
        Task {
            await logoutService.logout(reason: .userInitiated)
            dismiss(animated: true)
        }
    }
}
