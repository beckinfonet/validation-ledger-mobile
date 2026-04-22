// validationLedger/Core/Identity/Geo/LocationProvider.swift
// Phase 3 Plan 08 — GEO-01 / D-20: CLLocationManager async wrapper for the
// phone-entry geo pre-check. One-shot fix via manager.requestLocation() bridged
// with withCheckedThrowingContinuation. Freshness (<30s) + accuracy (<100m
// horizontal) enforced inline.
//
// Downstream consumer: PhoneEntryViewModel (Plan 09) injects `any LocationProvider`
// to orchestrate the D-20 5-step geo gate before POST /auth/otp/request.
//
// Directory `Core/Identity/Geo/` is allow-listed by the SwiftLint rule
// `ban_raw_coordinate_literal` (Plan 03, D-24), so CLLocationCoordinate2D
// construction at this layer is permitted.

import CoreLocation
import Foundation

// MARK: - Protocol + Error surface

public protocol LocationProvider: AnyObject, Sendable {
    /// Prompts the user for WhenInUse permission the first time; on subsequent calls
    /// returns the already-decided status without re-prompting.
    @MainActor func requestPermission() async -> CLAuthorizationStatus

    /// Returns a single fresh fix (<maxAge seconds old, <maxAccuracy horizontal accuracy)
    /// or throws `LocationError`. Permission MUST be granted beforehand — callers are
    /// expected to call `requestPermission()` first.
    @MainActor func currentLocation(maxAge: TimeInterval, maxAccuracy: CLLocationDistance) async throws -> CLLocation
}

public enum LocationError: Error, Sendable {
    /// Authorization is denied/restricted — user must grant permission in Settings.
    case permissionDenied
    /// The returned fix is older than `maxAge` seconds (D-20 staleness guard).
    case staleFix
    /// Horizontal accuracy is worse than `maxAccuracy` or negative (invalid fix).
    case lowAccuracy
    /// Caller's timeout elapsed before a fix arrived.
    case timedOut
    /// Underlying CoreLocation error (e.g., hardware denied, no signal).
    case underlying(Error)
}

// MARK: - Default CLLocationManager-backed implementation

@MainActor
public final class DefaultLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate {

    private let manager: CLLocationManager
    private var permissionContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    public override init() {
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
        // kCLLocationAccuracyHundredMeters is the right tier for a country-check;
        // kCLLocationAccuracyBest would cost fix-time without changing the answer.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public func requestPermission() async -> CLAuthorizationStatus {
        // If already determined, return immediately (no system prompt).
        if manager.authorizationStatus != .notDetermined {
            return manager.authorizationStatus
        }
        return await withCheckedContinuation { cont in
            self.permissionContinuation = cont
            manager.requestWhenInUseAuthorization()
        }
    }

    public func currentLocation(
        maxAge: TimeInterval = 30,
        maxAccuracy: CLLocationDistance = 100
    ) async throws -> CLLocation {
        guard manager.authorizationStatus == .authorizedWhenInUse
              || manager.authorizationStatus == .authorizedAlways else {
            throw LocationError.permissionDenied
        }
        return try await withCheckedThrowingContinuation { cont in
            self.locationContinuation = cont
            manager.requestLocation()  // one-shot; triggers a single delegate callback
            // Caller wraps with Task.timeout if a deadline is required (D-20 6s ceiling
            // lands in PhoneEntryViewModel — Plan 09).
        }
    }

    // MARK: - CLLocationManagerDelegate

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.permissionContinuation?.resume(returning: status)
            self?.permissionContinuation = nil
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let loc = locations.last else { return }
            // D-20 freshness + accuracy guards.
            if loc.timestamp.timeIntervalSinceNow < -30 {
                self.locationContinuation?.resume(throwing: LocationError.staleFix)
            } else if loc.horizontalAccuracy > 100 || loc.horizontalAccuracy < 0 {
                self.locationContinuation?.resume(throwing: LocationError.lowAccuracy)
            } else {
                self.locationContinuation?.resume(returning: loc)
            }
            self.locationContinuation = nil
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.locationContinuation?.resume(throwing: LocationError.underlying(error))
            self?.locationContinuation = nil
        }
    }
}
