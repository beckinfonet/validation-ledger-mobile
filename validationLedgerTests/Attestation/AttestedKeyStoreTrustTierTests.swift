// validationLedgerTests/Attestation/AttestedKeyStoreTrustTierTests.swift
// Phase 6 DEV-04 (D6-01 / D6-02): round-trip + itemNotFound→nil coverage for the
// AttestedKeyStore.read/writeTrustTier accessors that carry the backend-driven
// trust tier across the post-OTP container swap.
//
// Pattern: per-test unique KeychainStore(service:) isolates Keychain state across
// concurrent test runs — mirrors GenerateKeyOnlyOnceTest / KeychainStoreTests.
// No in-memory double exists in this project; the real KeychainStore with a
// unique service-id is the established test seam (the system Keychain entry is
// scoped to a throwaway service-id and never collides with a real install).

import Testing
import Foundation
@testable import validationLedger

@Suite("D6-01/D6-02 — AttestedKeyStore.trustTier round-trip + fresh-store-nil")
struct AttestedKeyStoreTrustTierTests {

    /// Unique Keychain service-id per test run to avoid cross-suite contamination.
    private func uniqueStore() -> AttestedKeyStore {
        let keychain = KeychainStore(service: "vl.test.trustTier.\(UUID().uuidString)")
        return AttestedKeyStore(keychain: keychain)
    }

    @Test("writeTrustTier(.hardwareAttested) → readTrustTier() returns .hardwareAttested")
    func roundTripHardwareAttested() throws {
        let store = uniqueStore()
        try store.writeTrustTier(.hardwareAttested)
        #expect(try store.readTrustTier() == .hardwareAttested,
                "D6-01: a written .hardwareAttested tier MUST round-trip back through readTrustTier")
    }

    @Test("writeTrustTier(.softwareOnly) → readTrustTier() returns .softwareOnly")
    func roundTripSoftwareOnly() throws {
        let store = uniqueStore()
        try store.writeTrustTier(.softwareOnly)
        #expect(try store.readTrustTier() == .softwareOnly,
                "D6-01: a written .softwareOnly tier MUST round-trip back through readTrustTier")
    }

    @Test("readTrustTier() on a fresh store returns nil and does NOT throw")
    func freshStoreReturnsNil() throws {
        let store = uniqueStore()
        #expect(try store.readTrustTier() == nil,
                "D6-02: a never-written device.trustTier MUST translate itemNotFound to nil, not throw")
    }

    @Test("second writeTrustTier of a different tier overwrites — readTrustTier returns the second value")
    func writeOverwrites() throws {
        let store = uniqueStore()
        try store.writeTrustTier(.softwareOnly)
        #expect(try store.readTrustTier() == .softwareOnly)

        // First-login register may upgrade the tier on a later /device/register.
        try store.writeTrustTier(.hardwareAttested)
        #expect(try store.readTrustTier() == .hardwareAttested,
                "D6-01: a second writeTrustTier MUST overwrite — readTrustTier returns the latest value")
    }
}
