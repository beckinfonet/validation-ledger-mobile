// validationLedgerTests/KYC/GeoContextTests.swift
// Requirement: Pitfall 5 — GPS freshness/accuracy gate for capture-time geo context.
// GREEN suite (plan 05-03). RED scaffold landed in Wave 0 / plan 05-01.
//
// GeoContext is a thin actor cache OVER the shipped `LocationProvider`. These tests
// inject a stub `LocationProvider` and a fixed `now` closure so the <30s / ≤100m
// freshness gate is exercised deterministically — no real `CLLocationManager`.

import Testing
import Foundation
import CoreLocation
@testable import validationLedger

// MARK: - Test doubles

/// A stub `LocationProvider` that returns a scripted `CLLocation` (or throws) so the
/// GeoContext freshness gate can be tested without CoreLocation hardware.
private final class StubLocationProvider: LocationProvider, @unchecked Sendable {
    /// The location handed back by the next `currentLocation` call. When `nil`,
    /// `currentLocation` throws `nextError` (default `.timedOut`).
    var nextLocation: CLLocation?
    var nextError: LocationError = .timedOut
    /// Count of `currentLocation(...)` invocations — proves refresh is/ isn't called.
    private(set) var currentLocationCallCount = 0

    init(nextLocation: CLLocation? = nil) {
        self.nextLocation = nextLocation
    }

    @MainActor func requestPermission() async -> CLAuthorizationStatus { .authorizedWhenInUse }

    @MainActor func currentLocation(
        maxAge: TimeInterval,
        maxAccuracy: CLLocationDistance
    ) async throws -> CLLocation {
        currentLocationCallCount += 1
        if let loc = nextLocation { return loc }
        throw nextError
    }
}

/// Build a `CLLocation` with a controllable timestamp + horizontal accuracy.
private func makeLocation(
    timestamp: Date,
    horizontalAccuracy: CLLocationAccuracy
) -> CLLocation {
    CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
        altitude: 0,
        horizontalAccuracy: horizontalAccuracy,
        verticalAccuracy: -1,
        timestamp: timestamp
    )
}

@Suite("GeoContext — freshness/accuracy gate (Pitfall 5)")
struct GeoContextTests {

    @Test("A fresh, accurate cached fix is returned by freshLocation()")
    func freshFixIsAccepted() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        // Fix captured 10s before `now`, accuracy 25m — within <30s / ≤100m.
        let location = makeLocation(
            timestamp: fixedNow.addingTimeInterval(-10),
            horizontalAccuracy: 25
        )
        let provider = StubLocationProvider(nextLocation: location)
        let context = GeoContext(locationProvider: provider, now: { fixedNow })

        try await context.refresh()
        let fix = try await context.freshLocation()

        #expect(fix.timestamp == location.timestamp)
        #expect(fix.horizontalAccuracy == 25)
    }

    @Test("A fix that was fresh when cached but is now >30s old is rejected as stale")
    func staleCachedFixIsRejected() async throws {
        // refresh() runs at t0; freshLocation() is read 45s later.
        let captureNow = Date(timeIntervalSince1970: 1_000_000)
        let location = makeLocation(timestamp: captureNow, horizontalAccuracy: 20)

        let provider = StubLocationProvider(nextLocation: location)
        // `now` advances: first read (refresh re-validate path) sees +45s.
        let advancedNow = captureNow.addingTimeInterval(45)
        let context = GeoContext(locationProvider: provider, now: { advancedNow })

        try await context.refresh()
        // The provider will hand back the SAME stale location on the internal
        // refresh retry, so freshLocation() must ultimately throw.
        await #expect(throws: LocationError.self) {
            _ = try await context.freshLocation()
        }
    }

    @Test("A fix with horizontalAccuracy worse than 100m is rejected")
    func lowAccuracyFixIsRejected() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        // Fresh (5s old) but accuracy 250m — fails the ≤100m gate.
        let location = makeLocation(
            timestamp: fixedNow.addingTimeInterval(-5),
            horizontalAccuracy: 250
        )
        let provider = StubLocationProvider(nextLocation: location)
        let context = GeoContext(locationProvider: provider, now: { fixedNow })

        try await context.refresh()
        await #expect(throws: LocationError.self) {
            _ = try await context.freshLocation()
        }
    }

    @Test("A fix with negative horizontalAccuracy (invalid) is rejected")
    func negativeAccuracyFixIsRejected() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let location = makeLocation(
            timestamp: fixedNow.addingTimeInterval(-5),
            horizontalAccuracy: -1
        )
        let provider = StubLocationProvider(nextLocation: location)
        let context = GeoContext(locationProvider: provider, now: { fixedNow })

        try await context.refresh()
        await #expect(throws: LocationError.self) {
            _ = try await context.freshLocation()
        }
    }

    @Test("With no fix ever cached, freshLocation() attempts a refresh then rejects")
    func noCachedFixTriggersRefreshThenRejects() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        // Provider has no location and throws — no fix can ever be cached.
        let provider = StubLocationProvider(nextLocation: nil)
        provider.nextError = .timedOut
        let context = GeoContext(locationProvider: provider, now: { fixedNow })

        await #expect(throws: LocationError.self) {
            _ = try await context.freshLocation()
        }
        // freshLocation() must have attempted at least one refresh.
        #expect(provider.currentLocationCallCount >= 1)
    }

    @Test("A stale cached fix triggers exactly one refresh that yields a fresh fix")
    func staleCacheRefreshesToFreshFix() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        // First refresh() caches a stale fix (60s old).
        let staleFix = makeLocation(
            timestamp: fixedNow.addingTimeInterval(-60),
            horizontalAccuracy: 20
        )
        let provider = StubLocationProvider(nextLocation: staleFix)
        let context = GeoContext(locationProvider: provider, now: { fixedNow })
        try await context.refresh()

        // Before the next freshLocation(), the provider starts returning a FRESH fix.
        let freshFix = makeLocation(
            timestamp: fixedNow.addingTimeInterval(-2),
            horizontalAccuracy: 15
        )
        provider.nextLocation = freshFix

        let resolved = try await context.freshLocation()
        #expect(resolved.timestamp == freshFix.timestamp)
        #expect(resolved.horizontalAccuracy == 15)
    }
}
