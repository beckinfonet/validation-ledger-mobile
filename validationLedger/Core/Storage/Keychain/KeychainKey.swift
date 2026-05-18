// validationLedger/Core/Storage/Keychain/KeychainKey.swift
import Foundation

public struct KeychainKey: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    // Typed keys used across Phase 2+ (declared here so the storage layer
    // is the source-of-truth for key names — avoids string-typo bugs).
    public static let sessionToken = KeychainKey(rawValue: "session.token")
    public static let installUUID  = KeychainKey(rawValue: "install.uuid")

    // Phase 3 D-33: cached session metadata + biometric domain state.
    // All session-scope keys live under the same
    // .afterFirstUnlockThisDeviceOnly accessibility class as sessionToken
    // (AUTH-03) and are wiped together by KeychainStore.deleteAll(under: .session)
    // (see KeychainScope — Plan 04, D-16).
    // Raw values are referenced by name in downstream plans (06, 09); do NOT rename.
    public static let sessionRole          = KeychainKey(rawValue: "session.role")
    public static let sessionUserID        = KeychainKey(rawValue: "session.userID")
    public static let biometricDomainState = KeychainKey(rawValue: "biometric.domainState")

    // Phase 5 D-13: cached KYC status string. Sourced from
    // `OTPVerifyEndpoint.Response.kycStatus` at OTP-verify and refreshed by
    // `GET /kyc/status` once routed. Cold boot reads this OPTIMISTICALLY (no
    // round-trip — Phase 3 D-04 philosophy) to route to `.kyc` or `.role`.
    //
    // This is a member of `KeychainScope.session` — the cached status STRING is
    // session metadata and IS wiped on logout, exactly like `sessionRole`.
    // CRITICAL: this Keychain cache is a DIFFERENT store from the on-disk
    // `KYCSessionStore` artifact blob — only this cache is session-scoped; the
    // on-disk session must NOT be wiped on logout (D-02).
    public static let kycStatus            = KeychainKey(rawValue: "session.kycStatus")

    // Phase 4 DEV-04 (D-01, D-03): App Attest identifier + last-heartbeat-timestamp Keychain entries.
    // Both MUST NOT be members of KeychainScope.session — D-03 preserves attestedKeyId across logout
    // so the same install presents the same attestation after re-login. Raw values are referenced
    // by name in downstream plans (03, 06, 07, 09); do NOT rename.
    public static let attestedKeyId    = KeychainKey(rawValue: "device.attestedKeyId")
    public static let lastHeartbeatAt  = KeychainKey(rawValue: "device.lastHeartbeatAt")
}
