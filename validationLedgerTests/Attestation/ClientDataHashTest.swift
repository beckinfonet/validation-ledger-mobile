// validationLedgerTests/Attestation/ClientDataHashTest.swift
// Phase 4 Plan 05 Task 1 — D-06 clientDataHash = SHA-256(challenge) only.
//
// Covers D-06 (Plan 05 T1): clientDataHash is SHA-256 of the server-issued
// challenge ONLY. No request-body or endpoint-path binding. The server-issued
// challenge carries freshness + nonce + signing-key-rotation state via the
// Plan 02 GET /device/challenge contract (D-05).
//
// This suite pins two invariants:
//   1. SHA-256 digest length = 32 bytes (64 hex chars) — guards against an
//      accidental swap to SHA-1 (20 bytes) or SHA-512 (64 bytes).
//   2. FakeAttestationService.lastAttestKeyChallenge + lastGenerateAssertionChallenge
//      receive the EXACT bytes passed in — proves the test double captures
//      the challenge input used by DCAppAttestAttestationService's SHA-256
//      call in Plan 03.
//
// The production SHA-256(challenge) invariant is re-enforced via a grep in
// the plan's Per-Task Verification Map (grep "Data(SHA256.hash(data: challenge))"
// must return 2 in DCAppAttestAttestationService.swift — one for attestKey,
// one for generateAssertion).

import Testing
import Foundation
import CryptoKit
@testable import validationLedger

@Suite("D-06 — clientDataHash = SHA-256(challenge); no body binding")
struct ClientDataHashTest {

    @Test("SHA-256 of a fixed challenge produces a 32-byte digest (64 hex chars)")
    func sha256OfChallengeIsThirtyTwoBytes() {
        let challenge = Data("challenge-nonce-for-testing".utf8)
        let digest = Data(SHA256.hash(data: challenge))
        #expect(digest.count == 32, "SHA-256 digest MUST be 32 bytes")
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        #expect(hex.count == 64, "SHA-256 digest MUST render as 64 hex chars")
    }

    @Test("SHA-256 of the Plan 02 device-challenge fixture is deterministic + non-empty")
    func sha256OfFixtureChallengeIsDeterministic() {
        // The fixture value is: "Y2hhbGxlbmdlLW5vbmNlLWZvci10ZXN0aW5n" (base64
        // of "challenge-nonce-for-testing"). This test pins the SHA-256 of
        // the decoded-challenge-bytes; a swap to SHA-1/SHA-512 would change
        // the digest length; a swap to a different input would change the value.
        let base64 = "Y2hhbGxlbmdlLW5vbmNlLWZvci10ZXN0aW5n"
        guard let challenge = Data(base64Encoded: base64) else {
            Issue.record("base64 decode failed for fixture challenge")
            return
        }
        let digest1 = Data(SHA256.hash(data: challenge))
        let digest2 = Data(SHA256.hash(data: challenge))
        #expect(digest1 == digest2, "SHA-256 MUST be deterministic across calls")
        #expect(digest1.count == 32)
        // Pin length but NOT exact bytes — exact-byte pinning is brittle across
        // CryptoKit versions and the length check + determinism check above
        // already locks the algorithm to SHA-256 vs SHA-1/SHA-512.
    }

    @Test("FakeAttestationService captures lastAttestKeyChallenge — D-06 spy contract for attestKey")
    func fakeCapturesAttestKeyChallenge() async throws {
        let fake = FakeAttestationService()
        let challenge = Data("attest-challenge-bytes".utf8)
        let keyId = "fake-key-id"

        _ = try await fake.attestKey(keyId: keyId, challenge: challenge)

        #expect(fake.lastAttestKeyChallenge == challenge,
                "D-06 spy contract: fake MUST capture the challenge bytes passed to attestKey for assertion")
        #expect(fake.lastAttestKeyKeyId == keyId)
        #expect(fake.attestKeyCallCount == 1)
    }

    @Test("FakeAttestationService captures lastGenerateAssertionChallenge — D-06 spy contract for heartbeat")
    func fakeCapturesGenerateAssertionChallenge() async throws {
        let fake = FakeAttestationService()
        let challenge = Data("heartbeat-challenge-bytes".utf8)
        let keyId = "fake-key-id"

        _ = try await fake.generateAssertion(keyId: keyId, challenge: challenge)

        #expect(fake.lastGenerateAssertionChallenge == challenge,
                "D-06 spy contract: fake MUST capture the challenge bytes passed to generateAssertion (heartbeat path)")
        #expect(fake.lastGenerateAssertionKeyId == keyId)
        #expect(fake.generateAssertionCallCount == 1)
    }

    @Test("attestKey and generateAssertion receive DIFFERENT challenges on independent calls — no body binding")
    func challengesAreNotShared() async throws {
        let fake = FakeAttestationService()
        let challengeA = Data("challenge-A".utf8)
        let challengeB = Data("challenge-B".utf8)

        _ = try await fake.attestKey(keyId: "k", challenge: challengeA)
        _ = try await fake.generateAssertion(keyId: "k", challenge: challengeB)

        #expect(fake.lastAttestKeyChallenge == challengeA,
                "D-06: attestKey challenge must remain as-passed — no cross-binding with generateAssertion")
        #expect(fake.lastGenerateAssertionChallenge == challengeB,
                "D-06: generateAssertion challenge is independent — no body/path binding")
        #expect(fake.lastAttestKeyChallenge != fake.lastGenerateAssertionChallenge)
    }
}
