// validationLedger/Core/Auth/LogoutService.swift
// Phase 3 D-16 / D-17 (Plan 07): SINGLE source of truth for session teardown.
// Three call sites all funnel here:
//   - ProfileViewController (Plan 10) "Log out" tap → .userInitiated
//   - Auth401ResponseInterceptor (Plan 07 Task 3)   → .auth401  (D-28)
//   - DEV-06 "another active session" path          → .anotherActiveSession  (D-18)
//
// 6-step orchestration (D-16) — order matters for race-safety (Pitfall 3:
// notification post is the LAST step, after all teardown completes).
//
// === Warning 2 fix: Steps 2 + 4 collapse ===
// D-16 documents 6 conceptual steps; the implementation collapses Step 2
// (deleteAll(under: .session)) and Step 4 (clear stored evaluatedPolicyDomainState)
// because KeychainScope.session (Plan 04) INCLUDES .biometricDomainState in the
// delete set. The 6-step contract is preserved at the documented level; the
// implementation does 5 actual Keychain ops. Test `logoutClearsBiometricDomainState`
// asserts that `try? keychain.get(.biometricDomainState)` returns nil post-logout.

import Foundation

public enum LogoutReason: String, Sendable {
    case userInitiated
    case auth401
    case anotherActiveSession
}

extension Notification.Name {
    /// Posted by `LogoutService` AFTER all teardown steps complete (Pitfall 3).
    /// SceneDelegate (Plan 11) observes this and root-swaps the AppPhase based on
    /// the `userInfo[.LogoutReasonKey]` string raw-value.
    public static let sessionDidInvalidate = Notification.Name("validationLedger.sessionDidInvalidate")

    /// userInfo key for `LogoutReason.rawValue` (stable encoding per D-30).
    public static let LogoutReasonKey = Notification.Name("validationLedger.LogoutReasonKey")
}

public protocol LogoutService: AnyObject, Sendable {
    func logout(reason: LogoutReason) async
}

@MainActor
public final class DefaultLogoutService: LogoutService {
    private let keychain: KeychainStore
    private let keyStore: any KeyStoreProtocol
    private let sessionLock: any SessionLockService
    private let logger: any Logger
    private let notificationCenter: NotificationCenter

    public init(
        keychain: KeychainStore,
        keyStore: any KeyStoreProtocol,
        sessionLock: any SessionLockService,
        logger: any Logger,
        notificationCenter: NotificationCenter = .default
    ) {
        self.keychain = keychain
        self.keyStore = keyStore
        self.sessionLock = sessionLock
        self.logger = logger
        self.notificationCenter = notificationCenter
    }

    public func logout(reason: LogoutReason) async {
        logger.info(event: .init("logout_started"), fields: [.event: reason.rawValue])

        // STEP 1: Clear in-memory session state — services hold their own state;
        // SessionLockService.invalidate (step 5) handles its part. Other in-memory
        // state lives in Coordinators/ViewModels which are torn down by the
        // SceneDelegate observer (post-step-6) when it root-swaps.

        // STEP 2 + STEP 4 (collapsed per Warning 2 fix):
        // Wipe session Keychain entries — sessionToken, sessionRole, sessionUserID,
        // AND biometricDomainState. KeychainScope.session (Plan 04) includes ALL FOUR.
        // Step 4 of D-16 ("clear stored evaluatedPolicyDomainState from Keychain")
        // is therefore subsumed by this single deleteAll call. The 6-step contract
        // is preserved at the documented level; this implementation collapses to
        // one Keychain operation for atomicity + simplicity.
        try? keychain.deleteAll(under: .session)

        // STEP 3: Delete SE authorization key (deviceKey is preserved — device identity,
        // not session-bound — the next OTP-verify re-registers with the same deviceKey).
        try? keyStore.deleteKey(slot: .authorization)

        // STEP 5: Invalidate session lock state.
        sessionLock.invalidate()

        // STEP 6: Post notification LAST (Pitfall 3 — observers must see fully-cleared state).
        logger.info(event: .init("logout_complete"), fields: [.event: reason.rawValue])
        notificationCenter.post(
            name: .sessionDidInvalidate,
            object: nil,
            userInfo: [Notification.Name.LogoutReasonKey: reason.rawValue]
        )
    }
}
