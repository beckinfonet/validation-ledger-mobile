// validationLedgerTests/Networking/FixtureLoader.swift
// Test helper: load a JSON fixture from the test bundle by name.
// Usage: let data = try FixtureLoader.loadFixture("otp-request-success")
//
// Uses a bundle-marker class (private final class) to resolve the test bundle —
// Bundle(for: FixtureBundleMarker.self) works under XCTest + Swift Testing without
// needing SwiftPM's Bundle.module.

import Foundation

private final class FixtureBundleMarker {}

enum FixtureLoader {
    enum Error: Swift.Error { case fixtureNotFound(String) }

    static func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureBundleMarker.self)
        // Try "Fixtures/<name>.json" first (subdirectory preservation), then flat "<name>.json".
        if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") {
            return try Data(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        throw Error.fixtureNotFound(name)
    }
}
