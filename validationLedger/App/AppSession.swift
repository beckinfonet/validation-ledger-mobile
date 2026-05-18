// validationLedger/App/AppSession.swift
// Phase 4 DEV-04 (D-12 + D-14): mutable session-scoped state holder referenced
// by AppContainer.session.
//
// Currently tracks:
//   - trustTier: TrustTier — set by /device/register + /device/heartbeat
//     responses (D-12). Default at construct time is .softwareOnly — the safe
//     default: LimitedTrustBanner (Plan 08) shows until the backend confirms
//     .hardwareAttested. Brief over-showing of the banner is preferable to
//     ever missing the banner when the backend actually said softwareOnly.
//
// Why a class (not a struct on AppContainer): AppContainer's properties are
// all `let` by convention, but trustTier is mutable across the lifetime of a
// session — heartbeat responses can downgrade/upgrade it. A
// `@MainActor final class` gives reference semantics so the Plan 07
// SceneDelegate heartbeat helper + Plan 08 banner render both read/write
// through the same holder.
//
// Thread safety: `@MainActor` — all reads + writes occur on the main actor.
// Plan 07 SceneDelegate helper is @MainActor; Plan 08 banner render is
// @MainActor; AppContainer.init runs on the main thread in the app bootstrap
// path. Swift concurrency enforces serialization; no ad-hoc locking needed.
//
// Lifetime: one AppSession instance per AppContainer. Logout (SESS-04) does
// NOT mutate AppSession — the container itself is discarded (or swapped) on
// logout per the ARCH-04 abrupt-replace pattern, so a fresh AppSession with
// the default .softwareOnly tier is constructed by the post-logout container.
//
// Threat model (04-06 T-APP-ATTEST-07): `@MainActor` class + Swift
// concurrency enforce that `trustTier` mutations serialize. Plan 07
// heartbeat helper + Plan 08 banner render are both @MainActor, so reads
// and writes cannot race.

import Foundation

// Phase 6 Plan 03 (D6-10 / WARNING-2): trustTier observation.
//
// `AppSession` STAYS a plain `@MainActor final class` — NO SwiftUI
// `@Observable` / `ObservableObject` (UIKit-first, CLAUDE.md). The observation
// mechanism is a `Notification.Name` posted from the `trustTier` `didSet`,
// mirroring the project's existing `.sessionDidInvalidate` precedent (a
// cross-object UIKit observation channel). `AppCoordinator` subscribes —
// scoped to its container's `AppSession` instance — so the role-shell
// `LimitedTrustBanner` re-renders when the heartbeat (D-12) or the first-login
// consumer mutates the tier, WITHOUT a root-swap and WITHOUT animation
// (ADR 0002 abrupt-replace posture).
extension Notification.Name {
    /// Posted by `AppSession` from the `trustTier` `didSet`. The `object` is the
    /// posting `AppSession` instance (observers scope to it); `userInfo` carries
    /// the new tier's `rawValue` under `AppSession.trustTierUserInfoKey`.
    public static let trustTierDidChange = Notification.Name("validationLedger.trustTierDidChange")
}

@MainActor
public final class AppSession {

    /// `userInfo` key for the new `TrustTier.rawValue` on a `.trustTierDidChange`
    /// post. A `String` rawValue (not the enum) keeps the `userInfo` dictionary
    /// `Sendable`-clean and avoids leaking a non-`Sendable` payload.
    public static let trustTierUserInfoKey = "trustTier"

    /// Server-returned trust tier. Default is `.softwareOnly` (safe default —
    /// LimitedTrustBanner in Plan 08 renders until backend confirms
    /// `.hardwareAttested`). Set on every `/device/register` +
    /// `/device/heartbeat` response (D-12).
    ///
    /// Observable (D6-10): every mutation posts `.trustTierDidChange` so the
    /// role-shell banner re-renders. `AppContainer` seeds the initial value from
    /// the persisted `device.trustTier` Keychain item (D6-01 consumer) — that
    /// initial seed is set through `init` and does NOT post (no observer is
    /// wired yet at construction time).
    public var trustTier: TrustTier {
        didSet {
            NotificationCenter.default.post(
                name: .trustTierDidChange,
                object: self,
                userInfo: [Self.trustTierUserInfoKey: trustTier.rawValue]
            )
        }
    }

    public init(trustTier: TrustTier = .softwareOnly) {
        self.trustTier = trustTier
    }
}
