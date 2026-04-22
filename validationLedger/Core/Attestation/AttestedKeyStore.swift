// validationLedger/Core/Attestation/AttestedKeyStore.swift
// Phase 4 DEV-04 (D-01 + D-03 + D-07): Keychain persistence wrapper for
// attestedKeyId + lastHeartbeatAt.
//
// Both entries use `.afterFirstUnlockThisDeviceOnly` accessibility per D-01
// (mirrors the existing AUTH-03 / sessionToken accessibility class).
//
// Neither key is a member of the session-scope Keychain group — D-03
// preserves attestedKeyId across logout so the same install presents the
// same attestation after re-login (see KeychainScope.swift comments +
// Plan 02 scope containment tests for the scope membership table).
//
// Lifecycle:
//   - attestedKeyId: written by DCAppAttestAttestationService.generateKeyIfNeeded
//     on first-install (D-01, once-per-install). Deleted ONLY by
//     clearPersistedKeyId() — called by (a) backend re-attest signal
//     (D-04 attestationInvalid / nonceExpired / keyCompromised) or
//     (b) DevMenu "Re-attest now" row (Plan 07). Never deleted on logout.
//   - lastHeartbeatAt: overwritten on every successful /device/heartbeat
//     response (D-07). Not explicitly deleted — the FOUND-02 first-launch
//     Keychain wipe clears it along with everything else if the user
//     reinstalls.
//
// PII discipline (FOUND-01): keyId bytes never exposed to Logger or
// analytics. This wrapper is the only legitimate boundary between the
// Keychain and the attestation services.

import Foundation

public struct AttestedKeyStore: Sendable {
    private let keychain: KeychainStore

    public init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    // MARK: - attestedKeyId

    /// Returns the persisted attestedKeyId, or `nil` if never written (first
    /// install or post-clearPersistedKeyId). Throws only on unexpected
    /// Keychain errors — `itemNotFound` is translated to `nil` per the
    /// DeviceFingerprint.resolveInstallUUID analog pattern.
    public func readAttestedKeyId() throws -> String? {
        do {
            let data = try keychain.get(.attestedKeyId)
            return String(data: data, encoding: .utf8)
        } catch KeychainError.itemNotFound {
            return nil
        }
    }

    /// Writes `keyId` (UTF-8 bytes) to Keychain under `.attestedKeyId` with
    /// `.afterFirstUnlockThisDeviceOnly` accessibility (D-01).
    public func writeAttestedKeyId(_ keyId: String) throws {
        try keychain.set(
            Data(keyId.utf8),
            for: .attestedKeyId,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
    }

    /// Deletes the persisted attestedKeyId. Idempotent — missing key is a
    /// no-op (KeychainStore.delete treats errSecItemNotFound as success).
    public func deleteAttestedKeyId() throws {
        try keychain.delete(.attestedKeyId)
    }

    // MARK: - lastHeartbeatAt

    /// Returns the persisted last-heartbeat timestamp, or `nil` if never
    /// written (first install or pre-first-heartbeat).
    public func readLastHeartbeatAt() throws -> Date? {
        do {
            let data = try keychain.get(.lastHeartbeatAt)
            guard let str = String(data: data, encoding: .utf8) else { return nil }
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: str)
        } catch KeychainError.itemNotFound {
            return nil
        }
    }

    /// Writes `date` as an ISO8601 string (UTF-8 bytes) to Keychain under
    /// `.lastHeartbeatAt` with `.afterFirstUnlockThisDeviceOnly`
    /// accessibility (D-01). ISO8601 with `Z` suffix matches the
    /// `expires_at` / `registered_at` convention in the Plan 02 fixtures.
    public func writeLastHeartbeatAt(_ date: Date) throws {
        let formatter = ISO8601DateFormatter()
        let str = formatter.string(from: date)
        try keychain.set(
            Data(str.utf8),
            for: .lastHeartbeatAt,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
    }
}
