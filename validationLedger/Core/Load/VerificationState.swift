// validationLedger/Core/Load/VerificationState.swift
// Phase 7 LOAD-02 (D-09): the fail-closed verification-state enum.
//
// This is the SECURITY PRIMITIVE for the entire Phase 7 contract. Every
// party's verification level in the chain-of-trust graph (Phase 9) reads from
// this enum. A wrong default here would silently upgrade trust on the client
// — exactly what PROJECT.md's core value ("Identity that cannot be spoofed and
// a chain-of-trust that cannot be faked") forbids.
//
// D-09 — fail-closed semantics:
//   1. PRESENT-KNOWN wire value         → matching case.
//   2. PRESENT-UNKNOWN wire value       → .unverified (least-trusted; the
//      decoder degrades the trust signal so a future server superstring
//      ("compromised", "trusted", etc.) NEVER upgrades trust on this client).
//   3. MISSING parent field             → hard DecodingError. A nullable wire
//      schema would let a server bug silently drop the field; the iOS contract
//      treats absence as a hard contract violation that callers surface.
//
// The closed case set (D-09):
//   - .verified   — KYC verified + device-bound counterparty.
//   - .pending    — KYC submitted, awaiting backend review.
//   - .unverified — no verification on file YET. Distinct from .flagged.
//   - .flagged    — actively suspicious / known fraud signal. NOT the same as
//                   .unverified ("not-yet-verified" vs. "negatively-flagged").
//
// PATTERN CONTRAST with RejectionReasonCode (Core/Identity/KYC/):
// RejectionReasonCode performs its degrade-on-unknown at the CALL SITE
// (`copy(for:)`). D-09 EXPLICITLY FORBIDS that form for VerificationState
// — any consumer could bypass the call-site degrade and read the raw string,
// while a decoder-layer degrade applies to EVERY consumer automatically.
// The degrade MUST live in init(from:) so no consumer can bypass it.
//
// PATTERN NET-NEW for v1.1: this is the first fail-closed closed-enum decode
// in the codebase. ChainIntegrity.Verdict (Plan 01 Task 3) mirrors the
// pattern with a "most-suspicious" default rather than "least-trusted".

import Foundation

public enum VerificationState: String, Sendable, CaseIterable {
    case verified
    case pending
    case unverified
    case flagged
}

extension VerificationState: Decodable {
    /// Fail-closed decoder per D-09.
    ///
    /// - PRESENT-KNOWN → exact matching case.
    /// - PRESENT-UNKNOWN → `.unverified` (least-trusted; the wire-value
    ///   degrade ensures a future server superstring cannot upgrade trust on
    ///   the client).
    /// - MISSING (parent field absent) → hard `DecodingError.keyNotFound`,
    ///   thrown by the synthesized parent decoder BEFORE this initializer
    ///   ever runs. The `try container.decode(...)` call below would throw
    ///   `DecodingError.typeMismatch` for a non-string wire value (e.g. a
    ///   number or array); that too is intentional — only a string survives.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // Known string → exact case. Unknown string → .unverified (fail-closed).
        self = VerificationState(rawValue: raw) ?? .unverified
    }
}
