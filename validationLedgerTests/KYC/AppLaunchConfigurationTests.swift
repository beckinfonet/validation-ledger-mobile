// validationLedgerTests/KYC/AppLaunchConfigurationTests.swift
// Regression guard for the legacy-window-sizing bug (debug session
// `front-camera-preview-black`, round 5 / Bug A).
//
// THE BUG: the app's Info.plist declared a `UIApplicationSceneManifest` but NO
// `UILaunchScreen` (and no launch storyboard exists anywhere in the project).
// Without a launch screen iOS runs the app in a LEGACY compatibility canvas of
// 320×480 — the `UIWindowScene` never receives the real device geometry, so
// `UIWindow(windowScene:)` and every VC pushed into it are 320×480 on a
// 393×852 device. The on-device `kyc_camera event=final_state` log proved this:
// `view.bounds={{0,0},{320,480}}` on a Dynamic-Island iPhone.
//
// THE FIX: an empty `<key>UILaunchScreen</key><dict/>` opts the app into the
// modern launch path; iOS then sizes the window to the full device geometry.
//
// This test asserts the key's presence so a future Info.plist edit cannot
// silently drop it and reintroduce the 320×480 legacy canvas. Mirrors
// `CameraUsageDescriptionTests` / `BiometricServiceTests` /
// `CountryGateTests` plist-assertion pattern (a unit test cannot exercise the
// OS launch canvas itself — the key-presence check is the locking mechanism).

import Testing
import Foundation
@testable import validationLedger

@Suite("App launch configuration — modern (non-legacy) window sizing")
struct AppLaunchConfigurationTests {

    @Test("Info.plist declares UILaunchScreen so the window is not capped at the legacy 320×480 canvas")
    func infoPlistHasLaunchScreen() throws {
        let source = try Self.infoPlistSource()
        #expect(source.contains("<key>UILaunchScreen</key>"),
                "Info.plist is missing UILaunchScreen — without it iOS runs the app in a legacy 320×480 compatibility canvas and every view controller (incl. the KYC face-capture screen) is 320×480 instead of full-screen on a modern device")
    }

    // MARK: - Helpers

    /// Reads Info.plist via #filePath-relative URL. This file lives at
    /// validationLedgerTests/KYC/AppLaunchConfigurationTests.swift — 3 hops to
    /// repo root; the project's Info.plist is validationLedger/App/Info.plist.
    static func infoPlistSource(file: StaticString = #filePath) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let repoRoot = fileURL
            .deletingLastPathComponent()  // KYC/
            .deletingLastPathComponent()  // validationLedgerTests/
            .deletingLastPathComponent()  // <repo root>
        let target = repoRoot
            .appendingPathComponent("validationLedger")
            .appendingPathComponent("App")
            .appendingPathComponent("Info.plist")
        return try String(contentsOf: target, encoding: .utf8)
    }
}
