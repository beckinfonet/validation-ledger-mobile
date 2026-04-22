// validationLedger/Features/Onboarding/Auth/AuthCoordinator.swift
// Phase 3 Plan 09 — D-01: owns the auth UINavigationController.
//
// SceneDelegate (Plan 11) installs `coordinator.rootViewController` as
// `window.rootViewController` for AppPhase.auth. On verify success,
// `onAuthenticated(role:)` bubbles to AppCoordinator → SceneDelegate root-swap
// to .role(role).
//
// Flow: PhoneEntryVC → (on submit) → OTPVC → (on verify) → onAuthenticated(role:)

import UIKit

@MainActor
final class AuthCoordinator {
    let rootViewController: UIViewController
    var onAuthenticated: ((Role) -> Void)?

    private let nav: UINavigationController
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container

        let phoneVM = PhoneEntryViewModel(
            apiClient: container.apiClient,
            location: container.locationProvider,
            countryGate: container.countryGate,
            logger: container.logger
        )
        let phoneVC = PhoneEntryViewController(viewModel: phoneVM)
        let nav = UINavigationController(rootViewController: phoneVC)
        self.nav = nav
        self.rootViewController = nav

        phoneVM.onPhoneSubmitted = { [weak self] otpSessionID in
            self?.pushOTP(otpSessionID: otpSessionID)
        }
    }

    // MARK: - Navigation

    private func pushOTP(otpSessionID: String) {
        let vm = OTPViewModel(
            otpSessionID: otpSessionID,
            apiClient: container.apiClient,
            keychain: container.keychainStore,
            keyStore: container.keyStore,
            biometric: container.biometricService,
            sessionLock: container.sessionLock,
            logger: container.logger
        )
        let vc = OTPViewController(viewModel: vm)
        vm.onAuthenticated = { [weak self] role in
            self?.onAuthenticated?(role)
        }
        nav.pushViewController(vc, animated: true)
    }
}
