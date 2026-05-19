// validationLedger/Core/Networking/Mock/MockURLProtocol.swift
// Phase 2 Plan 03: moved to Core/Networking/Mock/ alongside MockFixture.swift + Fixtures/.
// Phase 2 Plan 01 NSLock-guarded handler registry (WR-01 fix) retained unchanged.
// Phase 1 scaffolded this with a single hardcoded /ping fixture + an unlocked public static array (WR-01).
// Phase 2 Plan 01 replaces it with:
//   (a) NSLock-guarded handler registry (closes WR-01 test parallelism race)
//   (b) Explicit register(_:) / reset() / currentHandlers public API — tests no longer mutate the array directly
//   (c) Removal of the Phase 1 defaultPingHandler — every test registers its own fixture, no global defaults survive
//   (d) Typed Handler closure alias (@Sendable) so Swift 6 concurrency checks pass
// The registerFixture<E: APIEndpoint>(...) extension ships with Plan 03 (MockFixture.swift in this same directory).
//
// Pattern: a session's protocolClasses array is set to [MockURLProtocol.self]; the session is used by APIClient
// (Plan 02) or direct URLSession tests; MockURLProtocol intercepts requests and consults its handler list.
// First handler whose closure returns non-nil wins; no-match -> 404.
//
// === Phase 7 LOAD-01 additive change (07-04) ===
// Four new symbols are appended below the original class, in a single end-of-file extension:
//   - public enum InjectedFailure                 (typed failure descriptor: HTTP status or URLError code)
//   - public static func registerFixtureWithLatency<E: APIEndpoint>(...)   (delay-then-deliver fixture)
//   - public static func registerForcedFailure(for:method:kind:)           (force a URLError or HTTP error)
//   - public static func resetFailureHandlers()                            (clear failure handlers only)
//
// Roadmap SC #5 — preservation guarantee (must_haves truth #3):
//   register(_:), reset(), and MockFixture.registerFixture(for:path:method:statusCode:body:)
//   remain byte-identical to their pre-Phase-7 source. _handlers storage, handlersLock,
//   the Handler typealias, currentHandlers, canInit, canonicalRequest, and stopLoading()
//   are also preserved verbatim.
//
// startLoading() — minimal extension (must_haves truth #4):
//   The existing success-handler for-loop AND the 404-fallback remain bit-exact in their
//   original form. ONE new line is INSERTED between the for-loop and the 404 fallback
//   which delegates to a private dispatchFailureHandlers() helper. The helper returns
//   true if it dispatched a failure (success-or-404 path unchanged otherwise). This is
//   the smallest change required to deliver real URLError via client?.urlProtocol(self,
//   didFailWithError:) — must_haves truth #4 ("not via a synthesized HTTPURLResponse").
//
// Threading on registerFixtureWithLatency: implemented via Thread.sleep(forTimeInterval:)
// inside the registered Handler closure. Acceptable because URLProtocol's startLoading
// runs on URLSession's internal background queue (NOT the main thread); the sleep blocks
// that worker, never main. Documented per T-07-18 (accept disposition).

import Foundation

public final class MockURLProtocol: URLProtocol {
    public typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)?

    private static let handlersLock = NSLock()
    private static var _handlers: [Handler] = []

    /// Register a handler. Handlers are consulted in registration order; first non-nil return wins.
    /// Call MockURLProtocol.reset() at the top of each test to avoid stale-fixture leakage across tests.
    public static func register(_ handler: @escaping Handler) {
        handlersLock.withLock { _handlers.append(handler) }
    }

    /// Remove all registered handlers. Call at the top of every @Test body that uses fixtures.
    public static func reset() {
        handlersLock.withLock { _handlers.removeAll() }
    }

    /// Snapshot of current handlers, lock-guarded. Used internally by startLoading.
    private static var currentHandlers: [Handler] {
        handlersLock.withLock { _handlers }
    }

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    public override func stopLoading() {}

    public override func startLoading() {
        for handler in Self.currentHandlers {
            if let (response, data) = handler(request) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }
        // Phase 7 LOAD-01 additive: if a failure-handler matches, dispatch via didFailWithError
        // (for URLError) or via the success-response triplet (for HTTP errors), and return.
        if Self.dispatchFailureHandlers(for: request, client: client, protocolInstance: self) { return }
        // No handler matched — return 404 so tests fail loudly rather than hang.
        let url = request.url ?? URL(string: "about:blank")!
        let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - Phase 7 additive (LOAD-01, 07-04)
//
// Net-new latency + forced-failure injection. The existing public API surface
// (register / reset / registerFixture) and the existing _handlers storage are
// untouched. Failure handlers live in a SEPARATE _failureHandlers array under
// a sibling NSLock; resetFailureHandlers() clears it WITHOUT touching _handlers
// (must_haves truth #3: reset() body preserved byte-identical, no widening).

extension MockURLProtocol {

    /// Typed failure descriptor — what a forced-failure handler delivers when it matches.
    public enum InjectedFailure: Sendable {
        /// Deliver an `HTTPURLResponse` with the given status code + body. Routes through
        /// the standard `urlProtocol(_:didReceive:cacheStoragePolicy:)` + `didLoad` triplet
        /// — same path the success-handler loop uses.
        case http(statusCode: Int, body: Data)
        /// Deliver a `URLError` with the given code via `client?.urlProtocol(_:didFailWithError:)`.
        /// This is the transport-failure path — URLSession's caller sees a thrown `URLError`,
        /// not an `HTTPURLResponse`. Must_haves truth #4.
        case urlError(URLError.Code)
    }

    /// Internal type used by the _failureHandlers array. Closure returns a typed
    /// `InjectedFailure` if it matches the request, or nil if it doesn't.
    fileprivate typealias FailureHandler = @Sendable (URLRequest) -> InjectedFailure?

    fileprivate static let failureHandlersLock = NSLock()
    fileprivate static var _failureHandlers: [FailureHandler] = []

    /// Snapshot of current failure handlers, lock-guarded. Used internally by startLoading.
    fileprivate static var currentFailureHandlers: [FailureHandler] {
        failureHandlersLock.withLock { _failureHandlers }
    }

    /// Register a fixture that waits `latency` seconds before delivering its response.
    ///
    /// Implementation registers via the EXISTING `register(_:)` API — no new storage.
    /// The registered closure calls `Thread.sleep(forTimeInterval: latency)` synchronously
    /// BEFORE returning the (HTTPURLResponse, Data) tuple. This blocks URLSession's
    /// internal background worker (NOT the main thread) for `latency` seconds, then
    /// the standard success-path triplet delivers the response.
    ///
    /// Caller-facing semantics match `registerFixture<E>`:
    ///   - matches when `request.url?.path == path && request.httpMethod == method.rawValue`
    ///   - delivers an `HTTPURLResponse` with the given `statusCode`, `body`, and `headers`
    ///
    /// Follow-up note (T-07-18): if simulator-flake surfaces under high parallelism,
    /// switch to `DispatchQueue.global().asyncAfter(deadline:)` driving `client?.urlProtocol(...)`
    /// directly from `startLoading`. Recorded in 07-04-SUMMARY.
    public static func registerFixtureWithLatency<E: APIEndpoint>(
        for endpoint: E.Type,
        path: String,
        method: HTTPMethod,
        statusCode: Int,
        body: Data,
        latency: TimeInterval,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) {
        register { request in
            guard request.url?.path == path else { return nil }
            guard request.httpMethod == method.rawValue else { return nil }
            if latency > 0 {
                Thread.sleep(forTimeInterval: latency)
            }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (resp, body)
        }
    }

    /// Register a forced-failure handler scoped to a specific path + method.
    ///
    /// HTTP-status kinds (`.http(statusCode:body:)`) route through the success-response
    /// triplet — `URLSession.data(for:)` returns the `(Data, HTTPURLResponse)` pair.
    /// URLError kinds (`.urlError(code)`) route through `client?.urlProtocol(_:didFailWithError:)`
    /// — `URLSession.data(for:)` throws the `URLError`.
    ///
    /// Storage is separate from `_handlers` (the success-handler array). Success handlers
    /// are checked FIRST in `startLoading()`; failure handlers are checked only if no success
    /// handler matched. This means a failure-handler will never shadow a success fixture on
    /// the same path (MockURLProtocolForcedFailureTests Test 5 — coexistence).
    public static func registerForcedFailure(
        for path: String,
        method: HTTPMethod,
        kind: InjectedFailure
    ) {
        let handler: FailureHandler = { request in
            guard request.url?.path == path else { return nil }
            guard request.httpMethod == method.rawValue else { return nil }
            return kind
        }
        failureHandlersLock.withLock { _failureHandlers.append(handler) }
    }

    /// Clear all registered failure handlers. Tests that use forced-failure handlers
    /// call BOTH `MockURLProtocol.reset()` AND `MockURLProtocol.resetFailureHandlers()`
    /// at top of test body + matching `defer` for teardown.
    public static func resetFailureHandlers() {
        failureHandlersLock.withLock { _failureHandlers.removeAll() }
    }

    /// Internal dispatch helper called from `startLoading()` after the success-handler
    /// for-loop returns no match. Returns true iff a failure handler matched and
    /// dispatched a response/error to the client; false otherwise (caller continues
    /// to the 404 fallback).
    fileprivate static func dispatchFailureHandlers(
        for request: URLRequest,
        client: URLProtocolClient?,
        protocolInstance: URLProtocol
    ) -> Bool {
        for handler in currentFailureHandlers {
            guard let kind = handler(request) else { continue }
            switch kind {
            case .http(let statusCode, let body):
                let url = request.url ?? URL(string: "about:blank")!
                let resp = HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(protocolInstance, didReceive: resp, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(protocolInstance, didLoad: body)
                client?.urlProtocolDidFinishLoading(protocolInstance)
                return true
            case .urlError(let code):
                let error = URLError(code)
                client?.urlProtocol(protocolInstance, didFailWithError: error)
                return true
            }
        }
        return false
    }
}
