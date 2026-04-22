// validationLedgerTests/Attestation/FakeAttestationService.swift
// Test double for AttestationService — records call counts and returns scriptable outcomes.
// Used by Plan 05 D-01/D-06/D-07 tests + Plan 06 AppContainer wiring tests.

import Foundation
@testable import validationLedger

final class FakeAttestationService: AttestationService, @unchecked Sendable {

    // Scriptable outcomes
    var nextGenerateKeyIfNeeded: Result<(keyId: String, status: AttestationStatus), Error> = .success(("fake-key-id", .attested))
    var nextAttestKey: Result<Data, Error> = .success(Data("fake-attestation-object".utf8))
    var nextGenerateAssertion: Result<Data, Error> = .success(Data("fake-assertion".utf8))

    // Call counters (D-01 once-per-install assertion support)
    private(set) var generateKeyIfNeededCallCount = 0
    private(set) var attestKeyCallCount = 0
    private(set) var generateAssertionCallCount = 0
    private(set) var clearPersistedKeyIdCallCount = 0

    // Last-args capture (D-06 clientDataHash assertion support)
    private(set) var lastAttestKeyChallenge: Data?
    private(set) var lastGenerateAssertionChallenge: Data?
    private(set) var lastAttestKeyKeyId: String?
    private(set) var lastGenerateAssertionKeyId: String?

    func generateKeyIfNeeded() async throws -> (keyId: String, status: AttestationStatus) {
        generateKeyIfNeededCallCount += 1
        return try nextGenerateKeyIfNeeded.get()
    }

    func attestKey(keyId: String, challenge: Data) async throws -> Data {
        attestKeyCallCount += 1
        lastAttestKeyKeyId = keyId
        lastAttestKeyChallenge = challenge
        return try nextAttestKey.get()
    }

    func generateAssertion(keyId: String, challenge: Data) async throws -> Data {
        generateAssertionCallCount += 1
        lastGenerateAssertionKeyId = keyId
        lastGenerateAssertionChallenge = challenge
        return try nextGenerateAssertion.get()
    }

    func clearPersistedKeyId() throws {
        clearPersistedKeyIdCallCount += 1
    }
}
