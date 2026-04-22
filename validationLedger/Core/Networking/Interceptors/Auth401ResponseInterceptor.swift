// validationLedger/Core/Networking/Interceptors/Auth401ResponseInterceptor.swift
// Phase 3 D-28 / AUTH-05 (Plan 07): ResponseInterceptor that triggers
// LogoutService.logout(.auth401) on any HTTP 401 from a non-OTP path.
//
// The interceptor does NOT swallow the response — it returns (data, response)
// normally so the calling endpoint code can still see the 401 (typically maps to
// NetworkError.httpError at the APIClient boundary).
//
// Excluded paths: /auth/otp/request and /auth/otp/verify — a 401 there means
// "wrong code", not "session expired". The LogoutService fire is a detached
// Task so the response returns to the caller immediately; SceneDelegate (Plan 11)
// handles the root-swap when it observes the .sessionDidInvalidate notification.

import Foundation

public struct Auth401ResponseInterceptor: ResponseInterceptor {
    public static let defaultExcludedPaths: Set<String> = [
        "/auth/otp/request",
        "/auth/otp/verify"
    ]

    private let logoutService: any LogoutService
    private let excludedPaths: Set<String>

    public init(
        logoutService: any LogoutService,
        excludedPaths: Set<String> = Auth401ResponseInterceptor.defaultExcludedPaths
    ) {
        self.logoutService = logoutService
        self.excludedPaths = excludedPaths
    }

    public func intercept(
        send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
        request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await send(request)
        if response.statusCode == 401,
           let path = request.url?.path,
           !excludedPaths.contains(path) {
            // Fire-and-forget — caller still gets the 401 response to handle/decode
            // normally. SceneDelegate (Plan 11) handles the root-swap on the
            // .sessionDidInvalidate notification posted by LogoutService.
            let service = logoutService
            Task { await service.logout(reason: .auth401) }
        }
        return (data, response)
    }
}
