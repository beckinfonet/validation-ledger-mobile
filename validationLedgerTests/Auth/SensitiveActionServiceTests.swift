// validationLedgerTests/Auth/SensitiveActionServiceTests.swift
// Plan 07 TDD — AUTH-06 constructibility + D-11 single-prompt design (Blocker 3).
// Per 03-PATTERNS.md flagged convention: unit tests use Swift Testing (`import Testing`),
// NOT XCTest. XCUITests stay on XCTest in a separate target.

import Testing
import Foundation
import LocalAuthentication
@testable import validationLedger

@Suite("SensitiveActionService — M1 single-prompt surface (AUTH-06, D-11, D-12, Blocker 3)")
@MainActor
struct SensitiveActionServiceTests {

    // MARK: - #filePath resolver (matches KeyStoreProtocolDeleteTests helper)

    private func sourcePath(_ relative: String) -> URL {
        // thisFile = <repoRoot>/validationLedgerTests/Auth/SensitiveActionServiceTests.swift
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()   // drop file
            .deletingLastPathComponent()   // drop Auth/
            .deletingLastPathComponent()   // drop validationLedgerTests/
        var url = repoRoot.appendingPathComponent("validationLedger")
        for component in relative.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        return url
    }

    // MARK: - Tests

    @Test("D-12: SensitiveActionService is constructible with the expected dependencies + signature")
    func constructibleWithSignature() {
        let keyStore = SoftwareKeyStore()
        let svc: any SensitiveActionService = DefaultSensitiveActionService(
            keyStore: keyStore,
            logger: NoOpLogger()
        )
        // Signature shape (compile-time only — documents the async-throws contract):
        let _: (Data, String) async throws -> Data = svc.authorize
    }

    @Test("D-11 / Blocker 3: SensitiveActionService source uses .deviceOwnerAuthenticationWithBiometrics (NOT .deviceOwnerAuthentication)")
    func usesStrictBiometricPolicy() throws {
        let source = try String(contentsOf: sourcePath("Core/Auth/SensitiveActionService.swift"), encoding: .utf8)
        #expect(source.contains(".deviceOwnerAuthenticationWithBiometrics"),
                "Sensitive actions must use strict biometric policy (SE ACL .biometryCurrentSet rejects passcode)")
        // Forbid the passcode-fallback policy anywhere in the source. Using the
        // exact-identifier form avoids collisions with the "WithBiometrics" variant.
        #expect(!source.contains(".deviceOwnerAuthentication,"),
                "Sensitive actions must NOT use .deviceOwnerAuthentication policy (would allow passcode unlock that the SE ACL rejects)")
        #expect(!source.contains(".deviceOwnerAuthentication)"),
                "Sensitive actions must NOT use .deviceOwnerAuthentication policy (would allow passcode unlock that the SE ACL rejects)")
    }

    @Test("D-11 / Blocker 3: SensitiveActionService source passes context to keyStore.signWithAuthorization (single-prompt)")
    func passesContextToSign() throws {
        let source = try String(contentsOf: sourcePath("Core/Auth/SensitiveActionService.swift"), encoding: .utf8)
        #expect(source.contains("signWithAuthorization(payload, context: ctx)"),
                "SensitiveActionService must pass the LAContext to keyStore.signWithAuthorization for single-prompt (Blocker 3)")
    }

    @Test("D-11 / Blocker 3: SensitiveActionService does NOT call BiometricService — uses raw LAContext directly (single-prompt)")
    func doesNotUseBiometricService() throws {
        let source = try String(contentsOf: sourcePath("Core/Auth/SensitiveActionService.swift"), encoding: .utf8)
        // The init must NOT take a BiometricService — that would imply the double-prompt design
        // (BiometricService.evaluate then keyStore.sign re-prompts).
        #expect(!source.contains("biometric: any BiometricService"),
                "SensitiveActionService must NOT inject BiometricService — single-prompt uses raw LAContext directly")
        #expect(source.contains("LAContext()"),
                "SensitiveActionService must construct a fresh LAContext per call")
    }
}

// MARK: - Test fakes

private final class NoOpLogger: Logger, @unchecked Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
    func log(_ level: LogLevel, _ message: String) {}
}
