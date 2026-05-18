// validationLedger/Core/Auth/SessionRestoreService.swift
// Phase 3 Plan 06 (D-04/D-05): synchronous Keychain probe called from SceneDelegate
// BEFORE first paint. "Valid" = both sessionToken and sessionRole present. No JWT exp
// parse, no /auth/me round-trip — backend's first authenticated call returns 401 →
// AUTH-05 auto-logout.
//
// Phase 5 D-13: the probe additionally reads the cached `KeychainKey.kycStatus`
// (written at OTP-verify) so cold boot can route to the KYC hard gate vs. the role
// shell. The read is OPTIMISTIC — no round-trip; `GET /kyc/status` refreshes once
// routed. A `kycStatus` that is absent or != "verified" yields `.needsKYC(role:)`,
// failing CLOSED to the KYC gate (threat T-05-07-02) — never open to the role shell.

import Foundation

public enum SessionRestoreResult: Sendable, Equatable {
    /// A valid session whose cached `kycStatus == "verified"` — route to the role shell.
    case restored(role: Role)
    /// Phase 5 D-13: a valid session whose cached `kycStatus` is absent or not
    /// "verified" — route to the `.kyc` hard gate. The role is carried so the KYC
    /// gate's verified-"Continue" CTA can route on to the role shell.
    case needsKYC(role: Role)
    case needsAuth
}

public protocol SessionRestoreService: Sendable {
    /// Synchronous Keychain read — sub-millisecond. Safe to call on the main
    /// thread before first presentRoot.
    func probe() -> SessionRestoreResult
}

public final class DefaultSessionRestoreService: SessionRestoreService, @unchecked Sendable {
    private let keychain: KeychainStore
    private let logger: any Logger

    public init(keychain: KeychainStore, logger: any Logger) {
        self.keychain = keychain
        self.logger = logger
    }

    public func probe() -> SessionRestoreResult {
        let token = (try? keychain.get(.sessionToken)).flatMap { String(data: $0, encoding: .utf8) }
        let roleString = (try? keychain.get(.sessionRole)).flatMap { String(data: $0, encoding: .utf8) }

        guard let token, !token.isEmpty,
              let roleString, let role = Role(rawValue: roleString) else {
            // Partial state cleanup per D-04 — wipe whatever's there to avoid
            // zombie keychain items confusing the next probe.
            try? keychain.delete(.sessionToken)
            try? keychain.delete(.sessionRole)
            try? keychain.delete(.sessionUserID)
            try? keychain.delete(.kycStatus)
            logger.info(event: .init("session_restore_needs_auth"),
                        fields: [.event: "no_valid_session"])
            return .needsAuth
        }

        // Phase 5 D-13: read the cached KYC status optimistically. An absent or
        // non-"verified" value fails CLOSED to the `.kyc` hard gate (T-05-07-02) —
        // a verified user routes to the role shell; everyone else to the KYC gate.
        let kycStatus = (try? keychain.get(.kycStatus)).flatMap { String(data: $0, encoding: .utf8) }
        guard kycStatus == "verified" else {
            logger.info(event: .init("session_restored_needs_kyc"),
                        fields: [.event: roleString])
            return .needsKYC(role: role)
        }

        logger.info(event: .init("session_restored"),
                    fields: [.event: roleString])
        return .restored(role: role)
    }
}
