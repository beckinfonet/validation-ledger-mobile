// validationLedger/Core/Auth/SessionRestoreService.swift
// Phase 3 Plan 06 (D-04/D-05): synchronous Keychain probe called from SceneDelegate
// BEFORE first paint. "Valid" = both sessionToken and sessionRole present. No JWT exp
// parse, no /auth/me round-trip — backend's first authenticated call returns 401 →
// AUTH-05 auto-logout.

import Foundation

public enum SessionRestoreResult: Sendable, Equatable {
    case restored(role: Role)
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
            logger.info(event: .init("session_restore_needs_auth"),
                        fields: [.event: "no_valid_session"])
            return .needsAuth
        }
        logger.info(event: .init("session_restored"),
                    fields: [.event: roleString])
        return .restored(role: role)
    }
}
