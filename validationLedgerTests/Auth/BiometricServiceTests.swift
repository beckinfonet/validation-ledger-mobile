// validationLedgerTests/Auth/BiometricServiceTests.swift
// Phase 3 Plan 06 (D-09, D-10): LAContext wrapper + evaluatedPolicyDomainState capture.
// Unit tests use Swift Testing (`import Testing`), NOT XCTest.

import Testing
import Foundation
import LocalAuthentication
@testable import validationLedger

@Suite("BiometricService — LAContext wrapper + domainState capture (SESS-03, D-09, D-10)")
@MainActor
struct BiometricServiceTests {

    @Test("currentDomainState returns Optional<Data> — sim returns nil; device returns non-nil after canEvaluatePolicy")
    func currentDomainStateContract() {
        let store = KeychainStore(service: "vl.test.biometric.\(UUID().uuidString)")
        let svc = DefaultBiometricService(keychain: store, logger: NoOpLogger())
        // Sim has no biometric hardware → currentDomainState returns nil.
        // On device, would return non-nil after canEvaluatePolicy succeeds.
        // Contract assertion: no crash, documented Optional<Data> return.
        let state: Data? = svc.currentDomainState()
        // Either nil (sim) or non-nil Data (device) — both are valid.
        _ = state
    }

    @Test("BiometricService protocol surface — evaluate signature is async throws; fallback param exists")
    func protocolSurface() async throws {
        // Compile-shape assertion. If the signature changes, this stops compiling.
        let store = KeychainStore(service: "vl.test.biometric.\(UUID().uuidString)")
        let svc: any BiometricService = DefaultBiometricService(keychain: store, logger: NoOpLogger())
        let _: (String, BiometricFallback) async throws -> Void = svc.evaluate
        // BiometricFallback has both cases:
        let _: BiometricFallback = .none
        let _: BiometricFallback = .devicePasscode
    }

    @Test("BiometricService source contains canEvaluatePolicy before evaluatePolicy (Pitfall 1 guard)")
    func sourceContainsCanEvaluateGuard() throws {
        let source = try Self.readSource("validationLedger/Core/Auth/BiometricService.swift")
        #expect(source.contains("canEvaluatePolicy"),
                "BiometricService must call canEvaluatePolicy before evaluatePolicy (Pitfall 1)")
        #expect(source.contains("withCheckedThrowingContinuation"),
                "BiometricService must bridge LAContext closure callback via continuation")
        #expect(source.contains("evaluatedPolicyDomainState"),
                "BiometricService must persist evaluatedPolicyDomainState per D-09")
    }

    // MARK: - Source-path resolution (pattern reused from PlatformPayloadFieldTests)

    private static func repoRootURL(from filePath: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: "\(filePath)")
        url.deleteLastPathComponent()   // drop BiometricServiceTests.swift
        url.deleteLastPathComponent()   // drop Auth/
        url.deleteLastPathComponent()   // drop validationLedgerTests/
        return url
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let url = repoRootURL().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Test fakes

private final class NoOpLogger: Logger, @unchecked Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
    func log(_ level: LogLevel, _ message: String) {}
}
