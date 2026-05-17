// validationLedger/App/AppDelegate.swift
// UIKit lifecycle entry point (ARCH-01). First-launch Keychain wipe runs HERE,
// BEFORE AppContainer resolves (D-20 invariant enforced by placement).
//
// Phase 5 Plan 07 (UPL-05): the KYC background-upload-continuation BGTask handler
// is REGISTERED here, at launch, before `didFinishLaunchingWithOptions` returns —
// `BGTaskScheduler.register` traps if called any later (RESEARCH Pattern 6). The
// `KYCUploadScheduler` is owned by AppDelegate (the single instance) and passed
// into every composition root the SceneDelegate builds. The BGTask handler
// captures the SCENE composition root's `kycUploader` via the scheduler's
// live-uploader slot (filled by SceneDelegate) — it never builds a fresh
// composition root here, so only one `KYCSessionStore` ever touches the on-disk
// store (threat T-05-07-06). The `grep` gate asserts zero composition-root
// construction in this file.
//
// No SwiftUI in this file or anywhere in validationLedger/App/ (ARCH-01).

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Phase 5 Plan 07 (UPL-05): the single KYC background-upload scheduler. Its
    /// BGTask launch handler is registered in `didFinishLaunchingWithOptions`;
    /// `SceneDelegate` reads this and (a) fills its live-uploader slot, (b) calls
    /// `scheduleUploadContinuation` on background. Owned here for the app's
    /// lifetime — the BGTask handler is registered exactly once per process.
    let kycUploadScheduler = KYCUploadScheduler(
        logger: OSLogLoggerImpl(
            subsystem: LoggingSubsystem.identity,
            category: "identity.kyc.bgtask"
        )
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // D-20 / FOUND-02: wipe Keychain on first install.
        // Runs synchronously before SceneDelegate constructs AppContainer.
        // Cannot log here — Logger is resolved in AppContainer (which must NOT exist yet).
        KeychainWiper.wipeOnFirstLaunch(defaults: .standard, accessGroup: nil)

        // UPL-05: register the BGTask launch handler BEFORE launch completes
        // (RESEARCH Pattern 6 — BGTaskScheduler.register traps if called later).
        // The handler resolves the uploader via the scheduler's live-uploader
        // slot, which SceneDelegate fills with the scene AppContainer's
        // `kycUploader` — the handler captures that uploader, never a new
        // AppContainer (threat T-05-07-06).
        kycUploadScheduler.registerHandler()

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
