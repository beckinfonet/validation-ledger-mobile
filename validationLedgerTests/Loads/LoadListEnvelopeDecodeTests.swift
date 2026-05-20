// validationLedgerTests/Loads/LoadListEnvelopeDecodeTests.swift
// Phase 8 Plan 01 Task 4 — formal test surface for the LoadListItem envelope.
//
// Covers Phase 8 contract decisions:
//   D-02: LoadListItem { load: Load; displayedCounterparty: TrustNode? }.
//   D-03: nil counterparty fail-closes (UI renders neutral-grey UNVERIFIED);
//         JSON null AND missing-key BOTH decode to Swift nil via the
//         synthesized decodeIfPresent for the Optional.
//   D-04: per-role counterparty role assignment (broker -> carrier,
//         shipper/carrier/dispatch -> broker, factoring -> carrier) plus the
//         Phase 7 D-11 shared-world invariant across role fixtures.
//   D-05: nextCursor decodes as-is (string round-trip) AND nil-null both work.
//   Phase 7 D-09: unknown verification_state superstrings degrade to
//                 .unverified at the VerificationState decoder layer — locked
//                 here at the LoadListItem composition level.
//
// === .serialized requirement ===
// Tests 1, 5, 6, 9 register fixtures with MockURLProtocol (the global
// _handlers array — see MockURLProtocol.swift line 51-56). Per the
// `ios-test-suite-pitfalls` project memory, suites that touch the global
// fixture registry MUST be .serialized to avoid the parallel-execution race
// that produces ~58 false-negative 404s on full-suite runs.
//
// === Synthesized-JSON helper ===
// Tests 2, 3, 4, 7, 8 are pure JSONDecoder tests — they synthesize a JSON
// string, decode via the SAME `JSONDecoder` configuration `APIClient.default-
// Decoder()` ships (.convertFromSnakeCase + .iso8601), and assert the typed
// result. Reusing APIClient.defaultDecoder() directly keeps these tests
// honest about the production decoder configuration.
//
// === Threat coverage ===
// T-08-03 (Decoder safety): Tests 2/3 lock the nil-counterparty fail-closed
// behavior at the synthesized-decoder layer; Test 4 locks the unknown-
// verification_state degrade at the LoadListItem composition. T-08-04 (PII):
// every fixture-driven test uses synthetic party names from the existing
// Phase 7 + Phase 8 fixture corpus (Acme Trucking Inc., FreightWise Brokerage,
// PhantomLine Logistics — already shipped in load-detail-*.json).

import Testing
import Foundation
@testable import validationLedger

@Suite("LoadListEnvelopeDecodeTests — Phase 8 D-02/D-03/D-04 + D-09 cross-fixture coverage", .serialized)
struct LoadListEnvelopeDecodeTests {

    // MARK: - APIClient assembly (matches Phase 7 KYCUploaderTestSupport.makeClient())

    /// The mock base URL every endpoint-driven test uses.
    private static let baseURL = URL(string: "https://mock.local")!

    private func makeAPIClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let networkClient = URLSessionNetworkClient(config: .mock, session: session)
        return APIClient(
            baseURL: Self.baseURL,
            networkClient: networkClient,
            requestInterceptors: [],
            responseInterceptors: []
        )
    }

    /// Decode a hand-authored JSON string through an APIClient.defaultDecoder()-
    /// configured JSONDecoder — pinning every synthesized-JSON test to the
    /// production decoder configuration so any drift in .convertFromSnakeCase /
    /// .iso8601 surfaces here.
    private func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = APIClient.defaultDecoder()
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    /// A minimal-valid Load JSON object literal — every required field on
    /// Load.swift, no optional fields. Used by Tests 2/3/4 to drive synthetic
    /// LoadListItem decode scenarios without re-listing the full Load schema
    /// in each test body.
    private static let minimalLoadJSON: String = """
    "load": {
        "id": "VL-SYNTH-1",
        "reference_number": "REF-SYNTH-1",
        "origin": {
            "city": "Anaheim",
            "state": "CA",
            "postal_code": "92805",
            "country": "US"
        },
        "destination": {
            "city": "Atlanta",
            "state": "GA",
            "postal_code": "30303",
            "country": "US"
        },
        "equipment": "dry_van",
        "weight": 40000,
        "rate": 2500.0,
        "pickup_at": "2026-04-02T08:00:00Z",
        "deliver_at": "2026-04-06T17:00:00Z",
        "status": "posted",
        "state_history": []
    }
    """

    // MARK: - Test 1 — envelope wraps Load + counterparty (broker fixture, D-04)

    @Test("Test 1: broker fixture rows decode as LoadListItem envelopes with carrier counterparty (D-02 + D-04)")
    func envelopeWrapsLoadAndCounterpartyForBrokerList() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        let data = try FixtureLoader.loadFixture("loads-list-broker")
        MockURLProtocol.registerFixture(
            for: LoadListEndpoint.self,
            path: "/loads/broker",
            method: .get,
            statusCode: 200,
            body: data
        )

        let response = try await makeAPIClient().request(LoadListEndpoint(role: .broker))
        #expect(response.loads.count > 0, "broker fixture MUST have at least one row")

        let first = response.loads[0]
        // The Load aggregate decodes (round-trip).
        #expect(!first.load.id.isEmpty, "first row's load.id MUST round-trip")
        // The counterparty either decodes as a TrustNode with role == .carrier,
        // or it is nil (D-03 — some rows naturally have no counterparty yet,
        // e.g. a draft/posted load). At least one row in the broker fixture
        // MUST surface a non-nil carrier counterparty.
        let firstCounterparty = first.displayedCounterparty
        if let cp = firstCounterparty {
            #expect(cp.role == .carrier,
                    "D-04: broker view sees carrier counterparties; first row's cp.role was \(cp.role)")
        }
        let anyCarrierCounterparty = response.loads.contains { item in
            item.displayedCounterparty?.role == .carrier
        }
        #expect(anyCarrierCounterparty,
                "D-04: at least one broker row MUST carry a non-nil counterparty whose role is .carrier")
    }

    // MARK: - Test 2 — JSON null counterparty decodes to nil (D-03)

    @Test("Test 2: displayed_counterparty: null decodes to Swift nil (D-03 fail-closed)")
    func decodeIfPresentHandlesNullCounterparty() throws {
        let json = """
        {
            "loads": [
                {
                    \(Self.minimalLoadJSON),
                    "displayed_counterparty": null
                }
            ],
            "next_cursor": null
        }
        """
        let response: LoadListEndpoint.Response = try decode(json)
        #expect(response.loads.count == 1, "single-row synthesized envelope MUST decode to a 1-item array")
        #expect(response.loads[0].displayedCounterparty == nil,
                "D-03: JSON null MUST decode to Swift nil via synthesized decodeIfPresent")
    }

    // MARK: - Test 3 — missing counterparty key decodes to nil (D-03)

    @Test("Test 3: missing displayed_counterparty key decodes to Swift nil (RESEARCH Pitfall 3)")
    func decodeIfPresentHandlesMissingCounterpartyKey() throws {
        let json = """
        {
            "loads": [
                {
                    \(Self.minimalLoadJSON)
                }
            ],
            "next_cursor": null
        }
        """
        let response: LoadListEndpoint.Response = try decode(json)
        #expect(response.loads.count == 1, "single-row synthesized envelope MUST decode to a 1-item array")
        #expect(response.loads[0].displayedCounterparty == nil,
                "D-03: a MISSING displayed_counterparty key MUST decode to Swift nil, identically to JSON null — proving the synthesized decodeIfPresent unifies both forms")
    }

    // MARK: - Test 4 — unknown verification_state degrades to .unverified (Phase 7 D-09)

    @Test("Test 4: unknown verification_state degrades to .unverified at the LoadListItem layer (Phase 7 D-09)")
    func unknownVerificationStateDegradesToUnverified() throws {
        let json = """
        {
            "loads": [
                {
                    \(Self.minimalLoadJSON),
                    "displayed_counterparty": {
                        "party_id": "party-carrier-future",
                        "role": "carrier",
                        "display_name": "Future Carrier Inc.",
                        "verification_state": "compromised",
                        "kyc_completed_at": null,
                        "device_binding_status": "bound",
                        "usdot_number": null,
                        "usdot_authority_status": "active",
                        "prior_relationship_count": 0
                    }
                }
            ],
            "next_cursor": null
        }
        """
        let response: LoadListEndpoint.Response = try decode(json)
        #expect(response.loads.count == 1)
        let cp = try #require(response.loads[0].displayedCounterparty,
                              "row MUST decode a non-nil TrustNode when displayed_counterparty is a JSON object")
        #expect(cp.verificationState == .unverified,
                "Phase 7 D-09: an unknown verification_state superstring MUST degrade to .unverified at the LoadListItem composition layer — never softening trust on the client")
    }

    // MARK: - Test 5 — degraded fixture: one null + one flagged row

    @Test("Test 5: loads-list-degraded-counterparty.json carries one null counterparty + one flagged counterparty")
    func degradedFixtureCarriesOneNullAndOneFlagged() throws {
        let data = try FixtureLoader.loadFixture("loads-list-degraded-counterparty")
        let response: LoadListEndpoint.Response = try APIClient.defaultDecoder()
            .decode(LoadListEndpoint.Response.self, from: data)

        let hasNullCounterparty = response.loads.contains { $0.displayedCounterparty == nil }
        let hasFlaggedCounterparty = response.loads.contains {
            $0.displayedCounterparty?.verificationState == .flagged
        }
        #expect(hasNullCounterparty,
                "08-CONTEXT.md D-04 second half: degraded fixture MUST have >= 1 row with nil counterparty")
        #expect(hasFlaggedCounterparty,
                "08-CONTEXT.md D-04 second half: degraded fixture MUST have >= 1 row with a flagged counterparty")
    }

    // MARK: - Test 6 — shared-world invariant: broker vs shipper see different role counterparty

    @Test("Test 6: broker vs shipper VL-1001 carry different-role counterparties (Phase 7 D-11 shared-world)")
    func sharedWorldInvariantBrokerVsShipperSeesDifferentRoleCounterpartyForSameLoadID() throws {
        let brokerData = try FixtureLoader.loadFixture("loads-list-broker")
        let shipperData = try FixtureLoader.loadFixture("loads-list-shipper")
        let decoder = APIClient.defaultDecoder()
        let brokerResponse = try decoder.decode(LoadListEndpoint.Response.self, from: brokerData)
        let shipperResponse = try decoder.decode(LoadListEndpoint.Response.self, from: shipperData)

        // VL-1001 is the canonical shared-world load — present in every role
        // fixture per Phase 7 D-11 + 07-RESEARCH.md "Shared-World Fixture Roster".
        let brokerVL1001 = try #require(
            brokerResponse.loads.first { $0.load.id == "VL-1001" },
            "broker fixture MUST contain VL-1001 (shared-world roster)"
        )
        let shipperVL1001 = try #require(
            shipperResponse.loads.first { $0.load.id == "VL-1001" },
            "shipper fixture MUST contain VL-1001 (shared-world roster)"
        )
        let brokerCp = try #require(brokerVL1001.displayedCounterparty,
                                    "broker view of VL-1001 MUST carry a non-nil counterparty")
        let shipperCp = try #require(shipperVL1001.displayedCounterparty,
                                     "shipper view of VL-1001 MUST carry a non-nil counterparty")
        #expect(brokerCp.role == .carrier,
                "D-04: broker view of any load MUST carry the carrier counterparty (got \(brokerCp.role))")
        #expect(shipperCp.role == .broker,
                "D-04: shipper view of any load MUST carry the broker counterparty (got \(shipperCp.role))")
        #expect(brokerCp.role != shipperCp.role,
                "Phase 7 D-11 shared-world: the same load ID surfaces a DIFFERENT-role counterparty in each role's view — broker sees carrier (\(brokerCp.role)), shipper sees broker (\(shipperCp.role))")
    }

    // MARK: - Test 7 — next_cursor: "abc-123" round-trips

    @Test("Test 7: next_cursor:\"abc-123\" round-trips through .convertFromSnakeCase (D-05)")
    func nextCursorRoundTripsAcrossSnakeCaseBridge() throws {
        let json = """
        {
            "loads": [],
            "next_cursor": "abc-123"
        }
        """
        let response: LoadListEndpoint.Response = try decode(json)
        #expect(response.nextCursor == "abc-123",
                "D-05 + .convertFromSnakeCase: next_cursor wire form MUST round-trip as nextCursor")
    }

    // MARK: - Test 8 — next_cursor: null decodes to nil

    @Test("Test 8: next_cursor:null decodes to nil (D-05)")
    func nilNextCursorDecodesToNil() throws {
        let json = """
        {
            "loads": [],
            "next_cursor": null
        }
        """
        let response: LoadListEndpoint.Response = try decode(json)
        #expect(response.nextCursor == nil,
                "D-05: explicit JSON null MUST decode to Swift nil on the optional nextCursor")
    }

    // MARK: - Test 9 — empty envelope fixture decodes to zero rows

    @Test("Test 9: loads-list-empty.json decodes to zero rows (envelope-shape passthrough)")
    func emptyEnvelopeFixtureDecodesToZeroRows() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        defer {
            MockURLProtocol.reset()
            MockURLProtocol.resetFailureHandlers()
        }

        let data = try FixtureLoader.loadFixture("loads-list-empty")
        // Use any role; the fixture's body wins because we register it
        // directly under the chosen path.
        MockURLProtocol.registerFixture(
            for: LoadListEndpoint.self,
            path: "/loads/shipper",
            method: .get,
            statusCode: 200,
            body: data
        )

        let response = try await makeAPIClient().request(LoadListEndpoint(role: .shipper))
        #expect(response.loads.isEmpty,
                "loads-list-empty.json MUST decode to zero rows under the new envelope shape")
        #expect(response.nextCursor == nil,
                "loads-list-empty.json's next_cursor MUST decode to nil (envelope-shape passthrough)")
    }
}
