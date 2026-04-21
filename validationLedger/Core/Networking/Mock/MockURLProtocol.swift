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
        // No handler matched — return 404 so tests fail loudly rather than hang.
        let url = request.url ?? URL(string: "about:blank")!
        let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}
