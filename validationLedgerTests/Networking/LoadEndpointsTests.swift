// validationLedgerTests/Networking/LoadEndpointsTests.swift
// Phase 7 LOAD-01 (Plan 03) — endpoint-shape + minimal Response decode
// tests for the 3 new load-domain endpoints.
//
// Scope: path / method / body assertions for each endpoint, exhaustive
// sweeps across the 5 Role cases (LoadListEndpoint) and the 6 LoadAction
// cases (LoadActionEndpoint), plus a single representative
// Response-decode-via-APIClient.defaultDecoder() smoke test per endpoint
// to prove the Response type composes. The full fixture-decode matrix
// lives in Plan 05 (where the per-VL JSON fixtures are authored); this
// suite covers ONLY the endpoint surface and minimal-Response decode.
//
// This suite does NOT touch `MockURLProtocol`, so it is plain
// `@Suite("…")` — `.serialized` is unnecessary (see 07-PATTERNS.md
// "Shared Patterns" — .serialized is only required when the global mock
// handler array is mutated).
//
// Decoder: every decode uses `APIClient.defaultDecoder()` so any drift
// in `.convertFromSnakeCase` / `.iso8601` strategy surfaces here, same
// pattern as DeviceChallengeEndpointTests.

import Testing
import Foundation
@testable import validationLedger

@Suite("LoadEndpointsTests — shape + minimal decode")
struct LoadEndpointsTests {

    // MARK: - Endpoint shape (path / method / body)

    @Test("LoadListEndpoint(role:) — path is /loads/{role}, method is GET, body is nil")
    func loadListEndpointShape() {
        for role in Role.allCases {
            let ep = LoadListEndpoint(role: role)
            #expect(
                ep.path == "/loads/\(role.rawValue)",
                "D-15: LoadListEndpoint MUST place role in the URL path, not a query string"
            )
            #expect(ep.method == .get, "LoadListEndpoint MUST be GET")
            #expect(ep.body == nil, "LoadListEndpoint MUST have a nil body (EmptyBody GET)")
        }
        // Spot-check a concrete value so a future Role.rawValue rename
        // would fail this test loudly.
        #expect(LoadListEndpoint(role: .broker).path == "/loads/broker")
    }

    @Test("LoadDetailEndpoint(loadID:) — path is /loads/{loadID}, method is GET, body is nil")
    func loadDetailEndpointShape() {
        for id in ["VL-1001", "VL-1009", "VL-1042"] {
            let ep = LoadDetailEndpoint(loadID: id)
            #expect(ep.path == "/loads/\(id)", "D-15: loadID MUST live in the URL path")
            #expect(ep.method == .get, "LoadDetailEndpoint MUST be GET")
            #expect(ep.body == nil, "LoadDetailEndpoint MUST have a nil body (EmptyBody GET)")
        }
    }

    @Test("LoadActionEndpoint(loadID:action:body:) — path is /loads/{loadID}/{action.pathSegment}, method is POST")
    func loadActionEndpointShape() {
        let body = LoadActionEndpoint.RequestBody(
            actorRole: .broker,
            targetPartyID: nil,
            respondByAt: nil,
            note: nil
        )
        for action in LoadAction.allCases {
            let ep = LoadActionEndpoint(loadID: "VL-1042", action: action, body: body)
            #expect(
                ep.path == "/loads/VL-1042/\(action.pathSegment)",
                "D-15: action MUST live in the URL path via LoadAction.pathSegment"
            )
            #expect(
                ep.method == .post,
                "D-19: LoadActionEndpoint MUST be POST so the existing IdempotencyInterceptor auto-injects Idempotency-Key"
            )
            #expect(ep.body != nil, "LoadActionEndpoint MUST carry a non-nil typed RequestBody")
        }
        // D-05 spot-check — advanceStatus MUST map to the bare "status"
        // segment (NOT "advance_status" / "advanceStatus"). Backend treats
        // POST /loads/{id}/status as "advance by one canonical step".
        let advanceEp = LoadActionEndpoint(loadID: "VL-1042", action: .advanceStatus, body: body)
        #expect(advanceEp.path == "/loads/VL-1042/status", "D-05: advanceStatus pathSegment MUST be 'status'")
    }

    // MARK: - RequestBody encoding (wire format)

    @Test("LoadActionEndpoint.RequestBody encodes typed fields under .convertToSnakeCase strategy")
    func loadActionRequestBodyEncoding() throws {
        let body = LoadActionEndpoint.RequestBody(
            actorRole: .broker,
            targetPartyID: "party-carrier-acme-001",
            respondByAt: nil,
            note: "tender request"
        )
        // Production decoder/encoder so any drift in the wire contract
        // surfaces here (mirrors DeviceChallengeEndpointTests.decodesResponse).
        let encoder = APIClient.defaultEncoder()
        let json = try encoder.encode(body)
        let str = String(data: json, encoding: .utf8) ?? ""

        // Role encodes as the lowercased rawValue ("broker").
        #expect(str.contains("\"actor_role\""), "actor_role wire key expected, got: \(str)")
        #expect(str.contains("\"broker\""), "Role.broker MUST encode as the literal string \"broker\"")

        // Trailing-acronym field with explicit CodingKey bridge.
        #expect(
            str.contains("\"target_party_id\""),
            "target_party_id wire key expected, got: \(str)"
        )
        #expect(
            !str.contains("target_party_i_d"),
            "Mangled trailing-acronym key: \(str)"
        )
        #expect(str.contains("\"party-carrier-acme-001\""), "targetPartyID value missing: \(str)")
        #expect(str.contains("\"note\""), "note field missing: \(str)")
        // respondByAt was nil — JSONEncoder default omits nil optionals,
        // so the key should NOT appear.
        #expect(!str.contains("respond_by_at"), "nil respondByAt MUST be omitted from wire form")
    }

    // MARK: - Response decoding (minimal smoke tests)

    @Test("LoadListEndpoint.Response decodes an empty paginated envelope (D-16)")
    func loadListResponseDecodesEmptyEnvelope() throws {
        let json = Data(#"{"loads":[],"next_cursor":null}"#.utf8)
        let decoder = APIClient.defaultDecoder()
        let response = try decoder.decode(LoadListEndpoint.Response.self, from: json)
        #expect(response.loads.isEmpty, "Empty loads array MUST decode as an empty Swift array")
        #expect(response.nextCursor == nil, "next_cursor:null MUST decode to nil (D-16 paginated envelope)")
    }

    @Test("LoadDetailEndpoint.Response embeds ChainOfTrust (D-08, smoke)")
    func loadDetailResponseEmbedsChainOfTrust() throws {
        // Minimal hand-authored JSON — NOT a fixture file. Plan 05 owns the
        // per-VL fixture set; Plan 03 covers only the endpoint surface and
        // a minimal Response composition smoke test.
        //
        // The Load shape must satisfy every required field on
        // validationLedger/Core/Load/Load.swift (id, referenceNumber,
        // origin, destination, equipment, weight, rate, pickupAt,
        // deliverAt, status, stateHistory; respondByAt + tenderEligibility
        // are optional). The ChainOfTrust shape must satisfy nodes, edges,
        // integrity (Plan 02), and ChainIntegrity must satisfy verdict +
        // reason + implicatedNodeIDs + implicatedEdgeIDs (Plan 01).
        let json = Data(#"""
        {
          "load": {
            "id": "VL-1001",
            "reference_number": "REF-1001",
            "origin": {
              "city": "Dallas",
              "state": "TX",
              "postal_code": "75201",
              "country": "US"
            },
            "destination": {
              "city": "Atlanta",
              "state": "GA",
              "postal_code": "30303",
              "country": "US"
            },
            "equipment": "dry_van",
            "weight": 42000,
            "rate": 2150.00,
            "pickup_at": "2026-05-20T08:00:00Z",
            "deliver_at": "2026-05-22T17:00:00Z",
            "status": "posted",
            "state_history": []
          },
          "chain_of_trust": {
            "nodes": [],
            "edges": [],
            "integrity": {
              "verdict": "clean",
              "reason": "",
              "implicated_node_ids": [],
              "implicated_edge_ids": []
            }
          }
        }
        """#.utf8)

        let decoder = APIClient.defaultDecoder()
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: json)

        #expect(response.load.id == "VL-1001", "Load.id MUST round-trip")
        #expect(response.load.status == .posted, "Load.status MUST decode via the LoadStatus closed enum")
        #expect(response.chainOfTrust.nodes.isEmpty, "Empty nodes array MUST decode as []")
        #expect(response.chainOfTrust.edges.isEmpty, "Empty edges array MUST decode as []")
        #expect(
            response.chainOfTrust.integrity.verdict == .clean,
            "D-08: integrity verdict MUST decode via the ChainIntegrity.Verdict closed enum"
        )
    }
}
