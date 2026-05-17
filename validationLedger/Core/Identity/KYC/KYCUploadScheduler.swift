// validationLedger/Core/Identity/KYC/KYCUploadScheduler.swift
// Phase 5 Plan 07 — UPL-05: the background upload-continuation scheduler.
//
// === RATIFIED USER DECISION (RESEARCH Pitfall 2) ===
// Phase 5 ships the foreground `URLSession` chunk loop (`KYCUploader`, plan 04)
// PLUS a `BGProcessingTaskRequest` that grants the app runtime when it is
// backgrounded mid-upload. It does NOT build a file-based background-mode
// session — that is the explicit M2 follow-up. This file therefore never
// references a background session; the `grep` acceptance gate confirms zero
// file-based-background-session API usage here.
//
// === THE HANDLER CAPTURES THE SCENE CONTAINER'S UPLOADER ===
// `BGTaskScheduler.register` MUST run before launch completes (RESEARCH Pattern 6
// — `register` traps otherwise). But the composition root does not exist at the
// `AppDelegate` launch line. The seam: `AppDelegate` registers the *handler* at
// launch; the `SceneDelegate` fills the live uploader slot once its scene's
// composition root is built. When the BGTask fires, the handler resolves the
// uploader via that slot — it captures the SCENE composition root's
// `kycUploader`, and never builds a second composition root. Building a second
// one would create a second `KYCSessionStore` pointed at the same on-disk file,
// risking a torn read/write (threat T-05-07-06). The `grep` gate asserts zero
// composition-root construction in this file and in `AppDelegate`.

import Foundation
import BackgroundTasks

/// The injectable seam over `BGTaskScheduler`. `BGTaskScheduler` itself cannot
/// run under the simulator test host — registration traps and `submit` is a
/// no-op — so the scheduling DECISION logic is exercised against a fake that
/// conforms to this protocol. `DefaultBGTaskScheduling` wraps the real
/// `BGTaskScheduler.shared` in production.
public protocol BGTaskScheduling: Sendable {
    /// Register a launch handler for `identifier`. Mirrors
    /// `BGTaskScheduler.register(forTaskWithIdentifier:using:launchHandler:)`.
    func register(
        forTaskWithIdentifier identifier: String,
        launchHandler: @escaping @Sendable (BGTask) -> Void
    ) -> Bool

    /// Submit a `BGProcessingTaskRequest`. Mirrors `BGTaskScheduler.submit(_:)`.
    func submit(_ request: BGTaskRequest) throws
}

/// Production `BGTaskScheduling` — delegates to `BGTaskScheduler.shared`.
public struct DefaultBGTaskScheduling: BGTaskScheduling {
    public init() {}

    public func register(
        forTaskWithIdentifier identifier: String,
        launchHandler: @escaping @Sendable (BGTask) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil,
            launchHandler: launchHandler
        )
    }

    public func submit(_ request: BGTaskRequest) throws {
        try BGTaskScheduler.shared.submit(request)
    }
}

/// Schedules + handles the UPL-05 background upload-continuation `BGProcessingTask`.
///
/// One instance is owned by `AppDelegate` (constructed at launch). The
/// `SceneDelegate` hands it the scene `AppContainer`'s `kycUploader` so the
/// BGTask handler resumes the live foreground chunk loop. ARCH-04 initializer-DI:
/// the `BGTaskScheduling` seam is injected (a fake in tests).
public final class KYCUploadScheduler: @unchecked Sendable {

    /// The BGTask identifier — MUST match the `BGTaskSchedulerPermittedIdentifiers`
    /// entry in `Info.plist` (declared by plan 01) or `register`/`submit` trap.
    public static let taskIdentifier = "com.maldin.validationLedger.kyc-upload"

    private let scheduler: BGTaskScheduling
    private let logger: any Logger

    /// The live uploader slot. `SceneDelegate` fills this once its scene's
    /// `AppContainer` is built; the BGTask handler reads it via `uploaderProvider`.
    /// Guarded by `lock` — the handler closure runs on a `BGTaskScheduler` queue
    /// while `SceneDelegate` writes on the main thread.
    private let lock = NSLock()
    private var liveUploader: KYCUploader?

    public init(scheduler: BGTaskScheduling = DefaultBGTaskScheduling(), logger: any Logger) {
        self.scheduler = scheduler
        self.logger = logger
    }

    // MARK: - Live-uploader slot (filled by SceneDelegate)

    /// Store the scene `AppContainer`'s `kycUploader` so the BGTask handler can
    /// resolve it. Called by `SceneDelegate` once the scene container is built.
    public func setLiveUploader(_ uploader: KYCUploader) {
        lock.lock()
        liveUploader = uploader
        lock.unlock()
    }

    /// The `uploaderProvider` the handler resolves at fire-time. Returns the live
    /// scene-container uploader, or `nil` if no scene container has been built
    /// yet (extremely rare — app was never foregrounded). The handler NEVER
    /// constructs an `AppContainer` to satisfy a `nil` here.
    private func currentUploader() -> KYCUploader? {
        lock.lock()
        defer { lock.unlock() }
        return liveUploader
    }

    // MARK: - Registration (called from AppDelegate at launch)

    /// Register the BGTask launch handler. MUST be called from
    /// `application(_:didFinishLaunchingWithOptions:)` BEFORE launch completes —
    /// `BGTaskScheduler.register` traps if called later (RESEARCH Pattern 6).
    ///
    /// The handler resolves the uploader via the live-uploader slot (filled by
    /// `SceneDelegate`). When the slot is `nil` it completes the task with
    /// `success: false` and constructs NOTHING — it never builds an `AppContainer`.
    public func registerHandler() {
        let registered = scheduler.register(
            forTaskWithIdentifier: Self.taskIdentifier
        ) { [weak self] task in
            self?.handle(task)
        }
        if registered {
            logger.info(event: LogEvent("kyc_bgtask_registered"), fields: [:])
        } else {
            // A failed registration is non-fatal — UPL-05 is a best-effort grant
            // of background runtime; the foreground chunk loop still works.
            logger.warn(event: LogEvent("kyc_bgtask_register_failed"), fields: [:])
        }
    }

    // MARK: - Handler (BGTask fire-time)

    /// The BGTask handler. Resolves the live scene-container uploader and runs
    /// `resumeAllPendingUploads()`; sets `task.setTaskCompleted(success:)`.
    ///
    /// On expiry the OS calls `task.expirationHandler` — `KYCUploader` already
    /// persists chunk progress to the store after every ack (plan 04), so an
    /// expiry loses at most the single in-flight chunk; the next launch resumes.
    private func handle(_ task: BGTask) {
        guard let uploader = currentUploader() else {
            // No scene container was ever built — nothing to resume. Complete
            // with success: false and construct NOTHING (no second AppContainer
            // → no second KYCSessionStore — threat T-05-07-06).
            logger.warn(event: LogEvent("kyc_bgtask_no_live_uploader"), fields: [:])
            task.setTaskCompleted(success: false)
            return
        }

        let work = Task {
            await uploader.resumeAllPendingUploads()
            task.setTaskCompleted(success: true)
        }

        // On expiry: cancel the resume work. Progress is already persisted after
        // every ack (plan 04 Pitfall 4) so at most the in-flight chunk is lost.
        task.expirationHandler = { [weak self] in
            work.cancel()
            self?.logger.warn(event: LogEvent("kyc_bgtask_expired"), fields: [:])
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Scheduling (called from SceneDelegate.sceneDidEnterBackground)

    /// Submit a `BGProcessingTaskRequest` IFF `hasPendingUploads` is true. Called
    /// from `SceneDelegate.sceneDidEnterBackground` — when the app backgrounds
    /// with at least one non-committed artifact, the OS is asked for runtime to
    /// keep the foreground chunk loop alive (UPL-05).
    ///
    /// `requiresNetworkConnectivity = true` — a chunk upload needs the network.
    /// `requiresExternalPower = false` — KYC uploads are small; do not gate on a
    /// charger (a driver verifying at the dock is rarely plugged in).
    public func scheduleUploadContinuation(hasPendingUploads: Bool) {
        guard hasPendingUploads else {
            // No incomplete upload — nothing to continue; submit nothing.
            return
        }
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try scheduler.submit(request)
            logger.info(event: LogEvent("kyc_bgtask_scheduled"), fields: [:])
        } catch {
            // A failed submit is non-fatal — the upload resumes on next launch
            // via `resumeAllPendingUploads()` regardless of the BGTask grant.
            logger.warn(event: LogEvent("kyc_bgtask_submit_failed"), fields: [:])
        }
    }
}
