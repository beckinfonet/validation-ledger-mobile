// validationLedgerTests/Networking/MockURLProtocolForcedFailureTests.swift
// Phase 7 Plan 04 — verifies LOAD-01 SC #4 + D-14 forced-failure paths on
// MockURLProtocol.registerForcedFailure. Two delivery mechanisms exercised:
//   - .urlError(URLError.Code) → client?.urlProtocol(_:didFailWithError:)
//     → URLSession.data(for:) throws a URLError. (must_haves truth #4)
//   - .http(statusCode:body:) → didReceive/didLoad/didFinishLoading triplet
//     → URLSession.data(for:) returns (Data, HTTPURLResponse) normally.
//
// Tests go DIRECT via URLSession (no APIClient). The contract under test
// is MockURLProtocol's failure-dispatch surface, not APIClient's mapping
// of URLError -> NetworkError (covered by APIClientEndpointTests).
//
// .serialized is mandatory: tests mutate the global _failureHandlers
// array (and, in coexistence test, _handlers as well).

import Testing
import Foundation
@testable import validationLedger

@Suite("MockURLProtocol forced-failure injection (LOAD-01 SC #4 + D-14)", .serialized)
struct MockURLProtocolForcedFailureTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("registerForcedFailure with .urlError(.timedOut) delivers a URLError to the caller")
    func deliversTimedOutURLError() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        MockURLProtocol.registerForcedFailure(
            for: "/test/timeout",
            method: .get,
            kind: .urlError(.timedOut)
        )

        var req = URLRequest(url: URL(string: "https://mock.local/test/timeout")!)
        req.httpMethod = "GET"

        do {
            _ = try await makeSession().data(for: req)
            Issue.record("expected URLError(.timedOut) to be thrown")
        } catch {
            let urlError = error as? URLError
            #expect(urlError != nil, "thrown error should be a URLError, got \(error)")
            #expect(urlError?.code == .timedOut, "expected .timedOut, got \(String(describing: urlError?.code))")
        }
    }

    @Test("registerForcedFailure with .urlError(.notConnectedToInternet) delivers that URLError code")
    func deliversNotConnectedURLError() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        MockURLProtocol.registerForcedFailure(
            for: "/test/offline",
            method: .get,
            kind: .urlError(.notConnectedToInternet)
        )

        var req = URLRequest(url: URL(string: "https://mock.local/test/offline")!)
        req.httpMethod = "GET"

        do {
            _ = try await makeSession().data(for: req)
            Issue.record("expected URLError(.notConnectedToInternet) to be thrown")
        } catch {
            let urlError = error as? URLError
            #expect(urlError != nil, "thrown error should be a URLError, got \(error)")
            #expect(urlError?.code == .notConnectedToInternet,
                    "expected .notConnectedToInternet, got \(String(describing: urlError?.code))")
        }
    }

    @Test("registerForcedFailure with .http(statusCode: 409, body: ...) delivers a 409 HTTPURLResponse with the body")
    func deliversHTTP409WithBody() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        let body = Data(#"{"error_code":"load.stale_state","message":"x"}"#.utf8)
        MockURLProtocol.registerForcedFailure(
            for: "/test/409",
            method: .get,
            kind: .http(statusCode: 409, body: body)
        )

        var req = URLRequest(url: URL(string: "https://mock.local/test/409")!)
        req.httpMethod = "GET"

        let (data, response) = try await makeSession().data(for: req)
        #expect((response as? HTTPURLResponse)?.statusCode == 409)
        let bodyString = String(data: data, encoding: .utf8) ?? ""
        #expect(bodyString.contains("load.stale_state"),
                "expected response body to contain 'load.stale_state', got: \(bodyString)")
    }

    @Test("registerForcedFailure with .http(statusCode: 422) delivers a 422 with body")
    func deliversHTTP422WithBody() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        let body = Data(#"{"error_code":"load.invalid_transition","message":"x"}"#.utf8)
        MockURLProtocol.registerForcedFailure(
            for: "/test/422",
            method: .get,
            kind: .http(statusCode: 422, body: body)
        )

        var req = URLRequest(url: URL(string: "https://mock.local/test/422")!)
        req.httpMethod = "GET"

        let (data, response) = try await makeSession().data(for: req)
        #expect((response as? HTTPURLResponse)?.statusCode == 422)
        let bodyString = String(data: data, encoding: .utf8) ?? ""
        #expect(bodyString.contains("load.invalid_transition"),
                "expected response body to contain 'load.invalid_transition', got: \(bodyString)")
    }

    @Test("registerForcedFailure: success-fixture and forced-failure on different paths coexist (first-match-wins discipline)")
    func successAndFailureCoexist() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        // Register a SUCCESS fixture on /test/success via the EXISTING registerFixture<E> API.
        let successBody = Data(#"{"ok":true}"#.utf8)
        MockURLProtocol.registerFixture(
            for: DeviceChallengeEndpoint.self,
            path: "/test/success",
            method: .get,
            statusCode: 200,
            body: successBody
        )
        // Register a FORCED FAILURE on /test/fail.
        MockURLProtocol.registerForcedFailure(
            for: "/test/fail",
            method: .get,
            kind: .urlError(.cannotConnectToHost)
        )

        let session = makeSession()

        // Success path — must NOT be shadowed by the failure-handler array.
        var reqSuccess = URLRequest(url: URL(string: "https://mock.local/test/success")!)
        reqSuccess.httpMethod = "GET"
        let (successData, successResponse) = try await session.data(for: reqSuccess)
        #expect((successResponse as? HTTPURLResponse)?.statusCode == 200)
        let successText = String(data: successData, encoding: .utf8) ?? ""
        #expect(successText.contains("ok"),
                "expected /test/success body to contain 'ok', got: \(successText)")

        // Failure path — must throw URLError(.cannotConnectToHost).
        var reqFail = URLRequest(url: URL(string: "https://mock.local/test/fail")!)
        reqFail.httpMethod = "GET"
        do {
            _ = try await session.data(for: reqFail)
            Issue.record("expected URLError(.cannotConnectToHost) to be thrown for /test/fail")
        } catch {
            let urlError = error as? URLError
            #expect(urlError != nil, "thrown error should be a URLError, got \(error)")
            #expect(urlError?.code == .cannotConnectToHost,
                    "expected .cannotConnectToHost, got \(String(describing: urlError?.code))")
        }
    }
}
