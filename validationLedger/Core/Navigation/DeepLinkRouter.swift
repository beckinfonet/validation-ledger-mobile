// validationLedger/Core/Navigation/DeepLinkRouter.swift
import Foundation

public final class DeepLinkRouter: @unchecked Sendable {
    public enum State { case cold, ready }
    private var state: State = .cold
    private var queue: [URL] = []
    private let queueLock = NSLock()

    public init() {}

    public var pendingCount: Int {
        queueLock.lock(); defer { queueLock.unlock() }
        return queue.count
    }

    public var isReady: Bool {
        queueLock.lock(); defer { queueLock.unlock() }
        return state == .ready
    }

    public func receive(_ url: URL) {
        queueLock.lock(); defer { queueLock.unlock() }
        if state == .cold {
            queue.append(url)
        } else {
            route(url)
        }
    }

    public func bootstrapComplete() {
        queueLock.lock()
        let pending = queue
        queue.removeAll()
        state = .ready
        queueLock.unlock()
        pending.forEach(route)
    }

    private func route(_ url: URL) {
        // Phase 1: log + no-op. Real handlers wire in Phase 3 (SHELL-*)
        // and M3 (push + universal links).
        // Cannot call Logger here — Phase 1 DeepLinkRouter may be constructed
        // before Logger resolves in AppContainer. Phase 2+ will pass Logger
        // via initializer.
    }
}
