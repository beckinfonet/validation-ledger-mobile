// validationLedger/Core/Auth/SessionRestoreProbe.swift
// Phase 3 Plan 11 Blocker 6 fix: lightweight cold-boot probe helper for SceneDelegate.
//
// SceneDelegate calls this BEFORE the first `presentRoot` so it can route to .auth or
// .role(role) based on Keychain state. presentRoot then constructs the FULL AppContainer
// fresh per ADR 0002 (D-10) — observers subscribed by the full container are owned by
// that container's lifetime, which matches the window's rootViewController lifetime, so
// they do not leak.
//
// Why this helper exists — and what it refuses to do:
//   The obvious "just construct an AppContainer, read its sessionRestore, throw it away"
//   approach leaks observer tokens. AppContainer.init constructs DefaultSessionLockService,
//   which subscribes to UIApplication.didEnterBackgroundNotification + didBecomeActive
//   per D-08. Those observers hold a retain path to the SessionLockService instance; the
//   instance holds a retain path to the AppContainer (via `keychain`). Discarding the
//   temp container leaves the observer tokens alive, pointing at a now-orphaned service.
//
// The probe therefore constructs ONLY the minimum needed to call
// `DefaultSessionRestoreService.probe()`:
//   - KeychainStore (no observers, no side-effects)
//   - a stateless Logger fake (no observers, no file handles)
//   - DefaultSessionRestoreService (pure keychain read)
//
// It does NOT instantiate:
//   - DefaultSessionLockService  (would subscribe to UIApplication notifications — D-08)
//   - DefaultBiometricService    (unneeded for probe)
//   - DefaultLocationProvider    (CLLocationManager is expensive to spin up)
//   - DefaultCountryGate         (CLGeocoder is expensive to spin up)
//   - APIClient / URLSession     (networking not needed for a Keychain probe)

import Foundation

public enum SessionRestoreProbe {
    /// Returns `.restored(role:)` when Keychain has a valid sessionToken + sessionRole,
    /// or `.needsAuth` otherwise. Called from `SceneDelegate.scene(_:willConnectTo:)`
    /// before the first `presentRoot` per D-04 / D-05.
    ///
    /// Keychain reads are sub-millisecond — safe to call on the main thread before
    /// the window becomes key and visible.
    public static func probe(env: Environment) -> SessionRestoreResult {
        let keychain = KeychainStore(accessGroup: env.keychainAccessGroup)
        let service = DefaultSessionRestoreService(
            keychain: keychain,
            logger: NoOpProbeLogger()
        )
        return service.probe()
    }
}

/// Stateless logger used only by `SessionRestoreProbe`. Emits nothing; never subscribes to
/// anything; never holds state. Avoids constructing `OSLogLoggerImpl` + `PIIScrubber` for a
/// single one-shot probe where the only log line is `session_restore_needs_auth` /
/// `session_restored`, which the real AppContainer's logger re-emits at the next (real)
/// service call. Using a no-op logger keeps the helper cost near-zero.
private final class NoOpProbeLogger: Logger, @unchecked Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
    func log(_ level: LogLevel, _ message: String) {}
}
