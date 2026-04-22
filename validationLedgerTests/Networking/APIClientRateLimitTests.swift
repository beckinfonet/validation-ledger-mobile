// validationLedgerTests/Networking/APIClientRateLimitTests.swift
// Phase 3 Plan 05 / D-02 / AUTH-02: APIClient 429 + Retry-After parsing.
// Fills the Wave 0 stub seeded by Plan 01. The fixture `otp-verify-rate-limited.json`
// (Plan 01) is paired with a `Retry-After: 60` HTTP header registered via
// MockURLProtocol — transport-boundary parsing yields a typed
// `NetworkError.rateLimited(retryAfter:)` that OTPViewModel (Plan 09) will consume
// to drive a 1-Hz Verify-button-disable countdown.

import Testing
import Foundation
@testable import validationLedger

@Suite("APIClient — 429 + Retry-After parsing (AUTH-02, D-02)", .serialized)
struct APIClientRateLimitTests {

    // MARK: - Test helpers

    private static let testBaseURL = URL(string: "https://mock.local")!

    private func makeAPIClient() -> APIClient {
        // Mirrors APIClientEndpointTests.makeClient() — MockURLProtocol-backed URLSession,
        // no request/response interceptors so the 429 path is isolated from retry/idempotency.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let networkClient = URLSessionNetworkClient(
            config: .mock,
            session: session
        )
        return APIClient(
            baseURL: Self.testBaseURL,
            networkClient: networkClient,
            requestInterceptors: [],
            responseInterceptors: []
        )
    }

    // MARK: - Tests

    @Test("429 + Retry-After: 60 (delta-seconds) → NetworkError.rateLimited(retryAfter: 60)")
    func rateLimitedDeltaSeconds() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        let body = try FixtureLoader.loadFixture("otp-verify-rate-limited")
        MockURLProtocol.register { req in
            guard req.url?.path == "/auth/otp/verify" else { return nil }
            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 429,
                httpVersion: "HTTP/1.1",
                headerFields: ["Retry-After": "60", "Content-Type": "application/json"]
            )!
            return (resp, body)
        }

        let client = makeAPIClient()
        let endpoint = OTPVerifyEndpoint(otpSessionID: "sess-abc-123", code: "123456")

        do {
            _ = try await client.request(endpoint)
            Issue.record("Expected NetworkError.rateLimited; got success")
        } catch let NetworkError.rateLimited(retryAfter) {
            #expect(retryAfter == 60)
        } catch {
            Issue.record("Expected NetworkError.rateLimited; got \(error)")
        }
    }

    @Test("429 + NO Retry-After header → NetworkError.rateLimited(retryAfter: 60) (default fallback)")
    func rateLimitedDefaultFallback() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        MockURLProtocol.register { req in
            guard req.url?.path == "/auth/otp/verify" else { return nil }
            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 429,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]   // no Retry-After
            )!
            return (resp, Data("{}".utf8))
        }

        let client = makeAPIClient()
        let endpoint = OTPVerifyEndpoint(otpSessionID: "sess-abc-123", code: "123456")

        do {
            _ = try await client.request(endpoint)
            Issue.record("Expected NetworkError.rateLimited; got success")
        } catch let NetworkError.rateLimited(retryAfter) {
            #expect(retryAfter == 60)
        } catch {
            Issue.record("Expected NetworkError.rateLimited; got \(error)")
        }
    }

    @Test("parseRetryAfter handles HTTP-date format (RFC-1123 GMT)")
    func parseRetryAfterHttpDate() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // 60 seconds in the future, formatted as RFC-1123 GMT date.
        let future = now.addingTimeInterval(60)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let dateStr = formatter.string(from: future)

        let resp = HTTPURLResponse(
            url: URL(string: "https://mock.local/x")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": dateStr]
        )!
        let parsed = APIClient.parseRetryAfter(from: resp, now: now)
        // Allow ±2 second tolerance for date round-trip precision.
        #expect(parsed != nil)
        if let parsed { #expect(abs(parsed - 60) <= 2) }
    }

    @Test("Non-429 5xx still throws httpError (no regression)")
    func non429StillHttpError() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        MockURLProtocol.register { req in
            guard req.url?.path == "/auth/otp/verify" else { return nil }
            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, Data("{\"error\":\"server\"}".utf8))
        }

        let client = makeAPIClient()
        let endpoint = OTPVerifyEndpoint(otpSessionID: "sess-abc-123", code: "123456")

        do {
            _ = try await client.request(endpoint)
            Issue.record("Expected NetworkError.httpError; got success")
        } catch let NetworkError.httpError(statusCode, _) {
            #expect(statusCode == 500)
        } catch NetworkError.rateLimited {
            Issue.record("500 should NOT be classified as rate-limited")
        } catch {
            Issue.record("Expected NetworkError.httpError(500); got \(error)")
        }
    }
}
