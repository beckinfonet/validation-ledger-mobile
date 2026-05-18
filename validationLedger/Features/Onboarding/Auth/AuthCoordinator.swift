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

    /// Fires when OTP-verify succeeds AND the user's `kycStatus == "verified"` —
    /// AppCoordinator root-swaps to the role shell.
    var onAuthenticated: ((Role) -> Void)?

    /// Phase 5 D-12: fires when OTP-verify succeeds but the user is not yet
    /// KYC-verified — AppCoordinator root-swaps to `AppPhase.kyc(role)`, the KYC
    /// hard gate. Bubbled from `OTPViewModel.onKYCRequired`.
    var onKYCRequired: ((Role) -> Void)?

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
            // Phase 6 DEV-04: STEP 5 first-login App Attest. AppContainer
            // selects the concrete impl (DCAppAttest on device /
            // SimulatorBypass under #if DEBUG && targetEnvironment(simulator)).
            attestationService: container.attestationService,
            logger: container.logger
        )
        let vc = OTPViewController(viewModel: vm)
        vm.onAuthenticated = { [weak self] role in
            self?.onAuthenticated?(role)
        }
        // Phase 5 D-12: a not-yet-KYC-verified user bubbles up through onKYCRequired.
        vm.onKYCRequired = { [weak self] role in
            self?.onKYCRequired?(role)
        }
        nav.pushViewController(vc, animated: true)
    }
}
