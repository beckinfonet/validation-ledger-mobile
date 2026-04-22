// validationLedger/Core/Networking/NetworkError.swift
// Typed networking error surface consumed by APIClient + interceptors + NetworkClient.
// Phase 2 Plan 01 introduces this to close Phase 1 CR-01 (NetworkClient force-cast).
// All Phase 2 networking code throws exclusively through these cases — callers never see raw DecodingError or OSStatus.

import Foundation

public enum NetworkError: Error, Sendable {
    /// CR-01 fix site — session returned a non-HTTP URLResponse (custom scheme, file://, etc.).
    case unexpectedResponseType(URLResponse)
    /// Response status code outside 2xx. Includes raw body for caller diagnostics.
    case httpError(statusCode: Int, data: Data)
    /// JSONDecoder threw on the response body — wrapped here so callers don't see Foundation's DecodingError directly.
    case decodingFailed(Error)
    /// JSONEncoder threw when serializing the endpoint body.
    case encodingFailed(Error)
    /// RetryInterceptor exhausted its max-attempts budget without a successful response.
    case retriesExhausted
    /// PinningSessionDelegate rejected the server trust (pin mismatch or chain invalid).
    case pinningFailed
    /// NetworkConfig.live was selected but Environment.apiBaseURL is nil (WR-06 carryover — Plan 07 closes).
    case baseURLMissing
    /// Phase 3 Plan 05 (AUTH-02 / D-02): backend returned HTTP 429. The associated
    /// value carries the parsed `Retry-After` seconds (defaults to 60 if the header
    /// is missing or malformed). iOS surfaces the backend-authoritative countdown —
    /// OTPViewModel (Plan 09) drives a 1-Hz Verify-button-disable countdown off this
    /// value. iOS does NOT count attempts locally (D-02 explicitly rejects local count).
    case rateLimited(retryAfter: TimeInterval)
}
