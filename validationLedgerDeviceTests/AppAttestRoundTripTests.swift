// validationLedgerDeviceTests/AppAttestRoundTripTests.swift
// Phase 4 Plan 09 — D-13 (3) App Attest attestKey + generateAssertion real-hardware round-trip.
//
// Target membership: validationLedgerDeviceTests ONLY.
// Simulator returns `DCAppAttestService.shared.isSupported == false` — running this
// suite there would produce `.unsupported` at every test (no real SEP, no Apple
// attestation chain). RESEARCH Pitfall 2 + 04-PATTERNS.md Pattern 20 analog.
//
// Test cleanup: every @Test purges the attestedKeyId + lastHeartbeatAt Keychain
// entries in a defer block (mirrors SecureEnclaveKeyStoreTests.purgeAllKeys).
// This prevents state leakage across runs on the same physical iPhone.
//
// Apple quota tolerance (RESEARCH Pitfall 2 + T-APP-ATTEST-13 `accept`):
// `DCAppAttestService.generateKey()` / `attestKey()` / `generateAssertion()` on a
// real device occasionally returns `DCError.Code.serverUnavailable`, interpreted
// as `.quotaExceeded` per D-09. The test accepts either outcome:
//   - (status == .attested)      → happy path, assertion round-trip completes
//   - (status == .quotaExceeded) → quota bite; the test logs and passes (acceptable)
// Only `.error` / `.unknownSystemFailure` / `.entitlementMissing` paths record an Issue.
// This matches the SecureEnclaveKeyStoreTests.signWithAuthorizationBiometricOrFail
// "accept-either-outcome" pattern.
//
// MainActor discipline: `DCAppAttestAttestationService` is @MainActor because
// DCAppAttestService callbacks land on an unspecified queue and the production
// impl hops to the main actor to write the Keychain. Test methods are annotated
// `@MainActor` to satisfy actor isolation when instantiating + driving it.

import Testing
import Foundation
import CryptoKit
import DeviceCheck
@testable import validationLedger

@Suite("AppAttest round-trip — D-13 (3) device real-hardware")
struct AppAttestRoundTripTests {

    // MARK: - Test helpers

    /// Use a dedicated Keychain service suffix so this suite's keys are
    /// isolated from the real app's attestation entries on the same iPhone.
    /// Mirrors the `.tests.attest` pattern referenced in the plan.
    private static let testService = "com.maldin.validationLedger.tests.attest"

    private func makeTestKeychain() -> KeychainStore {
        KeychainStore(accessGroup: nil, service: Self.testService)
    }

    private func purgeAttestationKeychain(keychain: KeychainStore) {
        try? keychain.delete(.attestedKeyId)
        try? keychain.delete(.lastHeartbeatAt)
    }

    private func makeService(keychain: KeychainStore) -> DCAppAttestAttestationService {
        let logger = OSLogLoggerImpl(
            subsystem: LoggingSubsystem.auth,
            category: "auth.attestation.test"
        )
        let store = AttestedKeyStore(keychain: keychain)
        return DCAppAttestAttestationService(
            keyStore: store,
            logger: logger
        )
    }

    // MARK: - Tests

    @Test("DCAppAttestService is supported on this device (baseline)")
    @MainActor
    func attestServiceSupported() {
        // Mirrors SecureEnclaveKeyStoreTests.secureEnclaveAvailable: a single
        // precondition assertion at the top of the suite confirming the device
        // baseline. If a pre-A10 device somehow joined the CI pool, every
        // other test would return .unsupported and this assertion surfaces
        // the environment problem directly instead of hiding it.
        #expect(
            DCAppAttestService.shared.isSupported == true,
            "Device tests require App Attest capability; pre-A10 or missing iOS 17 would fail here"
        )
    }

    @Test("generateKeyIfNeeded returns .attested OR .quotaExceeded (Pitfall 2 accept-either)")
    @MainActor
    func attestKeyRoundTrip() async throws {
        let keychain = makeTestKeychain()
        purgeAttestationKeychain(keychain: keychain)
        defer { purgeAttestationKeychain(keychain: keychain) }

        let service = makeService(keychain: keychain)

        // D-01 once-per-install: the first call may invoke DCAppAttestService.generateKey();
        // subsequent calls in this test read the Keychain-persisted keyId.
        let (keyId, status) = try await service.generateKeyIfNeeded()

        // D-13-3 + Pitfall 2 accept-either: `.attested` OR `.quotaExceeded` are
        // both valid CI outcomes.
        #expect(
            status == .attested || status == .quotaExceeded,
            "status must be .attested (happy) or .quotaExceeded (quota); got \(status)"
        )

        // If we got a real keyId, exercise the attestKey round-trip too.
        if status == .attested, !keyId.isEmpty {
            let challenge = Data("test-challenge-\(UUID().uuidString)".utf8)
            do {
                let attestationObject = try await service.attestKey(
                    keyId: keyId,
                    challenge: challenge
                )
                #expect(
                    !attestationObject.isEmpty,
                    "attestationObject CBOR must be non-empty on happy path"
                )
            } catch AttestationError.rateLimited {
                // Quota bite mid-test — acceptable per Pitfall 2.
            } catch AttestationError.serverUnavailable {
                // Transient Apple attestation-server unreachability — acceptable.
            } catch {
                Issue.record("attestKey failed with non-quota error: \(error)")
            }
        }
    }

    @Test("generateAssertion round-trips on real hardware (skipped if no persisted keyId)")
    @MainActor
    func generateAssertionRoundTrip() async throws {
        let keychain = makeTestKeychain()
        purgeAttestationKeychain(keychain: keychain)
        defer { purgeAttestationKeychain(keychain: keychain) }

        let service = makeService(keychain: keychain)

        let (keyId, status) = try await service.generateKeyIfNeeded()

        // Pitfall 2 accept-either: a `.quotaExceeded` outcome at this layer
        // makes the rest of the round-trip a no-op rather than a failure.
        guard status == .attested, !keyId.isEmpty else {
            #expect(
                status == .quotaExceeded || status == .unsupported,
                "non-.attested outcome must be .quotaExceeded or .unsupported; got \(status)"
            )
            return
        }

        let challenge = Data("assertion-challenge-\(UUID().uuidString)".utf8)
        do {
            // Real `generateAssertion` requires a previously attested key. The
            // CI-visible contract is: attestKey succeeds, then generateAssertion
            // returns a non-empty CBOR-encoded assertion.
            _ = try await service.attestKey(keyId: keyId, challenge: challenge)
            let assertion = try await service.generateAssertion(
                keyId: keyId,
                challenge: challenge
            )
            #expect(!assertion.isEmpty, "assertion must be non-empty on happy path")
        } catch AttestationError.rateLimited {
            // Acceptable per Pitfall 2.
        } catch AttestationError.serverUnavailable {
            // Acceptable — transient server unreachability.
        } catch {
            Issue.record("Round-trip failed with non-quota error: \(error)")
        }
    }

    @Test("D-01 — generateKeyIfNeeded called twice returns the SAME keyId from Keychain")
    @MainActor
    func generateKeyIdempotencyAcrossCalls() async throws {
        let keychain = makeTestKeychain()
        purgeAttestationKeychain(keychain: keychain)
        defer { purgeAttestationKeychain(keychain: keychain) }

        let service = makeService(keychain: keychain)

        let (firstKeyId, firstStatus) = try await service.generateKeyIfNeeded()
        // If quota bit us on the first call, we cannot assert idempotency — the
        // test is a no-op for that execution but NOT a failure.
        guard firstStatus == .attested, !firstKeyId.isEmpty else {
            #expect(
                firstStatus == .quotaExceeded || firstStatus == .unsupported,
                "non-.attested first call must be .quotaExceeded or .unsupported; got \(firstStatus)"
            )
            return
        }

        let (secondKeyId, secondStatus) = try await service.generateKeyIfNeeded()
        // D-01 contract: second call reads the Keychain-persisted keyId; it must
        // NEVER call DCAppAttestService.generateKey() a second time (which would
        // burn quota AND return a different keyId).
        #expect(secondStatus == .attested, "D-01: second call must read Keychain → .attested")
        #expect(
            secondKeyId == firstKeyId,
            "D-01: second call MUST return the persisted keyId (once-per-install contract)"
        )
    }
}
