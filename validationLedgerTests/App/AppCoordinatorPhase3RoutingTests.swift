// validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift
// Plan 11 (SHELL-01, DEV-06, D-01, D-18): verify the composition root now fills
// .auth (AuthCoordinator) + .anotherActiveSession (AnotherActiveSessionViewController)
// cases on AppCoordinator.makeRoot(for:); AppContainer constructs all 6 new Phase 3
// services; APIClient is wired with Auth401ResponseInterceptor; SceneDelegate cold-boot
// uses the lightweight SessionRestoreProbe helper (Blocker 6) rather than a full
// AppContainer (which would leak SessionLockService notification observers).
//
// Per 03-PATTERNS.md convention: unit tests use Swift Testing; XCUITests remain on XCTest.

import Testing
import Foundation
import UIKit
@testable import validationLedger

@Suite("AppCoordinator — .auth + .anotherActiveSession routing (SHELL-01, DEV-06, D-01, D-18)")
@MainActor
struct AppCoordinatorPhase3RoutingTests {

    // MARK: - Helpers

    private func debugEnv() -> Environment {
        Environment(name: "test", keychainAccessGroup: nil, apiBaseURL: nil)
    }

    private func makeContainer() -> AppContainer {
        AppContainer(
            env: debugEnv(),
            networkConfig: .mock,
            isSecureEnclaveAvailable: true
        )
    }

    private func readSource(_ relativePath: String) throws -> String {
        // Source-level structural assertions walk up from the test bundle's resource
        // root to locate the repo root, then read the canonical relative path. If the
        // file cannot be located we surface a clear error — the assertion is the plan's
        // grep contract, not a runtime-behavior check.
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(relativePath),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // App/
                .deletingLastPathComponent()   // validationLedgerTests/
                .deletingLastPathComponent()   // repo root
                .appendingPathComponent(relativePath),
        ]
        for url in candidates {
            if fm.fileExists(atPath: url.path) {
                return try String(contentsOf: url, encoding: .utf8)
            }
        }
        throw NSError(
            domain: "AppCoordinatorPhase3RoutingTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate \(relativePath)"]
        )
    }

    // MARK: - Tests

    @Test("AppPhase has all 4 cases: launch, auth, role, anotherActiveSession")
    func appPhaseCases() {
        // Compile-time exhaustiveness — if any case is missing, this file fails to build.
        let _: AppPhase = .launch
        let _: AppPhase = .auth
        let _: AppPhase = .role(.shipper)
        let _: AppPhase = .anotherActiveSession
    }

    @Test("AppContainer constructs all 6 Phase 3 services as typed properties")
    func containerHasPhase3Services() {
        let container = makeContainer()
        // Type-only assertions — the `let` properties trap on init failure, so reaching
        // this point confirms construction succeeded. Typed references also ensure the
        // plan's promised protocol-typed properties exist on AppContainer.
        let _: any SessionRestoreService  = container.sessionRestore
        let _: any BiometricService       = container.biometricService
        let _: any SensitiveActionService = container.sensitiveAction
        let _: any LogoutService          = container.logoutService
        let _: any LocationProvider       = container.locationProvider
        let _: any CountryGate            = container.countryGate
    }

    @Test("AppContainer source wires Auth401ResponseInterceptor alongside RetryInterceptor")
    func auth401InterceptorWired() throws {
        let source = try readSource("validationLedger/App/AppContainer.swift")
        #expect(source.contains("Auth401ResponseInterceptor"),
                "AppContainer must wire Auth401ResponseInterceptor into responseInterceptors (Phase 3 D-28)")
        #expect(source.contains("RetryInterceptor"),
                "RetryInterceptor (Phase 2) must remain wired alongside the Phase 3 additions")
    }

    @Test("SceneDelegate source uses SessionRestoreProbe (Blocker 6) and observes .sessionDidInvalidate")
    func sceneDelegateObserves() throws {
        let source = try readSource("validationLedger/App/SceneDelegate.swift")
        #expect(source.contains("sessionDidInvalidate"),
                "SceneDelegate must observe .sessionDidInvalidate per D-18")
        #expect(source.contains("SessionRestoreProbe.probe(env:"),
                "SceneDelegate must call SessionRestoreProbe.probe(env:) on cold-boot per D-04/D-05 + Blocker 6")
        // Blocker 6: the probe path must NOT construct a temporary AppContainer inside
        // the cold-boot block (which would leak SessionLockService notification observers
        // per D-08). presentRoot constructs the real AppContainer separately per ADR 0002.
        if let probeBlockStart = source.range(of: "Phase 3 D-04/D-05") {
            let chunk = source[probeBlockStart.lowerBound...].prefix(800)
            #expect(!chunk.contains("AppContainer(env:"),
                    "Blocker 6: cold-boot probe path must NOT construct a temporary AppContainer — use SessionRestoreProbe.probe(env:) instead")
        } else {
            Issue.record("Expected 'Phase 3 D-04/D-05' marker in SceneDelegate.swift")
        }
    }

    @Test("AppCoordinator source handles .auth and .anotherActiveSession cases")
    func appCoordinatorHandlesPhase3Cases() throws {
        let source = try readSource("validationLedger/App/AppCoordinator.swift")
        #expect(source.contains("AuthCoordinator"),
                "AppCoordinator.makeRoot must construct AuthCoordinator for .auth (D-01)")
        #expect(source.contains("AnotherActiveSessionViewController"),
                "AppCoordinator.makeRoot must construct AnotherActiveSessionViewController for .anotherActiveSession (D-18)")
    }

    @Test("AppCoordinator.makeRoot(.anotherActiveSession) returns an AnotherActiveSessionViewController")
    func makeRootAnotherActiveSession() {
        let container = makeContainer()
        let coord = AppCoordinator(container: container, phase: .anotherActiveSession)
        #expect(coord.rootViewController is AnotherActiveSessionViewController,
                ".anotherActiveSession phase must produce an AnotherActiveSessionViewController root (D-18/D-19)")
    }

    @Test("AppCoordinator.makeRoot(.auth) returns a UINavigationController (AuthCoordinator's root)")
    func makeRootAuth() {
        let container = makeContainer()
        let coord = AppCoordinator(container: container, phase: .auth)
        // AuthCoordinator exposes its nav as rootViewController; AppCoordinator installs
        // that same UINavigationController as its own rootViewController.
        #expect(coord.rootViewController is UINavigationController,
                ".auth phase must produce the AuthCoordinator's UINavigationController root (D-01)")
    }

    @Test("AppCoordinator.makeRoot(.role(.carrier)) routes to a CarrierTabBarController")
    func makeRootRole() {
        let container = makeContainer()
        let coord = AppCoordinator(container: container, phase: .role(.carrier))
        // Phase 4 Plan 08 (D-11/D-12): under the default .softwareOnly trust tier the
        // role tab bar is wrapped in the limited-trust banner container, so the
        // CarrierTabBarController is the wrapper's child rather than the root itself.
        // Under .hardwareAttested the wrapper is a no-op and the tab bar is the root.
        let carrierTabBar = coord.rootViewController as? CarrierTabBarController
            ?? coord.rootViewController.children.first as? CarrierTabBarController
        #expect(carrierTabBar != nil,
                ".role(.carrier) must route to a CarrierTabBarController (RoleCoordinator dispatch preserved, banner-wrapped under .softwareOnly)")
    }

    @Test("SessionRestoreProbe source constructs only lightweight dependencies (Blocker 6)")
    func sessionRestoreProbeIsLightweight() throws {
        // Structural assertion: if the helper instantiated DefaultSessionLockService it
        // would subscribe to UIApplication.didEnterBackgroundNotification per D-08 and
        // leak its observer token when the probe helper is discarded.
        //
        // We scan for CONSTRUCTOR patterns (e.g. `DefaultSessionLockService(`) rather than
        // bare type names so the probe's explanatory comments — which intentionally call
        // out the services it MUST NOT construct — don't trip the negative assertions.
        let source = try readSource("validationLedger/Core/Auth/SessionRestoreProbe.swift")
        #expect(source.contains("DefaultSessionRestoreService("),
                "SessionRestoreProbe must construct DefaultSessionRestoreService")
        #expect(!source.contains("DefaultSessionLockService("),
                "Blocker 6: SessionRestoreProbe must NOT construct DefaultSessionLockService (leaks notification observers per D-08)")
        #expect(!source.contains("DefaultBiometricService("),
                "Blocker 6: SessionRestoreProbe must NOT construct DefaultBiometricService (unneeded for probe)")
        #expect(!source.contains("DefaultLocationProvider("),
                "Blocker 6: SessionRestoreProbe must NOT construct DefaultLocationProvider (unneeded for probe)")
        #expect(!source.contains("DefaultCountryGate("),
                "Blocker 6: SessionRestoreProbe must NOT construct DefaultCountryGate (unneeded for probe)")
    }

    @Test("SessionRestoreProbe.probe returns a SessionRestoreResult without crashing")
    func sessionRestoreProbeRuns() {
        // Exercise the helper end-to-end. Test-process Keychain state is not deterministic,
        // so we accept either branch of the result — the test asserts non-crash + signature.
        let result = SessionRestoreProbe.probe(env: debugEnv())
        switch result {
        case .needsAuth, .restored:
            break
        }
    }

    @Test("SceneDelegate source wires BiometricLockViewController (Phase 3 gap-closure Plan 13 — SESS-01/02/03)")
    func biometricLockWiringIsPresent() throws {
        // 03-VERIFICATION.md gap 1: "grep for 'BiometricLockViewController' across the
        // app source returns only the file itself + comments in SensitiveActionService
        // /BiometricService. Zero construction sites." This test makes that regression
        // impossible — if SceneDelegate ever drops the wiring, this test fails.
        let source = try readSource("validationLedger/App/SceneDelegate.swift")

        // Core construction site — the VC is now actually built by SceneDelegate.
        #expect(source.contains("BiometricLockViewController("),
                "SceneDelegate must construct BiometricLockViewController — closes 03-VERIFICATION.md gap 1")

        // SESS-02: foreground re-check observer for >5min background case.
        #expect(source.contains("UIApplication.didBecomeActiveNotification"),
                "SceneDelegate must observe UIApplication.didBecomeActiveNotification for SESS-02 foreground re-check")

        // Explicit lockState call site — proves the presentation is driven by the
        // SessionLockService state machine (not a hardcoded present).
        #expect(source.contains("sessionLock.lockState(now:"),
                "SceneDelegate must call container.sessionLock.lockState(now:) to decide whether to present the lock VC")

        // Helper + handler names — structural landmarks that make the wiring grep-able.
        #expect(source.contains("presentBiometricLockIfNeeded(container:"),
                "SceneDelegate must expose the presentBiometricLockIfNeeded helper signature")
        #expect(source.contains("handleDidBecomeActive"),
                "SceneDelegate must have handleDidBecomeActive handler for the didBecomeActive observer")

        // SESS-03 M1 placeholder — .biometricReEnrolled funnels through LogoutService.
        #expect(source.contains("logoutService.logout(reason: .userInitiated)"),
                "SceneDelegate's onReBindRequested callback must route through LogoutService.logout(.userInitiated) per 03-VERIFICATION.md gap 1 'missing' item 3 (SESS-03 M1 placeholder)")

        // Idempotency guard — no stacked lock VCs.
        #expect(source.contains("presentedLockVC"),
                "SceneDelegate must hold a weak reference to the presented lock VC to prevent duplicate presentation on didBecomeActive fire-during-prompt")

        // Phase tracking — lock overlay only on .role phase.
        #expect(source.contains("currentPhase"),
                "SceneDelegate must track the current AppPhase so handleDidBecomeActive knows when to re-check lockState (only meaningful on .role)")

        // Security posture — dismiss/present without animation per RESEARCH §iOS API #6.
        #expect(source.contains("animated: false"),
                "SceneDelegate must present and dismiss the lock VC with animated: false (security — no reveal animation)")
    }
}
