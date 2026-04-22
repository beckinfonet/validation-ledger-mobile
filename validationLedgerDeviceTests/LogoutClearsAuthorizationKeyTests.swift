// validationLedgerDeviceTests/LogoutClearsAuthorizationKeyTests.swift
// Phase 4 Plan 09 — D-13 (4) Logout SE ACL clearing on real device +
// D-03 invariant (attestedKeyId preserved across logout).
//
// Target membership: validationLedgerDeviceTests ONLY.
// Simulator cannot exercise the SE authorizationKey clearing path (no SE),
// so the real assertion about SecureEnclaveKeyStore.deleteKey(slot: .authorization)
// lives on hardware CI (Plan 10) — this suite.
//
// This test retires Phase 3 HUMAN-UAT item #4 ("logout wipes keys") into CI
// coverage per the Phase 4 D-13 contract (04-CONTEXT.md L79-82).
//
// D-03 invariant pinned on device (04-CONTEXT.md L41):
//   attestedKeyId is preserved across logout. Logout's teardown (SESS-04)
//   wipes sessionToken, clears authorizationKey ACL, tears down the role
//   coordinator stack, but does NOT touch the attestedKeyId Keychain item.
//   Same device + same install = same attestation after re-login.
//
// API surface used (verified against source):
//   - DefaultLogoutService.logout(reason: LogoutReason) async     // NOT throws
//     (Core/Auth/LogoutService.swift L63). Call as `await`, no `try`.
//   - KeychainScope.session membership: sessionToken, sessionRole,
//     sessionUserID, biometricDomainState (Core/Storage/Keychain/KeychainStore.swift L117-124).
//     attestedKeyId is DELIBERATELY NOT in that list — D-03 lands in the code.
//   - AttestedKeyStore.readAttestedKeyId()/writeAttestedKeyId(_:)/deleteAttestedKeyId()
//     (Core/Attestation/AttestedKeyStore.swift).
//   - SecureEnclaveKeyStore.publicKeyRepresentation() returns the device slot;
//     deleteKey(slot: .authorization) is idempotent (errSecItemNotFound → success).

import Testing
import Foundation
import Security
@testable import validationLedger

@Suite("Logout SE ACL clearing + attestedKeyId preservation — D-13 (4) + D-03")
struct LogoutClearsAuthorizationKeyTests {

    // MARK: - Test helpers

    /// Purge everything this test touches — SE keys (both slots) + session
    /// Keychain + attestation Keychain. Cross-test state isolation discipline
    /// mirrors SecureEnclaveKeyStoreTests.purgeAllKeys + attestedKeyId/lastHeartbeatAt
    /// purge from AppAttestRoundTripTests.
    private func purgeAll(keychain: KeychainStore) {
        // SE keys (both slots) — authKey + deviceKey
        let authQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Data("com.maldin.validationLedger.authKey".utf8),
        ]
        let deviceQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Data("com.maldin.validationLedger.deviceKey".utf8),
        ]
        _ = SecItemDelete(authQuery as CFDictionary)
        _ = SecItemDelete(deviceQuery as CFDictionary)

        // Session-scope Keychain items + attestation items.
        try? keychain.delete(.sessionToken)
        try? keychain.delete(.sessionRole)
        try? keychain.delete(.sessionUserID)
        try? keychain.delete(.biometricDomainState)
        try? keychain.delete(.attestedKeyId)
        try? keychain.delete(.lastHeartbeatAt)
    }

    /// Construct an AppContainer with a SeededBiometricService override so
    /// nothing inside the container's init can prompt Face ID on the
    /// physical iPhone. Real KeychainStore + SecureEnclaveKeyStore +
    /// DefaultLogoutService compose as in the production app.
    @MainActor
    private func makeContainer() -> AppContainer {
        AppContainer(
            env: Environment.current,
            networkConfig: nil,
            isSecureEnclaveAvailable: true,
            biometricServiceOverride: SeededBiometricService()
        )
    }

    // MARK: - Tests

    @Test("Logout clears authorizationKey SE ACL + session Keychain (SESS-04)")
    @MainActor
    func logoutClearsAuthorizationKey() async throws {
        let container = makeContainer()
        purgeAll(keychain: container.keychainStore)
        defer { purgeAll(keychain: container.keychainStore) }

        // Build up session state: generate SE keys (both slots) + stash a
        // sessionToken under the session scope.
        let (devicePubBefore, authPubBefore) = try container.keyStore.generateDeviceIdentityKeys()
        #expect(!devicePubBefore.isEmpty)
        #expect(!authPubBefore.isEmpty)

        try container.keychainStore.set(
            Data("session-token-xyz".utf8),
            for: .sessionToken,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )

        // Sanity pre-conditions.
        let tokenBefore = try container.keychainStore.get(.sessionToken)
        #expect(
            tokenBefore == Data("session-token-xyz".utf8),
            "sessionToken must be in Keychain pre-logout"
        )

        // Invoke the real LogoutService. `logout(reason:)` is `async` — NOT
        // `async throws` — so no `try`. Call with `.userInitiated` to match
        // the production ProfileViewController → LogoutService path (D-16).
        await container.logoutService.logout(reason: .userInitiated)

        // D-13-4 post-condition #1 (SESS-04): session token wiped.
        let tokenAfter: Data? = try? container.keychainStore.get(.sessionToken)
        #expect(
            tokenAfter == nil,
            "SESS-04: sessionToken must be wiped on logout (KeychainScope.session includes it)"
        )

        // D-13-4 post-condition #2: authorizationKey SE entry deleted.
        // SecureEnclaveKeyStore.publicKeyRepresentation() targets the DEVICE
        // slot (unchanged) — to observe authKey deletion we query the SE by
        // its application tag directly. Post-logout, SecItemCopyMatching must
        // return errSecItemNotFound.
        let authTag = Data("com.maldin.validationLedger.authKey".utf8)
        let authProbeQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: authTag,
            kSecReturnRef: true,
        ]
        var authItem: CFTypeRef?
        let authStatus = SecItemCopyMatching(authProbeQuery as CFDictionary, &authItem)
        #expect(
            authStatus == errSecItemNotFound,
            "D-13-4: authorizationKey SE entry must be deleted on logout; got status \(authStatus)"
        )

        // D-16 STEP 3 preservation: deviceKey SE entry SURVIVES logout
        // (device identity, not session-bound — the next OTP-verify
        // re-registers with the same deviceKey, mirroring attestedKeyId).
        let deviceTag = Data("com.maldin.validationLedger.deviceKey".utf8)
        let deviceProbeQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: deviceTag,
            kSecReturnRef: true,
        ]
        var deviceItem: CFTypeRef?
        let deviceStatus = SecItemCopyMatching(deviceProbeQuery as CFDictionary, &deviceItem)
        #expect(
            deviceStatus == errSecSuccess,
            "D-16 STEP 3: deviceKey SE entry must survive logout (device identity, not session-bound)"
        )
    }

    @Test("D-03 — Logout does NOT delete attestedKeyId")
    @MainActor
    func logoutPreservesAttestedKeyId() async throws {
        let container = makeContainer()
        purgeAll(keychain: container.keychainStore)
        defer { purgeAll(keychain: container.keychainStore) }

        // Seed Keychain with a persisted attestedKeyId as if App Attest had
        // already completed during a prior session. Pair with a sessionToken
        // so the logout path has something to actually tear down.
        try container.keychainStore.set(
            Data("keyid-survives-logout".utf8),
            for: .attestedKeyId,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
        try container.keychainStore.set(
            Data("session-token-xyz".utf8),
            for: .sessionToken,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )

        // Sanity: the attestedKeyId is present pre-logout.
        let kidBefore = try container.keychainStore.get(.attestedKeyId)
        #expect(
            kidBefore == Data("keyid-survives-logout".utf8),
            "attestedKeyId must be in Keychain pre-logout"
        )

        // Invoke the real LogoutService.
        await container.logoutService.logout(reason: .userInitiated)

        // D-03 invariant on device: attestedKeyId MUST survive logout.
        let kidAfter = try container.keychainStore.get(.attestedKeyId)
        let kidAfterString = String(data: kidAfter, encoding: .utf8)
        #expect(
            kidAfterString == "keyid-survives-logout",
            "D-03: attestedKeyId MUST be preserved across logout (same device + same install = same attestation)"
        )

        // And sessionToken MUST be wiped — this is the positive contrast
        // that proves logout actually ran and deleted session-scope items
        // but not the attestation item. Both assertions together pin D-03.
        let tokenAfter: Data? = try? container.keychainStore.get(.sessionToken)
        #expect(
            tokenAfter == nil,
            "SESS-04 contrast: sessionToken wiped while attestedKeyId preserved (both invariants hold)"
        )
    }
}
