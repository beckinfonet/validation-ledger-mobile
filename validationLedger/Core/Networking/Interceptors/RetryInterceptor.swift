// validationLedger/Core/Networking/Interceptors/RetryInterceptor.swift
// NET-05: Retry idempotent GETs on 5xx + retryable URLErrors with exponential backoff + jitter.
//
// Spec (NET-05): GET only, max 3 retries (4 attempts total).
// Research Pattern 6: base 500ms, ×2^attempt, ±20% jitter, ceiling 4000ms.
//
// POST/PUT/DELETE are NEVER retried here — see Pitfall 8 (silent-duplicate risk). Phase 5's
// resumable-chunk upload uses a DIFFERENT mechanism (same Idempotency-Key across retries);
// that's not a generic retry and lives in UPL-03.
//
// On final-attempt 5xx the interceptor RETURNS the last (data, response) pair rather than
// throwing — APIClient then sees the 5xx in the 200-299 range check and throws
// NetworkError.httpError. Retries are transparent to the caller; the final result IS the
// 5xx response, handled downstream. Only when every attempt throws (and no response was
// ever captured) do we throw NetworkError.retriesExhausted (or the last caught URLError).

import Foundation

public struct RetryInterceptor: ResponseInterceptor {
    private let maxRetries: Int
    private let baseDelayMs: UInt64
    private let ceilingMs: UInt64

    public init(maxRetries: Int = 3, baseDelayMs: UInt64 = 500, ceilingMs: UInt64 = 4_000) {
        precondition(maxRetries >= 0, "maxRetries must be non-negative")
        precondition(baseDelayMs > 0, "baseDelayMs must be positive")
        precondition(ceilingMs >= baseDelayMs, "ceilingMs must be >= baseDelayMs")
        self.maxRetries = maxRetries
        self.baseDelayMs = baseDelayMs
        self.ceilingMs = ceilingMs
    }

    public func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        // NET-05: only GET is retry-eligible. POST/PUT/DELETE pass through unchanged.
        guard request.httpMethod == "GET" else {
            return try await send(request)
        }

        var lastError: Error?
        var lastResult: (Data, HTTPURLResponse)?

        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await send(request)
                // Retry on 5xx if we still have budget.
                if (500...599).contains(response.statusCode), attempt < maxRetries {
                    lastResult = (data, response)
                    try await Task.sleep(nanoseconds: delayForAttempt(attempt) * 1_000_000)
                    continue
                }
                // 2xx/3xx/4xx or final-attempt 5xx: return directly, caller handles.
                return (data, response)
            } catch let urlError as URLError where isRetryable(urlError) {
                lastError = urlError
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: delayForAttempt(attempt) * 1_000_000)
                    continue
                }
            } catch {
                // Non-retryable error — rethrow without retry.
                throw error
            }
        }

        // All retries exhausted.
        if let lastResult {
            // Return the last 5xx response for caller to handle (per spec — no throw on 5xx).
            return lastResult
        }
        throw lastError ?? NetworkError.retriesExhausted
    }

    // MARK: - Backoff math

    /// Internal-access (not private) so @testable imports can exercise the math directly.
    /// Returns the sleep duration in milliseconds for the given retry attempt index.
    /// Delay = min(baseDelayMs << attempt, ceilingMs) ± 20% uniform jitter.
    func delayForAttempt(_ attempt: Int) -> UInt64 {
        // Guard against overflow of the shift when attempt is large. After the shift would
        // exceed ceilingMs we clamp anyway, so short-circuit once we've saturated.
        let rawShift: UInt64
        if attempt >= 62 {
            // 1 << 62 is the largest safe shift for UInt64; beyond that, saturate to ceiling.
            rawShift = UInt64.max
        } else {
            // Use overflow-checking shift via multiply equivalence: baseDelayMs * 2^attempt,
            // but prefer the simple shift since attempt stays small in practice.
            rawShift = baseDelayMs << attempt
        }
        let capped = min(rawShift, ceilingMs)
        // ±20% jitter (uniform). Work in Int64 so negative jitter is representable, then clamp.
        let jitterRange = Double(capped) * 0.2
        let maxJitter = Int64(jitterRange)
        let jitter: Int64 = maxJitter > 0
            ? Int64.random(in: -maxJitter...maxJitter)
            : 0
        let withJitter = Int64(capped) + jitter
        return UInt64(max(0, withJitter))
    }

    // MARK: - Retryable URLError classification

    /// Internal-access for @testable imports. Returns true for the documented retryable
    /// URLError cases; false for everything else (including .cancelled, which is a caller-
    /// initiated abort and must never be silently retried).
    func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost,
             .timedOut,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
