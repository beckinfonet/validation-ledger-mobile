// validationLedger/Features/Onboarding/Auth/OTPViewModel.swift
// Phase 3 Plan 09 — AUTH-02 + AUTH-03 + D-02 + D-06 + D-27.
// Phase 6 Plan 02 — DEV-04: STEP 5 first-login App Attest orchestration.
//
// Drives the OTP verification + post-verify device registration flow.
// After successful OTPVerify, runs the D-27 7-step orchestration:
//   1. OTPVerify — sessionToken/role/userID returned
//   2. Persist sessionToken/role/userID to Keychain (D-06/AUTH-03)
//   3. generateDeviceIdentityKeys (DEV-01/DEV-02)
//   4. (combined with 3 — single protocol call)
//   5. App Attest + POST /device/register (DEV-04 / Phase 6):
//      generateKeyIfNeeded() -> GET /device/challenge -> attestKey() -> POST
//      /device/register with the real attestation payload + DeviceFingerprint
//      (DEV-05). The captured register response's trustTier is persisted to
//      Keychain via AttestedKeyStore.writeTrustTier (D6-01).
//   6. BiometricService.evaluate(reason:fallback: .none) — records initial
//      evaluatedPolicyDomainState for SESS-03 re-enrollment detection (D-09)
//   7. Return role via onAuthenticated — AppCoordinator root-swaps to .role(role)
//
// STEP 5 attestation postures (Phase 6 / 06-RESEARCH):
//   - D6-04 graceful skip: a non-.attested / non-.simulatorBypass status is
//     carried into the register payload with nil attestedKeyId/attestationObject;
//     login STILL completes (unlike the heartbeat path which returns early).
//   - D6-05 degrade-and-continue: a transient attestation failure (challenge
//     fetch throws or attestKey throws) degrades the payload to
//     attestationStatus = .error with nil fields, and STILL POSTs /device/register.
//     App Attest is never a login gate.
//   - D6-06 challengeExpired retry: a `challengeExpired` server error on the
//     register POST refetches the challenge, re-attests, and retries the POST
//     exactly ONCE. A second consecutive expiry surfaces as .registerFailed.
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
    /// Phase 6 DEV-04 (D6-01): App Attest service for the STEP 5 first-login
    /// orchestration. AppContainer selects the concrete impl (DCAppAttest on
    /// device / SimulatorBypass under #if DEBUG && targetEnvironment(simulator))
    /// and injects it through this initializer — OTPViewModel just consumes it.
    private let attestationService: any AttestationService
    private let logger: any Logger

    /// Phase 6 DEV-04 (D6-01): the Keychain hand-off channel for the
    /// backend-driven trust tier. Constructed internally from the already-held
    /// `keychain` — mirrors `SceneDelegate.performHeartbeatIfNeeded`, which
    /// builds `AttestedKeyStore(keychain:)` the same way rather than injecting
    /// the store directly.
    private let attestedKeyStore: AttestedKeyStore

    private var countdownTimer: Timer?

    public init(
        otpSessionID: String,
        apiClient: APIClient,
        keychain: KeychainStore,
        keyStore: any KeyStoreProtocol,
        biometric: any BiometricService,
        sessionLock: any SessionLockService,
        attestationService: any AttestationService,
        logger: any Logger
    ) {
        self.otpSessionID = otpSessionID
        self.apiClient = apiClient
        self.keychain = keychain
        self.keyStore = keyStore
        self.biometric = biometric
        self.sessionLock = sessionLock
        self.attestationService = attestationService
        self.attestedKeyStore = AttestedKeyStore(keychain: keychain)
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

        // === STEP 5: App Attest + POST /device/register (DEV-04 + D-02 three-key) ===
        // Phase 6 fulfills the DEV-04 gap: STEP 5 now fires App Attest before the
        // register POST. generateKeyIfNeeded() -> GET /device/challenge ->
        // attestKey() produces the real attestation payload; a non-.attested
        // status or a transient failure degrades gracefully (D6-04 / D6-05) and
        // login is never blocked. The captured register response's trustTier is
        // persisted to Keychain (D6-01). The progress slot stays at 4/6 — the
        // attestation work folds into the existing STEP 5 slot (06-RESEARCH A3).
        state = .settingUp(progress: 4, total: 6)
        let fingerprintPayload: DeviceRegisterEndpoint.DeviceFingerprintPayload
        do {
            let fingerprint = try DeviceFingerprint.current(keychain: keychain)
            fingerprintPayload = DeviceRegisterEndpoint.DeviceFingerprintPayload(
                model: fingerprint.model,
                iosVersion: fingerprint.iosVersion,
                installUUID: fingerprint.installUUID
            )
        } catch {
            logger.warn(event: .init("device_register_failed"),
                        fields: [.event: String(describing: error)])
            // D-27 step 5 failure does NOT clear keychain — retry-able via retryRegister().
            state = .registerFailed
            return
        }

        // D6-04 / D6-05: build the attestation fields. Never throws — a
        // non-.attested status or a transient failure both resolve to a
        // graceful fields tuple (nil keyId/object + a degraded status).
        var attestation = await buildAttestationFields()

        let registerResponse: DeviceRegisterEndpoint.Response
        do {
            do {
                registerResponse = try await postDeviceRegister(
                    devicePub: devicePub,
                    authPub: authPub,
                    attestation: attestation,
                    fingerprint: fingerprintPayload
                )
            } catch let NetworkError.httpError(_, data)
                where AttestationErrorResponseInterceptor.extractErrorCode(from: data) == "challengeExpired" {
                // D6-06: the backend rejected a stale challenge. Refetch the
                // challenge, re-attest, and retry the register POST exactly ONCE.
                // A second consecutive challengeExpired (or any other failure on
                // the retry) is NOT retried again — it surfaces below.
                logger.warn(event: .init("attestation_first_login_challenge_expired_retry"),
                            fields: [:])
                attestation = await buildAttestationFields()
                registerResponse = try await postDeviceRegister(
                    devicePub: devicePub,
                    authPub: authPub,
                    attestation: attestation,
                    fingerprint: fingerprintPayload
                )
            }
        } catch {
            logger.warn(event: .init("device_register_failed"),
                        fields: [.event: String(describing: error)])
            // D-27 step 5 failure does NOT clear keychain — retry-able via retryRegister().
            state = .registerFailed
            return
        }

        // D6-01: persist the backend-driven trustTier to Keychain. A Keychain
        // write failure must NOT block login — `try?` degrades to the safe
        // `.softwareOnly` default downstream (the role-shell AppContainer
        // re-hydrates from this key in Plan 03).
        try? attestedKeyStore.writeTrustTier(registerResponse.trustTier)

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

    // MARK: - STEP 5 attestation orchestration (DEV-04 / Phase 6)

    /// The attestation fields for one `/device/register` POST attempt.
    private struct AttestationFields {
        let attestedKeyId: String?
        let attestationObject: Data?
        let status: AttestationStatus
    }

    /// Runs the App Attest orchestration for one register attempt:
    /// `generateKeyIfNeeded()` -> `GET /device/challenge` -> `attestKey()`.
    ///
    /// Never throws — this is the D6-04/D6-05 graceful-skip + degrade boundary.
    /// Outcomes:
    ///   - D6-04 graceful skip: a non-.attested / non-.simulatorBypass status
    ///     yields nil keyId/object + the real status (the backend routes the
    ///     device to `.softwareOnly`). attestKey is NOT called and no challenge
    ///     is fetched.
    ///   - happy path: a usable-key status yields the real attestedKeyId +
    ///     attestationObject + the status.
    ///   - D6-05 degrade: a transient failure (challenge fetch throws,
    ///     base64-decode fails, or attestKey throws) yields nil keyId/object +
    ///     `status = .error`. Login is never blocked.
    ///
    /// PII discipline (D6-07 / Pattern A / T-06-02-01): the attestation log
    /// calls below carry ONLY the event name + `AttestationStatus.rawValue` (a
    /// closed-set string) — never `String(describing: error)`, `.userInfo`, or
    /// `.localizedDescription`.
    private func buildAttestationFields() async -> AttestationFields {
        do {
            // D-01: idempotent, once-per-install — returns the existing key on a hit.
            let (keyId, status) = try await attestationService.generateKeyIfNeeded()

            // D6-04 graceful skip: no usable key. Carry the status; omit fields.
            guard status == .attested || status == .simulatorBypass else {
                logger.warn(event: .init("attestation_first_login_skipped_no_key"),
                            fields: [.event: status.rawValue])
                return AttestationFields(attestedKeyId: nil, attestationObject: nil, status: status)
            }

            // Fetch the challenge (D-05) and base64-decode to raw bytes (D-06).
            let challengeResponse = try await apiClient.request(DeviceChallengeEndpoint())
            guard let challengeData = Data(base64Encoded: challengeResponse.challenge) else {
                // A non-decodable challenge is a degrade, not a login block (D6-05).
                logger.warn(event: .init("attestation_first_login_degraded"), fields: [:])
                return AttestationFields(attestedKeyId: nil, attestationObject: nil, status: .error)
            }

            // Produce the CBOR attestationObject (SHA-256 of challenge inside the service).
            let attestationObject = try await attestationService.attestKey(
                keyId: keyId, challenge: challengeData
            )
            return AttestationFields(
                attestedKeyId: keyId,
                attestationObject: attestationObject,
                status: status
            )
        } catch {
            // D6-05 transient degrade — challenge fetch OR attestKey threw.
            // Login still completes with attestationStatus = .error.
            logger.warn(event: .init("attestation_first_login_degraded"), fields: [:])
            return AttestationFields(attestedKeyId: nil, attestationObject: nil, status: .error)
        }
    }

    /// Issues a single `POST /device/register`. Throws the typed `NetworkError`
    /// surfaced by `APIClient` so the STEP 5 caller can pattern-match a
    /// `challengeExpired` body for the D6-06 retry.
    private func postDeviceRegister(
        devicePub: Data,
        authPub: Data,
        attestation: AttestationFields,
        fingerprint: DeviceRegisterEndpoint.DeviceFingerprintPayload
    ) async throws -> DeviceRegisterEndpoint.Response {
        try await apiClient.request(
            DeviceRegisterEndpoint(
                devicePublicKey: devicePub.base64EncodedString(),
                authorizationPublicKey: authPub.base64EncodedString(),
                attestedKeyId: attestation.attestedKeyId,
                attestationObject: attestation.attestationObject,
                attestationStatus: attestation.status,
                fingerprint: fingerprint
            )
        )
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
