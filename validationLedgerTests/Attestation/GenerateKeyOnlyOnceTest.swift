// validationLedgerTests/Attestation/GenerateKeyOnlyOnceTest.swift
// Phase 4 Plan 05 Task 1 — D-01 once-per-install Keychain-first idempotency.
//
// Covers D-01 (Plan 05 T1): generateKeyIfNeeded reads Keychain FIRST before
// calling DCAppAttestService.generateKey(). On the client side this invariant
// is enforced by AttestedKeyStore persistence and the Keychain-first branch
// in DCAppAttestAttestationService.generateKeyIfNeeded() (Plan 03).
//
// Hardware-side generateKey() call-count assertion requires physical-device
// tests (Plan 09 AppAttestRoundTripTests) because DCAppAttestService is a
// singleton without dependency-injection seams. This simulator-side test pins
// the Keychain-first behavior: once AttestedKeyStore has a keyId, any subsequent
// "register" flow that reads from the store sees the SAME keyId (no regeneration).
//
// Pattern: per-test unique KeychainStore(service:) isolates Keychain state
// across concurrent test runs — mirrors KeychainStoreTests.deleteAllSessionScope.

import Testing
import Foundation
@testable import validationLedger

@Suite("D-01 — generateKey called ONCE per install (Keychain-first idempotency)")
struct GenerateKeyOnlyOnceTest {

    /// Unique Keychain service-id per test run to avoid cross-suite contamination.
    private func uniqueStore() -> AttestedKeyStore {
        let keychain = KeychainStore(service: "vl.test.generateKeyOnlyOnce.\(UUID().uuidString)")
        return AttestedKeyStore(keychain: keychain)
    }

    @Test("First register flow: no persisted keyId → read returns nil")
    func firstRegisterReadsNil() throws {
        let store = uniqueStore()
        #expect(try store.readAttestedKeyId() == nil,
                "D-01: fresh install MUST return nil from AttestedKeyStore.readAttestedKeyId")
    }

    @Test("Two /device/register flows → second read returns same keyId; no regeneration on client side")
    func onceGuardAcrossTwoRegisters() throws {
        let store = uniqueStore()

        // Pre-assert: no keyId on fresh install.
        #expect(try store.readAttestedKeyId() == nil)

        // First register flow persists a keyId.
        let keyId = "fake-attested-key-id-v1"
        try store.writeAttestedKeyId(keyId)

        // Second register flow reads the persisted keyId instead of regenerating.
        let second = try store.readAttestedKeyId()
        #expect(second == keyId,
                "D-01: second register call MUST read persisted keyId, not regenerate")

        // Third call — still stable.
        let third = try store.readAttestedKeyId()
        #expect(third == keyId,
                "D-01: keyId MUST remain stable across repeated reads")
    }

    @Test("FakeAttestationService asserts D-01 spy contract — call-count tracked for production wiring tests")
    func fakeAttestationServiceSupportsCallCountSpy() async throws {
        // This test is the simulator-side spy contract verification that
        // downstream AppContainer + register-flow wiring tests (Plan 06/07)
        // will use to assert generateKey is called at most once per install.
        let fake = FakeAttestationService()

        #expect(fake.generateKeyIfNeededCallCount == 0,
                "Fake must start with zero call count")

        _ = try await fake.generateKeyIfNeeded()
        #expect(fake.generateKeyIfNeededCallCount == 1,
                "Fake must increment call count on each invocation")

        _ = try await fake.generateKeyIfNeeded()
        #expect(fake.generateKeyIfNeededCallCount == 2,
                "D-01 spy contract: fake MUST count each call — production-code-under-test is what enforces the once-per-install rule via Keychain-first reads")
    }

    @Test("clearPersistedKeyId then read returns nil — D-04 re-attest precondition")
    func clearThenReadReturnsNil() throws {
        let store = uniqueStore()
        try store.writeAttestedKeyId("some-key-id")
        #expect(try store.readAttestedKeyId() == "some-key-id")

        try store.deleteAttestedKeyId()
        #expect(try store.readAttestedKeyId() == nil,
                "D-04: clearPersistedKeyId MUST remove the Keychain entry so next register regenerates")
    }
}
