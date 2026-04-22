// validationLedger/Core/Auth/SessionLockService.swift
// Phase 1 FOUND-07 surface, EXTENDED in Phase 3 (Plan 06) with:
//   - lockState(now:) -> LockState          (D-07)
//   - LockReason enum                       (D-07)
//   - UIApplication notification self-subscription (D-08)
//   - evaluatedPolicyDomainState diff via injected BiometricService (D-09)
//
// The Phase 1 shouldRequireBiometric(now:) wrapper is preserved as a convenience
// over lockState(now:) so existing callers + tests continue to compile.

import Foundation
import UIKit  // Phase 3 D-08 — UIApplication notification names

public enum LockReason: Sendable, Equatable {
    case coldBoot
    case backgroundTimeout
    case biometricReEnrolled
    case neverUnlocked   // semantically same as coldBoot; kept for future expressiveness
}

public enum LockState: Sendable, Equatable {
    case unlocked
    case locked(reason: LockReason)
}

public protocol SessionLockService: AnyObject, Sendable {
    // Phase 3 primary API:
    func lockState(now: Date) -> LockState

    // Phase 1 wrapper retained for back-compat:
    func shouldRequireBiometric(now: Date) -> Bool

    func recordBiometricSuccess(at: Date)
    func invalidate()
}

@MainActor
public final class DefaultSessionLockService: SessionLockService {
    // MARK: - Mutable state (MainActor-protected per D-31)
    private var lastSuccess: Date?
    private var enteredBackgroundAt: Date?
    private let backgroundGrace: TimeInterval = 5 * 60

    // MARK: - Dependencies (initializer-DI per ARCH-04)
    private let biometric: any BiometricService
    private let keychain: KeychainStore
    private let notificationCenter: NotificationCenter

    // MARK: - Notification observer tokens (cleaned up in deinit)
    private var bgToken: NSObjectProtocol?
    private var fgToken: NSObjectProtocol?

    public init(
        biometric: any BiometricService,
        keychain: KeychainStore,
        notificationCenter: NotificationCenter = .default
    ) {
        self.biometric = biometric
        self.keychain = keychain
        self.notificationCenter = notificationCenter

        // D-08: self-subscribe to background/foreground transitions on the main queue.
        // [weak self] avoids retain cycle (Pitfall 6).
        bgToken = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Notification callbacks are delivered on the main queue (queue: .main above);
            // hop explicitly into MainActor-isolated code via a Task for Swift-concurrency
            // correctness, and use [weak self] to avoid a retain cycle.
            Task { @MainActor [weak self] in
                self?.enteredBackgroundAt = Date()
            }
        }
        fgToken = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // SceneDelegate observes the same notification and queries lockState — no work here.
        }
    }

    deinit {
        if let bgToken { notificationCenter.removeObserver(bgToken) }
        if let fgToken { notificationCenter.removeObserver(fgToken) }
    }

    // MARK: - SessionLockService

    public func lockState(now: Date) -> LockState {
        // 1) Re-enrollment check (highest priority — overrides everything else).
        if let stored = try? keychain.get(.biometricDomainState),
           let current = biometric.currentDomainState(),
           stored != current {
            return .locked(reason: .biometricReEnrolled)
        }
        // 2) Cold-boot — never authenticated this process.
        guard lastSuccess != nil else {
            return .locked(reason: .coldBoot)
        }
        // 3) Background timeout.
        if let bgAt = enteredBackgroundAt, now.timeIntervalSince(bgAt) > backgroundGrace {
            return .locked(reason: .backgroundTimeout)
        }
        // 4) Within grace AND biometric current — unlocked.
        return .unlocked
    }

    public func shouldRequireBiometric(now: Date) -> Bool {
        return lockState(now: now) != .unlocked
    }

    public func recordBiometricSuccess(at date: Date) {
        lastSuccess = date
        enteredBackgroundAt = nil
    }

    public func invalidate() {
        lastSuccess = nil
        enteredBackgroundAt = nil
        // Per D-16 step 4 + RESEARCH §Anti-Patterns: also clear the stored domainState
        // so a re-login user doesn't get a false biometricReEnrolled prompt.
        try? keychain.delete(.biometricDomainState)
    }
}
