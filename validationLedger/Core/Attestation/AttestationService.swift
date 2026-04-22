// validationLedger/Core/Attestation/AttestationService.swift
// Phase 4 DEV-04: protocol surface for App Attest. Implementations:
//   - DCAppAttestAttestationService:     production device (Plan 03 fills in)
//   - SimulatorBypassAttestationService: #if DEBUG && targetEnvironment(simulator) (Plan 03)
// AppContainer (Plan 06) selects via #if DEBUG && targetEnvironment(simulator),
// mirroring KeyStoreProtocol's dual-impl resolver.
//
// Decision IDs cited by methods below:
//   - D-01: once-per-install generateKey — reads Keychain first before calling DCAppAttestService.generateKey()
//   - D-03: attestedKeyId preserved across logout — clearPersistedKeyId() is NEVER called from LogoutService
//   - D-04: re-attestation is backend-driven — clearPersistedKeyId() only on backend triggers + DEBUG DevMenu
//   - D-05: challenge delivery via GET /device/challenge — protocol consumes challenge Data already fetched
//   - D-06: clientDataHash = SHA-256(challenge) — no request-body or path binding
//   - D-07: assertion cadence is registration + heartbeat only — no per-request assertions in M1
//
// Protocol is deliberately NOT @MainActor at the protocol level — impls may
// opt in (the DCAppAttest production impl marks @MainActor because
// DCAppAttestService callbacks arrive on an unspecified queue and the impl
// needs to hop back for Keychain writes).

import Foundation

public protocol AttestationService: AnyObject, Sendable {
    /// D-01: once-per-install. Reads Keychain (KeychainKey.attestedKeyId) first;
    /// only calls DCAppAttestService.generateKey() if the entry is absent. On
    /// failure routes the NSError through statusForDCError(_:) to produce the
    /// appropriate AttestationStatus — the caller receives an empty keyId in
    /// non-.attested branches and decides how to populate the /device/register
    /// payload (see D-09: attestationObject + attestedKeyId omitted when
    /// status != .attested).
    func generateKeyIfNeeded() async throws -> (keyId: String, status: AttestationStatus)

    /// D-06: clientDataHash = SHA-256(challenge). Produces the CBOR-encoded
    /// attestationObject consumed by POST /device/register (Plan 04). The
    /// caller is responsible for fetching the challenge from GET
    /// /device/challenge (D-05) and hashing is performed inside the
    /// implementation — callers pass the raw challenge bytes.
    func attestKey(keyId: String, challenge: Data) async throws -> Data

    /// D-07: produces an assertion for POST /device/heartbeat (Plan 04).
    /// Same clientDataHash rule as attestKey (D-06). Called on cold-boot after
    /// SessionRestoreProbe returns .restored(role), and on didBecomeActive
    /// when lastHeartbeatAt is more than 24h old (Plan 11 integration).
    func generateAssertion(keyId: String, challenge: Data) async throws -> Data

    /// D-04: deletes the persisted attestedKeyId from Keychain so the next
    /// generateKeyIfNeeded() call regenerates. Called ONLY by two paths:
    ///   1. Backend re-attestation signal (attestationInvalid / nonceExpired /
    ///      keyCompromised — see docs/attestation-rotation.md).
    ///   2. DEBUG-only DevMenu "Re-attest now" row (Plan 07).
    /// NEVER called from LogoutService — D-03 preserves attestedKeyId across
    /// logout so the same install presents the same attestation after re-login.
    func clearPersistedKeyId() throws
}
