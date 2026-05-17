// validationLedger/Features/Profile/ProfileViewController.swift
// Phase 3 D-03 / AUTH-04: presented modally from each role's tab bar avatar
// affordance (Plan 11 wires the avatar). M1 surface = a Log out button +
// (Phase 5 D-08) a "Verification status" row.
//
// === Phase 5 D-08 — the KYC status screen's SECOND entry point ===
// The KYC status screen has two entry points (D-08): the post-submit push
// (KYCCoordinator.pushStatus) and — here — a role-shell re-entry row so a
// verified or under-review user can re-check status WITHOUT re-running KYC.
// It is the SAME single status screen plan 06 built; this row simply opens it.
//
// ARCH-05 (one feature module never imports a sibling feature module): the
// Profile feature does NOT construct `KYCStatusViewController` itself — that VC
// belongs to the Onboarding/KYC feature. Instead the composition root
// (`AppContainer`) hands this VC a `kycStatusScreenFactory` closure built from
// `Core/` deps (apiClient / kycSessionStore / logger). The closure is opaque
// here — its return type is a bare `UIViewController` — so this file never
// names an Onboarding type and never declares a cross-feature module import.
//
// Threat model:
//   T-03-10-02 (mitigate): LogoutService.logout is AWAITED before dismiss;
//   notification posts as the LAST step in LogoutService (Pitfall 3). Observers
//   see fully-cleared state; Profile dismisses only after teardown completes.
//   T-05-08-03 (accept): the KYC status row exists only inside the role shell,
//   which is only reachable post-verification (D-12 gate, plan 07). An
//   unverified user is inside KYCCoordinator and has no Profile tab — the row
//   cannot be a gate bypass.

import UIKit

final class ProfileViewController: UIViewController {

    private let logoutService: any LogoutService

    /// D-08 — builds the KYC status screen on demand. Supplied by the
    /// composition root (`AppContainer`) from `Core/` dependencies so
    /// `Features/Profile` never cross-imports `Features/Onboarding` (ARCH-05).
    /// `nil` (the default) hides the row — keeps every existing caller and the
    /// Phase-3 tests unchanged.
    private let kycStatusScreenFactory: (() -> UIViewController)?

    init(
        logoutService: any LogoutService,
        kycStatusScreenFactory: (() -> UIViewController)? = nil
    ) {
        self.logoutService = logoutService
        self.kycStatusScreenFactory = kycStatusScreenFactory
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

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        // D-08 — "Verification status" row, styled like the "Log out" row.
        // Only shown when the composition root supplied the factory (i.e. in
        // the role shell). Tapping it pushes the SAME KYC status screen plan 06
        // built; that screen re-fetches GET /kyc/status on appear (D-09).
        if kycStatusScreenFactory != nil {
            var statusCfg = UIButton.Configuration.bordered()
            statusCfg.title = NSLocalizedString(
                "profile.kyc_status.row",
                value: "Verification status",
                comment: "Profile screen — opens the KYC status screen (D-08 re-entry)"
            )
            statusCfg.image = UIImage(systemName: "checkmark.shield")
            statusCfg.imagePadding = 8
            let statusButton = UIButton(configuration: statusCfg)
            statusButton.contentHorizontalAlignment = .leading
            statusButton.addTarget(self, action: #selector(kycStatusTapped), for: .touchUpInside)
            statusButton.accessibilityIdentifier = "profile-kyc-status"
            contentStack.addArrangedSubview(statusButton)
        }

        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = "Log out"
        cfg.baseBackgroundColor = .systemRed
        let logoutButton = UIButton(configuration: cfg)
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
        logoutButton.accessibilityIdentifier = "profile-logout"
        logoutButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(logoutButton)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),

            logoutButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            logoutButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            logoutButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }

    @objc private func dismissSelf() { dismiss(animated: true) }

    // MARK: - D-08 — KYC status re-entry

    /// Open the KYC status screen — the same single screen plan 06 built. It is
    /// pushed onto Profile's own navigation controller (Profile is presented in
    /// a `UINavigationController`, see `RoleCoordinator.wrapTabsWithNavAndInstallAvatar`);
    /// `KYCStatusViewController.viewWillAppear` re-fetches GET /kyc/status (D-09).
    @objc private func kycStatusTapped() {
        guard let factory = kycStatusScreenFactory else { return }
        let statusVC = factory()
        if let nav = navigationController {
            nav.pushViewController(statusVC, animated: true)
        } else {
            // Defensive: if Profile is somehow presented without a nav stack,
            // present the status screen modally rather than dropping the tap.
            present(UINavigationController(rootViewController: statusVC), animated: true)
        }
    }

    @objc private func logoutTapped() {
        // SceneDelegate observer (Plan 11) handles the .sessionDidInvalidate Notification
        // → roots-swap to .auth. We just kick the LogoutService funnel and dismiss.
        Task {
            await logoutService.logout(reason: .userInitiated)
            dismiss(animated: true)
        }
    }
}
