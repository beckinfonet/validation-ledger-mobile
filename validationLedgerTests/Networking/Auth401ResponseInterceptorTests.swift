// validationLedgerTests/Networking/Auth401ResponseInterceptorTests.swift
// Plan 07 TDD — AUTH-05, D-28: 401 on non-OTP paths fires LogoutService.logout(.auth401);
// /auth/otp/request + /auth/otp/verify are excluded (401 there means "wrong code").
// Per 03-PATTERNS.md flagged convention: unit tests use Swift Testing (`import Testing`),
// NOT XCTest.

import Testing
import Foundation
@testable import validationLedger

// MARK: - Test fakes

/// An actor-backed fake that conforms to LogoutService. The protocol requires
/// `AnyObject, Sendable`; an actor is a reference type (`AnyObject`) and
/// automatically `Sendable`, so conformance works without `@unchecked`.
private actor SpyLogout: LogoutService {
    private(set) var calls: [LogoutReason] = []

    func logout(reason: LogoutReason) async {
        calls.append(reason)
    }

    func callCount() -> Int { calls.count }
    func reasons() -> [LogoutReason] { calls }
}

@Suite("Auth401ResponseInterceptor — non-OTP 401 → logout (AUTH-05, D-28)")
struct Auth401ResponseInterceptorTests {

    private func httpResponse(url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    private func request(path: String) -> URLRequest {
        URLRequest(url: URL(string: "https://test.example.com\(path)")!)
    }

    // MARK: - Tests

    @Test("D-28 default excluded paths are exactly the OTP endpoints")
    func defaultExcludedPaths() {
        #expect(Auth401ResponseInterceptor.defaultExcludedPaths == ["/auth/otp/request", "/auth/otp/verify"])
    }

    @Test("401 on non-OTP path triggers logout(.auth401)")
    func authPath401TriggersLogout() async throws {
        let spy = SpyLogout()
        let interceptor = Auth401ResponseInterceptor(logoutService: spy)
        let req = request(path: "/loads")
        _ = try await interceptor.intercept(
            send: { r in (Data(), self.httpResponse(url: r.url!, status: 401)) },
            request: req
        )
        // Yield to allow the fire-and-forget Task to land.
        try await Task.sleep(nanoseconds: 50_000_000)
        let reasons = await spy.reasons()
        #expect(reasons == [.auth401])
    }

    @Test("401 on /auth/otp/request does NOT trigger logout")
    func otpRequestPath401Excluded() async throws {
        let spy = SpyLogout()
        let interceptor = Auth401ResponseInterceptor(logoutService: spy)
        _ = try await interceptor.intercept(
            send: { r in (Data(), self.httpResponse(url: r.url!, status: 401)) },
            request: request(path: "/auth/otp/request")
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await spy.callCount() == 0)
    }

    @Test("401 on /auth/otp/verify does NOT trigger logout")
    func otpVerifyPath401Excluded() async throws {
        let spy = SpyLogout()
        let interceptor = Auth401ResponseInterceptor(logoutService: spy)
        _ = try await interceptor.intercept(
            send: { r in (Data(), self.httpResponse(url: r.url!, status: 401)) },
            request: request(path: "/auth/otp/verify")
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await spy.callCount() == 0)
    }

    @Test("Non-401 status codes do NOT trigger logout", arguments: [200, 400, 403, 500])
    func nonAuthStatusPassesThrough(status: Int) async throws {
        let spy = SpyLogout()
        let interceptor = Auth401ResponseInterceptor(logoutService: spy)
        _ = try await interceptor.intercept(
            send: { r in (Data(), self.httpResponse(url: r.url!, status: status)) },
            request: request(path: "/loads")
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await spy.callCount() == 0)
    }

    @Test("Interceptor returns the 401 response to the caller (does not swallow it)")
    func passesResponseThrough() async throws {
        let spy = SpyLogout()
        let interceptor = Auth401ResponseInterceptor(logoutService: spy)
        let body = Data("{\"error\":\"unauthorized\"}".utf8)
        let (data, response) = try await interceptor.intercept(
            send: { r in (body, self.httpResponse(url: r.url!, status: 401)) },
            request: request(path: "/loads")
        )
        #expect(data == body)
        #expect(response.statusCode == 401)
    }
}
