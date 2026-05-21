// validationLedgerTests/Loads/CarrierDirectoryDecodeTests.swift
// Phase 10 Plan 05 Task 1 — decode coverage for the new `CarrierDirectoryEndpoint`
// and the new `tender-carrier-directory.json` fixture.
//
// Locks the Plan-05 must-haves:
//   - D-07: ~6-8 synthetic carriers spanning ALL FOUR VerificationState cases
//   - Specifics line 263-265: at least one .flagged carrier cross-references the
//     "Chameleon Cargo" fraud archetype (the platform thesis visible the first
//     time a broker opens the picker)
//   - T-10-04 (T-08-04 inheritance) — synthetic names, no real-world carriers
//   - Phase 7 D-09: VerificationState fail-closed decoder still applies
//   - RESEARCH § Architectural Responsibility Map row 6: carriers decode as
//     [TrustNode] — the existing Phase 7 frozen domain type (no new type)
//
// Decoder routes through `APIClient.defaultDecoder()` so any drift in the
// production decoder configuration (`.convertFromSnakeCase` + `.iso8601`)
// surfaces here, identical to the rest of the Phase 7/8/9 decode test suites.

import Testing
import Foundation
@testable import validationLedger

@Suite("CarrierDirectoryDecodeTests — Phase 10 Plan 05 (D-07 + Specifics 263-265 + T-10-04)")
struct CarrierDirectoryDecodeTests {

    // MARK: - Test 1 — fixture decodes via the production decoder

    @Test("Test 1: tender-carrier-directory.json decodes to a CarrierDirectoryEndpoint.Response with 6-8 carriers")
    func fixtureDecodesViaDefaultDecoder() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("tender-carrier-directory")
        let response = try decoder.decode(CarrierDirectoryEndpoint.Response.self, from: data)
        #expect(response.carriers.count >= 6,
                "D-07: directory MUST carry at least 6 carriers (lower bound of the 6-8 range)")
        #expect(response.carriers.count <= 8,
                "D-07: directory MUST carry at most 8 carriers (upper bound of the 6-8 range)")
    }

    // MARK: - Test 2 — all 4 VerificationState cases present (D-07)

    @Test("Test 2: directory carriers span ALL FOUR VerificationState cases (D-07)")
    func fixtureIncludesAllFourVerificationStates() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("tender-carrier-directory")
        let response = try decoder.decode(CarrierDirectoryEndpoint.Response.self, from: data)
        let states = Set(response.carriers.map(\.verificationState))
        #expect(states == Set([.verified, .pending, .unverified, .flagged]),
                "D-07: the directory MUST span .verified / .pending / .unverified / .flagged — got \(states)")
    }

    // MARK: - Test 3 — Chameleon Cargo fraud archetype anchors the .flagged row (Specifics 263-265)

    @Test("Test 3: at least one .flagged carrier matches the 'Chameleon' fraud-archetype anchor (Specifics line 264)")
    func fixtureIncludesChameleonCargoAsFlagged() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("tender-carrier-directory")
        let response = try decoder.decode(CarrierDirectoryEndpoint.Response.self, from: data)
        let chameleonFlagged = response.carriers.contains { carrier in
            carrier.displayName.lowercased().contains("chameleon")
                && carrier.verificationState == .flagged
        }
        #expect(chameleonFlagged,
                "Specifics line 264: at least one carrier whose displayName contains 'chameleon' (case-insensitive) MUST have verificationState == .flagged — the platform-thesis anchor for the picker")
    }

    // MARK: - Test 4 — every directory carrier carries role == .carrier

    @Test("Test 4: every directory entry's role == .carrier")
    func fixtureAllCarriersHaveCarrierRole() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("tender-carrier-directory")
        let response = try decoder.decode(CarrierDirectoryEndpoint.Response.self, from: data)
        for carrier in response.carriers {
            #expect(carrier.role == .carrier,
                    "every directory entry's role MUST be .carrier — got \(carrier.role) for \(carrier.displayName)")
        }
    }

    // MARK: - Test 5 — synthetic names only (T-10-04 / T-08-04 zero-PII discipline)

    @Test("Test 5: directory carrier names are SYNTHETIC — no real-world carrier brand names (T-10-04)")
    func fixtureCarriersAreSyntheticNotRealNames() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("tender-carrier-directory")
        let response = try decoder.decode(CarrierDirectoryEndpoint.Response.self, from: data)
        // T-10-04 allowlist: real-world carrier brand names that MUST NOT appear
        // in the fixture (case-insensitive substring match). The list is small
        // by design — the synthetic-name discipline is enforced by the
        // fixture-header comment + this test, not by an exhaustive blocklist.
        let forbiddenSubstrings: [String] = [
            "schneider", "knight", "werner", "j.b. hunt", "jb hunt", "swift",
            "fedex", "ups", "old dominion", "yrc", "estes", "saia", "xpo",
        ]
        for carrier in response.carriers {
            let lower = carrier.displayName.lowercased()
            for forbidden in forbiddenSubstrings {
                #expect(!lower.contains(forbidden),
                        "T-10-04: carrier displayName '\(carrier.displayName)' MUST NOT contain real-world brand substring '\(forbidden)'")
            }
        }
    }

    // MARK: - Test 6 — at least one .verified carrier (unblocks happy-path Send)

    @Test("Test 6: directory MUST contain at least one .verified carrier (happy-path Send unblocked)")
    func fixtureHasAtLeastOneVerifiedCarrier() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("tender-carrier-directory")
        let response = try decoder.decode(CarrierDirectoryEndpoint.Response.self, from: data)
        let verifiedCount = response.carriers.filter { $0.verificationState == .verified }.count
        #expect(verifiedCount >= 1,
                "directory MUST have >= 1 .verified carrier; otherwise the tender-sheet Send button is permanently disabled and the happy path is blocked")
    }

    // MARK: - Test 7 — endpoint path + method

    @Test("Test 7: CarrierDirectoryEndpoint exposes GET /carriers/directory (no body)")
    func endpointPathAndMethod() {
        let endpoint = CarrierDirectoryEndpoint()
        #expect(endpoint.path == "/carriers/directory",
                "the endpoint path MUST be the bare '/carriers/directory' (RESEARCH § Architectural Responsibility Map row 6)")
        #expect(endpoint.method == .get,
                "the endpoint method MUST be GET — D-19 IdempotencyInterceptor only injects on POST/PUT, so the absent body is correct")
    }
}
