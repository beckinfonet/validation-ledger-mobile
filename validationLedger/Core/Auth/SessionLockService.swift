// validationLedger/Core/Auth/SessionLockService.swift
import Foundation

public protocol SessionLockService: AnyObject, Sendable {
    /// True if the app MUST show a biometric prompt before revealing content.
    /// Unified invariant: cold-boot-with-valid-token OR background>5min-then-foreground
    /// OR never-unlocked-this-session.
    func shouldRequireBiometric(now: Date) -> Bool

    /// Record a successful biometric. Called from Phase 3 biometric service.
    func recordBiometricSuccess(at: Date)

    /// Clear the stored timestamp (e.g., on logout).
    func invalidate()
}

// Phase 1 stub — returns true always initially (forces caller to handle the unlock path).
public final class DefaultSessionLockService: SessionLockService, @unchecked Sendable {
    private var lastSuccess: Date?
    private let backgroundGrace: TimeInterval = 5 * 60
    private let lock = NSLock()

    public init() {}

    public func shouldRequireBiometric(now: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let last = lastSuccess else { return true }
        return now.timeIntervalSince(last) > backgroundGrace
    }

    public func recordBiometricSuccess(at date: Date) {
        lock.lock(); defer { lock.unlock() }
        lastSuccess = date
    }

    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        lastSuccess = nil
    }
}
