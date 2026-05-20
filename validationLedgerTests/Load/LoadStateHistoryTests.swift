// validationLedgerTests/Load/LoadStateHistoryTests.swift
// Phase 7 Plan 05 Task 3 — Load.stateHistory ordering + LoadStatusEvent decode
// (D-02). The Phase 9 LOAD-06 timeline UI ("Tendered 2 days ago") renders
// directly from this array; this suite pins the wire-to-Swift mapping of the
// stateHistory contract.
//
// D-02 is the source-of-truth for timeline data — the client renders in array
// order, the server is responsible for ordering. Test 4 below documents that
// the decoder does NOT re-sort the array — out-of-order events are faithfully
// preserved.
//
// Every decode routes through `APIClient.defaultDecoder()` so any drift in
// the production decoder configuration surfaces here. Plain `@Suite`; no
// MockURLProtocol touch.

import Testing
import Foundation
@testable import validationLedger

@Suite("LoadStateHistoryTests — Load.stateHistory ordering + LoadStatusEvent decode (D-02)")
struct LoadStateHistoryTests {

    @Test("VL-1001 stateHistory decodes in monotonic non-decreasing timestamp order ending at .delivered (LOAD-06 timeline source-of-truth)")
    func vl1001MonotonicOrdering() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1001")
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

        let history = response.load.stateHistory
        #expect(history.last?.status == .delivered, "VL-1001 stateHistory MUST end at .delivered (delivered load)")

        // Monotonic non-decreasing — adjacent timestamps satisfy t[i] <= t[i+1].
        let pairs = zip(history, history.dropFirst())
        let monotonic = pairs.allSatisfy { $0.timestamp <= $1.timestamp }
        #expect(monotonic, "VL-1001 stateHistory timestamps MUST be monotonic non-decreasing")
    }

    @Test("VL-1002 stateHistory contains the canonical in-transit progression posted→tendered→accepted→dispatched→inTransit in order")
    func vl1002CanonicalInTransitProgression() throws {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1002")
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

        let history = response.load.stateHistory
        #expect(history.last?.status == .inTransit, "VL-1002 stateHistory MUST end at .inTransit")

        // Find the index of each canonical milestone — all must be present
        // AND appear in the canonical order (no time-traveling backwards).
        let canonical: [LoadStatus] = [.posted, .tendered, .accepted, .dispatched, .inTransit]
        var lastIndex = -1
        for expected in canonical {
            guard let idx = history.firstIndex(where: { $0.status == expected }) else {
                Issue.record("VL-1002 stateHistory MUST contain a \(expected) event")
                return
            }
            #expect(
                idx > lastIndex,
                "VL-1002 canonical milestone \(expected) MUST appear after the previous milestone in stateHistory"
            )
            lastIndex = idx
        }
    }

    @Test("LoadStatusEvent.actor decodes as nil when wire field is null (Pitfall 5 — in-array optional absence)")
    func actorDecodesAsNilOnNullWire() throws {
        // VL-1006 is the draft fixture; its only stateHistory event has
        // actor: null (pre-counterparty draft transition). This is the
        // canonical Pitfall 5 (in-array optional absence) case for
        // LoadStatusEvent.
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1006")
        let response = try decoder.decode(LoadDetailEndpoint.Response.self, from: data)

        let history = response.load.stateHistory
        #expect(!history.isEmpty, "VL-1006 stateHistory MUST have at least one event")
        #expect(
            history.contains { $0.actor == nil },
            "Pitfall 5: VL-1006 MUST contain at least one LoadStatusEvent whose `actor` decodes to nil from wire `null`"
        )
    }

    @Test("stateHistory events preserve declared wire order (decoder does NOT re-sort)")
    func decoderPreservesDeclaredOrder() throws {
        // Hand-authored JSON with deliberately OUT-OF-ORDER timestamps. The
        // client renders in array order; the server is responsible for
        // sorting. This test pins that contract: a server bug that emits
        // out-of-order events surfaces as an out-of-order timeline UI, NOT
        // as a silently-resorted Swift array.
        //
        // The Load shape satisfies every required field on Load.swift.
        let json = Data(#"""
        {
          "id": "VL-9999",
          "reference_number": "REF-9999-XX",
          "origin": {
            "city": "Salt Lake City",
            "state": "UT",
            "postal_code": "84101",
            "country": "US"
          },
          "destination": {
            "city": "Boise",
            "state": "ID",
            "postal_code": "83702",
            "country": "US"
          },
          "equipment": "dry_van",
          "weight": 41000,
          "rate": 1850.00,
          "pickup_at": "2026-05-01T08:00:00Z",
          "deliver_at": "2026-05-01T18:00:00Z",
          "status": "posted",
          "state_history": [
            { "status": "posted", "timestamp": "2026-05-01T12:00:00Z", "actor": null },
            { "status": "draft",  "timestamp": "2026-04-30T09:00:00Z", "actor": null }
          ],
          "respond_by_at": null,
          "tender_eligibility": null
        }
        """#.utf8)

        let decoder = APIClient.defaultDecoder()
        let load = try decoder.decode(Load.self, from: json)
        let history = load.stateHistory

        #expect(history.count == 2, "Decoded stateHistory MUST preserve both events")
        // Array order is preserved — element 0 is posted (later timestamp),
        // element 1 is draft (earlier timestamp). The decoder does NOT
        // re-sort.
        #expect(
            history[0].timestamp > history[1].timestamp,
            "Decoder MUST preserve declared wire order — element 0 timestamp > element 1 timestamp (server-supplied ordering is authoritative)"
        )
        #expect(history[0].status == .posted, "Element 0 status MUST be the wire-declared first event (.posted)")
        #expect(history[1].status == .draft,  "Element 1 status MUST be the wire-declared second event (.draft)")
    }
}
