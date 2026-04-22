// validationLedger/Core/Attestation/SimulatorBypassAttestationService.swift
// Phase 4 DEV-04 (D-10): DEBUG + simulator-only bypass for AttestationService.
// Production builds never ship this code path.
//
// File-top gate: `#if DEBUG && targetEnvironment(simulator)` wraps the ENTIRE
// file body. This is a deliberate deviation from the SoftwareKeyStore pattern
// (which is not gated) because D-10 states "Production builds never ship this
// code path" — the file-top gate ensures the symbols do not even exist in a
// Release archive. Plan 05 adds a Release-strings grep gate that fails the
// build if "sim-bypass-" appears in a Release binary.
//
// Wire contract:
//   - attestedKeyId = "sim-bypass-{installUUID}" (D-10; backend fixture
//     recognizer matches on this prefix)
//   - attestationObject = literal UTF-8 bytes of "sim-bypass-attestation-object-v1"
//   - assertion         = literal UTF-8 bytes of "sim-bypass-assertion-v1"
//   The mock backend's /device/register fixture (Plan 02/04) accepts these
//   verbatim and returns trustTier = "softwareOnly".
//
// AppContainer (Plan 06) selects this impl inside the same
// `#if DEBUG && targetEnvironment(simulator)` guard — the `#else` branch
// selects DCAppAttestAttestationService unconditionally.
//
// Keychain persistence goes through AttestedKeyStore (same as the production
// impl) so clearPersistedKeyId() has something real to delete and the
// Keychain state invariant is identical across impls.

#if DEBUG && targetEnvironment(simulator)
import Foundation

public final class SimulatorBypassAttestationService: AttestationService, @unchecked Sendable {

    private let keychain: KeychainStore
    private let attestedKeyStore: AttestedKeyStore

    public init(keychain: KeychainStore) {
        self.keychain = keychain
        self.attestedKeyStore = AttestedKeyStore(keychain: keychain)
    }

    public func generateKeyIfNeeded() async throws -> (keyId: String, status: AttestationStatus) {
        // D-10: sim-bypass-{installUUID} — the Plan 02/04 fixture recognizer
        // matches this prefix and returns trustTier: "softwareOnly".
        let installUUID = try DeviceFingerprint.current(keychain: keychain).installUUID
        let keyId = "sim-bypass-\(installUUID)"
        // Persist so clearPersistedKeyId() has something to delete and the
        // Keychain state matches the production path's invariant. D-03
        // preservation across logout applies on the simulator path too.
        try attestedKeyStore.writeAttestedKeyId(keyId)
        return (keyId, .simulatorBypass)
    }

    public func attestKey(keyId: String, challenge: Data) async throws -> Data {
        // D-10: fixed fake bytes; mock backend fixture recognizes verbatim.
        return Data("sim-bypass-attestation-object-v1".utf8)
    }

    public func generateAssertion(keyId: String, challenge: Data) async throws -> Data {
        // D-10: fixed fake bytes; mock backend fixture recognizes verbatim.
        return Data("sim-bypass-assertion-v1".utf8)
    }

    public func clearPersistedKeyId() throws {
        try attestedKeyStore.deleteAttestedKeyId()
    }
}
#endif
