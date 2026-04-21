// validationLedger/Core/Networking/MockURLProtocol.swift
// Scaffolding for M1 test transport. Real endpoint fixtures (OTP request/verify,
// device register, KYC chunked upload) land Phase 2 per NET-01..NET-05.
// Phase 1 ships ONE trivial fixture (GET /ping → {"ok":true}) so the test
// target can import + compile without errors.

import Foundation

public final class MockURLProtocol: URLProtocol {
    public static var handlers: [(URLRequest) -> (HTTPURLResponse, Data)?] = [defaultPingHandler]

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        for handler in Self.handlers {
            if let (response, data) = handler(request) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }
        // No handler matched — 404
        let url = request.url ?? URL(string: "about:blank")!
        let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {}

    // Phase 1 single fixture.
    private static let defaultPingHandler: (URLRequest) -> (HTTPURLResponse, Data)? = { request in
        guard let url = request.url, url.path.hasSuffix("/ping") else { return nil }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        let body = Data(#"{"ok":true}"#.utf8)
        return (resp, body)
    }
}
