// validationLedgerTests/Features/Onboarding/Auth/PhoneEntryViewModelTests.swift
// Phase 3 Plan 09 — AUTH-01 + GEO-01 + GEO-02 + D-20 + D-26.
// Per 03-PATTERNS.md flagged convention: unit tests use Swift Testing (`import Testing`),
// NOT XCTest. XCUITests stay on XCTest in a separate target.

import Testing
import Foundation
import CoreLocation
@testable import validationLedger

@Suite("PhoneEntryViewModel — E.164 + geo gate orchestration (AUTH-01, GEO-01, GEO-02, D-20, D-26)")
@MainActor
struct PhoneEntryViewModelTests {

    // MARK: - Fakes

    @MainActor
    final class FakeLocation: LocationProvider {
        var permissionStatus: CLAuthorizationStatus = .authorizedWhenInUse
        var location: CLLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        var locationError: Error?
        func requestPermission() async -> CLAuthorizationStatus { permissionStatus }
        func currentLocation(maxAge: TimeInterval, maxAccuracy: CLLocationDistance) async throws -> CLLocation {
            if let locationError { throw locationError }
            return location
        }
    }

    final class FakeCountryGate: CountryGate, @unchecked Sendable {
        var stubbedISO: String = "US"
        var stubbedError: Error?
        func resolveCountry(for location: CLLocation) async throws -> String {
            if let stubbedError { throw stubbedError }
            return stubbedISO
        }
    }

    // MARK: - Static format helpers (D-26)

    @Test("D-26 formatDisplay — 10 digits → `(XXX) XXX-XXXX`")
    func formatDisplayFull() {
        #expect(PhoneEntryViewModel.formatDisplay("5551234567") == "(555) 123-4567")
    }

    @Test("D-26 formatDisplay — short inputs format progressively")
    func formatDisplayPartial() {
        #expect(PhoneEntryViewModel.formatDisplay("555") == "555")
        #expect(PhoneEntryViewModel.formatDisplay("5551") == "(555) 1")
        #expect(PhoneEntryViewModel.formatDisplay("5551234") == "(555) 123-4")
    }

    @Test("D-26 formatE164 — prepends +1 to digits")
    func formatE164() {
        #expect(PhoneEntryViewModel.formatE164("5551234567") == "+15551234567")
    }

    @Test("D-26 submit gate — enabled only at exactly 10 digits")
    func submitGate() {
        let vm = makeVM(loc: FakeLocation(), gate: FakeCountryGate())
        vm.phoneDigits = "555123456"
        #expect(vm.submitEnabled == false)
        vm.phoneDigits = "5551234567"
        #expect(vm.submitEnabled == true)
        vm.phoneDigits = "55512345678"
        // 11 digits — still false (gate is exact match).
        #expect(vm.submitEnabled == false)
    }

    // MARK: - submit() orchestration (D-20)

    @Test("D-21 submit with permission denied → state .needsLocationPermission")
    func submitWithDeniedPermission() async {
        let loc = FakeLocation()
        loc.permissionStatus = .denied
        let vm = makeVM(loc: loc, gate: FakeCountryGate())
        vm.phoneDigits = "5551234567"
        await vm.submit()
        #expect(vm.state == .needsLocationPermission)
    }

    @Test("D-20 submit with non-US country → state .nonUSCountry")
    func submitNonUS() async {
        let gate = FakeCountryGate()
        gate.stubbedISO = "CA"
        let vm = makeVM(loc: FakeLocation(), gate: gate)
        vm.phoneDigits = "5551234567"
        await vm.submit()
        #expect(vm.state == .nonUSCountry)
    }

    @Test("D-21 submit with geocode failure → state .nonUSCountry (defense-in-depth)")
    func submitGeocodeFailure() async {
        let gate = FakeCountryGate()
        gate.stubbedError = GeoError.cannotResolveCountry
        let vm = makeVM(loc: FakeLocation(), gate: gate)
        vm.phoneDigits = "5551234567"
        await vm.submit()
        #expect(vm.state == .nonUSCountry)
    }

    // MARK: - Helpers

    private func makeVM(loc: any LocationProvider, gate: any CountryGate) -> PhoneEntryViewModel {
        // The 6 tests above fail BEFORE APIClient is called, so any APIClient placeholder
        // works. Construct a minimal in-memory client backed by MockURLProtocol.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let netClient = URLSessionNetworkClient(config: .mock, session: session)
        let api = APIClient(
            baseURL: URL(string: "https://mock.local")!,
            networkClient: netClient,
            requestInterceptors: [],
            responseInterceptors: []
        )
        return PhoneEntryViewModel(
            apiClient: api,
            location: loc,
            countryGate: gate,
            logger: NoOpLogger()
        )
    }
}

// MARK: - Test fakes

private final class NoOpLogger: Logger, @unchecked Sendable {
    func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {}
    func log(_ level: LogLevel, _ message: String) {}
}
