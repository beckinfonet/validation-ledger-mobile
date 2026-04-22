// validationLedger/Features/Onboarding/Auth/BiometricLockViewController.swift
// Phase 3 D-13/D-14: full-screen modal overlay presented by SceneDelegate
// (Plan 11) when SessionLockService.lockState != .unlocked. Reason-specific copy
// per D-14. Tap "Unlock" → BiometricService.evaluate. On success → dismiss
// (caller's onUnlockSuccess closure).
//
// Access-level note (matches AuthCoordinator Plan 09 deviation 1): AppContainer is
// internal; any type constructed from container-provided services stays internal.

import UIKit

@MainActor
final class BiometricLockViewController: UIViewController {

    private let reason: LockReason
    private let biometric: any BiometricService
    private let sessionLock: any SessionLockService
    private let onUnlockSuccess: () -> Void
    private let onReBindRequested: () -> Void

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let unlockButton: UIButton

    init(
        reason: LockReason,
        biometric: any BiometricService,
        sessionLock: any SessionLockService,
        onUnlockSuccess: @escaping () -> Void,
        onReBindRequested: @escaping () -> Void = {}
    ) {
        self.reason = reason
        self.biometric = biometric
        self.sessionLock = sessionLock
        self.onUnlockSuccess = onUnlockSuccess
        self.onReBindRequested = onReBindRequested

        var cfg = UIButton.Configuration.borderedProminent()
        cfg.title = "Unlock"
        self.unlockButton = UIButton(configuration: cfg)
        self.unlockButton.accessibilityIdentifier = "biometric-unlock-button"

        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        // VoiceOver: capture focus inside the lock VC so user can't VoiceOver-swipe
        // to elements behind. RESEARCH §iOS API #6 line 908.
        view.accessibilityViewIsModal = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // D-14 reason-specific copy
        switch reason {
        case .coldBoot, .neverUnlocked:
            titleLabel.text = "Welcome back"
            subtitleLabel.text = "Verify identity to continue"
        case .backgroundTimeout:
            titleLabel.text = "Session paused"
            subtitleLabel.text = "Verify to continue"
        case .biometricReEnrolled:
            titleLabel.text = "Biometric changed"
            subtitleLabel.text = "You'll need to re-bind this device"
            var cfg = UIButton.Configuration.bordered()
            cfg.title = "Re-bind device"
            unlockButton.configuration = cfg
        }

        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.textAlignment = .center
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, unlockButton])
        stack.axis = .vertical
        stack.spacing = 24
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
        ])

        unlockButton.addTarget(self, action: #selector(unlockTapped), for: .touchUpInside)

        // Auto-prompt on appear for non-rebinding reasons (D-13 product intent:
        // OS prompt fires immediately, not after manual button tap).
        if reason != .biometricReEnrolled {
            Task { await self.attemptUnlock() }
        }
    }

    @objc private func unlockTapped() {
        if reason == .biometricReEnrolled {
            onReBindRequested()
            return
        }
        Task { await attemptUnlock() }
    }

    private func attemptUnlock() async {
        do {
            try await biometric.evaluate(
                reason: subtitleLabel.text ?? "Verify identity",
                fallback: .devicePasscode  // D-15 — session unlock allows passcode fallback
            )
            sessionLock.recordBiometricSuccess(at: .now)
            onUnlockSuccess()
        } catch {
            // Silent — user retries via Unlock button. Per RESEARCH §iOS API #2:
            // "Don't auto-retry — it confuses the user when the OS prompt vanishes."
        }
    }
}
