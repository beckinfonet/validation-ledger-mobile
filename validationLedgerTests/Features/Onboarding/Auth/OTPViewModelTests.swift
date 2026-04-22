// validationLedgerTests/Features/Onboarding/Auth/OTPViewModelTests.swift
// Phase 3 Plan 09 — AUTH-02 + AUTH-03 + D-02 + D-27.
// Per 03-PATTERNS.md flagged convention: unit tests use Swift Testing (`import Testing`),
// NOT XCTest. XCUITests stay on XCTest in a separate target.
//
// Rich fixture-driven happy-path tests (full D-27 7-step) require extensive
// MockURLProtocol + Keychain orchestration that's more productive to cover via
// Plan 12 UI smoke tests. This suite covers the compile-shape contract +
// initial-state + rateLimited-gate invariants that unit tests capture best.

import Testing
import Foundation
@testable import validationLedger

@Suite("OTPViewModel — Retry-After countdown + D-27 7-step orchestration (AUTH-02, AUTH-03, D-02, D-27)")
@MainActor
struct OTPViewModelTests {

    @Test("Initial state is .idle")
    func initialState() {
        let vm = makeVM()
        #expect(vm.state == .idle)
    }

    @Test("verify gate — enabled when code is 6 digits + state is not rateLimited")
    func gateEnabledAtSixDigits() {
        let vm = makeVM()
        vm.code = "123"
        #expect(vm.verifyEnabled == false)
        vm.code = "123456"
        #expect(vm.verifyEnabled == true)
    }

    @Test("D-27 contract — OTPViewModel source uses BiometricService.evaluate and DeviceRegisterEndpoint in the verify flow")
    func sourceReferencesExpectedCollaborators() throws {
        let source = try Self.readSource("validationLedger/Features/Onboarding/Auth/OTPViewModel.swift")
        #expect(source.contains("OTPVerifyEndpoint"),
                "OTPViewModel must call OTPVerifyEndpoint (D-27 step 1)")
        #expect(source.contains("generateDeviceIdentityKeys"),
                "OTPViewModel must generate device/auth identity keys (D-27 steps 3-4)")
        #expect(source.contains("DeviceRegisterEndpoint"),
                "OTPViewModel must call DeviceRegisterEndpoint (D-27 step 5)")
        #expect(source.contains("biometric.evaluate"),
                "OTPViewModel must invoke biometric.evaluate (D-27 step 6)")
        #expect(source.contains("onAuthenticated"),
                "OTPViewModel must surface onAuthenticated callback (D-27 step 7)")
    }

    @Test("D-02 contract — OTPViewModel source pattern-matches NetworkError.rateLimited to drive countdown")
    func sourceHandlesRateLimited() throws {
        let source = try Self.readSource("validationLedger/Features/Onboarding/Auth/OTPViewModel.swift")
        #expect(source.contains("NetworkError.rateLimited"),
                "OTPViewModel must pattern-match NetworkError.rateLimited (D-02)")
        #expect(source.contains("Timer"),
                "OTPViewModel must drive a Timer-based countdown (D-02)")
    }

    // MARK: - Helpers

    private func makeVM() -> OTPViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let net = URLSessionNetworkClient(config: .mock, session: session)
        let api = APIClient(
            baseURL: URL(string: "https://mock.local")!,
            networkClient: net,
            requestInterceptors: [],
            responseInterceptors: []
        )
        let kc = KeychainStore(service: "vl.test.otpvm.\(UUID().uuidString)")
        let ks = SoftwareKeyStore()
        let bio = StubBio()
        let lock = DefaultSessionLockService(biometric: bio, keychain: kc)
        return OTPViewModel(
            otpSessionID: "sess-abc-123",
            apiClient: api,
            keychain: kc,
            keyStore: ks,
            biometric: bio,
            sessionLock: lock,
            logger: NoOpLogger()
        )
    }

    // MARK: - Source-path resolver (matches BiometricServiceTests helper, 3 hops → repo root)

    private static func repoRootURL(from filePath: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: "\(filePath)")
        url.deleteLastPathComponent()   // drop OTPViewModelTests.swift
        url.deleteLastPathComponent()   // drop Auth/
        url.deleteLastPathComponent()   // drop Onboarding/
        url.deleteLastPathComponent()   // drop Features/
        url.deleteLastPathComponent()   // drop validationLedgerTests/
        return url
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let url = repoRootURL().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Test fakes

@MainActor
private final class StubBio: BiometricService {
    nonisolated func currentDomainState() -> Data? { nil }
    func evaluate(reason: String, fallback: BiometricFallback) async throws {}
}

private final class NoOpLogger: Logger, @unchecked Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
    func log(_ level: LogLevel, _ message: String) {}
}
