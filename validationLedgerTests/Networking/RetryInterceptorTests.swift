// validationLedgerTests/Networking/RetryInterceptorTests.swift
// NET-05 validation. No MockURLProtocol — we pass a send closure directly to the interceptor,
// counting invocations via an actor-backed counter (thread-safe across async retries).
// Parameterized tests cover the status-code + method matrix.

import Testing
import Foundation
@testable import validationLedger

@Suite("RetryInterceptor — GET-only + backoff (NET-05)")
struct RetryInterceptorTests {

    private static let testURL = URL(string: "https://mock.local/endpoint")!

    /// Actor-backed invocation counter for the send closure (Sendable-safe under Swift 6).
    private actor Counter {
        private(set) var count = 0
        func increment() { count += 1 }
        func current() -> Int { count }
    }

    private func request(method: String) -> URLRequest {
        var req = URLRequest(url: Self.testURL)
        req.httpMethod = method
        return req
    }

    private func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: Self.testURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }

    /// Small baseDelayMs for tests so the suite runs quickly.
    private func fastInterceptor(maxRetries: Int = 3) -> RetryInterceptor {
        RetryInterceptor(maxRetries: maxRetries, baseDelayMs: 1, ceilingMs: 16)
    }

    // MARK: - GET + 5xx → retries exhaust

    @Test(
        "GET + retryable 5xx → calls send (1 + maxRetries) times",
        arguments: [500, 502, 503, 504]
    )
    func getRetriesOn5xx(statusCode: Int) async throws {
        let counter = Counter()
        let interceptor = fastInterceptor(maxRetries: 3)
        let response = httpResponse(statusCode: statusCode)
        let (_, out) = try await interceptor.intercept(
            send: { _ in
                await counter.increment()
                return (Data(), response)
            },
            request: request(method: "GET")
        )
        #expect(out.statusCode == statusCode)
        let calls = await counter.current()
        #expect(calls == 4)  // 1 initial + 3 retries
    }

    // MARK: - GET + non-retryable → single call

    @Test(
        "GET + non-retryable status → single send",
        arguments: [200, 201, 204, 400, 401, 403, 404]
    )
    func getDoesNotRetryOnNon5xx(statusCode: Int) async throws {
        let counter = Counter()
        let interceptor = fastInterceptor()
        let response = httpResponse(statusCode: statusCode)
        _ = try await interceptor.intercept(
            send: { _ in
                await counter.increment()
                return (Data(), response)
            },
            request: request(method: "GET")
        )
        let calls = await counter.current()
        #expect(calls == 1)
    }

    // MARK: - Non-GET → never retries

    @Test(
        "Non-GET method + 500 → no retry, single send",
        arguments: ["POST", "PUT", "DELETE"]
    )
    func nonGETDoesNotRetry(method: String) async throws {
        let counter = Counter()
        let interceptor = fastInterceptor()
        let five_hundred = httpResponse(statusCode: 500)
        _ = try await interceptor.intercept(
            send: { _ in
                await counter.increment()
                return (Data(), five_hundred)
            },
            request: request(method: method)
        )
        let calls = await counter.current()
        #expect(calls == 1)
    }

    // MARK: - GET + URLError → retries exhaust

    @Test("GET + retryable URLError on every attempt → throws after (1 + maxRetries) attempts")
    func getRetriesOnURLErrorAndThrows() async throws {
        let counter = Counter()
        let interceptor = fastInterceptor(maxRetries: 3)

        await #expect(throws: (any Error).self) {
            _ = try await interceptor.intercept(
                send: { _ in
                    await counter.increment()
                    throw URLError(.networkConnectionLost)
                },
                request: self.request(method: "GET")
            )
        }
        let calls = await counter.current()
        #expect(calls == 4)
    }

    // MARK: - Non-retryable URLError → rethrows immediately

    @Test("GET + non-retryable URLError → rethrows after single attempt")
    func getRethrowsNonRetryableURLError() async throws {
        let counter = Counter()
        let interceptor = fastInterceptor()

        await #expect(throws: URLError.self) {
            _ = try await interceptor.intercept(
                send: { _ in
                    await counter.increment()
                    throw URLError(.userCancelledAuthentication)
                },
                request: self.request(method: "GET")
            )
        }
        let calls = await counter.current()
        #expect(calls == 1)
    }

    // MARK: - isRetryable classification

    @Test("isRetryable returns true for each documented retryable code")
    func isRetryableAcceptsDocumentedCodes() {
        let interceptor = RetryInterceptor()
        let retryable: [URLError.Code] = [
            .networkConnectionLost,
            .timedOut,
            .notConnectedToInternet,
            .cannotConnectToHost,
            .dnsLookupFailed,
        ]
        for code in retryable {
            #expect(
                interceptor.isRetryable(URLError(code)) == true,
                "\(code) should be retryable"
            )
        }
    }

    @Test("isRetryable returns false for non-retryable codes")
    func isRetryableRejectsOtherCodes() {
        let interceptor = RetryInterceptor()
        let nonRetryable: [URLError.Code] = [
            .userCancelledAuthentication,
            .badURL,
            .unsupportedURL,
            .cancelled,
        ]
        for code in nonRetryable {
            #expect(
                interceptor.isRetryable(URLError(code)) == false,
                "\(code) should NOT be retryable"
            )
        }
    }

    // MARK: - Backoff math

    @Test("delayForAttempt(0) is base ± 20%")
    func backoffAttemptZero() {
        let interceptor = RetryInterceptor(maxRetries: 3, baseDelayMs: 1000, ceilingMs: 10_000)
        for _ in 0..<20 {
            let delay = interceptor.delayForAttempt(0)
            #expect(delay >= 800)   // 1000 − 20% = 800
            #expect(delay <= 1200)  // 1000 + 20% = 1200
        }
    }

    @Test("delayForAttempt respects ceiling")
    func backoffCeiling() {
        let interceptor = RetryInterceptor(maxRetries: 10, baseDelayMs: 500, ceilingMs: 4_000)
        // At attempt 10, 500 << 10 = 512_000; ceiling clamps to 4_000; with ±20% jitter → [3200, 4800].
        for _ in 0..<20 {
            let delay = interceptor.delayForAttempt(10)
            #expect(delay >= 3_200)
            #expect(delay <= 4_800)
        }
    }
}
