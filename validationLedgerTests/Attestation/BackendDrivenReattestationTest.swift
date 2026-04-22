// validationLedgerTests/Attestation/BackendDrivenReattestationTest.swift
// Phase 4 Plan 05 Task 1 — D-04 backend-driven re-attestation precondition.
//
// Covers D-04 (Plan 05 T1): clearPersistedKeyId deletes the Keychain entry so
// the next generateKeyIfNeeded() call regenerates. This is the simulator-side
// invariant that the AttestationErrorResponseInterceptor (Plan 07 Task 3)
// relies on to drive the attestationInvalid/nonceExpired/keyCompromised retry
// flow.
//
// End-to-end interceptor chain assertion (interceptor.intercept → clear → fresh
// generateKey → retry) lives in AttestationErrorResponseInterceptorTest.swift
// (Plan 05 Task 4) — that test is gated behind Plan 07 Task 3 (Wave 4) until
// the interceptor production type lands.
//
// PII discipline: assertions reference only Keychain read/write semantics, not
// keyId byte values.

import Testing
import Foundation
@testable import validationLedger

@Suite("D-04 — Backend-driven re-attestation")
struct BackendDrivenReattestationTest {

    /// Unique Keychain service-id per test — isolates Keychain state.
    private func uniqueStore() -> AttestedKeyStore {
        let keychain = KeychainStore(service: "vl.test.backendDrivenReattest.\(UUID().uuidString)")
        return AttestedKeyStore(keychain: keychain)
    }

    @Test("clearPersistedKeyId deletes Keychain entry; next read returns nil")
    func reattestFlow() throws {
        let store = uniqueStore()
        try store.writeAttestedKeyId("old-key-id")
        #expect(try store.readAttestedKeyId() == "old-key-id")

        // Simulate backend-error-code response interceptor calling clearPersistedKeyId
        // (i.e. AttestedKeyStore.deleteAttestedKeyId()):
        try store.deleteAttestedKeyId()
        #expect(try store.readAttestedKeyId() == nil,
                "D-04: clearPersistedKeyId MUST remove the Keychain entry so next register regenerates")
    }

    @Test("After clear, a fresh write persists a NEW keyId — proves regeneration path is unblocked")
    func clearThenWriteNewKey() throws {
        let store = uniqueStore()
        try store.writeAttestedKeyId("original-key-id")
        try store.deleteAttestedKeyId()

        // Next "register" flow: generateKeyIfNeeded produces a fresh keyId and
        // writes it. The write path is not blocked by a lingering stale entry.
        try store.writeAttestedKeyId("fresh-key-id-after-reattest")

        #expect(try store.readAttestedKeyId() == "fresh-key-id-after-reattest",
                "D-04: after clear + generateKey, Keychain MUST hold the fresh keyId")
    }

    @Test("clearPersistedKeyId is idempotent — second call on empty Keychain does not throw")
    func clearIsIdempotent() throws {
        let store = uniqueStore()
        try store.deleteAttestedKeyId()   // first call — nothing to delete, should be no-op
        try store.deleteAttestedKeyId()   // second call — still no-op
        // If either call throws, the interceptor's retry path would be brittle on
        // the cold-path where the user invokes /device/register right after a
        // clearPersistedKeyId from DevMenu's Re-attest row (Plan 07 Task 2).
    }

    @Test("FakeAttestationService.clearPersistedKeyIdCallCount records each interceptor-driven clear")
    func fakeClearPersistedKeyIdSpy() throws {
        let fake = FakeAttestationService()
        #expect(fake.clearPersistedKeyIdCallCount == 0)

        try fake.clearPersistedKeyId()
        #expect(fake.clearPersistedKeyIdCallCount == 1,
                "D-04 spy contract: fake MUST count each clearPersistedKeyId — Plan 07 Task 3 interceptor test relies on this")

        try fake.clearPersistedKeyId()
        #expect(fake.clearPersistedKeyIdCallCount == 2)
    }

    @Test("FakeAttestationService scriptable outcome drives D-04 re-attest flow — scripted 'fresh-keyid' returned on next generateKeyIfNeeded")
    func fakeScriptableGenerateKeyAfterClear() async throws {
        let fake = FakeAttestationService()
        try fake.clearPersistedKeyId()
        fake.nextGenerateKeyIfNeeded = .success(("fresh-key-id-post-reattest", .attested))

        let (keyId, status) = try await fake.generateKeyIfNeeded()

        #expect(keyId == "fresh-key-id-post-reattest",
                "D-04: fake's nextGenerateKeyIfNeeded script must return the scripted value — interceptor tests depend on this")
        #expect(status == .attested)
    }
}
