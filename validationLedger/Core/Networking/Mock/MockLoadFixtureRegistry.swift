// validationLedger/Core/Networking/Mock/MockLoadFixtureRegistry.swift
// Phase 7 LOAD-01 (D-17 + Plan 07-06): DEBUG-only mock-fixture registry that
// wires the Phase 7 named-load library + per-role lists + action handler onto
// MockURLProtocol for the organic DEBUG tap-through flow.
//
// === D-17 mirror of MockOTPRoleFixtureRegistry ===
// File-shape EXACTLY mirrors `MockOTPRoleFixtureRegistry.swift`:
//   - `#if DEBUG` ... `#endif` file-level gate (Threat T-07-27 — Release binary
//     must not contain the symbol; verified by a Release-strings grep).
//   - `enum MockLoadFixtureRegistry { static func registerAppDefaults() { ... } }`
//   - Uses the LOW-LEVEL `MockURLProtocol.register(_:)` API (not
//     `MockFixture.registerFixture<E>`) so a single closure can vary response
//     by URL-path-suffix — the per-role and per-VL dispatch lives in the
//     closures themselves.
//
// === KEY DIVERGENCE from MockOTPRoleFixtureRegistry ===
// `MockOTPRoleFixtureRegistry.registerForRole(_:)` invokes MockURLProtocol's
// reset entry-point at the top because it owns the entire UI-test request
// set. This registry MUST NOT invoke that entry-point — it is called from
// `AppContainer.init`'s DEBUG block IMMEDIATELY AFTER
// `MockDefaultFixtures.registerAppDefaults()`, and a reset here would
// clobber the catch-all dispatchHandler MockDefaultFixtures just installed.
// Plan 07-06 must_haves key-link explicitly forbids this; the registry only
// APPENDS handlers via `MockURLProtocol.register(_:)`.
//
// === JSON-loading approach (Option A: inline Data literal) ===
// Plan 07-06's `<interfaces>` block presents two acceptable approaches —
// (A) inline JSON as Swift raw-string Data literals, (B) Bundle.main loading
// with the fixture files added to the App target's Resources phase.
//
// **This file uses Option A — inline JSON literals.** Rationale:
//   1. The project uses `PBXFileSystemSynchronizedRootGroup` for both the
//      app target and the test target (validationLedger.xcodeproj/project.pbxproj
//      lines 57-81). The fixtures live inside the TEST target's synchronized
//      group; physically moving or duplicating them into the App target's
//      synchronized tree would require either an `exceptions` entry in the
//      App target's `PBXFileSystemSynchronizedBuildFileExceptionSet`
//      (delicate pbxproj edit) or a literal file copy inside the App target
//      tree (creates drift in two places).
//   2. The DEBUG-only registry never ships in Release, so the file-size cost
//      of the inlined JSON is irrelevant to App Store binaries.
//   3. The cost: the JSON content is duplicated between the test fixture
//      files and these Swift literals. Mitigation: this file's `MARK: - JSON
//      payloads` sections carry a "AUTHORITATIVE COPY" banner; a hand-edit
//      to one MUST be paired with a hand-edit to the other. A Phase 8-or-
//      later todo (recorded in 07-06-SUMMARY): consolidate via a shared
//      "demo bundle" if drift becomes a maintenance pain.
//
// === Three handlers registered ===
//   1. Per-role list handler: GET /loads/{role-rawValue} → 200 + loads-list-{role}.json
//      Falls through if the suffix isn't a known role (e.g. "/loads/VL-1042").
//   2. Per-VL detail handler: GET /loads/{loadID where loadID has prefix "VL-"}
//      → 200 + load-detail-{loadID}.json for the 12 named loads. Falls through
//      to MockDefaultFixtures.dispatchHandler / 404 for unknown VL- IDs.
//   3. Action-success handler: POST /loads/{loadID}/{post|tender|accept|reject|cancel|status}
//      → 200 + load-action-success.json. The DEBUG tap-through always succeeds
//      — failure outcomes (409 / 422 / 500 / urlError) are exercised by
//      Plan 04's forced-failure path in PER-TEST setup, not in the default
//      registry.
//
// === First-match-wins ordering ===
// `MockURLProtocol.startLoading()` iterates handlers in registration order;
// the first to return non-nil wins (per MockURLProtocolRegistryTests). Order
// in `AppContainer.init`:
//   line A: MockDefaultFixtures.registerAppDefaults()          // catch-all dispatchHandler
//   line B: MockLoadFixtureRegistry.registerAppDefaults()      // appended AFTER
// MockDefaultFixtures' dispatchHandler returns `nil` for every load-domain
// path (its switch covers only auth/device/KYC paths), so the load handlers
// effectively run before any 404 fallback. The dispatchFailureHandlers path
// is consulted only AFTER all success handlers have returned nil.
//
// === Pitfall 4 — MockDefaultFixtures byte-identical preservation ===
// D-17 + Plan 07-06 acceptance criteria require zero changes to
// `MockDefaultFixtures.swift`. This file is the SOLE Mock-directory addition
// for the Load domain; MockDefaultFixtures.dispatchHandler MUST NOT be
// extended with `/loads/...` cases.

#if DEBUG

import Foundation

enum MockLoadFixtureRegistry {

    // WR-01 — process-lifetime guard against handler-array accumulation.
    //
    // Each `SceneDelegate.presentRoot(_:)` builds a fresh `AppContainer` (per
    // ADR 0002 abrupt-replace; DevMenu also drives this on every role swap).
    // Pre-WR-01, the DEBUG block in `AppContainer.init` called
    // `MockLoadFixtureRegistry.registerAppDefaults()` on every container
    // construction, appending three more closures to the global
    // `MockURLProtocol._handlers` array every time. After N role swaps the
    // array carried N copies of the same three handlers — memory grew
    // linearly, lookup cost O(N) per request, and the closure list became
    // a quiet leak surface for any future closure that captures the
    // outer container.
    //
    // The guard makes registration idempotent: the first call inside the
    // process registers; subsequent calls are no-ops. The registry CANNOT
    // call `MockURLProtocol.reset()` (file-header lines 17-24) because reset
    // would clobber the catch-all `MockDefaultFixtures.dispatchHandler`
    // registered immediately before this method runs. The static-flag
    // approach respects that constraint while closing the accumulation leak.
    //
    // Process-scope is correct here: every Swift-test invocation runs in a
    // fresh process, so the flag does NOT leak across tests; and AppContainer
    // construction is the only call site, so the flag does not need to be
    // reset between role swaps within a single app session. If a future test
    // ever needs to re-register (e.g. to swap fixtures), it should call the
    // future `MockLoadFixtureRegistry.resetForUITestOnly()` seam — NOT
    // toggle `hasRegisteredAppDefaults` directly.
    private static var hasRegisteredAppDefaults = false

    /// Register the Phase 7 load-domain default handlers with MockURLProtocol.
    /// Called from `AppContainer.init`'s DEBUG block adjacent to
    /// `MockDefaultFixtures.registerAppDefaults()`. APPEND-ONLY — never calls
    /// MockURLProtocol's reset entry-point (which would clobber the
    /// MockDefaultFixtures handlers registered immediately before this call).
    ///
    /// WR-01: idempotent — the first call in a process registers; subsequent
    /// calls are no-ops. This closes a per-role-swap handler-array
    /// accumulation leak in DEBUG sessions (DevMenu drives a fresh
    /// `AppContainer.init` on every role swap; pre-WR-01 each swap appended
    /// three more closures to `MockURLProtocol._handlers`).
    static func registerAppDefaults() {
        guard !hasRegisteredAppDefaults else { return }
        hasRegisteredAppDefaults = true

        // (1) Per-role list handler: GET /loads/{role-rawValue}
        MockURLProtocol.register { request in
            guard request.httpMethod == "GET" else { return nil }
            guard let path = request.url?.path, path.hasPrefix("/loads/") else { return nil }
            let suffix = String(path.dropFirst("/loads/".count))
            // Suffix must be exactly the role rawValue (no further slashes).
            guard !suffix.contains("/") else { return nil }
            guard let body = listPayloads[suffix] else { return nil }
            return make200(body: body, url: request.url)
        }

        // (2) Per-VL detail handler: GET /loads/{loadID where prefix == "VL-"}
        MockURLProtocol.register { request in
            guard request.httpMethod == "GET" else { return nil }
            guard let path = request.url?.path, path.hasPrefix("/loads/") else { return nil }
            let suffix = String(path.dropFirst("/loads/".count))
            guard !suffix.contains("/"), suffix.hasPrefix("VL-") else { return nil }
            guard let body = detailPayloads[suffix] else { return nil }
            return make200(body: body, url: request.url)
        }

        // (3) Action-success handler: POST /loads/{loadID}/{actionPathSegment}
        // Matches every LoadAction.pathSegment (post, tender, accept, reject,
        // cancel, status) on any VL-prefixed loadID. The default DEBUG tap-
        // through always succeeds; failure outcomes are exercised by Plan 04's
        // forced-failure path in PER-TEST setup, not here.
        MockURLProtocol.register { request in
            guard request.httpMethod == "POST" else { return nil }
            guard let path = request.url?.path, path.hasPrefix("/loads/") else { return nil }
            let suffix = String(path.dropFirst("/loads/".count))
            // Expect "{VL-####}/{action}" — exactly two segments split on "/".
            let parts = suffix.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let loadID = String(parts[0])
            let actionSegment = String(parts[1])
            guard loadID.hasPrefix("VL-") else { return nil }
            guard actionPathSegments.contains(actionSegment) else { return nil }
            return make200(body: actionSuccessPayload, url: request.url)
        }
    }

    // MARK: - HTTPURLResponse builder

    private static func make200(body: Data, url: URL?) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url ?? URL(string: "https://mock.local/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, body)
    }

    // MARK: - Recognised LoadAction path segments

    /// Every `LoadAction.pathSegment` value — kept as a literal `Set<String>`
    /// to keep the registry self-contained for the DEBUG tap-through path.
    /// The canonical source of truth is `LoadAction.swift`; if a new
    /// LoadAction case is added, this set must be extended in lock-step.
    private static let actionPathSegments: Set<String> = [
        "post", "tender", "accept", "reject", "cancel", "status",
    ]

    // MARK: - Per-role list payload table (AUTHORITATIVE COPY of test fixtures)

    /// Lookup table for the per-role list handler. Each entry is the same
    /// snake_case JSON shipped at
    /// `validationLedgerTests/Networking/Fixtures/loads-list-{role}.json`,
    /// inlined here so the DEBUG App bundle does not require the test-target
    /// fixture files. Drift between this table and the test fixtures becomes
    /// a demo-vs-test inconsistency (Threat T-07-31, accept disposition).
    private static let listPayloads: [String: Data] = [
        "shipper": Data(#"""
{
  "loads": [
    {
      "load": {
        "id": "VL-1001",
        "reference_number": "REF-1001-AA",
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
        "weight": 42500,
        "rate": 3850.0,
        "pickup_at": "2026-04-02T08:00:00Z",
        "deliver_at": "2026-04-06T17:00:00Z",
        "status": "delivered",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-03-30T14:00:00Z",
            "actor": {
              "party_id": "party-shipper-pacificgoods",
              "role": "shipper",
              "display_name": "Pacific Goods LLC"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-03-30T14:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-03-31T09:15:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-03-31T11:42:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-02T07:30:00Z",
            "actor": {
              "party_id": "party-dispatch-overland",
              "role": "dispatch",
              "display_name": "Overland Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-02T08:45:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "delivered",
            "timestamp": "2026-04-06T16:48:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1002",
        "reference_number": "REF-1002-BB",
        "origin": {
          "city": "Salinas",
          "state": "CA",
          "postal_code": "93901",
          "country": "US"
        },
        "destination": {
          "city": "Chicago",
          "state": "IL",
          "postal_code": "60601",
          "country": "US"
        },
        "equipment": "reefer",
        "weight": 38900,
        "rate": 5125.5,
        "pickup_at": "2026-04-14T06:00:00Z",
        "deliver_at": "2026-04-17T20:00:00Z",
        "status": "in_transit",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-11T12:00:00Z",
            "actor": {
              "party_id": "party-shipper-globalexports",
              "role": "shipper",
              "display_name": "Global Exports Co."
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-11T12:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-12T10:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-12T13:18:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-14T05:30:00Z",
            "actor": {
              "party_id": "party-dispatch-cornerstone",
              "role": "dispatch",
              "display_name": "Cornerstone Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-14T06:25:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1003",
        "reference_number": "REF-1003-CC",
        "origin": {
          "city": "Memphis",
          "state": "TN",
          "postal_code": "38103",
          "country": "US"
        },
        "destination": {
          "city": "Dallas",
          "state": "TX",
          "postal_code": "75201",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 40200,
        "rate": 1875.0,
        "pickup_at": "2026-04-20T07:00:00Z",
        "deliver_at": "2026-04-21T18:00:00Z",
        "status": "posted",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-18T15:00:00Z",
            "actor": {
              "party_id": "party-shipper-easternfoods",
              "role": "shipper",
              "display_name": "Eastern Foods Distributing"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-18T15:45:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1005",
        "reference_number": "REF-1005-EE",
        "origin": {
          "city": "Newark",
          "state": "NJ",
          "postal_code": "07102",
          "country": "US"
        },
        "destination": {
          "city": "Charlotte",
          "state": "NC",
          "postal_code": "28202",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 39800,
        "rate": 2185.0,
        "pickup_at": "2026-04-24T07:00:00Z",
        "deliver_at": "2026-04-25T19:00:00Z",
        "status": "posted",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-18T10:00:00Z",
            "actor": {
              "party_id": "party-shipper-easternfoods",
              "role": "shipper",
              "display_name": "Eastern Foods Distributing"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-18T10:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-19T13:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "expired",
            "timestamp": "2026-04-19T15:00:00Z",
            "actor": null
          },
          {
            "status": "posted",
            "timestamp": "2026-04-19T15:00:05Z",
            "actor": null
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1006",
        "reference_number": "REF-1006-FF",
        "origin": {
          "city": "Stockton",
          "state": "CA",
          "postal_code": "95202",
          "country": "US"
        },
        "destination": {
          "city": "Portland",
          "state": "OR",
          "postal_code": "97204",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 41750,
        "rate": 2675.0,
        "pickup_at": "2026-04-26T07:00:00Z",
        "deliver_at": "2026-04-27T18:00:00Z",
        "status": "draft",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-20T16:00:00Z",
            "actor": null
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    }
  ],
  "next_cursor": null
}
"""#.utf8),
        "broker": Data(#"""
{
  "loads": [
    {
      "load": {
        "id": "VL-1001",
        "reference_number": "REF-1001-AA",
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
        "weight": 42500,
        "rate": 3850.0,
        "pickup_at": "2026-04-02T08:00:00Z",
        "deliver_at": "2026-04-06T17:00:00Z",
        "status": "delivered",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-03-30T14:00:00Z",
            "actor": {
              "party_id": "party-shipper-pacificgoods",
              "role": "shipper",
              "display_name": "Pacific Goods LLC"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-03-30T14:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-03-31T09:15:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-03-31T11:42:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-02T07:30:00Z",
            "actor": {
              "party_id": "party-dispatch-overland",
              "role": "dispatch",
              "display_name": "Overland Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-02T08:45:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "delivered",
            "timestamp": "2026-04-06T16:48:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-acme",
        "role": "carrier",
        "display_name": "Acme Trucking Inc.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-22T13:05:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0123456",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1002",
        "reference_number": "REF-1002-BB",
        "origin": {
          "city": "Salinas",
          "state": "CA",
          "postal_code": "93901",
          "country": "US"
        },
        "destination": {
          "city": "Chicago",
          "state": "IL",
          "postal_code": "60601",
          "country": "US"
        },
        "equipment": "reefer",
        "weight": 38900,
        "rate": 5125.5,
        "pickup_at": "2026-04-14T06:00:00Z",
        "deliver_at": "2026-04-17T20:00:00Z",
        "status": "in_transit",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-11T12:00:00Z",
            "actor": {
              "party_id": "party-shipper-globalexports",
              "role": "shipper",
              "display_name": "Global Exports Co."
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-11T12:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-12T10:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-12T13:18:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-14T05:30:00Z",
            "actor": {
              "party_id": "party-dispatch-cornerstone",
              "role": "dispatch",
              "display_name": "Cornerstone Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-14T06:25:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-redrock",
        "role": "carrier",
        "display_name": "Red Rock Carriers",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-18T08:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1003",
        "reference_number": "REF-1003-CC",
        "origin": {
          "city": "Memphis",
          "state": "TN",
          "postal_code": "38103",
          "country": "US"
        },
        "destination": {
          "city": "Dallas",
          "state": "TX",
          "postal_code": "75201",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 40200,
        "rate": 1875.0,
        "pickup_at": "2026-04-20T07:00:00Z",
        "deliver_at": "2026-04-21T18:00:00Z",
        "status": "posted",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-18T15:00:00Z",
            "actor": {
              "party_id": "party-shipper-easternfoods",
              "role": "shipper",
              "display_name": "Eastern Foods Distributing"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-18T15:45:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": null
    },
    {
      "load": {
        "id": "VL-1004",
        "reference_number": "REF-1004-DD",
        "origin": {
          "city": "Phoenix",
          "state": "AZ",
          "postal_code": "85003",
          "country": "US"
        },
        "destination": {
          "city": "Denver",
          "state": "CO",
          "postal_code": "80202",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 41200,
        "rate": 2450.0,
        "pickup_at": "2026-04-22T09:00:00Z",
        "deliver_at": "2026-04-23T16:00:00Z",
        "status": "tendered",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-19T11:00:00Z",
            "actor": {
              "party_id": "party-shipper-pacificgoods",
              "role": "shipper",
              "display_name": "Pacific Goods LLC"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-19T11:25:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-20T14:00:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          }
        ],
        "respond_by_at": "2026-04-20T16:00:00Z",
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-acme",
        "role": "carrier",
        "display_name": "Acme Trucking Inc.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-22T13:05:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0123456",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1005",
        "reference_number": "REF-1005-EE",
        "origin": {
          "city": "Newark",
          "state": "NJ",
          "postal_code": "07102",
          "country": "US"
        },
        "destination": {
          "city": "Charlotte",
          "state": "NC",
          "postal_code": "28202",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 39800,
        "rate": 2185.0,
        "pickup_at": "2026-04-24T07:00:00Z",
        "deliver_at": "2026-04-25T19:00:00Z",
        "status": "posted",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-18T10:00:00Z",
            "actor": {
              "party_id": "party-shipper-easternfoods",
              "role": "shipper",
              "display_name": "Eastern Foods Distributing"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-18T10:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-19T13:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "expired",
            "timestamp": "2026-04-19T15:00:00Z",
            "actor": null
          },
          {
            "status": "posted",
            "timestamp": "2026-04-19T15:00:05Z",
            "actor": null
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-nationallink",
        "role": "carrier",
        "display_name": "National Link Carriers",
        "verification_state": "pending",
        "kyc_completed_at": null,
        "device_binding_status": "unbound",
        "usdot_number": "1144882",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1006",
        "reference_number": "REF-1006-FF",
        "origin": {
          "city": "Stockton",
          "state": "CA",
          "postal_code": "95202",
          "country": "US"
        },
        "destination": {
          "city": "Portland",
          "state": "OR",
          "postal_code": "97204",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 41750,
        "rate": 2675.0,
        "pickup_at": "2026-04-26T07:00:00Z",
        "deliver_at": "2026-04-27T18:00:00Z",
        "status": "draft",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-20T16:00:00Z",
            "actor": null
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": null
    },
    {
      "load": {
        "id": "VL-1008",
        "reference_number": "REF-1008-HH",
        "origin": {
          "city": "Houston",
          "state": "TX",
          "postal_code": "77002",
          "country": "US"
        },
        "destination": {
          "city": "Tulsa",
          "state": "OK",
          "postal_code": "74103",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 40500,
        "rate": 1495.0,
        "pickup_at": "2026-04-23T08:00:00Z",
        "deliver_at": "2026-04-23T19:00:00Z",
        "status": "posted",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-19T14:00:00Z",
            "actor": {
              "party_id": "party-shipper-easternfoods",
              "role": "shipper",
              "display_name": "Eastern Foods Distributing"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-19T14:25:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": false,
          "disabled_reason": "Carrier identity not yet verified \u2014 Phase 5 KYC outstanding"
        }
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-nationallink",
        "role": "carrier",
        "display_name": "National Link Carriers",
        "verification_state": "unverified",
        "kyc_completed_at": null,
        "device_binding_status": "unbound",
        "usdot_number": "1144882",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1009",
        "reference_number": "REF-1009-II",
        "origin": {
          "city": "Long Beach",
          "state": "CA",
          "postal_code": "90802",
          "country": "US"
        },
        "destination": {
          "city": "Phoenix",
          "state": "AZ",
          "postal_code": "85003",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 43200,
        "rate": 3275.0,
        "pickup_at": "2026-04-18T07:00:00Z",
        "deliver_at": "2026-04-19T18:00:00Z",
        "status": "in_transit",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-15T11:00:00Z",
            "actor": {
              "party_id": "party-shipper-globalexports",
              "role": "shipper",
              "display_name": "Global Exports Co."
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-15T11:45:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-16T09:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-16T11:30:00Z",
            "actor": {
              "party_id": "party-broker-keystone",
              "role": "broker",
              "display_name": "Keystone Freight Group"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-18T06:30:00Z",
            "actor": {
              "party_id": "party-dispatch-overland",
              "role": "dispatch",
              "display_name": "Overland Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-18T07:42:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-redrock",
        "role": "carrier",
        "display_name": "Red Rock Carriers",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-18T08:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1010",
        "reference_number": "REF-1010-JJ",
        "origin": {
          "city": "Miami",
          "state": "FL",
          "postal_code": "33130",
          "country": "US"
        },
        "destination": {
          "city": "Jacksonville",
          "state": "FL",
          "postal_code": "32202",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 39950,
        "rate": 1685.0,
        "pickup_at": "2026-04-22T07:00:00Z",
        "deliver_at": "2026-04-22T19:00:00Z",
        "status": "accepted",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-19T12:00:00Z",
            "actor": {
              "party_id": "party-shipper-easternfoods",
              "role": "shipper",
              "display_name": "Eastern Foods Distributing"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-19T12:30:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-20T08:00:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-20T09:14:00Z",
            "actor": {
              "party_id": "party-carrier-phantomline",
              "role": "carrier",
              "display_name": "PhantomLine Logistics"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-phantomline",
        "role": "carrier",
        "display_name": "PhantomLine Logistics",
        "verification_state": "flagged",
        "kyc_completed_at": "2026-04-18T22:14:00Z",
        "device_binding_status": "mismatched",
        "usdot_number": "3998112",
        "usdot_authority_status": "revoked",
        "prior_relationships": []
      }
    }
  ],
  "next_cursor": null
}
"""#.utf8),
        "carrier": Data(#"""
{
  "loads": [
    {
      "load": {
        "id": "VL-1001",
        "reference_number": "REF-1001-AA",
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
        "weight": 42500,
        "rate": 3850.0,
        "pickup_at": "2026-04-02T08:00:00Z",
        "deliver_at": "2026-04-06T17:00:00Z",
        "status": "delivered",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-03-30T14:00:00Z",
            "actor": {
              "party_id": "party-shipper-pacificgoods",
              "role": "shipper",
              "display_name": "Pacific Goods LLC"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-03-30T14:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-03-31T09:15:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-03-31T11:42:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-02T07:30:00Z",
            "actor": {
              "party_id": "party-dispatch-overland",
              "role": "dispatch",
              "display_name": "Overland Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-02T08:45:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "delivered",
            "timestamp": "2026-04-06T16:48:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1002",
        "reference_number": "REF-1002-BB",
        "origin": {
          "city": "Salinas",
          "state": "CA",
          "postal_code": "93901",
          "country": "US"
        },
        "destination": {
          "city": "Chicago",
          "state": "IL",
          "postal_code": "60601",
          "country": "US"
        },
        "equipment": "reefer",
        "weight": 38900,
        "rate": 5125.5,
        "pickup_at": "2026-04-14T06:00:00Z",
        "deliver_at": "2026-04-17T20:00:00Z",
        "status": "in_transit",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-11T12:00:00Z",
            "actor": {
              "party_id": "party-shipper-globalexports",
              "role": "shipper",
              "display_name": "Global Exports Co."
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-11T12:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-12T10:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-12T13:18:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-14T05:30:00Z",
            "actor": {
              "party_id": "party-dispatch-cornerstone",
              "role": "dispatch",
              "display_name": "Cornerstone Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-14T06:25:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1004",
        "reference_number": "REF-1004-DD",
        "origin": {
          "city": "Phoenix",
          "state": "AZ",
          "postal_code": "85003",
          "country": "US"
        },
        "destination": {
          "city": "Denver",
          "state": "CO",
          "postal_code": "80202",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 41200,
        "rate": 2450.0,
        "pickup_at": "2026-04-22T09:00:00Z",
        "deliver_at": "2026-04-23T16:00:00Z",
        "status": "tendered",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-19T11:00:00Z",
            "actor": {
              "party_id": "party-shipper-pacificgoods",
              "role": "shipper",
              "display_name": "Pacific Goods LLC"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-19T11:25:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-20T14:00:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          }
        ],
        "respond_by_at": "2026-04-20T16:00:00Z",
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1007",
        "reference_number": "REF-1007-GG",
        "origin": {
          "city": "Detroit",
          "state": "MI",
          "postal_code": "48226",
          "country": "US"
        },
        "destination": {
          "city": "Indianapolis",
          "state": "IN",
          "postal_code": "46204",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 38450,
        "rate": 1325.0,
        "pickup_at": "2026-04-21T06:00:00Z",
        "deliver_at": "2026-04-21T17:00:00Z",
        "status": "dispatched",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-18T13:00:00Z",
            "actor": {
              "party_id": "party-shipper-globalexports",
              "role": "shipper",
              "display_name": "Global Exports Co."
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-18T13:30:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-19T09:00:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-19T10:15:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-21T05:42:00Z",
            "actor": {
              "party_id": "party-dispatch-cornerstone",
              "role": "dispatch",
              "display_name": "Cornerstone Dispatch"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1009",
        "reference_number": "REF-1009-II",
        "origin": {
          "city": "Long Beach",
          "state": "CA",
          "postal_code": "90802",
          "country": "US"
        },
        "destination": {
          "city": "Phoenix",
          "state": "AZ",
          "postal_code": "85003",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 43200,
        "rate": 3275.0,
        "pickup_at": "2026-04-18T07:00:00Z",
        "deliver_at": "2026-04-19T18:00:00Z",
        "status": "in_transit",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-15T11:00:00Z",
            "actor": {
              "party_id": "party-shipper-globalexports",
              "role": "shipper",
              "display_name": "Global Exports Co."
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-15T11:45:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-16T09:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-16T11:30:00Z",
            "actor": {
              "party_id": "party-broker-keystone",
              "role": "broker",
              "display_name": "Keystone Freight Group"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-18T06:30:00Z",
            "actor": {
              "party_id": "party-dispatch-overland",
              "role": "dispatch",
              "display_name": "Overland Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-18T07:42:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-broker-keystone",
        "role": "broker",
        "display_name": "Keystone Freight Group",
        "verification_state": "flagged",
        "kyc_completed_at": "2025-07-04T08:00:00Z",
        "device_binding_status": "mismatched",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1010",
        "reference_number": "REF-1010-JJ",
        "origin": {
          "city": "Miami",
          "state": "FL",
          "postal_code": "33130",
          "country": "US"
        },
        "destination": {
          "city": "Jacksonville",
          "state": "FL",
          "postal_code": "32202",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 39950,
        "rate": 1685.0,
        "pickup_at": "2026-04-22T07:00:00Z",
        "deliver_at": "2026-04-22T19:00:00Z",
        "status": "accepted",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-19T12:00:00Z",
            "actor": {
              "party_id": "party-shipper-easternfoods",
              "role": "shipper",
              "display_name": "Eastern Foods Distributing"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-19T12:30:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-20T08:00:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-20T09:14:00Z",
            "actor": {
              "party_id": "party-carrier-phantomline",
              "role": "carrier",
              "display_name": "PhantomLine Logistics"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    }
  ],
  "next_cursor": null
}
"""#.utf8),
        "dispatch": Data(#"""
{
  "loads": [
    {
      "load": {
        "id": "VL-1001",
        "reference_number": "REF-1001-AA",
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
        "weight": 42500,
        "rate": 3850.0,
        "pickup_at": "2026-04-02T08:00:00Z",
        "deliver_at": "2026-04-06T17:00:00Z",
        "status": "delivered",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-03-30T14:00:00Z",
            "actor": {
              "party_id": "party-shipper-pacificgoods",
              "role": "shipper",
              "display_name": "Pacific Goods LLC"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-03-30T14:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-03-31T09:15:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-03-31T11:42:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-02T07:30:00Z",
            "actor": {
              "party_id": "party-dispatch-overland",
              "role": "dispatch",
              "display_name": "Overland Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-02T08:45:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "delivered",
            "timestamp": "2026-04-06T16:48:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1002",
        "reference_number": "REF-1002-BB",
        "origin": {
          "city": "Salinas",
          "state": "CA",
          "postal_code": "93901",
          "country": "US"
        },
        "destination": {
          "city": "Chicago",
          "state": "IL",
          "postal_code": "60601",
          "country": "US"
        },
        "equipment": "reefer",
        "weight": 38900,
        "rate": 5125.5,
        "pickup_at": "2026-04-14T06:00:00Z",
        "deliver_at": "2026-04-17T20:00:00Z",
        "status": "in_transit",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-11T12:00:00Z",
            "actor": {
              "party_id": "party-shipper-globalexports",
              "role": "shipper",
              "display_name": "Global Exports Co."
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-11T12:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-12T10:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-12T13:18:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-14T05:30:00Z",
            "actor": {
              "party_id": "party-dispatch-cornerstone",
              "role": "dispatch",
              "display_name": "Cornerstone Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-14T06:25:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1004",
        "reference_number": "REF-1004-DD",
        "origin": {
          "city": "Phoenix",
          "state": "AZ",
          "postal_code": "85003",
          "country": "US"
        },
        "destination": {
          "city": "Denver",
          "state": "CO",
          "postal_code": "80202",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 41200,
        "rate": 2450.0,
        "pickup_at": "2026-04-22T09:00:00Z",
        "deliver_at": "2026-04-23T16:00:00Z",
        "status": "tendered",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-19T11:00:00Z",
            "actor": {
              "party_id": "party-shipper-pacificgoods",
              "role": "shipper",
              "display_name": "Pacific Goods LLC"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-19T11:25:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-20T14:00:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          }
        ],
        "respond_by_at": "2026-04-20T16:00:00Z",
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1007",
        "reference_number": "REF-1007-GG",
        "origin": {
          "city": "Detroit",
          "state": "MI",
          "postal_code": "48226",
          "country": "US"
        },
        "destination": {
          "city": "Indianapolis",
          "state": "IN",
          "postal_code": "46204",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 38450,
        "rate": 1325.0,
        "pickup_at": "2026-04-21T06:00:00Z",
        "deliver_at": "2026-04-21T17:00:00Z",
        "status": "dispatched",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-18T13:00:00Z",
            "actor": {
              "party_id": "party-shipper-globalexports",
              "role": "shipper",
              "display_name": "Global Exports Co."
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-18T13:30:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-19T09:00:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-19T10:15:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-21T05:42:00Z",
            "actor": {
              "party_id": "party-dispatch-cornerstone",
              "role": "dispatch",
              "display_name": "Cornerstone Dispatch"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1009",
        "reference_number": "REF-1009-II",
        "origin": {
          "city": "Long Beach",
          "state": "CA",
          "postal_code": "90802",
          "country": "US"
        },
        "destination": {
          "city": "Phoenix",
          "state": "AZ",
          "postal_code": "85003",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 43200,
        "rate": 3275.0,
        "pickup_at": "2026-04-18T07:00:00Z",
        "deliver_at": "2026-04-19T18:00:00Z",
        "status": "in_transit",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-15T11:00:00Z",
            "actor": {
              "party_id": "party-shipper-globalexports",
              "role": "shipper",
              "display_name": "Global Exports Co."
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-15T11:45:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-16T09:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-16T11:30:00Z",
            "actor": {
              "party_id": "party-broker-keystone",
              "role": "broker",
              "display_name": "Keystone Freight Group"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-18T06:30:00Z",
            "actor": {
              "party_id": "party-dispatch-overland",
              "role": "dispatch",
              "display_name": "Overland Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-18T07:42:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-broker-keystone",
        "role": "broker",
        "display_name": "Keystone Freight Group",
        "verification_state": "flagged",
        "kyc_completed_at": "2025-07-04T08:00:00Z",
        "device_binding_status": "mismatched",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1010",
        "reference_number": "REF-1010-JJ",
        "origin": {
          "city": "Miami",
          "state": "FL",
          "postal_code": "33130",
          "country": "US"
        },
        "destination": {
          "city": "Jacksonville",
          "state": "FL",
          "postal_code": "32202",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 39950,
        "rate": 1685.0,
        "pickup_at": "2026-04-22T07:00:00Z",
        "deliver_at": "2026-04-22T19:00:00Z",
        "status": "accepted",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-19T12:00:00Z",
            "actor": {
              "party_id": "party-shipper-easternfoods",
              "role": "shipper",
              "display_name": "Eastern Foods Distributing"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-19T12:30:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-20T08:00:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-20T09:14:00Z",
            "actor": {
              "party_id": "party-carrier-phantomline",
              "role": "carrier",
              "display_name": "PhantomLine Logistics"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    }
  ],
  "next_cursor": null
}
"""#.utf8),
        "factoring": Data(#"""
{
  "loads": [
    {
      "load": {
        "id": "VL-1001",
        "reference_number": "REF-1001-AA",
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
        "weight": 42500,
        "rate": 3850.0,
        "pickup_at": "2026-04-02T08:00:00Z",
        "deliver_at": "2026-04-06T17:00:00Z",
        "status": "delivered",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-03-30T14:00:00Z",
            "actor": {
              "party_id": "party-shipper-pacificgoods",
              "role": "shipper",
              "display_name": "Pacific Goods LLC"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-03-30T14:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-03-31T09:15:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-03-31T11:42:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-02T07:30:00Z",
            "actor": {
              "party_id": "party-dispatch-overland",
              "role": "dispatch",
              "display_name": "Overland Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-02T08:45:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "delivered",
            "timestamp": "2026-04-06T16:48:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-acme",
        "role": "carrier",
        "display_name": "Acme Trucking Inc.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-22T13:05:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0123456",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1009",
        "reference_number": "REF-1009-II",
        "origin": {
          "city": "Long Beach",
          "state": "CA",
          "postal_code": "90802",
          "country": "US"
        },
        "destination": {
          "city": "Phoenix",
          "state": "AZ",
          "postal_code": "85003",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 43200,
        "rate": 3275.0,
        "pickup_at": "2026-04-18T07:00:00Z",
        "deliver_at": "2026-04-19T18:00:00Z",
        "status": "in_transit",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-15T11:00:00Z",
            "actor": {
              "party_id": "party-shipper-globalexports",
              "role": "shipper",
              "display_name": "Global Exports Co."
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-15T11:45:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-16T09:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-16T11:30:00Z",
            "actor": {
              "party_id": "party-broker-keystone",
              "role": "broker",
              "display_name": "Keystone Freight Group"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-18T06:30:00Z",
            "actor": {
              "party_id": "party-dispatch-overland",
              "role": "dispatch",
              "display_name": "Overland Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-18T07:42:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-redrock",
        "role": "carrier",
        "display_name": "Red Rock Carriers",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-18T08:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1011",
        "reference_number": "REF-1011-KK",
        "origin": {
          "city": "Atlanta",
          "state": "GA",
          "postal_code": "30303",
          "country": "US"
        },
        "destination": {
          "city": "Birmingham",
          "state": "AL",
          "postal_code": "35203",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 40850,
        "rate": 1245.0,
        "pickup_at": "2026-04-12T07:00:00Z",
        "deliver_at": "2026-04-12T15:00:00Z",
        "status": "invoiced",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-08T10:00:00Z",
            "actor": {
              "party_id": "party-shipper-easternfoods",
              "role": "shipper",
              "display_name": "Eastern Foods Distributing"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-08T10:30:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-09T11:00:00Z",
            "actor": {
              "party_id": "party-broker-freightwise",
              "role": "broker",
              "display_name": "FreightWise Brokerage"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-09T13:00:00Z",
            "actor": {
              "party_id": "party-broker-keystone",
              "role": "broker",
              "display_name": "Keystone Freight Group"
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-12T06:30:00Z",
            "actor": {
              "party_id": "party-dispatch-cornerstone",
              "role": "dispatch",
              "display_name": "Cornerstone Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-12T07:25:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          },
          {
            "status": "delivered",
            "timestamp": "2026-04-12T14:50:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          },
          {
            "status": "pod_captured",
            "timestamp": "2026-04-12T15:05:00Z",
            "actor": {
              "party_id": "party-carrier-redrock",
              "role": "carrier",
              "display_name": "Red Rock Carriers"
            }
          },
          {
            "status": "invoiced",
            "timestamp": "2026-04-13T09:42:00Z",
            "actor": {
              "party_id": "party-factoring-stagepay",
              "role": "factoring",
              "display_name": "StagePay Funding"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-redrock",
        "role": "carrier",
        "display_name": "Red Rock Carriers",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-18T08:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-1012",
        "reference_number": "REF-1012-LL",
        "origin": {
          "city": "San Diego",
          "state": "CA",
          "postal_code": "92101",
          "country": "US"
        },
        "destination": {
          "city": "Tucson",
          "state": "AZ",
          "postal_code": "85701",
          "country": "US"
        },
        "equipment": "dry_van",
        "weight": 41100,
        "rate": 2375.0,
        "pickup_at": "2026-04-05T07:00:00Z",
        "deliver_at": "2026-04-05T17:00:00Z",
        "status": "funded",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-04-01T10:00:00Z",
            "actor": {
              "party_id": "party-shipper-pacificgoods",
              "role": "shipper",
              "display_name": "Pacific Goods LLC"
            }
          },
          {
            "status": "posted",
            "timestamp": "2026-04-01T10:30:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "tendered",
            "timestamp": "2026-04-02T09:00:00Z",
            "actor": {
              "party_id": "party-broker-sunbelt",
              "role": "broker",
              "display_name": "Sunbelt Logistics"
            }
          },
          {
            "status": "accepted",
            "timestamp": "2026-04-02T11:00:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "dispatched",
            "timestamp": "2026-04-05T06:30:00Z",
            "actor": {
              "party_id": "party-dispatch-overland",
              "role": "dispatch",
              "display_name": "Overland Dispatch"
            }
          },
          {
            "status": "in_transit",
            "timestamp": "2026-04-05T07:20:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "delivered",
            "timestamp": "2026-04-05T16:42:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "pod_captured",
            "timestamp": "2026-04-05T16:58:00Z",
            "actor": {
              "party_id": "party-carrier-acme",
              "role": "carrier",
              "display_name": "Acme Trucking Inc."
            }
          },
          {
            "status": "invoiced",
            "timestamp": "2026-04-06T09:00:00Z",
            "actor": {
              "party_id": "party-factoring-bridgecap",
              "role": "factoring",
              "display_name": "BridgeCap Capital"
            }
          },
          {
            "status": "funded",
            "timestamp": "2026-04-07T13:15:00Z",
            "actor": {
              "party_id": "party-factoring-bridgecap",
              "role": "factoring",
              "display_name": "BridgeCap Capital"
            }
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": null
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-acme",
        "role": "carrier",
        "display_name": "Acme Trucking Inc.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-22T13:05:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0123456",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    }
  ],
  "next_cursor": null
}
"""#.utf8),
    ]

    // MARK: - Per-VL load-detail payload table (AUTHORITATIVE COPY of test fixtures)

    /// Lookup table for the per-VL detail handler. Each entry is the JSON
    /// shipped at `validationLedgerTests/Networking/Fixtures/load-detail-VL-####.json`,
    /// inlined here for the same reason as `listPayloads` above. The 12
    /// named loads (D-12 / D-13) collectively cover every LoadStatus, all
    /// four VerificationState values, and all three ChainIntegrity verdicts.
    private static let detailPayloads: [String: Data] = [
        "VL-1001": Data(#"""
{
  "load": {
    "id": "VL-1001",
    "reference_number": "REF-1001-AA",
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
    "weight": 42500,
    "rate": 3850.00,
    "pickup_at": "2026-04-02T08:00:00Z",
    "deliver_at": "2026-04-06T17:00:00Z",
    "status": "delivered",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-03-30T14:00:00Z",
        "actor": {
          "party_id": "party-shipper-pacificgoods",
          "role": "shipper",
          "display_name": "Pacific Goods LLC"
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-03-30T14:30:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      },
      {
        "status": "tendered",
        "timestamp": "2026-03-31T09:15:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      },
      {
        "status": "accepted",
        "timestamp": "2026-03-31T11:42:00Z",
        "actor": {
          "party_id": "party-carrier-acme",
          "role": "carrier",
          "display_name": "Acme Trucking Inc."
        }
      },
      {
        "status": "dispatched",
        "timestamp": "2026-04-02T07:30:00Z",
        "actor": {
          "party_id": "party-dispatch-overland",
          "role": "dispatch",
          "display_name": "Overland Dispatch"
        }
      },
      {
        "status": "in_transit",
        "timestamp": "2026-04-02T08:45:00Z",
        "actor": {
          "party_id": "party-carrier-acme",
          "role": "carrier",
          "display_name": "Acme Trucking Inc."
        }
      },
      {
        "status": "delivered",
        "timestamp": "2026-04-06T16:48:00Z",
        "actor": {
          "party_id": "party-carrier-acme",
          "role": "carrier",
          "display_name": "Acme Trucking Inc."
        }
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": {
      "can_tender": true,
      "disabled_reason": null
    }
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-pacificgoods",
        "role": "shipper",
        "display_name": "Pacific Goods LLC",
        "verification_state": "verified",
        "kyc_completed_at": "2025-11-04T15:20:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-acme",
        "role": "carrier",
        "display_name": "Acme Trucking Inc.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-22T13:05:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0123456",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-dispatch-overland",
        "role": "dispatch",
        "display_name": "Overland Dispatch",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-01T10:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0987654",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-factoring-bridgecap",
        "role": "factoring",
        "display_name": "BridgeCap Capital",
        "verification_state": "verified",
        "kyc_completed_at": "2025-07-18T14:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1001-shipper-broker",
        "from_party_id": "party-shipper-pacificgoods",
        "to_party_id": "party-broker-freightwise",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1001-broker-carrier",
        "from_party_id": "party-broker-freightwise",
        "to_party_id": "party-carrier-acme",
        "relationship_state": "verified",
        "tender_ref": "TNDR-1001-A"
      },
      {
        "edge_id": "edge-VL-1001-carrier-dispatch",
        "from_party_id": "party-carrier-acme",
        "to_party_id": "party-dispatch-overland",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1001-carrier-factoring",
        "from_party_id": "party-carrier-acme",
        "to_party_id": "party-factoring-bridgecap",
        "relationship_state": "verified",
        "tender_ref": null
      }
    ],
    "integrity": {
      "verdict": "clean",
      "reason": "All parties verified; KYC current; carrier authority active; no fraud signals detected.",
      "implicated_node_ids": [],
      "implicated_edge_ids": []
    }
  }
}
"""#.utf8),
        "VL-1002": Data(#"""
{
  "load": {
    "id": "VL-1002",
    "reference_number": "REF-1002-BB",
    "origin": {
      "city": "Salinas",
      "state": "CA",
      "postal_code": "93901",
      "country": "US"
    },
    "destination": {
      "city": "Chicago",
      "state": "IL",
      "postal_code": "60601",
      "country": "US"
    },
    "equipment": "reefer",
    "weight": 38900,
    "rate": 5125.50,
    "pickup_at": "2026-04-14T06:00:00Z",
    "deliver_at": "2026-04-17T20:00:00Z",
    "status": "in_transit",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-11T12:00:00Z",
        "actor": {
          "party_id": "party-shipper-globalexports",
          "role": "shipper",
          "display_name": "Global Exports Co."
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-11T12:30:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      },
      {
        "status": "tendered",
        "timestamp": "2026-04-12T10:00:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      },
      {
        "status": "accepted",
        "timestamp": "2026-04-12T13:18:00Z",
        "actor": {
          "party_id": "party-carrier-redrock",
          "role": "carrier",
          "display_name": "Red Rock Carriers"
        }
      },
      {
        "status": "dispatched",
        "timestamp": "2026-04-14T05:30:00Z",
        "actor": {
          "party_id": "party-dispatch-cornerstone",
          "role": "dispatch",
          "display_name": "Cornerstone Dispatch"
        }
      },
      {
        "status": "in_transit",
        "timestamp": "2026-04-14T06:25:00Z",
        "actor": {
          "party_id": "party-carrier-redrock",
          "role": "carrier",
          "display_name": "Red Rock Carriers"
        }
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": null
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-globalexports",
        "role": "shipper",
        "display_name": "Global Exports Co.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-06-30T10:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-redrock",
        "role": "carrier",
        "display_name": "Red Rock Carriers",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-18T08:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-dispatch-cornerstone",
        "role": "dispatch",
        "display_name": "Cornerstone Dispatch",
        "verification_state": "verified",
        "kyc_completed_at": "2025-11-22T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1002-shipper-broker",
        "from_party_id": "party-shipper-globalexports",
        "to_party_id": "party-broker-freightwise",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1002-broker-carrier",
        "from_party_id": "party-broker-freightwise",
        "to_party_id": "party-carrier-redrock",
        "relationship_state": "verified",
        "tender_ref": "TNDR-1002-A"
      },
      {
        "edge_id": "edge-VL-1002-carrier-dispatch",
        "from_party_id": "party-carrier-redrock",
        "to_party_id": "party-dispatch-cornerstone",
        "relationship_state": "verified",
        "tender_ref": null
      }
    ],
    "integrity": {
      "verdict": "clean",
      "reason": "All parties verified; reefer load on schedule; no fraud signals.",
      "implicated_node_ids": [],
      "implicated_edge_ids": []
    }
  }
}
"""#.utf8),
        "VL-1003": Data(#"""
{
  "load": {
    "id": "VL-1003",
    "reference_number": "REF-1003-CC",
    "origin": {
      "city": "Memphis",
      "state": "TN",
      "postal_code": "38103",
      "country": "US"
    },
    "destination": {
      "city": "Dallas",
      "state": "TX",
      "postal_code": "75201",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 40200,
    "rate": 1875.00,
    "pickup_at": "2026-04-20T07:00:00Z",
    "deliver_at": "2026-04-21T18:00:00Z",
    "status": "posted",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-18T15:00:00Z",
        "actor": {
          "party_id": "party-shipper-easternfoods",
          "role": "shipper",
          "display_name": "Eastern Foods Distributing"
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-18T15:45:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": null
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-easternfoods",
        "role": "shipper",
        "display_name": "Eastern Foods Distributing",
        "verification_state": "verified",
        "kyc_completed_at": "2025-12-01T09:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1003-shipper-broker",
        "from_party_id": "party-shipper-easternfoods",
        "to_party_id": "party-broker-freightwise",
        "relationship_state": "verified",
        "tender_ref": null
      }
    ],
    "integrity": {
      "verdict": "clean",
      "reason": "Awaiting tender; shipper and broker verified.",
      "implicated_node_ids": [],
      "implicated_edge_ids": []
    }
  }
}
"""#.utf8),
        "VL-1004": Data(#"""
{
  "load": {
    "id": "VL-1004",
    "reference_number": "REF-1004-DD",
    "origin": {
      "city": "Phoenix",
      "state": "AZ",
      "postal_code": "85003",
      "country": "US"
    },
    "destination": {
      "city": "Denver",
      "state": "CO",
      "postal_code": "80202",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 41200,
    "rate": 2450.00,
    "pickup_at": "2026-04-22T09:00:00Z",
    "deliver_at": "2026-04-23T16:00:00Z",
    "status": "tendered",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-19T11:00:00Z",
        "actor": {
          "party_id": "party-shipper-pacificgoods",
          "role": "shipper",
          "display_name": "Pacific Goods LLC"
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-19T11:25:00Z",
        "actor": {
          "party_id": "party-broker-sunbelt",
          "role": "broker",
          "display_name": "Sunbelt Logistics"
        }
      },
      {
        "status": "tendered",
        "timestamp": "2026-04-20T14:00:00Z",
        "actor": {
          "party_id": "party-broker-sunbelt",
          "role": "broker",
          "display_name": "Sunbelt Logistics"
        }
      }
    ],
    "respond_by_at": "2026-04-20T16:00:00Z",
    "tender_eligibility": {
      "can_tender": true,
      "disabled_reason": null
    }
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-pacificgoods",
        "role": "shipper",
        "display_name": "Pacific Goods LLC",
        "verification_state": "verified",
        "kyc_completed_at": "2025-11-04T15:20:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-acme",
        "role": "carrier",
        "display_name": "Acme Trucking Inc.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-22T13:05:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0123456",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-dispatch-overland",
        "role": "dispatch",
        "display_name": "Overland Dispatch",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-01T10:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0987654",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1004-shipper-broker",
        "from_party_id": "party-shipper-pacificgoods",
        "to_party_id": "party-broker-sunbelt",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1004-broker-carrier",
        "from_party_id": "party-broker-sunbelt",
        "to_party_id": "party-carrier-acme",
        "relationship_state": "pending",
        "tender_ref": "TNDR-1004-A"
      },
      {
        "edge_id": "edge-VL-1004-carrier-dispatch",
        "from_party_id": "party-carrier-acme",
        "to_party_id": "party-dispatch-overland",
        "relationship_state": "verified",
        "tender_ref": null
      }
    ],
    "integrity": {
      "verdict": "clean",
      "reason": "Active tender; all parties verified; awaiting carrier response.",
      "implicated_node_ids": [],
      "implicated_edge_ids": []
    }
  }
}
"""#.utf8),
        "VL-1005": Data(#"""
{
  "load": {
    "id": "VL-1005",
    "reference_number": "REF-1005-EE",
    "origin": {
      "city": "Newark",
      "state": "NJ",
      "postal_code": "07102",
      "country": "US"
    },
    "destination": {
      "city": "Charlotte",
      "state": "NC",
      "postal_code": "28202",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 39800,
    "rate": 2185.00,
    "pickup_at": "2026-04-24T07:00:00Z",
    "deliver_at": "2026-04-25T19:00:00Z",
    "status": "posted",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-18T10:00:00Z",
        "actor": {
          "party_id": "party-shipper-easternfoods",
          "role": "shipper",
          "display_name": "Eastern Foods Distributing"
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-18T10:30:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      },
      {
        "status": "tendered",
        "timestamp": "2026-04-19T13:00:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      },
      {
        "status": "expired",
        "timestamp": "2026-04-19T15:00:00Z",
        "actor": null
      },
      {
        "status": "posted",
        "timestamp": "2026-04-19T15:00:05Z",
        "actor": null
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": {
      "can_tender": true,
      "disabled_reason": null
    }
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-easternfoods",
        "role": "shipper",
        "display_name": "Eastern Foods Distributing",
        "verification_state": "verified",
        "kyc_completed_at": "2025-12-01T09:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-nationallink",
        "role": "carrier",
        "display_name": "National Link Carriers",
        "verification_state": "pending",
        "kyc_completed_at": null,
        "device_binding_status": "unbound",
        "usdot_number": "1144882",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1005-shipper-broker",
        "from_party_id": "party-shipper-easternfoods",
        "to_party_id": "party-broker-freightwise",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1005-broker-carrier",
        "from_party_id": "party-broker-freightwise",
        "to_party_id": "party-carrier-nationallink",
        "relationship_state": "unverified",
        "tender_ref": "TNDR-1005-A"
      }
    ],
    "integrity": {
      "verdict": "caution",
      "reason": "Prior tender expired without response from target carrier; KYC pending.",
      "implicated_node_ids": ["party-carrier-nationallink"],
      "implicated_edge_ids": ["edge-VL-1005-broker-carrier"]
    }
  }
}
"""#.utf8),
        "VL-1006": Data(#"""
{
  "load": {
    "id": "VL-1006",
    "reference_number": "REF-1006-FF",
    "origin": {
      "city": "Stockton",
      "state": "CA",
      "postal_code": "95202",
      "country": "US"
    },
    "destination": {
      "city": "Portland",
      "state": "OR",
      "postal_code": "97204",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 41750,
    "rate": 2675.00,
    "pickup_at": "2026-04-26T07:00:00Z",
    "deliver_at": "2026-04-27T18:00:00Z",
    "status": "draft",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-20T16:00:00Z",
        "actor": null
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": {
      "can_tender": true,
      "disabled_reason": null
    }
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-pacificgoods",
        "role": "shipper",
        "display_name": "Pacific Goods LLC",
        "verification_state": "verified",
        "kyc_completed_at": "2025-11-04T15:20:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    ],
    "edges": [],
    "integrity": {
      "verdict": "clean",
      "reason": "Draft load; no counterparties tendered yet.",
      "implicated_node_ids": [],
      "implicated_edge_ids": []
    }
  }
}
"""#.utf8),
        "VL-1007": Data(#"""
{
  "load": {
    "id": "VL-1007",
    "reference_number": "REF-1007-GG",
    "origin": {
      "city": "Detroit",
      "state": "MI",
      "postal_code": "48226",
      "country": "US"
    },
    "destination": {
      "city": "Indianapolis",
      "state": "IN",
      "postal_code": "46204",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 38450,
    "rate": 1325.00,
    "pickup_at": "2026-04-21T06:00:00Z",
    "deliver_at": "2026-04-21T17:00:00Z",
    "status": "dispatched",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-18T13:00:00Z",
        "actor": {
          "party_id": "party-shipper-globalexports",
          "role": "shipper",
          "display_name": "Global Exports Co."
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-18T13:30:00Z",
        "actor": {
          "party_id": "party-broker-sunbelt",
          "role": "broker",
          "display_name": "Sunbelt Logistics"
        }
      },
      {
        "status": "tendered",
        "timestamp": "2026-04-19T09:00:00Z",
        "actor": {
          "party_id": "party-broker-sunbelt",
          "role": "broker",
          "display_name": "Sunbelt Logistics"
        }
      },
      {
        "status": "accepted",
        "timestamp": "2026-04-19T10:15:00Z",
        "actor": {
          "party_id": "party-carrier-redrock",
          "role": "carrier",
          "display_name": "Red Rock Carriers"
        }
      },
      {
        "status": "dispatched",
        "timestamp": "2026-04-21T05:42:00Z",
        "actor": {
          "party_id": "party-dispatch-cornerstone",
          "role": "dispatch",
          "display_name": "Cornerstone Dispatch"
        }
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": null
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-globalexports",
        "role": "shipper",
        "display_name": "Global Exports Co.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-06-30T10:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-redrock",
        "role": "carrier",
        "display_name": "Red Rock Carriers",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-18T08:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-dispatch-cornerstone",
        "role": "dispatch",
        "display_name": "Cornerstone Dispatch",
        "verification_state": "verified",
        "kyc_completed_at": "2025-11-22T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1007-shipper-broker",
        "from_party_id": "party-shipper-globalexports",
        "to_party_id": "party-broker-sunbelt",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1007-broker-carrier",
        "from_party_id": "party-broker-sunbelt",
        "to_party_id": "party-carrier-redrock",
        "relationship_state": "verified",
        "tender_ref": "TNDR-1007-A"
      },
      {
        "edge_id": "edge-VL-1007-carrier-dispatch",
        "from_party_id": "party-carrier-redrock",
        "to_party_id": "party-dispatch-cornerstone",
        "relationship_state": "verified",
        "tender_ref": null
      }
    ],
    "integrity": {
      "verdict": "clean",
      "reason": "Short-haul dispatch confirmed; all parties verified.",
      "implicated_node_ids": [],
      "implicated_edge_ids": []
    }
  }
}
"""#.utf8),
        "VL-1008": Data(#"""
{
  "load": {
    "id": "VL-1008",
    "reference_number": "REF-1008-HH",
    "origin": {
      "city": "Houston",
      "state": "TX",
      "postal_code": "77002",
      "country": "US"
    },
    "destination": {
      "city": "Tulsa",
      "state": "OK",
      "postal_code": "74103",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 40500,
    "rate": 1495.00,
    "pickup_at": "2026-04-23T08:00:00Z",
    "deliver_at": "2026-04-23T19:00:00Z",
    "status": "posted",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-19T14:00:00Z",
        "actor": {
          "party_id": "party-shipper-easternfoods",
          "role": "shipper",
          "display_name": "Eastern Foods Distributing"
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-19T14:25:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": {
      "can_tender": false,
      "disabled_reason": "Carrier identity not yet verified — Phase 5 KYC outstanding"
    }
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-easternfoods",
        "role": "shipper",
        "display_name": "Eastern Foods Distributing",
        "verification_state": "verified",
        "kyc_completed_at": "2025-12-01T09:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-nationallink",
        "role": "carrier",
        "display_name": "National Link Carriers",
        "verification_state": "unverified",
        "kyc_completed_at": null,
        "device_binding_status": "unbound",
        "usdot_number": "1144882",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1008-shipper-broker",
        "from_party_id": "party-shipper-easternfoods",
        "to_party_id": "party-broker-freightwise",
        "relationship_state": "verified",
        "tender_ref": null
      }
    ],
    "integrity": {
      "verdict": "caution",
      "reason": "Target carrier identity has not completed KYC; tender disabled until verification completes.",
      "implicated_node_ids": ["party-carrier-nationallink"],
      "implicated_edge_ids": []
    }
  }
}
"""#.utf8),
        "VL-1009": Data(#"""
{
  "load": {
    "id": "VL-1009",
    "reference_number": "REF-1009-II",
    "origin": {
      "city": "Long Beach",
      "state": "CA",
      "postal_code": "90802",
      "country": "US"
    },
    "destination": {
      "city": "Phoenix",
      "state": "AZ",
      "postal_code": "85003",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 43200,
    "rate": 3275.00,
    "pickup_at": "2026-04-18T07:00:00Z",
    "deliver_at": "2026-04-19T18:00:00Z",
    "status": "in_transit",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-15T11:00:00Z",
        "actor": {
          "party_id": "party-shipper-globalexports",
          "role": "shipper",
          "display_name": "Global Exports Co."
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-15T11:45:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      },
      {
        "status": "tendered",
        "timestamp": "2026-04-16T09:00:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      },
      {
        "status": "accepted",
        "timestamp": "2026-04-16T11:30:00Z",
        "actor": {
          "party_id": "party-broker-keystone",
          "role": "broker",
          "display_name": "Keystone Freight Group"
        }
      },
      {
        "status": "dispatched",
        "timestamp": "2026-04-18T06:30:00Z",
        "actor": {
          "party_id": "party-dispatch-overland",
          "role": "dispatch",
          "display_name": "Overland Dispatch"
        }
      },
      {
        "status": "in_transit",
        "timestamp": "2026-04-18T07:42:00Z",
        "actor": {
          "party_id": "party-carrier-redrock",
          "role": "carrier",
          "display_name": "Red Rock Carriers"
        }
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": null
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-globalexports",
        "role": "shipper",
        "display_name": "Global Exports Co.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-06-30T10:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-keystone",
        "role": "broker",
        "display_name": "Keystone Freight Group",
        "verification_state": "flagged",
        "kyc_completed_at": "2025-07-04T08:00:00Z",
        "device_binding_status": "mismatched",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-redrock",
        "role": "carrier",
        "display_name": "Red Rock Carriers",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-18T08:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-dispatch-overland",
        "role": "dispatch",
        "display_name": "Overland Dispatch",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-01T10:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0987654",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-factoring-bridgecap",
        "role": "factoring",
        "display_name": "BridgeCap Capital",
        "verification_state": "verified",
        "kyc_completed_at": "2025-07-18T14:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1009-shipper-broker",
        "from_party_id": "party-shipper-globalexports",
        "to_party_id": "party-broker-freightwise",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1009-broker-broker",
        "from_party_id": "party-broker-freightwise",
        "to_party_id": "party-broker-keystone",
        "relationship_state": "flagged",
        "tender_ref": "TNDR-1009-A"
      },
      {
        "edge_id": "edge-VL-1009-broker-carrier",
        "from_party_id": "party-broker-keystone",
        "to_party_id": "party-carrier-redrock",
        "relationship_state": "flagged",
        "tender_ref": "TNDR-1009-B"
      },
      {
        "edge_id": "edge-VL-1009-carrier-dispatch",
        "from_party_id": "party-carrier-redrock",
        "to_party_id": "party-dispatch-overland",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1009-carrier-factoring",
        "from_party_id": "party-carrier-redrock",
        "to_party_id": "party-factoring-bridgecap",
        "relationship_state": "verified",
        "tender_ref": null
      }
    ],
    "integrity": {
      "verdict": "compromised",
      "reason": "Intermediary broker re-tendered to a downstream carrier without the original broker's authorization — classic double-broker pattern. Recommend re-tender directly to the carrier and freeze payment to the intermediary.",
      "implicated_node_ids": ["party-broker-keystone"],
      "implicated_edge_ids": ["edge-VL-1009-broker-broker", "edge-VL-1009-broker-carrier"]
    }
  }
}
"""#.utf8),
        "VL-1010": Data(#"""
{
  "load": {
    "id": "VL-1010",
    "reference_number": "REF-1010-JJ",
    "origin": {
      "city": "Miami",
      "state": "FL",
      "postal_code": "33130",
      "country": "US"
    },
    "destination": {
      "city": "Jacksonville",
      "state": "FL",
      "postal_code": "32202",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 39950,
    "rate": 1685.00,
    "pickup_at": "2026-04-22T07:00:00Z",
    "deliver_at": "2026-04-22T19:00:00Z",
    "status": "accepted",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-19T12:00:00Z",
        "actor": {
          "party_id": "party-shipper-easternfoods",
          "role": "shipper",
          "display_name": "Eastern Foods Distributing"
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-19T12:30:00Z",
        "actor": {
          "party_id": "party-broker-sunbelt",
          "role": "broker",
          "display_name": "Sunbelt Logistics"
        }
      },
      {
        "status": "tendered",
        "timestamp": "2026-04-20T08:00:00Z",
        "actor": {
          "party_id": "party-broker-sunbelt",
          "role": "broker",
          "display_name": "Sunbelt Logistics"
        }
      },
      {
        "status": "accepted",
        "timestamp": "2026-04-20T09:14:00Z",
        "actor": {
          "party_id": "party-carrier-phantomline",
          "role": "carrier",
          "display_name": "PhantomLine Logistics"
        }
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": null
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-easternfoods",
        "role": "shipper",
        "display_name": "Eastern Foods Distributing",
        "verification_state": "verified",
        "kyc_completed_at": "2025-12-01T09:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-phantomline",
        "role": "carrier",
        "display_name": "PhantomLine Logistics",
        "verification_state": "flagged",
        "kyc_completed_at": "2026-04-18T22:14:00Z",
        "device_binding_status": "mismatched",
        "usdot_number": "3998112",
        "usdot_authority_status": "revoked",
        "prior_relationships": []
      },
      {
        "party_id": "party-dispatch-cornerstone",
        "role": "dispatch",
        "display_name": "Cornerstone Dispatch",
        "verification_state": "verified",
        "kyc_completed_at": "2025-11-22T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1010-shipper-broker",
        "from_party_id": "party-shipper-easternfoods",
        "to_party_id": "party-broker-sunbelt",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1010-broker-carrier",
        "from_party_id": "party-broker-sunbelt",
        "to_party_id": "party-carrier-phantomline",
        "relationship_state": "flagged",
        "tender_ref": "TNDR-1010-A"
      }
    ],
    "integrity": {
      "verdict": "compromised",
      "reason": "Carrier identity does not match USDOT authority on file — chameleon-carrier pattern. USDOT authority revoked; recent revocation. Stop dispatch and contact broker.",
      "implicated_node_ids": ["party-carrier-phantomline"],
      "implicated_edge_ids": ["edge-VL-1010-broker-carrier"]
    }
  }
}
"""#.utf8),
        "VL-1011": Data(#"""
{
  "load": {
    "id": "VL-1011",
    "reference_number": "REF-1011-KK",
    "origin": {
      "city": "Atlanta",
      "state": "GA",
      "postal_code": "30303",
      "country": "US"
    },
    "destination": {
      "city": "Birmingham",
      "state": "AL",
      "postal_code": "35203",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 40850,
    "rate": 1245.00,
    "pickup_at": "2026-04-12T07:00:00Z",
    "deliver_at": "2026-04-12T15:00:00Z",
    "status": "invoiced",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-08T10:00:00Z",
        "actor": {
          "party_id": "party-shipper-easternfoods",
          "role": "shipper",
          "display_name": "Eastern Foods Distributing"
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-08T10:30:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      },
      {
        "status": "tendered",
        "timestamp": "2026-04-09T11:00:00Z",
        "actor": {
          "party_id": "party-broker-freightwise",
          "role": "broker",
          "display_name": "FreightWise Brokerage"
        }
      },
      {
        "status": "accepted",
        "timestamp": "2026-04-09T13:00:00Z",
        "actor": {
          "party_id": "party-broker-keystone",
          "role": "broker",
          "display_name": "Keystone Freight Group"
        }
      },
      {
        "status": "dispatched",
        "timestamp": "2026-04-12T06:30:00Z",
        "actor": {
          "party_id": "party-dispatch-cornerstone",
          "role": "dispatch",
          "display_name": "Cornerstone Dispatch"
        }
      },
      {
        "status": "in_transit",
        "timestamp": "2026-04-12T07:25:00Z",
        "actor": {
          "party_id": "party-carrier-redrock",
          "role": "carrier",
          "display_name": "Red Rock Carriers"
        }
      },
      {
        "status": "delivered",
        "timestamp": "2026-04-12T14:50:00Z",
        "actor": {
          "party_id": "party-carrier-redrock",
          "role": "carrier",
          "display_name": "Red Rock Carriers"
        }
      },
      {
        "status": "pod_captured",
        "timestamp": "2026-04-12T15:05:00Z",
        "actor": {
          "party_id": "party-carrier-redrock",
          "role": "carrier",
          "display_name": "Red Rock Carriers"
        }
      },
      {
        "status": "invoiced",
        "timestamp": "2026-04-13T09:42:00Z",
        "actor": {
          "party_id": "party-factoring-stagepay",
          "role": "factoring",
          "display_name": "StagePay Funding"
        }
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": null
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-easternfoods",
        "role": "shipper",
        "display_name": "Eastern Foods Distributing",
        "verification_state": "verified",
        "kyc_completed_at": "2025-12-01T09:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-freightwise",
        "role": "broker",
        "display_name": "FreightWise Brokerage",
        "verification_state": "verified",
        "kyc_completed_at": "2025-08-12T09:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-keystone",
        "role": "broker",
        "display_name": "Keystone Freight Group",
        "verification_state": "flagged",
        "kyc_completed_at": "2025-07-04T08:00:00Z",
        "device_binding_status": "mismatched",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-redrock",
        "role": "carrier",
        "display_name": "Red Rock Carriers",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-18T08:30:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0445582",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-factoring-stagepay",
        "role": "factoring",
        "display_name": "StagePay Funding",
        "verification_state": "flagged",
        "kyc_completed_at": "2026-04-01T12:00:00Z",
        "device_binding_status": "mismatched",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1011-shipper-broker",
        "from_party_id": "party-shipper-easternfoods",
        "to_party_id": "party-broker-freightwise",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1011-broker-broker",
        "from_party_id": "party-broker-freightwise",
        "to_party_id": "party-broker-keystone",
        "relationship_state": "flagged",
        "tender_ref": "TNDR-1011-A"
      },
      {
        "edge_id": "edge-VL-1011-broker-carrier",
        "from_party_id": "party-broker-keystone",
        "to_party_id": "party-carrier-redrock",
        "relationship_state": "flagged",
        "tender_ref": "TNDR-1011-B"
      },
      {
        "edge_id": "edge-VL-1011-carrier-factoring",
        "from_party_id": "party-carrier-redrock",
        "to_party_id": "party-factoring-stagepay",
        "relationship_state": "flagged",
        "tender_ref": "INV-1011-X"
      }
    ],
    "integrity": {
      "verdict": "compromised",
      "reason": "Factoring company filed invoice on a double-brokered shipment; invoice routed to a factoring identity without an established relationship — clawback risk. Freeze funding and investigate factoring identity.",
      "implicated_node_ids": ["party-broker-keystone", "party-factoring-stagepay"],
      "implicated_edge_ids": ["edge-VL-1011-broker-broker", "edge-VL-1011-broker-carrier", "edge-VL-1011-carrier-factoring"]
    }
  }
}
"""#.utf8),
        "VL-1012": Data(#"""
{
  "load": {
    "id": "VL-1012",
    "reference_number": "REF-1012-LL",
    "origin": {
      "city": "San Diego",
      "state": "CA",
      "postal_code": "92101",
      "country": "US"
    },
    "destination": {
      "city": "Tucson",
      "state": "AZ",
      "postal_code": "85701",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 41100,
    "rate": 2375.00,
    "pickup_at": "2026-04-05T07:00:00Z",
    "deliver_at": "2026-04-05T17:00:00Z",
    "status": "funded",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-01T10:00:00Z",
        "actor": {
          "party_id": "party-shipper-pacificgoods",
          "role": "shipper",
          "display_name": "Pacific Goods LLC"
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-01T10:30:00Z",
        "actor": {
          "party_id": "party-broker-sunbelt",
          "role": "broker",
          "display_name": "Sunbelt Logistics"
        }
      },
      {
        "status": "tendered",
        "timestamp": "2026-04-02T09:00:00Z",
        "actor": {
          "party_id": "party-broker-sunbelt",
          "role": "broker",
          "display_name": "Sunbelt Logistics"
        }
      },
      {
        "status": "accepted",
        "timestamp": "2026-04-02T11:00:00Z",
        "actor": {
          "party_id": "party-carrier-acme",
          "role": "carrier",
          "display_name": "Acme Trucking Inc."
        }
      },
      {
        "status": "dispatched",
        "timestamp": "2026-04-05T06:30:00Z",
        "actor": {
          "party_id": "party-dispatch-overland",
          "role": "dispatch",
          "display_name": "Overland Dispatch"
        }
      },
      {
        "status": "in_transit",
        "timestamp": "2026-04-05T07:20:00Z",
        "actor": {
          "party_id": "party-carrier-acme",
          "role": "carrier",
          "display_name": "Acme Trucking Inc."
        }
      },
      {
        "status": "delivered",
        "timestamp": "2026-04-05T16:42:00Z",
        "actor": {
          "party_id": "party-carrier-acme",
          "role": "carrier",
          "display_name": "Acme Trucking Inc."
        }
      },
      {
        "status": "pod_captured",
        "timestamp": "2026-04-05T16:58:00Z",
        "actor": {
          "party_id": "party-carrier-acme",
          "role": "carrier",
          "display_name": "Acme Trucking Inc."
        }
      },
      {
        "status": "invoiced",
        "timestamp": "2026-04-06T09:00:00Z",
        "actor": {
          "party_id": "party-factoring-bridgecap",
          "role": "factoring",
          "display_name": "BridgeCap Capital"
        }
      },
      {
        "status": "funded",
        "timestamp": "2026-04-07T13:15:00Z",
        "actor": {
          "party_id": "party-factoring-bridgecap",
          "role": "factoring",
          "display_name": "BridgeCap Capital"
        }
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": null
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-pacificgoods",
        "role": "shipper",
        "display_name": "Pacific Goods LLC",
        "verification_state": "verified",
        "kyc_completed_at": "2025-11-04T15:20:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-acme",
        "role": "carrier",
        "display_name": "Acme Trucking Inc.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-22T13:05:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0123456",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-dispatch-overland",
        "role": "dispatch",
        "display_name": "Overland Dispatch",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-01T10:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0987654",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-factoring-bridgecap",
        "role": "factoring",
        "display_name": "BridgeCap Capital",
        "verification_state": "verified",
        "kyc_completed_at": "2025-07-18T14:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1012-shipper-broker",
        "from_party_id": "party-shipper-pacificgoods",
        "to_party_id": "party-broker-sunbelt",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1012-broker-carrier",
        "from_party_id": "party-broker-sunbelt",
        "to_party_id": "party-carrier-acme",
        "relationship_state": "verified",
        "tender_ref": "TNDR-1012-A"
      },
      {
        "edge_id": "edge-VL-1012-carrier-dispatch",
        "from_party_id": "party-carrier-acme",
        "to_party_id": "party-dispatch-overland",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1012-carrier-factoring",
        "from_party_id": "party-carrier-acme",
        "to_party_id": "party-factoring-bridgecap",
        "relationship_state": "verified",
        "tender_ref": "INV-1012-X"
      }
    ],
    "integrity": {
      "verdict": "clean",
      "reason": "Funded; full cycle complete with all parties verified.",
      "implicated_node_ids": [],
      "implicated_edge_ids": []
    }
  }
}
"""#.utf8),
    ]

    // MARK: - Action-success payload (AUTHORITATIVE COPY of test fixture)

    /// JSON returned by the action-success handler for every successful POST
    /// to `/loads/{loadID}/{action}`. Shipped at
    /// `validationLedgerTests/Networking/Fixtures/load-action-success.json`,
    /// inlined here. The payload is the VL-1004 post-accept response (status
    /// advanced to `accepted`, `state_history` appended with the new event,
    /// `chain_of_trust.integrity` reason rewritten to reflect the verified
    /// carrier handoff) — a single canonical success body for every action.
    private static let actionSuccessPayload: Data = Data(#"""
{
  "load": {
    "id": "VL-1004",
    "reference_number": "REF-1004-DD",
    "origin": {
      "city": "Phoenix",
      "state": "AZ",
      "postal_code": "85003",
      "country": "US"
    },
    "destination": {
      "city": "Denver",
      "state": "CO",
      "postal_code": "80202",
      "country": "US"
    },
    "equipment": "dry_van",
    "weight": 41200,
    "rate": 2450.0,
    "pickup_at": "2026-04-22T09:00:00Z",
    "deliver_at": "2026-04-23T16:00:00Z",
    "status": "accepted",
    "state_history": [
      {
        "status": "draft",
        "timestamp": "2026-04-19T11:00:00Z",
        "actor": {
          "party_id": "party-shipper-pacificgoods",
          "role": "shipper",
          "display_name": "Pacific Goods LLC"
        }
      },
      {
        "status": "posted",
        "timestamp": "2026-04-19T11:25:00Z",
        "actor": {
          "party_id": "party-broker-sunbelt",
          "role": "broker",
          "display_name": "Sunbelt Logistics"
        }
      },
      {
        "status": "tendered",
        "timestamp": "2026-04-20T14:00:00Z",
        "actor": {
          "party_id": "party-broker-sunbelt",
          "role": "broker",
          "display_name": "Sunbelt Logistics"
        }
      },
      {
        "status": "accepted",
        "timestamp": "2026-04-20T15:18:00Z",
        "actor": {
          "party_id": "party-carrier-acme",
          "role": "carrier",
          "display_name": "Acme Trucking Inc."
        }
      }
    ],
    "respond_by_at": null,
    "tender_eligibility": {
      "can_tender": true,
      "disabled_reason": null
    }
  },
  "chain_of_trust": {
    "nodes": [
      {
        "party_id": "party-shipper-pacificgoods",
        "role": "shipper",
        "display_name": "Pacific Goods LLC",
        "verification_state": "verified",
        "kyc_completed_at": "2025-11-04T15:20:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-broker-sunbelt",
        "role": "broker",
        "display_name": "Sunbelt Logistics",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-08T11:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": null,
        "usdot_authority_status": "not_applicable",
        "prior_relationships": []
      },
      {
        "party_id": "party-carrier-acme",
        "role": "carrier",
        "display_name": "Acme Trucking Inc.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-22T13:05:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0123456",
        "usdot_authority_status": "active",
        "prior_relationships": []
      },
      {
        "party_id": "party-dispatch-overland",
        "role": "dispatch",
        "display_name": "Overland Dispatch",
        "verification_state": "verified",
        "kyc_completed_at": "2025-10-01T10:00:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0987654",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    ],
    "edges": [
      {
        "edge_id": "edge-VL-1004-shipper-broker",
        "from_party_id": "party-shipper-pacificgoods",
        "to_party_id": "party-broker-sunbelt",
        "relationship_state": "verified",
        "tender_ref": null
      },
      {
        "edge_id": "edge-VL-1004-broker-carrier",
        "from_party_id": "party-broker-sunbelt",
        "to_party_id": "party-carrier-acme",
        "relationship_state": "verified",
        "tender_ref": "TNDR-1004-A"
      },
      {
        "edge_id": "edge-VL-1004-carrier-dispatch",
        "from_party_id": "party-carrier-acme",
        "to_party_id": "party-dispatch-overland",
        "relationship_state": "verified",
        "tender_ref": null
      }
    ],
    "integrity": {
      "verdict": "clean",
      "reason": "Tender accepted; carrier identity verified at handoff.",
      "implicated_node_ids": [],
      "implicated_edge_ids": []
    }
  }
}
"""#.utf8)

    // MARK: - Degraded-counterparty demo lane (DEBUG-only, NOT in registerAppDefaults)

    /// Register a single handler dispatching `GET /loads/degraded` to the
    /// `loads-list-degraded-counterparty.json` payload. Used by Phase 8 UI tests
    /// that need to exercise the fail-closed UI path (one row with null counterparty
    /// + one row with a flagged counterparty, per 08-CONTEXT.md D-04 second half).
    ///
    /// === Why a sentinel role suffix (`/loads/degraded`) ===
    /// 08-RESEARCH.md §Discretion offered two options: an extra registry method or
    /// an XCUITest `?demo=degraded` query parameter. The existing dispatcher in
    /// `registerAppDefaults()` matches on URL PATH SUFFIX with no query parsing
    /// (lines 89-99). A sentinel suffix is the idiomatic addition — it slots into
    /// the same path-suffix dispatch grammar without any new dispatcher code.
    ///
    /// === Test-only invocation (RESEARCH Open Question 2 ratified) ===
    /// This function is NEVER called from `registerAppDefaults()`. Tests that need
    /// the degraded scenario call it explicitly AFTER `MockURLProtocol.reset()`.
    /// Keeping it out of the organic DEBUG tap-through prevents the degraded
    /// fixture from leaking into the demo flow.
    static func registerForDegradedDemo() {
        MockURLProtocol.register { request in
            guard request.httpMethod == "GET" else { return nil }
            guard request.url?.path == "/loads/degraded" else { return nil }
            return make200(body: degradedPayload, url: request.url)
        }
    }

    /// Inline payload for `/loads/degraded` (AUTHORITATIVE COPY of
    /// `validationLedgerTests/Networking/Fixtures/loads-list-degraded-counterparty.json`).
    /// Drift-mitigation discipline matches the `listPayloads` table above: edits
    /// to either side MUST be paired.
    private static let degradedPayload: Data = Data(#"""
{
  "loads": [
    {
      "load": {
        "id": "VL-D001",
        "reference_number": "REF-D001",
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
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-03-30T14:00:00Z",
            "actor": null
          },
          {
            "status": "posted",
            "timestamp": "2026-03-30T14:30:00Z",
            "actor": null
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": null
    },
    {
      "load": {
        "id": "VL-D002",
        "reference_number": "REF-D002",
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
        "status": "tendered",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-03-30T14:00:00Z",
            "actor": null
          },
          {
            "status": "posted",
            "timestamp": "2026-03-30T14:30:00Z",
            "actor": null
          }
        ],
        "respond_by_at": "2026-04-10T16:00:00Z",
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-phantomline",
        "role": "carrier",
        "display_name": "PhantomLine Logistics",
        "verification_state": "flagged",
        "kyc_completed_at": "2026-04-01T12:00:00Z",
        "device_binding_status": "mismatched",
        "usdot_number": "9999999",
        "usdot_authority_status": "revoked",
        "prior_relationships": []
      }
    },
    {
      "load": {
        "id": "VL-D003",
        "reference_number": "REF-D003",
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
        "status": "accepted",
        "state_history": [
          {
            "status": "draft",
            "timestamp": "2026-03-30T14:00:00Z",
            "actor": null
          },
          {
            "status": "posted",
            "timestamp": "2026-03-30T14:30:00Z",
            "actor": null
          }
        ],
        "respond_by_at": null,
        "tender_eligibility": {
          "can_tender": true,
          "disabled_reason": null
        }
      },
      "displayed_counterparty": {
        "party_id": "party-carrier-acme",
        "role": "carrier",
        "display_name": "Acme Trucking Inc.",
        "verification_state": "verified",
        "kyc_completed_at": "2025-09-22T13:05:00Z",
        "device_binding_status": "bound",
        "usdot_number": "0123456",
        "usdot_authority_status": "active",
        "prior_relationships": []
      }
    }
  ],
  "next_cursor": null
}
"""#.utf8)
}

#endif
