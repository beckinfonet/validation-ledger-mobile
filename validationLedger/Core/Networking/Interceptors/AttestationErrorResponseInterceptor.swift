// validationLedger/Core/Networking/Interceptors/AttestationErrorResponseInterceptor.swift
// Phase 4 DEV-04 / D-04 automatic path: ResponseInterceptor that intercepts 4xx responses
// on /device/register + /device/heartbeat, inspects the response body's error_code field,
// and on the three canonical D-04 triggers (attestationInvalid / nonceExpired /
// keyCompromised):
//   1. Calls attestationService.clearPersistedKeyId()  — wipe Keychain entry
//   2. Calls attestationService.generateKeyIfNeeded()  — regenerate via DCAppAttestService.generateKey
//   3. Retries the original URLRequest exactly ONCE  — returns the retry result
//
// Mirrors the Phase 3 Auth401ResponseInterceptor pattern (same
// Core/Networking/Interceptors/ directory, same ResponseInterceptor conformance,
// same constructor-injection + excludedPaths-style overrides for tests). Registered
// in AppContainer's response-interceptor chain alongside Auth401ResponseInterceptor.
//
// Scope / filter stack (short-circuit in order):
//   Path filter: only `/device/register` + `/device/heartbeat` qualify. Any other
//     path flows through unchanged (no parse, no clear, no retry).
//   Status filter: only 4xx (400..<500). 2xx / 3xx / 5xx flow through.
//   Body filter: JSON body must contain a string `error_code` (or `errorCode`,
//     accepted as a forward-compat measure) whose value is in the canonical trigger
//     set. Non-JSON body / missing key / unknown code → flow through.
//
// Retry budget (T-APP-ATTEST-15 / D-15): EXACTLY ONE retry per top-level request.
// A second 4xx from the retry flows through unchanged. No recursion into this
// interceptor from the retry — the retry calls `send` directly, bypassing the
// interceptor stack above this one. Quota pressure is bounded to 1 extra
// DCAppAttestService.generateKey per D-04 trigger.
//
// Orthogonality with Auth401ResponseInterceptor (Phase 3 D-28): both interceptors
// are registered in the same chain but operate on disjoint conditions. Auth401
// fires on 401 only; this one fires on 4xx + canonical attestation error_code.
// A 401 on /device/heartbeat is handled by Auth401, not this — the body-parse
// gate guarantees we do not absorb a 401 that happens to carry an
// attestationInvalid body.
//
// PII discipline (FOUND-01 / 04-PATTERNS.md Pattern A): logger fields NEVER carry
// the response body bytes, the attestedKeyId, or the assertion. Only the event
// name + the parsed error_code string (a closed set of canonical values) + path
// flow through — all strings, all safe.

import Foundation

public struct AttestationErrorResponseInterceptor: ResponseInterceptor {

    /// Canonical D-04 re-attestation trigger codes. Must match the backend
    /// contract exactly (see docs/attestation-rotation.md).
    public static let canonicalTriggerCodes: Set<String> = [
        "attestationInvalid",
        "nonceExpired",
        "keyCompromised"
    ]

    /// Path filter: only the two attestation-carrying endpoints qualify.
    public static let defaultEligiblePaths: Set<String> = [
        "/device/register",
        "/device/heartbeat"
    ]

    private let attestationService: any AttestationService
    private let eligiblePaths: Set<String>
    private let triggerCodes: Set<String>
    private let logger: (any Logger)?

    public init(
        attestationService: any AttestationService,
        eligiblePaths: Set<String> = AttestationErrorResponseInterceptor.defaultEligiblePaths,
        triggerCodes: Set<String> = AttestationErrorResponseInterceptor.canonicalTriggerCodes,
        logger: (any Logger)? = nil
    ) {
        self.attestationService = attestationService
        self.eligiblePaths = eligiblePaths
        self.triggerCodes = triggerCodes
        self.logger = logger
    }

    public func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await send(request)

        // Path filter — only act on /device/register + /device/heartbeat.
        guard let path = request.url?.path, eligiblePaths.contains(path) else {
            return (data, response)
        }

        // Status filter — only 4xx triggers the D-04 flow.
        guard (400..<500).contains(response.statusCode) else {
            return (data, response)
        }

        // Body filter — parse error_code; short-circuit on any malformed body.
        guard let errorCode = Self.extractErrorCode(from: data),
              triggerCodes.contains(errorCode) else {
            return (data, response)
        }

        // D-04 canonical flow.
        logger?.info(event: .init("attestation_backend_reattest_triggered"), fields: [:])

        // 1. Clear persisted keyId (wipe Keychain entry).
        do {
            try attestationService.clearPersistedKeyId()
        } catch {
            // Safe-fail: log + flow through original response unchanged. Do NOT
            // throw — callers still need the original 4xx to handle normally.
            logger?.error(event: .init("attestation_clear_persisted_key_failed"), fields: [:])
            return (data, response)
        }

        // 2. Regenerate keyId (produces a fresh attestedKeyId on next Apple call).
        do {
            _ = try await attestationService.generateKeyIfNeeded()
        } catch {
            logger?.error(event: .init("attestation_regenerate_failed"), fields: [:])
            return (data, response)
        }

        // 3. Retry the original request EXACTLY ONCE. The retry calls `send`
        //    directly (the closure passed in by APIClient), which does NOT
        //    re-enter this interceptor — a second 4xx flows through unchanged.
        let (retriedData, retriedResponse) = try await send(request)
        return (retriedData, retriedResponse)
    }

    // MARK: - Body parsing

    /// Extracts top-level `error_code` from a JSON body. Returns nil on any
    /// decode failure (missing body, non-JSON, non-string value). Accepts both
    /// `error_code` (snake_case wire format) and `errorCode` (camelCase
    /// forward-compat) as a defensive measure against backend contract drift.
    internal static func extractErrorCode(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let code = obj["error_code"] as? String { return code }
        if let code = obj["errorCode"] as? String { return code }
        return nil
    }
}
