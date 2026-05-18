// validationLedger/Core/Storage/Keychain/KeychainStore.swift
// Hand-rolled SecItem wrapper. KeychainAccess is abandoned (2021); we own this ~150 LOC.
// Access group support (future Phase 2+) is wired in but nil-default for Phase 1.

import Foundation
import Security

public enum KeychainError: Error, Sendable {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case invalidData
}

public final class KeychainStore: @unchecked Sendable {
    private let accessGroup: String?
    private let service: String

    public init(accessGroup: String? = nil, service: String = "com.maldin.validationLedger") {
        self.accessGroup = accessGroup
        self.service = service
    }

    public func set(_ data: Data, for key: KeychainKey, accessibility: KeychainAccessibility) throws {
        var query = baseQuery(for: key)
        query[kSecValueData] = data
        query[kSecAttrAccessible] = accessibility.cfValue

        // Upsert pattern: try add; if duplicate, update.
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            var attrs: [CFString: Any] = [kSecValueData: data]
            attrs[kSecAttrAccessible] = accessibility.cfValue
            let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func get(_ key: KeychainKey) throws -> Data {
        var query = baseQuery(for: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw KeychainError.itemNotFound }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data else { throw KeychainError.invalidData }
        return data
    }

    public func delete(_ key: KeychainKey) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        // Idempotent: errSecItemNotFound is success.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func enumerateAll() throws -> [(KeychainKey, Data)] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnAttributes: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status != errSecItemNotFound else { return [] }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let array = items as? [[CFString: Any]] else { return [] }
        return array.compactMap { dict -> (KeychainKey, Data)? in
            guard let account = dict[kSecAttrAccount] as? String,
                  let data = dict[kSecValueData] as? Data else { return nil }
            return (KeychainKey(rawValue: account), data)
        }
    }

    // MARK: - Private

    private func baseQuery(for key: KeychainKey) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        return query
    }
}

// MARK: - Phase 3 Plan 04 (D-16 / D-33) — bulk-delete by KeychainScope

extension KeychainStore {
    /// Bulk-delete all keys belonging to `scope`. Idempotent — missing keys
    /// are silently skipped (composes over the existing `delete(_:)` contract,
    /// which treats `errSecItemNotFound` as success).
    ///
    /// Scope membership is an explicit enumerable set (see `KeychainScope`),
    /// NOT a snapshot of `enumerateAll()`. This is deliberately conservative:
    /// if a future plan adds a new Keychain-resident secret, it will NOT be
    /// silently vacuumed by `deleteAll(under: .session)` unless its key is
    /// added to the scope's membership table — engineers must opt-in.
    ///
    /// Used by LogoutService (Plan 07) to wipe session-scope state in one call.
    public func deleteAll(under scope: KeychainScope) throws {
        let keys: [KeychainKey]
        switch scope {
        case .session:
            // MUST stay in sync with `KeychainScope.session.contains(_:)` — the
            // scope's membership table is the source of truth for what "session
            // scope" means. Phase 5 D-13 added `kycStatus` to that table (the
            // cached KYC status STRING is session metadata, wiped on logout like
            // `sessionRole`); this delete list was missing it, so a logout left
            // a stale cached `kycStatus` behind. The on-disk `KYCSessionStore`
            // artifact blob is a SEPARATE store and deliberately survives logout
            // (D-02) — only this Keychain CACHE is session-scoped.
            keys = [
                .sessionToken,
                .sessionRole,
                .sessionUserID,
                .biometricDomainState,
                .kycStatus,
            ]
        }
        for key in keys {
            try delete(key)  // existing API; idempotent on errSecItemNotFound
        }
    }
}

// MARK: - KeychainWiper (FOUND-02 / D-20)
// Testable helper. AppDelegate (Plan 05) invokes this before AppContainer resolves.

public enum KeychainWiper {
    public static let firstLaunchFlagKey = "didCompleteFirstLaunch"

    public static func wipeOnFirstLaunch(defaults: UserDefaults = .standard, accessGroup: String? = nil) {
        guard !defaults.bool(forKey: firstLaunchFlagKey) else { return }

        let classes: [CFString] = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity,
        ]
        for secClass in classes {
            var query: [CFString: Any] = [kSecClass: secClass]
            if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
            // errSecSuccess or errSecItemNotFound both fine — we are idempotently wiping.
            SecItemDelete(query as CFDictionary)
        }
        defaults.set(true, forKey: firstLaunchFlagKey)
    }
}
