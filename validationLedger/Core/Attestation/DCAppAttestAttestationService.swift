// validationLedger/Core/Attestation/DCAppAttestAttestationService.swift
// Phase 4 DEV-04 production impl of AttestationService.
//
// Runs on device only. Simulator uses SimulatorBypassAttestationService via
// AppContainer's #if DEBUG && targetEnvironment(simulator) gate (Plan 06).
// Test membership: validationLedgerDeviceTests/AppAttestRoundTripTests (Plan 09).
//
// Decision citations:
//   D-01: generateKeyIfNeeded reads Keychain FIRST; calls DCAppAttestService.generateKey()
//         only when Keychain lacks attestedKeyId — ONCE per install.
//   D-04: clearPersistedKeyId() deletes Keychain entry so next call regenerates. Called
//         only by (a) backend error-code response interceptor (Plan 06/07) and
//         (b) DevMenu "Re-attest now" row (Plan 07). NEVER called on logout (D-03).
//   D-05: Challenge is fetched from backend (GET /device/challenge) by the caller;
//         passed in here as the `challenge: Data` argument. No client-side generation.
//   D-06: clientDataHash = SHA-256(challenge). Challenge-only; no body/path binding.
//   D-07: attestKey fires on first /device/register; generateAssertion fires for
//         /device/heartbeat — same SHA-256(challenge) rule.
//   D-09: DCError.Code mapped to AttestationStatus via statusForDCError(_:):
//           .featureUnsupported  → .entitlementMissing (build-config bug, log error)
//           .serverUnavailable   → .quotaExceeded      (Pitfall 2: Apple rate-limit surface)
//           .invalidInput, .invalidKey, .unknownSystemFailure → .error
//           isSupported == false → .unsupported (pre-A10 / missing iOS support)
//
// PII discipline (FOUND-01 + 04-PATTERNS.md Pattern A):
//   NEVER log raw attestationObject bytes or attestedKeyId bytes. Only log:
//     - AttestationStatus enum (via LogField.event string prefix attestation_status_*)
//     - DCError.Code rawValue as a .count field (integer, safe)
//     - call-site event name (safe)
//   AttestationError.underlying(NSError) NEVER flows into logger fields — its userInfo
//   may contain diagnostic bytes DeviceCheck attaches for Apple-internal debugging.

import Foundation
import DeviceCheck
import CryptoKit

@MainActor
public final class DCAppAttestAttestationService: AttestationService {

    private let service: DCAppAttestService
    private let keyStore: AttestedKeyStore
    private let logger: any Logger

    public init(
        service: DCAppAttestService = .shared,
        keyStore: AttestedKeyStore,
        logger: any Logger
    ) {
        self.service = service
        self.keyStore = keyStore
        self.logger = logger
    }

    // MARK: - AttestationService

    public func generateKeyIfNeeded() async throws -> (keyId: String, status: AttestationStatus) {
        // D-09 branch: isSupported == false → unsupported (pre-A10 / missing iOS).
        guard service.isSupported else {
            logger.warn(
                event: LogEvent("attestation_status_unsupported"),
                fields: [:]
            )
            return ("", .unsupported)
        }

        // D-01: Keychain-first idempotency guard. Return the persisted keyId
        // without calling DCAppAttestService.generateKey() — that call is
        // once-per-install (Pitfall 2: Apple's undocumented rate limit).
        if let existing = try keyStore.readAttestedKeyId(), !existing.isEmpty {
            return (existing, .attested)
        }

        do {
            let keyId = try await service.generateKey()
            try keyStore.writeAttestedKeyId(keyId)
            return (keyId, .attested)
        } catch let err as NSError where err.domain == DCError.errorDomain {
            let status = statusForDCError(err)
            // D-09 PII discipline: log the DCError.Code integer only (safe), the
            // AttestationStatus rawValue via the event prefix, and NOTHING from
            // err.userInfo.
            logger.error(
                event: LogEvent("attestation_generate_key_failed_\(status.rawValue)"),
                fields: [.count: err.code]
            )
            return ("", status)
        }
    }

    public func attestKey(keyId: String, challenge: Data) async throws -> Data {
        // D-06: clientDataHash = SHA-256(challenge) ONLY. No request body or
        // endpoint-path binding — the server-issued challenge (D-05/D-08)
        // already carries the freshness + nonce + signing-key-rotation state.
        let hash = Data(SHA256.hash(data: challenge))
        do {
            return try await service.attestKey(keyId, clientDataHash: hash)
        } catch let err as NSError where err.domain == DCError.errorDomain {
            throw mapDCError(err)
        }
    }

    public func generateAssertion(keyId: String, challenge: Data) async throws -> Data {
        // D-06 + D-07: same SHA-256(challenge) rule for assertions — the
        // /device/heartbeat challenge comes from the same GET /device/challenge
        // endpoint. D-07 cadence: cold-boot + 24h warm-active check.
        let hash = Data(SHA256.hash(data: challenge))
        do {
            return try await service.generateAssertion(keyId, clientDataHash: hash)
        } catch let err as NSError where err.domain == DCError.errorDomain {
            throw mapDCError(err)
        }
    }

    public func clearPersistedKeyId() throws {
        // D-04: Called by (a) backend-error-response interceptor (Plan 06/07)
        // when the server emits attestationInvalid / nonceExpired / keyCompromised,
        // and (b) DEBUG-only DevMenu "Re-attest now" row (Plan 07).
        // NEVER called from LogoutService (D-03 preserves attestedKeyId across logout).
        try keyStore.deleteAttestedKeyId()
        logger.info(event: LogEvent("attestation_key_cleared"), fields: [:])
    }

    // MARK: - DCError mapping (D-09)

    /// Maps an `NSError` with domain `DCError.errorDomain` to the wire-level
    /// `AttestationStatus` value used in the `/device/register` payload.
    /// Unknown codes default to `.error`.
    private func statusForDCError(_ err: NSError) -> AttestationStatus {
        guard let code = DCError.Code(rawValue: err.code) else { return .error }
        switch code {
        case .featureUnsupported: return .entitlementMissing   // D-09: build-config bug
        case .serverUnavailable:  return .quotaExceeded        // D-09 + Pitfall 2
        case .invalidInput, .invalidKey, .unknownSystemFailure: return .error
        @unknown default: return .error
        }
    }

    /// Maps an `NSError` with domain `DCError.errorDomain` to the Swift error
    /// taxonomy surfaced by `attestKey` / `generateAssertion`. Unknown codes
    /// fall through to `.underlying(err)` so the full `NSError` is preserved
    /// for diagnostic purposes at the caller (never flowed into Logger fields).
    private func mapDCError(_ err: NSError) -> AttestationError {
        guard let code = DCError.Code(rawValue: err.code) else {
            return .underlying(err)
        }
        switch code {
        case .featureUnsupported:   return .featureUnsupported
        case .serverUnavailable:    return .rateLimited
        case .invalidInput:         return .invalidInput
        case .invalidKey:           return .invalidKey
        case .unknownSystemFailure: return .unknownSystemFailure
        @unknown default:           return .underlying(err)
        }
    }
}
