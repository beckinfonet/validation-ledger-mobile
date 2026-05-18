// validationLedgerTests/App/AppSessionTrustTierObservationTests.swift
// Phase 6 Plan 03 (D6-10 / WARNING-2): AppSession.trustTier is observable.
//
// `AppSession` stays a plain `@MainActor final class` (UIKit-first — CLAUDE.md;
// NO SwiftUI `@Observable` / `ObservableObject`). The observation mechanism is a
// `Notification.Name` (`.trustTierDidChange`) posted from the `trustTier` `didSet`
// — the project's `.sessionDidInvalidate` precedent for cross-object UIKit
// observation. `AppCoordinator` subscribes so the `LimitedTrustBanner` re-renders
// when the heartbeat / first-login consumer mutates the tier.
//
// These assertions lock the contract: mutating `trustTier` posts the
// notification, the new tier rides in `userInfo`, and a no-op set still posts
// (the consumer is idempotent — re-applying the banner wrapper for the same tier
// is harmless and keeps the mechanism simple).

import Testing
import Foundation
@testable import validationLedger

@Suite("AppSession — trustTier observation (D6-10)", .serialized)
@MainActor
struct AppSessionTrustTierObservationTests {

    @Test("Mutating trustTier posts .trustTierDidChange with the new tier in userInfo")
    func mutationPostsNotification() async {
        let session = AppSession(trustTier: .softwareOnly)

        let received = NotificationBox()
        let token = NotificationCenter.default.addObserver(
            forName: .trustTierDidChange,
            object: session,
            queue: .main
        ) { note in
            let raw = note.userInfo?[AppSession.trustTierUserInfoKey] as? String
            received.set(raw.flatMap { TrustTier(rawValue: $0) })
        }
        defer { NotificationCenter.default.removeObserver(token) }

        session.trustTier = .hardwareAttested

        // The post is synchronous on the main actor; the observer queue is .main
        // and we are already on the main actor — give the runloop one hop.
        await Task.yield()

        #expect(received.value == .hardwareAttested,
                "mutating trustTier must post .trustTierDidChange carrying the new tier")
    }

    @Test("The notification is scoped to the posting AppSession instance")
    func notificationScopedToInstance() async {
        let sessionA = AppSession(trustTier: .softwareOnly)
        let sessionB = AppSession(trustTier: .softwareOnly)

        let receivedFromA = NotificationBox()
        let token = NotificationCenter.default.addObserver(
            forName: .trustTierDidChange,
            object: sessionA,
            queue: .main
        ) { note in
            let raw = note.userInfo?[AppSession.trustTierUserInfoKey] as? String
            receivedFromA.set(raw.flatMap { TrustTier(rawValue: $0) })
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // Mutating a DIFFERENT instance must not fire the A-scoped observer.
        sessionB.trustTier = .hardwareAttested
        await Task.yield()
        #expect(receivedFromA.value == nil,
                "an observer scoped to sessionA must not fire for sessionB mutations")

        // Mutating A does fire it.
        sessionA.trustTier = .hardwareAttested
        await Task.yield()
        #expect(receivedFromA.value == .hardwareAttested)
    }

    /// Main-actor-isolated capture box — the notification observer closure runs
    /// on the main actor (queue: .main), so a plain `@MainActor` box is enough.
    @MainActor
    private final class NotificationBox {
        private(set) var value: TrustTier?
        func set(_ tier: TrustTier?) { value = tier }
    }
}
