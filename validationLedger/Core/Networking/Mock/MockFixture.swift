// validationLedger/Core/Networking/Mock/MockFixture.swift
// Test-convenience extension on MockURLProtocol.
// MockURLProtocol.registerFixture(for:path:method:statusCode:body:) is the one-line call
// tests use to register a JSON fixture for a given endpoint. Match is by path + method —
// the endpoint TYPE is passed for symmetric readability with APIEndpoint callers and to
// pin the fixture to the endpoint at review time (readers see "this fixture is for X endpoint").

import Foundation

extension MockURLProtocol {
    /// Register a fixture handler scoped to a specific APIEndpoint's path + method.
    /// The `for endpoint:` parameter is documentation-only — match is by path + method.
    /// Tests pass the endpoint type so the reviewer sees which endpoint the fixture is bound to.
    public static func registerFixture<E: APIEndpoint>(
        for endpoint: E.Type,
        path: String,
        method: HTTPMethod,
        statusCode: Int,
        body: Data,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) {
        register { request in
            guard request.url?.path == path else { return nil }
            guard request.httpMethod == method.rawValue else { return nil }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (resp, body)
        }
    }
}
