// validationLedger/Core/Storage/Keychain/KeychainScope.swift
// Phase 3 Plan 04 (D-16 / D-33): scope enum for KeychainStore.deleteAll(under:).
//
// The .session scope groups the 4 keys that belong to an active authenticated
// session: sessionToken + sessionRole + sessionUserID + biometricDomainState.
// LogoutService (Plan 07) calls deleteAll(under: .session) to wipe these together
// when orchestrating teardown. The installUUID key (device identity) is
// INTENTIONALLY not in this scope — it persists across logout so the next
// sign-in on the same device is recognized as the same device.
//
// Analog: KeychainAccessibility.swift (sibling file) — single-case-per-concept
// enum pattern with a `Sendable` conformance and a pure-function resolver.

import Foundation

public enum KeychainScope: Sendable {
    /// All keys tied to an authenticated session (wiped on logout).
    /// Members: sessionToken, sessionRole, sessionUserID, biometricDomainState.
    case session

    /// Returns true if `key` belongs to this scope and should be deleted by
    /// `KeychainStore.deleteAll(under:)`. Non-scope keys (e.g., installUUID)
    /// return false — a scope-containment miss is NOT an error.
    public func contains(_ key: KeychainKey) -> Bool {
        switch self {
        case .session:
            return [
                KeychainKey.sessionToken,
                KeychainKey.sessionRole,
                KeychainKey.sessionUserID,
                KeychainKey.biometricDomainState,
            ].contains(key)
        }
    }
}
