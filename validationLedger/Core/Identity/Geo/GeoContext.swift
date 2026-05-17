// validationLedger/Core/Identity/Geo/GeoContext.swift
// Phase 5 Plan 03 — KYC-04 / RESEARCH Pitfall 5: the capture-time geo context.
//
// `GeoContext` is a thin actor cache OVER the shipped `LocationProvider`
// (Phase 3, GEO-01). It does NOT re-bridge CoreLocation — `LocationProvider`
// already owns the `CLLocationManager` continuation plumbing and the <30s /
// ≤100m freshness guards. `GeoContext` adds exactly one thing: a cached fix
// that the KYC capture step can read synchronously and re-validate at the
// moment of capture, refreshing once if it has gone stale.
//
// Why a freshness gate (Pitfall 5): GPS injected from a 60s-old or
// previous-capture fix breaks the product's fraud-detection premise — the
// location and the identity can no longer be correlated. The capture step
// reads through `freshLocation()` ONLY; a stale/inaccurate fix is rejected
// (throws) so capture is blocked until a fresh fix arrives.
//
// Directory `Core/Identity/Geo/` is allow-listed by the SwiftLint rule
// `ban_raw_coordinate_literal` (Phase 3, D-24) — coordinate handling at this
// layer is permitted. This file nonetheless never logs a raw coordinate:
// per GEO-03 / D-23, coordinates leave this layer only as a
// `PlatformPayloadField`, never via `LogField`/`AnalyticsField`.

import CoreLocation
import Foundation

/// Actor cache of a fresh `CLLocation` over the shipped `LocationProvider`.
///
/// Lifecycle: the KYC flow calls `refresh()` once at flow start; each artifact
/// capture calls `freshLocation()` which re-validates the cached fix against
/// the freshness gate and refreshes once if it has gone stale.
public actor GeoContext {

    /// The shipped one-shot location provider. `GeoContext` builds ON this —
    /// it does not duplicate the `CLLocationManager` bridge.
    private let locationProvider: any LocationProvider

    /// Maximum age, in seconds, a cached fix may have and still pass the gate.
    /// Matches `DefaultLocationProvider`'s 30s auth-path threshold (Pitfall 5).
    private let maxAge: TimeInterval

    /// Maximum horizontal accuracy, in meters, a cached fix may have. A fix with
    /// `horizontalAccuracy` worse than this — or negative (an invalid fix) — fails.
    private let maxAccuracy: CLLocationDistance

    /// Injected clock. Defaulting to `Date.init` keeps production behaviour
    /// unchanged; tests inject a fixed closure to exercise the gate deterministically.
    private let now: @Sendable () -> Date

    /// The most recently cached fix, or `nil` if `refresh()` has never succeeded.
    private var cachedFix: CLLocation?

    public init(
        locationProvider: any LocationProvider,
        maxAge: TimeInterval = 30,
        maxAccuracy: CLLocationDistance = 100,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.locationProvider = locationProvider
        self.maxAge = maxAge
        self.maxAccuracy = maxAccuracy
        self.now = now
    }

    /// Acquire a single fresh fix from the `LocationProvider` and cache it.
    ///
    /// Called once at KYC-flow start. Propagates any `LocationError` from the
    /// provider unchanged — a caller that cannot get an initial fix surfaces
    /// the UI-SPEC "couldn't confirm your location" copy.
    public func refresh() async throws {
        let fix = try await locationProvider.currentLocation(
            maxAge: maxAge,
            maxAccuracy: maxAccuracy
        )
        cachedFix = fix
    }

    /// Return a fix that is fresh (≤ `maxAge` old) and accurate (`0 ≤ accuracy ≤
    /// maxAccuracy`) as of `now()`.
    ///
    /// If the cached fix still passes the gate it is returned directly. If it is
    /// stale/inaccurate — or no fix has ever been cached — exactly one `refresh()`
    /// is attempted and the result re-validated; if it still fails the relevant
    /// `LocationError` is thrown. The capture step reads through this method only.
    public func freshLocation() async throws -> CLLocation {
        // Fast path: a previously cached fix that is still within the gate.
        if let fix = cachedFix, gateError(for: fix) == nil {
            return fix
        }

        // Stale, inaccurate, or never cached — attempt one refresh and re-validate.
        try await refresh()

        guard let refreshed = cachedFix else {
            // refresh() returning without a cached fix should be impossible
            // (it either caches or throws) — fail closed rather than return nil.
            throw LocationError.timedOut
        }
        if let error = gateError(for: refreshed) {
            throw error
        }
        return refreshed
    }

    // MARK: - Freshness gate

    /// Evaluate a fix against the freshness + accuracy gate. Returns the
    /// `LocationError` describing the first failed check, or `nil` when the fix
    /// passes. Mirrors `DefaultLocationProvider.didUpdateLocations`'s guards so
    /// the capture path enforces the SAME thresholds as the auth path.
    private func gateError(for fix: CLLocation) -> LocationError? {
        let age = now().timeIntervalSince(fix.timestamp)
        if age > maxAge {
            return .staleFix
        }
        if fix.horizontalAccuracy < 0 || fix.horizontalAccuracy > maxAccuracy {
            return .lowAccuracy
        }
        return nil
    }
}
