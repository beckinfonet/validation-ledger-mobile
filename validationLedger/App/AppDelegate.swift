// validationLedger/App/AppDelegate.swift
// UIKit lifecycle entry point (ARCH-01). First-launch Keychain wipe runs HERE,
// BEFORE AppContainer resolves (D-20 invariant enforced by placement).
//
// No SwiftUI in this file or anywhere in validationLedger/App/ (ARCH-01).

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // D-20 / FOUND-02: wipe Keychain on first install.
        // Runs synchronously before SceneDelegate constructs AppContainer.
        // Cannot log here — Logger is resolved in AppContainer (which must NOT exist yet).
        KeychainWiper.wipeOnFirstLaunch(defaults: .standard, accessGroup: nil)

        return true
    }

    // MARK: - UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // UISceneConfigurationName matches the entry in Info.plist scene manifest.
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
