// validationLedgerTests/Load/LoadDomainDecodeTests.swift
// Phase 7 Plan 05 Task 3 — per-fixture decode round-trip coverage across all
// 18 load fixtures + the 3 error-body fixtures + the empty-list mechanical
// fixture. This suite delivers Roadmap SC #1 ("every fixture decodes via
// APIClient.defaultDecoder()") for the LoadList / LoadDetail / LoadAction
// endpoints.
//
// All decodes route through `APIClient.defaultDecoder()` (NOT a fresh
// JSONDecoder) so any drift in the production decoder configuration
// (.convertFromSnakeCase / .iso8601) surfaces here — same pattern as
// DeviceChallengeEndpointTests.decodesResponse.
//
// This suite does NOT touch MockURLProtocol; plain `@Suite` is sufficient
// (`.serialized` is only needed when the global mock handler array is mutated
// — 07-PATTERNS.md "Shared Patterns").
//
// Plan 03 already covers endpoint shape + minimal Response composition
// (LoadEndpointsTests); this suite covers ONLY the per-fixture decode
// round-trip matrix — the fixtures Plan 06 wires into the mock fixture
// registry for the organic DEBUG tap-through.

import Testing
import Foundation
@testable import validationLedger

@Suite("LoadDomainDecodeTests — every load + role + action fixture decodes via APIClient.defaultDecoder()")
struct LoadDomainDecodeTests {

    /// The 12 named loads in the D-12 / D-13 library. Stable order — the
    /// failure message names the offending VL when one of the 12 fails.
    private static let allLoadIDs: [String] = [
        "VL-1001", "VL-1002", "VL-1003", "VL-1004",
        "VL-1005", "VL-1006", "VL-1007", "VL-1008",
        "VL-1009", "VL-1010", "VL-1011", "VL-1012",
    ]

    /// Per-role list contents per D-11 shared-world: each (role, count) pair
    /// is the expected `response.loads.count` value for that role's list
    /// fixture, derived from the 07-RESEARCH.md "Shared-World Fixture Roster"
    /// roster.
    private static let roleListCounts: [(role: String, count: Int)] = [
        ("shipper", 5),
        ("broker", 9),
        ("carrier", 6),
        ("dispatch", 6),
        ("factoring", 4),
    ]

    @Test("Every load-detail-VL-*.json decodes into LoadDetailEndpoint.Response with matching load.id (12 fixtures)")
    func everyLoadDetailFixtureDecodes() throws {
        let decoder = APIClient.defaultDecoder()
        for id in Self.allLoadIDs {
            let data = try FixtureLoader.loadFixture("load-detail-\(id)")
            let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)
            #expect(
                response.load.id == id,
                "load-detail-\(id).json MUST decode load.id == \(id) but got \(response.load.id)"
            )
            // Smoke-check the embedded ChainOfTrust composes — Plan 03 covers
            // the minimal-case; the per-fixture coverage lives here.
            // Empty arrays are valid (VL-1006 has chain.edges == []), so we
            // assert the field is decodable (Swift type system guarantees this
            // structurally) by reading it.
            _ = response.chainOfTrust.nodes
            _ = response.chainOfTrust.edges
            _ = response.chainOfTrust.integrity.verdict
        }
    }

    @Test("Every loads-list-{role}.json decodes into LoadListEndpoint.Response with the expected load count")
    func everyRoleListFixtureDecodes() throws {
        let decoder = APIClient.defaultDecoder()
        for (role, expected) in Self.roleListCounts {
            let data = try FixtureLoader.loadFixture("loads-list-\(role)")
            let response = try decoder.decode(LoadListEndpoint.Response.self, from: data)
            #expect(
                response.loads.count == expected,
                "loads-list-\(role).json MUST decode \(expected) loads (D-11 shared-world roster) but got \(response.loads.count)"
            )
            // Every load in the list decodes its status via the closed
            // LoadStatus enum — composition smoke check.
            for load in response.loads {
                _ = load.status
            }
        }
        // The empty-state mechanical fixture decodes to an empty array.
        let emptyData = try FixtureLoader.loadFixture("loads-list-empty")
        let emptyResponse = try decoder.decode(LoadListEndpoint.Response.self, from: emptyData)
        #expect(emptyResponse.loads.isEmpty, "loads-list-empty.json MUST decode to []")
    }

    @Test("load-action-success.json decodes into LoadActionEndpoint.Response (Load + re-supplied ChainOfTrust)")
    func loadActionSuccessFixtureDecodes() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-action-success")
        let response = try decoder.decode(LoadActionEndpoint.Response.self, from: data)
        #expect(!response.load.id.isEmpty, "Response.load.id MUST be non-empty")
        #expect(
            !response.chainOfTrust.nodes.isEmpty,
            "Response.chainOfTrust.nodes MUST be non-empty for the success fixture"
        )
        // The success fixture was built from VL-1004 → accepted, so the
        // updated status is .accepted.
        #expect(
            response.load.status == .accepted,
            "load-action-success.json MUST surface the post-action status (.accepted) on the updated Load"
        )
    }

    @Test("Action error-body fixtures parse as JSON with error_code + message (validate body shape)")
    func actionErrorBodyFixturesParse() throws {
        // The error-body fixtures are NOT decoded into a typed Response — the
        // v1.0 NetworkError doesn't yet have a typed error-body struct (the
        // mock layer surfaces them via the Data argument of
        // NetworkError.httpError). Plan 04 forced-failure delivers them as
        // the body of a 409/422/500 response. This test pins the WIRE SHAPE
        // (an object with `error_code` + `message` strings) so a fixture
        // schema drift surfaces here before it surfaces as a "mystery 422
        // with no body" bug downstream.
        let errorFixtures = [
            "load-action-conflict-409",
            "load-action-validation-422",
            "load-action-server-error-500",
        ]
        for name in errorFixtures {
            let data = try FixtureLoader.loadFixture(name)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json != nil, "\(name).json MUST be a top-level JSON object")
            #expect(json?["error_code"] is String, "\(name).json MUST carry error_code: String")
            #expect(json?["message"] is String, "\(name).json MUST carry message: String")
        }
    }

    @Test("LoadListEndpoint.Response.nextCursor is nil for every v1.1 fixture (D-16 single-page envelope)")
    func nextCursorIsNilOnEveryListFixture() throws {
        let decoder = APIClient.defaultDecoder()
        // All 5 per-role lists + the empty-state fixture.
        let listFixtures = Self.roleListCounts.map { "loads-list-\($0.role)" } + ["loads-list-empty"]
        for name in listFixtures {
            let data = try FixtureLoader.loadFixture(name)
            let response = try decoder.decode(LoadListEndpoint.Response.self, from: data)
            #expect(
                response.nextCursor == nil,
                "\(name).json MUST decode next_cursor as nil — v1.1 fixtures always return one page (D-16)"
            )
        }
    }
}
