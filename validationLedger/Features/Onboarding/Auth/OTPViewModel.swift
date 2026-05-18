// validationLedger/Features/Onboarding/Auth/OTPViewModel.swift
// Phase 3 Plan 09 — AUTH-02 + AUTH-03 + D-02 + D-06 + D-27.
//
// Drives the OTP verification + post-verify device registration flow.
// After successful OTPVerify, runs the D-27 7-step orchestration:
//   1. OTPVerify — sessionToken/role/userID returned
//   2. Persist sessionToken/role/userID to Keychain (D-06/AUTH-03)
//   3. generateDeviceIdentityKeys (DEV-01/DEV-02)
//   4. (combined with 3 — single protocol call)
//   5. POST /device/register with devicePublicKey + DeviceFingerprint (DEV-05)
//   6. BiometricService.evaluate(reason:fallback: .none) — records initial
//      evaluatedPolicyDomainState for SESS-03 re-enrollment detection (D-09)
//   7. Return role via onAuthenticated — AppCoordinator root-swaps to .role(role)
//
// Rate-limit handling (AUTH-02 / D-02):
//   - APIClient surfaces HTTP 429 as NetworkError.rateLimited(retryAfter:)
//     (Plan 05). OTPViewModel pattern-matches this and starts a 1-Hz Timer
//     that drives a .rateLimited(remaining:) state. Verify button disables
//     while rateLimited is non-zero; on reach 0 → state resets to .idle and
//     verifyEnabled re-computes against code length.
//
// State exposed via `onStateChange` closure per UIKit-first stance.

import Foundation

@MainActor
public final class OTPViewModel {

    // MARK: - State

    public enum State: Equatable, Sendable {
        case idle
        case verifying
        case settingUp(progress: Int, total: Int)
        case rateLimited(remainingSeconds: Int)
        case registerFailed          // D-27 step 5 failure — keychain NOT cleared; retry-able
        case error(message: String)
        case success(role: Role)
    }

    public private(set) var state: State = .idle {
        didSet {
            onStateChange?(state)
            onVerifyEnabledChange?(verifyEnabled)
        }
    }

    public var code: String = "" {
        didSet { onVerifyEnabledChange?(verifyEnabled) }
    }

    public var verifyEnabled: Bool {
        switch state {
        case .rateLimited: return false
        default: return code.count == 6
        }
    }

    // MARK: - Callbacks

    public var onStateChange: ((State) -> Void)?
    public var onVerifyEnabledChange: ((Bool) -> Void)?

    /// Fires when the verified user's `kycStatus == "verified"` — route to the
    /// role shell. (D-12: a non-verified user fires `onKYCRequired` instead.)
    public var onAuthenticated: ((Role) -> Void)?

    /// Phase 5 D-12: fires when OTP-verify succeeds but the response's
    /// `kycStatus` is absent or != "verified" — the user must complete KYC before
    /// the role shell is reachable. AuthCoordinator forwards this to
    /// `AppCoordinator`, which root-swaps to `AppPhase.kyc(role)`. Routing
    /// fails CLOSED: any non-"verified" value (including `nil`) routes to the
    /// KYC gate, never the role shell (threat T-05-07-02).
    public var onKYCRequired: ((Role) -> Void)?

    // MARK: - Dependencies (initializer-DI per ARCH-04)

    private let otpSessionID: String
    private let apiClient: APIClient
    private let keychain: KeychainStore
    private let keyStore: any KeyStoreProtocol
    private let biometric: any BiometricService
    private let sessionLock: any SessionLockService
    private let logger: any Logger

    private var countdownTimer: Timer?

    public init(
        otpSessionID: String,
        apiClient: APIClient,
        keychain: KeychainStore,
        keyStore: any KeyStoreProtocol,
        biometric: any BiometricService,
        sessionLock: any SessionLockService,
        logger: any Logger
    ) {
        self.otpSessionID = otpSessionID
        self.apiClient = apiClient
        self.keychain = keychain
        self.keyStore = keyStore
        self.biometric = biometric
        self.sessionLock = sessionLock
        self.logger = logger
    }

    deinit {
        // Timer invalidate is MainActor-safe on its scheduling run loop;
        // since this type is MainActor-bound and the timer was scheduled on
        // .main, invalidating here is correct.
        countdownTimer?.invalidate()
    }

    // MARK: - verify() — D-27 7-step orchestration

    public func verify() async {
        guard verifyEnabled else { return }
        state = .verifying

        // === STEP 1: OTP verify ===
        let verifyResp: OTPVerifyEndpoint.Response
        do {
            verifyResp = try await apiClient.request(
                OTPVerifyEndpoint(otpSessionID: otpSessionID, code: code)
            )
        } catch let NetworkError.rateLimited(retryAfter) {
            startCountdown(seconds: Int(retryAfter))
            return
        } catch let NetworkError.httpError(statusCode, _) where statusCode == 401 {
            state = .error(message: "Invalid code. Try again.")
            return
        } catch {
            logger.error(event: .init("otp_verify_failed"),
                         fields: [.event: String(describing: error)])
            state = .error(message: "Verification failed. Try again.")
            return
        }

        // === STEP 2: Persist session metadata to Keychain (D-06 / AUTH-03) ===
        state = .settingUp(progress: 1, total: 6)
        do {
            try keychain.set(Data(verifyResp.sessionToken.utf8),
                             for: .sessionToken,
                             accessibility: .afterFirstUnlockThisDeviceOnly)
            try keychain.set(Data(verifyResp.role.utf8),
                             for: .sessionRole,
                             accessibility: .afterFirstUnlockThisDeviceOnly)
            try keychain.set(Data(verifyResp.userID.utf8),
                             for: .sessionUserID,
                             accessibility: .afterFirstUnlockThisDeviceOnly)
            // Phase 5 D-13: cache the OTP-verify response's `kycStatus` so cold
            // boot can route on it (SessionRestoreService.probe reads this key).
            // The field is OPTIONAL — pre-Phase-5 fixtures omit it; when absent we
            // persist nothing and the cold-boot probe sees no cached value, which
            // fails CLOSED to the KYC gate (T-05-07-02). When present, persist it
            // under the same .afterFirstUnlockThisDeviceOnly class as sessionRole.
            if let kycStatus = verifyResp.kycStatus {
                try keychain.set(Data(kycStatus.utf8),
                                 for: .kycStatus,
                                 accessibility: .afterFirstUnlockThisDeviceOnly)
            } else {
                // No cached status — clear any stale prior value so the probe
                // does not route on a previous session's KYC state.
                try keychain.delete(.kycStatus)
            }
        } catch {
            logger.error(event: .init("otp_verify_keychain_failed"),
                         fields: [.event: String(describing: error)])
            state = .error(message: "Could not persist session. Try again.")
            return
        }

        // === STEPS 3+4: Generate device + authorization keys (DEV-01/DEV-02) ===
        state = .settingUp(progress: 2, total: 6)
        let devicePub: Data
        let authPub: Data
        do {
            let keys = try keyStore.generateDeviceIdentityKeys()
            devicePub = keys.devicePublicKey
            authPub = keys.authorizationPublicKey
        } catch {
            logger.error(event: .init("otp_verify_keygen_failed"),
                         fields: [.event: String(describing: error)])
            state = .error(message: "Could not set up this device. Try again.")
            return
        }

        // === STEP 5: POST /device/register (DEV-05 + D-02 three-key payload) ===
        // Phase 4 (04-04): Endpoint now carries the full three-key contract (D-02)
        // plus attestationStatus (D-09). Until Plan 03 wires DCAppAttestAttestationService,
        // OTPViewModel passes attestationStatus: .unsupported with nil attestation fields
        // — the omission rule (D-09) keeps those fields out of the wire payload.
        // Plan 06 AppContainer wiring will replace this with an AttestationService call
        // that returns the real status + optional attestedKeyId/attestationObject.
        state = .settingUp(progress: 4, total: 6)
        do {
            let fingerprint = try DeviceFingerprint.current(keychain: keychain)
            let payload = DeviceRegisterEndpoint.DeviceFingerprintPayload(
                model: fingerprint.model,
                iosVersion: fingerprint.iosVersion,
                installUUID: fingerprint.installUUID
            )
            _ = try await apiClient.request(
                DeviceRegisterEndpoint(
                    devicePublicKey: devicePub.base64EncodedString(),
                    authorizationPublicKey: authPub.base64EncodedString(),
                    attestedKeyId: nil,
                    attestationObject: nil,
                    attestationStatus: .unsupported,
                    fingerprint: payload
                )
            )
        } catch {
            logger.warn(event: .init("device_register_failed"),
                        fields: [.event: String(describing: error)])
            // D-27 step 5 failure does NOT clear keychain — retry-able via retryRegister().
            state = .registerFailed
            return
        }

        // === STEP 6: BiometricService.evaluate — records initial domainState (D-09) ===
        state = .settingUp(progress: 5, total: 6)
        do {
            try await biometric.evaluate(reason: "Sign in to Validation Ledger", fallback: .none)
            sessionLock.recordBiometricSuccess(at: .now)
        } catch {
            // Sim has no biometric hardware — still allow flow to proceed. SC-2 HUMAN-UAT
            // catches missing prompt on real device (T-03-09-04 accepted mitigation).
            logger.warn(event: .init("initial_biometric_failed_sim_or_cancel"),
                        fields: [.event: String(describing: error)])
        }

        // === STEP 7: Surface role to AuthCoordinator ===
        state = .settingUp(progress: 6, total: 6)
        guard let role = Role(rawValue: verifyResp.role) else {
            state = .error(message: "Unknown role: \(verifyResp.role)")
            return
        }
        state = .success(role: role)
        // Phase 5 D-12: route on the verified KYC status. A user whose
        // `kycStatus == "verified"` goes straight to the role shell; any other
        // value (including `nil`) routes into the `.kyc` hard gate — the role
        // shell is unreachable until KYC is submitted. Fails CLOSED (T-05-07-02).
        if verifyResp.kycStatus == "verified" {
            onAuthenticated?(role)
        } else {
            onKYCRequired?(role)
        }
    }

    // MARK: - Retry-After countdown (AUTH-02 / D-02)

    private func startCountdown(seconds: Int) {
        state = .rateLimited(remainingSeconds: max(0, seconds))
        countdownTimer?.invalidate()
        var remaining = max(0, seconds)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                remaining -= 1
                if remaining <= 0 {
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                    self.state = .idle
                } else {
                    self.state = .rateLimited(remainingSeconds: remaining)
                }
            }
        }
    }

    // MARK: - Recovery (D-27 step 5 failure)

    /// Re-runs the full verify() sequence. Idempotent because:
    ///  - Keychain.set is upsert
    ///  - generateDeviceIdentityKeys regenerates missing slots but is safe to
    ///    re-call (Plan 02 CR-02 + Plan 04 idempotency guards)
    ///  - /device/register is Idempotency-Key-protected (NET-04)
    public func retryRegister() async {
        guard case .registerFailed = state else { return }
        await verify()
    }
}
