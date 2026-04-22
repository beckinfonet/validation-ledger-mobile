// validationLedgerTests/Identity/Geo/LocationProviderTests.swift
// Plan 03-08 Task 1 — fills Plan 01 Wave 0 stub with real red→green cycle for GEO-01, D-20.
// Per 03-PATTERNS.md flagged convention: unit tests use Swift Testing (`import Testing`),
// NOT XCTest.

import Testing
import Foundation
import CoreLocation
@testable import validationLedger

@Suite("LocationProvider — CLLocationManager async wrapper (GEO-01, D-20)")
@MainActor
struct LocationProviderTests {

    @Test("LocationProvider protocol surface — requestPermission + currentLocation signatures")
    func protocolSurface() {
        // Compile-shape: verifies protocol declares both methods with the expected types.
        let svc: any LocationProvider = DefaultLocationProvider()
        let _: () async -> CLAuthorizationStatus = svc.requestPermission
        let _: (TimeInterval, CLLocationDistance) async throws -> CLLocation = svc.currentLocation
    }

    @Test("LocationError has all 5 cases")
    func locationErrorCases() {
        // Exhaustive case construction — the compiler enforces surface.
        let _: LocationError = .permissionDenied
        let _: LocationError = .staleFix
        let _: LocationError = .lowAccuracy
        let _: LocationError = .timedOut
        let _: LocationError = .underlying(NSError(domain: "test", code: 0))
    }

    @Test("LocationProvider source uses requestLocation (one-shot), NOT startUpdatingLocation")
    func sourceUsesOneShot() throws {
        let source = try Self.locationProviderSource()
        #expect(source.contains("manager.requestLocation()"),
                "Must use one-shot requestLocation per RESEARCH §iOS API #3")
        #expect(!source.contains("startUpdatingLocation"),
                "startUpdatingLocation is for streams, not auth pre-check")
        #expect(source.contains("withCheckedThrowingContinuation"),
                "Continuation bridge required for one-shot async")
    }

    @Test("LocationProvider source enforces D-20 freshness + accuracy guards")
    func sourceEnforcesGuards() throws {
        let source = try Self.locationProviderSource()
        #expect(source.contains("timeIntervalSinceNow < -30"),
                "Staleness guard missing — D-20 requires <30s freshness")
        #expect(source.contains("horizontalAccuracy > 100"),
                "Accuracy guard missing — D-20 requires <100m horizontal")
        #expect(source.contains("horizontalAccuracy < 0"),
                "Negative accuracy = invalid fix; must be rejected")
    }

    @Test("DefaultLocationProvider initializes on simulator without throwing")
    func initSmoke() {
        // Construction smoke — real GPS fix requires sim location set up; deferred
        // to Plan 09 integration tests + manual sim Location simulation.
        _ = DefaultLocationProvider()
    }

    // MARK: - Helpers

    /// Reads LocationProvider.swift via #filePath-relative URL resolution.
    /// Mirrors the pattern used by PlatformPayloadFieldTests (Plan 03) + Plan 02
    /// cr02IdempotentGuardPresent — xcodebuild's CWD is derived-data-scoped, not
    /// repo-root, so CWD-relative reads fail.
    static func locationProviderSource(file: StaticString = #filePath) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let repoRoot = fileURL
            .deletingLastPathComponent()  // Geo/
            .deletingLastPathComponent()  // Identity/
            .deletingLastPathComponent()  // validationLedgerTests/
            .deletingLastPathComponent()  // <repo root>
        let target = repoRoot
            .appendingPathComponent("validationLedger")
            .appendingPathComponent("Core")
            .appendingPathComponent("Identity")
            .appendingPathComponent("Geo")
            .appendingPathComponent("LocationProvider.swift")
        return try String(contentsOf: target, encoding: .utf8)
    }
}
