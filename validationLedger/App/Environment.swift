// validationLedger/App/Environment.swift
// Build-config-driven environment selector.
// Phase 1: mock-only; apiBaseURL nil in both DEBUG and release.
// Phase 2 Plan 07: .live path wired in AppContainer. release.apiBaseURL remains nil
//                   until the backend GSD project ships real URLs (see WR-06 in
//                   .planning/phases/01-foundational-conventions-scaffolding/01-REVIEW.md).
//                   AppContainer.defaultNetworkConfig(env:) fatalErrors if Release + nil
//                   baseURL, so shipping a Release build without a real URL is impossible
//                   — the binary crashes at launch before any networking is attempted.
//
// CI grep gate (WR-06): `grep 'apiBaseURL: nil' validationLedger/App/Environment.swift`
//                        is allowed while the PHASE-2-TODO marker is present; a future CI
//                        Release-tag job blocks shipping if the marker is still here when
//                        a release tag is pushed. See docs/ci.md WR-06 entry.
//
// When the backend ships real URLs:
//   1. Replace `apiBaseURL: nil` in the #else branch with `URL(string: "https://…")!`
//   2. Remove the PHASE-2-TODO comment + the CI grep-sentinel.
//   3. The Release-tag CI gate passes (no PHASE-2-TODO in Environment.swift).
// Until then, DEBUG builds use .mock and Release builds refuse to launch.

import Foundation

public struct Environment: Sendable {
    public let name: String
    public let keychainAccessGroup: String?
    /// Base URL for live networking — nil in Phase 1 + 2 (mock-only until backend ships).
    public let apiBaseURL: URL?

    public static let current: Environment = {
        #if DEBUG
        return Environment(
            name: "debug",
            keychainAccessGroup: nil,     // Phase 1: no access group declared yet (entitlements in Phase 2+)
            apiBaseURL: nil               // DEBUG: mock network only (AppContainer defaults to .mock)
        )
        #else
        return Environment(
            name: "release",
            keychainAccessGroup: nil,
            // PHASE-2-TODO (WR-06): set to production URL once backend GSD project ships.
            // AppContainer.defaultNetworkConfig(env:) fatalErrors here if nil at Release launch,
            // so shipping with this nil is impossible — CI grep gate is the source-level sentinel.
            apiBaseURL: nil
        )
        #endif
    }()
}

public extension Environment {
    /// Phase 3 D-19: contact for AnotherActiveSessionViewController support flow.
    /// M2+ may upgrade to in-app composer; M1 uses mailto:. Placeholder value —
    /// backend team finalizes pre-Release.
    static let supportEmail: String = "support@validationledger.example"
}
