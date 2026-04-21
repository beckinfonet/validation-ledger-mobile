// validationLedger/App/validationLedgerApp.swift
// Minimal UIKit launch stub — Plan 01 removed the SwiftUI scaffold per ARCH-01,
// but the app target still needs a linkable `_main` symbol so the unit-test host
// (TEST_HOST points at validationLedger.app) can load.
//
// Plan 05 replaces this stub with the full AppDelegate + SceneDelegate wiring
// (composition root / AppContainer). Keep this file minimal: a bare UIKit
// AppDelegate with no views, no scenes beyond defaults.
//
// This is a Rule-3 auto-fix applied during Plan 03 because Plan 01's retarget
// removed @main entirely, which broke xcodebuild test (app target fails to link).

import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Plan 05 wires: KeychainWiper.wipeOnFirstLaunch, AppContainer.resolve,
        // RoleCoordinator bootstrap, DeepLinkRouter.bootstrapComplete.
        //
        // Phase-1 stub: no UI is intentionally shown here — this target is
        // exercised via unit tests only for Plan 03.
        return true
    }
}
