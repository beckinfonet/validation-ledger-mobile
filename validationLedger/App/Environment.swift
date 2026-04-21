// validationLedger/App/Environment.swift
// Build-config-driven environment selector. Phase 1 only uses `.current`
// (derived from `#if DEBUG`); Phase 2 adds dev/staging/prod with real
// base URLs for live networking.

import Foundation

public struct Environment: Sendable {
    public let name: String
    public let keychainAccessGroup: String?
    /// Base URL for live networking — nil in Phase 1 (mock-only).
    public let apiBaseURL: URL?

    public static let current: Environment = {
        #if DEBUG
        return Environment(
            name: "debug",
            keychainAccessGroup: nil,     // Phase 1: no access group declared yet (entitlements in Phase 2+)
            apiBaseURL: nil               // Phase 1: mock network only
        )
        #else
        return Environment(
            name: "release",
            keychainAccessGroup: nil,
            apiBaseURL: nil
        )
        #endif
    }()
}
