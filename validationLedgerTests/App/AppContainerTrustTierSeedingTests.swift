// validationLedgerTests/App/AppContainerTrustTierSeedingTests.swift
// Phase 6 Plan 03 (D6-01 consumer): AppContainer seeds AppSession.trustTier
// from the persisted `device.trustTier` Keychain item.
//
// This is the consumer half of the cross-phase trustTier flow. Plan 06-02 wired
// the producer (`OTPViewModel` STEP 5 persists `trustTier` via
// `AttestedKeyStore.writeTrustTier` from the `/device/register` response). On the
// post-OTP role-shell construction AND on cold boot, the role-shell `AppContainer`
// re-hydrates `AppSession.trustTier` from that Keychain key — the auth-phase
// trustTier survives the ADR 0002 abrupt-replace via Keychain.
//
// `AppContainer.init` constructs its `KeychainStore` from `env.keychainAccessGroup`
// (default service `com.maldin.validationLedger`). These tests write/clear the
// `device.trustTier` item via an `AttestedKeyStore` over a `KeychainStore` with
// the SAME default service so the container reads exactly what the test wrote.
// `device.trustTier` is preserved across logout (06-01 D6-02) — each test clears
// it explicitly so the suite is order-independent.
//
// @Suite(.serialized) — `AppContainer.init` touches the global MockURLProtocol
// registry + the shared default-service Keychain; parallel siblings would thrash.

import Testing
import Foundation
@testable import validationLedger

@Suite("AppContainer — trustTier Keychain seeding (D6-01 consumer)", .serialized)
struct AppContainerTrustTierSeedingTests {

    // MARK: - Helpers

    private func debugEnv() -> Environment {
        Environment(name: "test", keychainAccessGroup: nil, apiBaseURL: nil)
    }

    /// An AttestedKeyStore over the SAME default-service Keychain that
    /// `AppContainer.init` builds (`KeychainStore(accessGroup: nil)`).
    private func defaultServiceAttestedKeyStore() -> AttestedKeyStore {
        AttestedKeyStore(keychain: KeychainStore(accessGroup: nil))
    }

    /// Remove any persisted `device.trustTier` so a test starts from the
    /// never-written state. There is no `deleteTrustTier` accessor (06-01 D6-02),
    /// so delete the underlying Keychain key directly.
    private func clearTrustTier() {
        try? KeychainStore(accessGroup: nil).delete(.trustTier)
    }

    // MARK: - Tests

    @Test("Seeds AppSession.trustTier from a persisted .hardwareAttested device.trustTier")
    @MainActor
    func seedsFromPersistedHardwareAttested() throws {
        clearTrustTier()
        defer { clearTrustTier() }

        // Producer side (mirrors OTPViewModel STEP 5 / Plan 06-02): persist a
        // backend-driven .hardwareAttested tier before the container is built.
        try defaultServiceAttestedKeyStore().writeTrustTier(.hardwareAttested)

        let container = AppContainer(
            env: debugEnv(),
            networkConfig: .mock,
            isSecureEnclaveAvailable: true
        )

        #expect(container.session.trustTier == .hardwareAttested,
                "AppContainer must seed AppSession.trustTier from the persisted device.trustTier")
    }

    @Test("Seeds AppSession.trustTier from a persisted .softwareOnly device.trustTier")
    @MainActor
    func seedsFromPersistedSoftwareOnly() throws {
        clearTrustTier()
        defer { clearTrustTier() }

        try defaultServiceAttestedKeyStore().writeTrustTier(.softwareOnly)

        let container = AppContainer(
            env: debugEnv(),
            networkConfig: .mock,
            isSecureEnclaveAvailable: true
        )

        #expect(container.session.trustTier == .softwareOnly,
                "a persisted .softwareOnly tier must seed the session as .softwareOnly")
    }

    @Test("Falls back to .softwareOnly when device.trustTier was never written")
    @MainActor
    func fallsBackToSoftwareOnlyWhenAbsent() {
        // No write — the never-written / first-install state.
        clearTrustTier()
        defer { clearTrustTier() }

        let container = AppContainer(
            env: debugEnv(),
            networkConfig: .mock,
            isSecureEnclaveAvailable: true
        )

        #expect(container.session.trustTier == .softwareOnly,
                "absent device.trustTier must fall back to the safe .softwareOnly default")
    }
}
