// validationLedger/Core/Identity/Geo/CountryGate.swift
// Phase 3 Plan 08 — GEO-02 / D-20 / D-21: reverse-geocode → ISO 3166-1 alpha-2
// country code. Returns "US" for the United States; nil for unverifiable
// (international waters, disputed regions) — but per D-21 defense-in-depth,
// ANY failure (network throw, empty placemarks, nil isoCountryCode) throws
// GeoError.cannotResolveCountry. PhoneEntryViewModel (Plan 09) maps this to
// NotAvailableInRegionViewController.
//
// Backend re-verifies country authoritatively. This client gate is defense-in-
// depth — it blocks accidental non-US auth attempts before the POST fires.
//
// Testability seam:
//   `ReverseGeocoder` protocol wraps `CLGeocoder.reverseGeocodeLocation`.
//   Results flow as `[any PlacemarkLike]` rather than `[CLPlacemark]` because
//   CLPlacemark's `init()` is unavailable on iOS — subclass-with-override is
//   NOT a viable test fake. The protocol seam lets tests construct plain
//   structs; production uses the `CLPlacemarkAdapter` that wraps `CLPlacemark`.
//
// Directory `Core/Identity/Geo/` is allow-listed by the SwiftLint rule
// `ban_raw_coordinate_literal` (Plan 03, D-24).

import CoreLocation
import Foundation

// MARK: - Error surface

public enum GeoError: Error, Sendable, Equatable {
    /// Any failure on the path from (CLLocation) → ISO country code. D-21
    /// defense-in-depth collapses network/empty/nil-iso into a single refusal.
    case cannotResolveCountry
}

// MARK: - Placemark seam

/// The minimal placemark surface CountryGate consumes. Decouples the callsite
/// from `CLPlacemark` so tests can supply a plain struct instead of trying to
/// subclass `CLPlacemark` (whose `init()` is unavailable on iOS).
public protocol PlacemarkLike: Sendable {
    var isoCountryCode: String? { get }
}

/// Production adapter — wraps a `CLPlacemark` and exposes its `isoCountryCode`.
public struct CLPlacemarkAdapter: PlacemarkLike, @unchecked Sendable {
    public let isoCountryCode: String?
    public init(_ placemark: CLPlacemark) {
        self.isoCountryCode = placemark.isoCountryCode
    }
}

// MARK: - Geocoder seam

public protocol ReverseGeocoder: Sendable {
    /// Returns an array of placemarks for the given location (usually one).
    /// Throws on network failure / timeout / ambiguous resolution.
    func reverseGeocode(_ location: CLLocation) async throws -> [any PlacemarkLike]
}

/// Production implementation — wraps `CLGeocoder.reverseGeocodeLocation` and
/// adapts each `CLPlacemark` via `CLPlacemarkAdapter`.
public struct CLReverseGeocoder: ReverseGeocoder {
    private let geocoder: CLGeocoder
    public init() { self.geocoder = CLGeocoder() }

    public func reverseGeocode(_ location: CLLocation) async throws -> [any PlacemarkLike] {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        return placemarks.map { CLPlacemarkAdapter($0) }
    }
}

// MARK: - CountryGate protocol + default implementation

public protocol CountryGate: AnyObject, Sendable {
    /// Returns the ISO 3166-1 alpha-2 country code (e.g., "US").
    /// Throws `GeoError.cannotResolveCountry` on ANY failure (D-21).
    func resolveCountry(for location: CLLocation) async throws -> String
}

public final class DefaultCountryGate: CountryGate, @unchecked Sendable {
    private let geocoder: any ReverseGeocoder

    public init(geocoder: any ReverseGeocoder = CLReverseGeocoder()) {
        self.geocoder = geocoder
    }

    public func resolveCountry(for location: CLLocation) async throws -> String {
        do {
            let placemarks = try await geocoder.reverseGeocode(location)
            guard let iso = placemarks.first?.isoCountryCode, !iso.isEmpty else {
                throw GeoError.cannotResolveCountry
            }
            return iso
        } catch is GeoError {
            throw GeoError.cannotResolveCountry
        } catch {
            // D-21: any underlying error (network, timeout, CLError) → refuse.
            throw GeoError.cannotResolveCountry
        }
    }
}
