// validationLedger/Core/Identity/PlatformPayloadField.swift
// GEO-03 + D-23: phantom-typed enum carrying coordinates ONLY to networking endpoint
// payload builders. Disjoint from LogField (and any future AnalyticsField) — there is
// no syntactic path from "I have a CLLocationCoordinate2D" to "the Logger accepts it"
// because Logger APIs take [LogField: Any] (NOT [PlatformPayloadField: Any]).
//
// Trying to pass a PlatformPayloadField to Logger.log produces the compile error:
//   "Cannot convert value of type 'PlatformPayloadField' to expected element type 'LogField'"
//
// Phase 3 first uses this in the auth/OTP request payload (Plan 09 PhoneEntryVM); future
// tender/accept/scan endpoints (M2+) extend the enum.
//
// SwiftLint rule `ban_raw_coordinate_literal` (Phase 3 D-24, .swiftlint.yml) enforces
// that raw `CLLocationCoordinate2D(latitude:)` literals may only appear inside
// Core/Networking/Endpoints/** or Core/Identity/Geo*/** — this enum is the sanctioned
// carrier type from those allow-listed sites out to the rest of the app.

import CoreLocation
import Foundation

public enum PlatformPayloadField: Sendable {
    /// The ONLY sanctioned way to attach a coordinate to a network payload.
    /// Sourced from CountryGate-validated CLLocation; never from raw literals
    /// outside `Core/Networking/Endpoints/**` or `Core/Identity/Geo*/**`
    /// (enforced by SwiftLint rule `ban_raw_coordinate_literal` — Task 2).
    case coordinate(CLLocationCoordinate2D)

    /// Server-relative timestamp accompanying a payload (e.g., capture time).
    case timestamp(Date)

    /// Backend-issued user identifier (NOT PII — opaque server-generated ID).
    case userIdentifier(String)

    /// Session token included in authenticated payload bodies (when not in headers).
    case sessionToken(String)
}
