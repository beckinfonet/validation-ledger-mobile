// validationLedgerTests/Identity/PlatformPayloadFieldTests.swift
// Phase 3 Plan 03: GEO-03 type discipline assertions (D-23).
// Unit tests use Swift Testing (`import Testing`), NOT XCTest.

import Testing
import Foundation
import CoreLocation
@testable import validationLedger

@Suite("PlatformPayloadField — phantom-typed enum disjoint from LogField (GEO-03, D-23)")
struct PlatformPayloadFieldTests {

    // MARK: - Source-path resolution
    //
    // Tests resolve the repo-relative source file via `#filePath` rather than trusting
    // xcodebuild's working directory (which is derivedData-scoped, not repo-root).
    // Pattern reused from SoftwareKeyStoreExtendedTests.cr02IdempotentGuardPresent.
    //
    // #filePath here is
    //   <repo>/validationLedgerTests/Identity/PlatformPayloadFieldTests.swift
    // …so two `deletingLastPathComponent()` calls walk up to `validationLedgerTests/`
    // and a third walks up to the repo root.
    private static func repoRootURL(from filePath: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: "\(filePath)")
        url.deleteLastPathComponent()   // drop PlatformPayloadFieldTests.swift
        url.deleteLastPathComponent()   // drop Identity/
        url.deleteLastPathComponent()   // drop validationLedgerTests/
        return url
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let url = repoRootURL().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Tests

    @Test("PlatformPayloadField.coordinate carries CLLocationCoordinate2D")
    func coordinateCaseExists() {
        let coord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let field = PlatformPayloadField.coordinate(coord)
        // Pattern-match to prove the case has the expected associated value.
        if case .coordinate(let c) = field {
            #expect(c.latitude == 37.7749)
            #expect(c.longitude == -122.4194)
        } else {
            Issue.record("PlatformPayloadField.coordinate did not match expected case")
        }
    }

    @Test("PlatformPayloadField has timestamp / userIdentifier / sessionToken cases")
    func otherCasesExist() {
        // Compilation success is the assertion — each case must be constructible with its
        // expected associated-value type.
        let _: PlatformPayloadField = .timestamp(Date())
        let _: PlatformPayloadField = .userIdentifier("u-1")
        let _: PlatformPayloadField = .sessionToken("tok-1")
        #expect(Bool(true))
    }

    @Test("Logger source contains NO `.coordinate` / `.latitude` / `.longitude` / `.location` LogField case")
    func loggerSourceHasNoCoordinateCase() throws {
        let source = try Self.readSource("validationLedger/Core/Logging/Logger.swift")
        // Negative assertions on the LogField enum body.
        #expect(!source.contains("case coordinates"),
                "LogField.coordinates case must be removed per D-23 — found in Logger.swift")
        #expect(!source.contains("case coordinate("),
                "LogField must not have any coordinate case")
        #expect(!source.contains("case latitude"),
                "LogField must not have a latitude case")
        #expect(!source.contains("case longitude"),
                "LogField must not have a longitude case")
        #expect(!source.contains("case location"),
                "LogField must not have a location case")
    }

    @Test("No production code in Logging/ references CLLocationCoordinate2D (GEO-03 compile-time invariant)")
    func noProductionViolations() throws {
        // Grep for any `LogField` consumer trying to attach a CLLocationCoordinate2D —
        // the compile-time invariant means this CAN'T exist; if it does, the
        // disjoint-types contract is broken. This is the same check encoded as a
        // CI grep for robustness against future maintenance edits.
        let loggerSrc = try Self.readSource("validationLedger/Core/Logging/Logger.swift")
        let scrubberSrc = try Self.readSource("validationLedger/Core/Logging/PIIScrubber.swift")
        #expect(!loggerSrc.contains("CLLocationCoordinate2D"),
                "Logger.swift references CLLocationCoordinate2D — D-23 violation")
        #expect(!scrubberSrc.contains("CLLocationCoordinate2D"),
                "PIIScrubber.swift references CLLocationCoordinate2D — D-23 violation")
    }
}
