// validationLedgerTests/Identity/Geo/CountryGateTests.swift
// Plan 03-08 Task 2 — fills Plan 01 Wave 0 stub with real red→green tests for
// GEO-02 / D-20 / D-21. D-21 defense-in-depth refusal posture: any geocode
// failure (network throw, empty placemarks, nil isoCountryCode) → throws
// GeoError.cannotResolveCountry.

import Testing
import Foundation
import CoreLocation
@testable import validationLedger

@Suite("CountryGate — reverse-geocode US-only refusal (GEO-02, D-20, D-21)")
struct CountryGateTests {

    // MARK: - Fakes

    /// Stubbed ReverseGeocoder — configurable per-test via either a placemarks array or an error.
    struct StubGeocoder: ReverseGeocoder {
        let stubbedPlacemarks: [CLPlacemark]?
        let stubbedError: Error?

        init(placemarks: [CLPlacemark]? = nil, error: Error? = nil) {
            self.stubbedPlacemarks = placemarks
            self.stubbedError = error
        }

        func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark] {
            if let stubbedError { throw stubbedError }
            return stubbedPlacemarks ?? []
        }
    }

    /// Subclass that overrides `isoCountryCode` — CLPlacemark has no public init
    /// for arbitrary fields, but the property is overridable in Swift.
    private final class TestPlacemark: CLPlacemark {
        private let _iso: String?

        init(isoCountryCode: String?) {
            self._iso = isoCountryCode
            super.init()
        }
        required init?(coder: NSCoder) { fatalError("unused") }
        override var isoCountryCode: String? { _iso }
    }

    // SF coordinates — allowed in Core/Identity/Geo*/ per the SwiftLint allow-list.
    private let testLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)

    // MARK: - Tests

    @Test("US placemark → returns 'US'")
    func resolvesUS() async throws {
        let geocoder = StubGeocoder(placemarks: [TestPlacemark(isoCountryCode: "US")])
        let gate = DefaultCountryGate(geocoder: geocoder)
        let iso = try await gate.resolveCountry(for: testLocation)
        #expect(iso == "US")
    }

    @Test("Non-US placemark → returns the actual ISO (caller decides refusal)")
    func resolvesNonUS() async throws {
        let geocoder = StubGeocoder(placemarks: [TestPlacemark(isoCountryCode: "CA")])
        let gate = DefaultCountryGate(geocoder: geocoder)
        let iso = try await gate.resolveCountry(for: testLocation)
        #expect(iso == "CA")
    }

    @Test("Empty placemarks array → throws GeoError.cannotResolveCountry (D-21)")
    func emptyPlacemarksRefuses() async {
        let geocoder = StubGeocoder(placemarks: [])
        let gate = DefaultCountryGate(geocoder: geocoder)
        do {
            _ = try await gate.resolveCountry(for: testLocation)
            Issue.record("Expected GeoError.cannotResolveCountry")
        } catch GeoError.cannotResolveCountry {
            // expected
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("Nil isoCountryCode in placemark → throws GeoError.cannotResolveCountry (D-21)")
    func nilIsoRefuses() async {
        let geocoder = StubGeocoder(placemarks: [TestPlacemark(isoCountryCode: nil)])
        let gate = DefaultCountryGate(geocoder: geocoder)
        do {
            _ = try await gate.resolveCountry(for: testLocation)
            Issue.record("Expected GeoError.cannotResolveCountry")
        } catch GeoError.cannotResolveCountry {
            // expected
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("Geocoder network failure → throws GeoError.cannotResolveCountry (D-21 defense-in-depth)")
    func networkFailureRefuses() async {
        let netError = NSError(domain: kCLErrorDomain, code: CLError.network.rawValue)
        let geocoder = StubGeocoder(error: netError)
        let gate = DefaultCountryGate(geocoder: geocoder)
        do {
            _ = try await gate.resolveCountry(for: testLocation)
            Issue.record("Expected GeoError.cannotResolveCountry")
        } catch GeoError.cannotResolveCountry {
            // expected
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("Info.plist contains NSLocationWhenInUseUsageDescription")
    func infoPlistHasUsageDescription() throws {
        let source = try Self.infoPlistSource()
        #expect(source.contains("NSLocationWhenInUseUsageDescription"),
                "Info.plist missing NSLocationWhenInUseUsageDescription — required for GEO-01 prompt")
        #expect(source.contains("United States"),
                "Usage description should mention United States — required by App Store reviewers + product spec")
    }

    // MARK: - Helpers

    /// Reads Info.plist via #filePath-relative URL (4 deleteLastPathComponent hops
    /// to repo root). The project's Info.plist lives at validationLedger/App/Info.plist
    /// (verified against validationLedger.xcodeproj INFOPLIST_FILE setting).
    static func infoPlistSource(file: StaticString = #filePath) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let repoRoot = fileURL
            .deletingLastPathComponent()  // Geo/
            .deletingLastPathComponent()  // Identity/
            .deletingLastPathComponent()  // validationLedgerTests/
            .deletingLastPathComponent()  // <repo root>
        let target = repoRoot
            .appendingPathComponent("validationLedger")
            .appendingPathComponent("App")
            .appendingPathComponent("Info.plist")
        return try String(contentsOf: target, encoding: .utf8)
    }
}
