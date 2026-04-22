// validationLedgerTests/Attestation/SimulatorBypassTest.swift
// Phase 4 Plan 05 Task 1 — D-10 SimulatorBypassAttestationService output format.
//
// File-top gate (`#if DEBUG && targetEnvironment(simulator)`) MATCHES the
// production file's gate — `SimulatorBypassAttestationService.swift` is
// itself wrapped in the same guard, so the type does not exist on device/Release
// targets. The Release-strings grep gate is enforced by
// `scripts/verify-release-no-sim-bypass.sh` (Plan 05 Task 3).
//
// Covers D-10 (Plan 05 T1):
//   - `attestedKeyId` prefix = "sim-bypass-" followed by the DeviceFingerprint
//     installUUID (Plan 02/04 fixture recognizer matches on this prefix).
//   - `attestationObject` = literal UTF-8 "sim-bypass-attestation-object-v1".
//   - `assertion` = literal UTF-8 "sim-bypass-assertion-v1".
//   - status returned is `.simulatorBypass`.
//
// PII discipline: assertion failures reference only the sim-bypass-* string
// prefixes — never Keychain bytes or installUUID values (per project rule).

#if DEBUG && targetEnvironment(simulator)

import Testing
import Foundation
@testable import validationLedger

@Suite("D-10 — SimulatorBypassAttestationService emits sim-bypass-{installUUID}")
struct SimulatorBypassTest {

    /// Unique Keychain service-id per test run — isolates the installUUID
    /// lookup in DeviceFingerprint.current(keychain:) across concurrent suites.
    private func uniqueKeychain() -> KeychainStore {
        KeychainStore(service: "vl.test.simulatorBypass.\(UUID().uuidString)")
    }

    @Test("generateKeyIfNeeded returns keyId with 'sim-bypass-' prefix + .simulatorBypass status")
    func generateKeyIfNeededReturnsSimBypassPrefix() async throws {
        let keychain = uniqueKeychain()
        let service = SimulatorBypassAttestationService(keychain: keychain)

        let (keyId, status) = try await service.generateKeyIfNeeded()

        #expect(keyId.hasPrefix("sim-bypass-"),
                "D-10: keyId MUST start with 'sim-bypass-' prefix so the backend fixture recognizer matches")
        #expect(status == .simulatorBypass,
                "D-10: status MUST be .simulatorBypass")
        // Defensive: the suffix is the installUUID (UUIDv4 = 36 chars with hyphens).
        // Total length is "sim-bypass-" (11 chars) + 36 = 47. Pin the minimum
        // so a regression that returns just "sim-bypass-" (empty UUID) fails.
        #expect(keyId.count >= "sim-bypass-".count + 8,
                "D-10: keyId MUST have a non-empty installUUID suffix")
    }

    @Test("attestKey returns fixed fake blob: sim-bypass-attestation-object-v1")
    func attestKeyReturnsFakeAttestationObject() async throws {
        let service = SimulatorBypassAttestationService(keychain: uniqueKeychain())
        let blob = try await service.attestKey(keyId: "any", challenge: Data())
        let str = String(data: blob, encoding: .utf8) ?? ""
        #expect(str == "sim-bypass-attestation-object-v1",
                "D-10: attestKey MUST return the verbatim fake attestation-object bytes the backend fixture recognizes")
    }

    @Test("generateAssertion returns fixed fake blob: sim-bypass-assertion-v1")
    func generateAssertionReturnsFakeAssertion() async throws {
        let service = SimulatorBypassAttestationService(keychain: uniqueKeychain())
        let blob = try await service.generateAssertion(keyId: "any", challenge: Data())
        let str = String(data: blob, encoding: .utf8) ?? ""
        #expect(str == "sim-bypass-assertion-v1",
                "D-10: generateAssertion MUST return the verbatim fake assertion bytes for /device/heartbeat")
    }

    @Test("generateKeyIfNeeded is idempotent — second call returns the same sim-bypass-{installUUID}")
    func generateKeyIfNeededIsIdempotent() async throws {
        let keychain = uniqueKeychain()
        let service = SimulatorBypassAttestationService(keychain: keychain)

        let (keyId1, _) = try await service.generateKeyIfNeeded()
        let (keyId2, _) = try await service.generateKeyIfNeeded()

        #expect(keyId1 == keyId2,
                "D-10 + D-01: sim-bypass keyId MUST be deterministic across calls — installUUID is the same for the install")
    }

    @Test("clearPersistedKeyId removes the Keychain entry — D-04 re-attest precondition on simulator")
    func clearPersistedKeyIdRemovesEntry() async throws {
        let keychain = uniqueKeychain()
        let service = SimulatorBypassAttestationService(keychain: keychain)
        let store = AttestedKeyStore(keychain: keychain)

        _ = try await service.generateKeyIfNeeded()
        #expect(try store.readAttestedKeyId() != nil,
                "simulator bypass MUST persist the keyId so clearPersistedKeyId has something to delete")

        try service.clearPersistedKeyId()
        #expect(try store.readAttestedKeyId() == nil,
                "D-04: clearPersistedKeyId MUST delete the Keychain entry")
    }
}

#endif
