// validationLedger/Core/Attestation/AttestationError.swift
// Phase 4 DEV-04 (D-09): Swift error taxonomy for AttestationService.
//
// Maps DCError.Code values to AttestationStatus via statusForDCError(_:) in
// DCAppAttestAttestationService (Plan 03). The .underlying case carries the
// raw NSError for logging — NEVER expose its userInfo to Logger.LogField or
// any analytics sink (FOUND-01 PII invariant). Call sites MUST log only the
// error.domain + error.code pair, never the full NSError or userInfo
// dictionary; the attestation object bytes can leak through userInfo keys
// that DeviceCheck attaches for diagnostic purposes.

import Foundation

public enum AttestationError: Error, Sendable {
    /// `DCAppAttestService.isSupported == false` — pre-A10 or missing iOS
    /// version. Maps to AttestationStatus.unsupported.
    case notSupported

    /// Entitlement missing — `DCError.Code.featureUnsupported`. Maps to
    /// AttestationStatus.entitlementMissing.
    case featureUnsupported

    /// Apple's undocumented rate limit — surfaces as `serverUnavailable` per
    /// RESEARCH Pitfall 2. Maps to AttestationStatus.quotaExceeded.
    case rateLimited

    /// Transient Apple attestation-server unreachability — also
    /// `DCError.Code.serverUnavailable` but interpreted as a retriable
    /// transient per D-09 when context makes quota-exhaustion unlikely.
    case serverUnavailable

    /// Key rotation required — backend emitted attestationInvalid /
    /// nonceExpired / keyCompromised. See docs/attestation-rotation.md.
    case invalidKey

    /// Client-side input error — malformed challenge, empty keyId, etc.
    case invalidInput

    /// `DCError.Code.unknownSystemFailure` catch-all.
    case unknownSystemFailure

    /// Catch-all for DCError.errorDomain edge cases not covered above.
    /// Callers MUST log only err.domain + err.code; err.userInfo may contain
    /// diagnostic data that DeviceCheck attaches and must never enter
    /// structured logging or analytics.
    case underlying(NSError)
}
