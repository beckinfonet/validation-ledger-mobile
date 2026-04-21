// validationLedgerDeviceTests/RefuseLaunchWithoutSecureEnclaveTests.swift
// DEV-03 / SC-4: A Release build must refuse to launch when SecureEnclave.isAvailable == false.
//
// Target membership: validationLedgerDeviceTests ONLY. The actual fatalError in AppContainer.init
// would abort the test process, so we test `AppContainer.preflightSecureEnclave(...)` — a pure
// Bool extract that returns the launch/no-launch decision WITHOUT triggering the trap.
//
// The production fatalError at AppContainer.init's `#else` guard-site is preserved — this test
// asserts the logic that gates it. Research A10 recommends parameter injection over
// subprocess-spawn; Plan 07 implements that recommendation via the `isSimulatorBuild` +
// `isDebugBuild` + `isSecureEnclaveAvailable` parameters on preflightSecureEnclave.

import Testing
import Foundation
import CryptoKit
@testable import validationLedger

@Suite("DEV-03 / SC-4 — Refuse launch without Secure Enclave")
struct RefuseLaunchWithoutSecureEnclaveTests {

    @Test("Device baseline: SecureEnclave.isAvailable is true on production hardware")
    func secureEnclaveAvailableOnDevice() {
        // This invariant is the foundation the entire Phase 2 keystore stack depends on.
        // Simulator builds never run this target; device builds always do.
        #expect(SecureEnclave.isAvailable == true, "Device tests must run on hardware with SE")
    }

    @Test("preflightSecureEnclave returns true when SE is available on device (Release path)")
    func preflightAcceptsAvailableSE() {
        // Production Release path: non-simulator, non-DEBUG, SE available → launch proceeds.
        let ok = AppContainer.preflightSecureEnclave(
            isSecureEnclaveAvailable: true,
            isSimulatorBuild: false,
            isDebugBuild: false
        )
        #expect(ok == true)
    }

    @Test("preflightSecureEnclave returns false when SE is unavailable on non-simulator non-DEBUG (Release SC-4 assertion)")
    func preflightRejectsMissingSEOnRelease() {
        // DEV-03 SC-4: Release build (non-simulator, non-DEBUG) + SE missing = refuse launch.
        // In production, this `false` return would trigger AppContainer.init's fatalError.
        let ok = AppContainer.preflightSecureEnclave(
            isSecureEnclaveAvailable: false,
            isSimulatorBuild: false,
            isDebugBuild: false
        )
        #expect(ok == false, "Release + SE-missing must refuse launch — this is SC-4")
    }

    @Test("preflightSecureEnclave returns true when simulator+DEBUG regardless of SE availability")
    func preflightAcceptsSimulatorDebug() {
        // Simulator + DEBUG uses SoftwareKeyStore — the SE check is bypassed (DEV-03 gate).
        let okWithSE = AppContainer.preflightSecureEnclave(
            isSecureEnclaveAvailable: true,
            isSimulatorBuild: true,
            isDebugBuild: true
        )
        let okWithoutSE = AppContainer.preflightSecureEnclave(
            isSecureEnclaveAvailable: false,
            isSimulatorBuild: true,
            isDebugBuild: true
        )
        #expect(okWithSE == true)
        #expect(okWithoutSE == true, "Simulator+DEBUG must accept even without SE — SoftwareKeyStore path")
    }

    @Test("preflightSecureEnclave returns false on non-simulator DEBUG (physical-device DEBUG build) without SE")
    func preflightRejectsDeviceDebugWithoutSE() {
        // Physical device + DEBUG + SE missing = refuse. This is the real-world failure mode
        // (developer running a DEBUG build on a device that happens to lack SE hardware) —
        // the gate behaves the same as Release because the SoftwareKeyStore path requires
        // BOTH isDebugBuild AND isSimulatorBuild, not either alone.
        let ok = AppContainer.preflightSecureEnclave(
            isSecureEnclaveAvailable: false,
            isSimulatorBuild: false,
            isDebugBuild: true
        )
        #expect(ok == false)
    }
}
