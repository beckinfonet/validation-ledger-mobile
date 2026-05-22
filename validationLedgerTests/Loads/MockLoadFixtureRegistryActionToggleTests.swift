// validationLedgerTests/Loads/MockLoadFixtureRegistryActionToggleTests.swift
// Phase 10 D-19 — tests for the 4 DEBUG-only failure-injection toggles wired
// in `MockLoadFixtureRegistry`. Verifies:
//   1. With no flags set, the default action-success handler still fires.
//   2. Each of conflict409 / validation422 / serverError500 fires its own
//      fixture body when the corresponding `…Active` closure returns true.
//   3. The `latencySlow` toggle inserts a delay then DEFERS to the next
//      matching handler (does NOT short-circuit).
//   4. Latency + a failure flag combined produces the failure body after the
//      delay (documents combined behavior).
//   5. Precedence order is conflict409 → validation422 → serverError500 →
//      latencySlow → existing-success (Pitfall 2 regression guard).
//
// Test-seam: `DebugActionFailureOverride` exposes each `…Active` check as a
// `static var … : () -> Bool` closure so a test can reassign in setUp and
// restore in tearDown. Production builds keep the default closure that reads
// `ProcessInfo.processInfo.arguments` — semantically identical to a Phase-5
// computed-property check.
//
// File-level `#if DEBUG` because `DebugActionFailureOverride` only exists in
// DEBUG builds. Release builds compile the toggle namespace AND this whole
// test class to zero bytes — but tests only run under DEBUG anyway.

#if DEBUG
import XCTest
@testable import validationLedger

final class MockLoadFixtureRegistryActionToggleTests: XCTestCase {

    // The `actionPathSegments` set in MockLoadFixtureRegistry expects 2 segments
    // for the action handler: `/loads/<VL-…>/<segment>`. We exercise `accept`.
    private let actionPath = "/loads/VL-001/accept"

    // MARK: - setUp / tearDown

    override func setUp() {
        super.setUp()
        // Clear MockURLProtocol so prior tests' handlers can't shadow ours.
        MockURLProtocol.reset()
        // Defeat the registry's process-lifetime guard (WR-01) — a sibling
        // test may have already registered then reset MockURLProtocol, leaving
        // the guard `true` and the handler array empty.
        MockLoadFixtureRegistry.resetForTestOnly()
        MockLoadFixtureRegistry.registerAppDefaults()
        // Ensure all 4 closures start each test in the "production-default" state:
        restoreProductionDefaults()
    }

    override func tearDown() {
        // Same restoration on tearDown to prevent leakage across tests + into
        // sibling suites (the process is shared inside a single xcodebuild test
        // invocation, even when @Suite isolation says otherwise — XCTestCase
        // closures are static state).
        restoreProductionDefaults()
        // Leave handlers cleared so siblings don't see our registry residue.
        MockURLProtocol.reset()
        MockLoadFixtureRegistry.resetForTestOnly()
        super.tearDown()
    }

    private func restoreProductionDefaults() {
        DebugActionFailureOverride.conflict409Active = {
            ProcessInfo.processInfo.arguments.contains(DebugActionFailureOverride.conflict409Flag)
        }
        DebugActionFailureOverride.validation422Active = {
            ProcessInfo.processInfo.arguments.contains(DebugActionFailureOverride.validation422Flag)
        }
        DebugActionFailureOverride.serverError500Active = {
            ProcessInfo.processInfo.arguments.contains(DebugActionFailureOverride.serverError500Flag)
        }
        DebugActionFailureOverride.latencySlowActive = {
            ProcessInfo.processInfo.arguments.contains(DebugActionFailureOverride.latencySlowFlag)
        }
    }

    // MARK: - Helpers

    /// Build a URLRequest that the registry's `(3*)` handlers will recognise:
    /// POST /loads/VL-001/accept. We bypass APIClient entirely — these tests
    /// exercise the registry's handler dispatch directly via MockURLProtocol.
    private func makeActionRequest() -> URLRequest {
        var req = URLRequest(url: URL(string: "https://mock.local\(actionPath)")!)
        req.httpMethod = "POST"
        return req
    }

    /// Drive MockURLProtocol's startLoading via URLSession + capture the
    /// (data, status) pair. Returns nil if URLSession threw.
    private func dispatch(_ request: URLRequest) async throws -> (Data, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("Expected HTTPURLResponse, got \(type(of: response))")
            return (data, -1)
        }
        return (data, http.statusCode)
    }

    private func bodiesEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        // The mock-registry inlined payloads carry a trailing newline (matches
        // the .json fixture files). Compare canonical JSON strings to avoid
        // brittle byte-equality across editors.
        guard let lhsObj = try? JSONSerialization.jsonObject(with: lhs) as? [String: Any],
              let rhsObj = try? JSONSerialization.jsonObject(with: rhs) as? [String: Any] else {
            return lhs == rhs
        }
        return NSDictionary(dictionary: lhsObj).isEqual(to: rhsObj)
    }

    // MARK: - Tests

    func test_default_noFlags_actionRequest_returnsSuccess() async throws {
        // All 4 flags inactive — the existing action-success handler fires.
        let (data, status) = try await dispatch(makeActionRequest())
        XCTAssertEqual(status, 200, "default path should return 200 from the existing success handler")
        // Success body is a `Load + ChainOfTrust` envelope — assert a known key.
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("success body should be JSON object")
            return
        }
        XCTAssertNotNil(obj["load"], "success body should carry a `load` key")
        XCTAssertNotNil(obj["chain_of_trust"], "success body should carry a `chain_of_trust` key")
        // CR-02 regression — load.id MUST match the requested loadID, NOT
        // the canonical VL-1004 template. The action-success handler used
        // to hardcode VL-1004 for every load; this assertion guards against
        // that regression.
        guard let load = obj["load"] as? [String: Any] else {
            XCTFail("`load` key must be a JSON object")
            return
        }
        XCTAssertEqual(load["id"] as? String, "VL-001",
                       "CR-02: success body's load.id MUST mirror the request's loadID (VL-001 per actionPath) — not the hardcoded VL-1004 template.")
    }

    func test_actionSuccessPayload_synthesizedFromRequestedLoadID_CR02() async throws {
        // CR-02 sweep — exercise three other VL-#### loadIDs and assert
        // each response's load.id mirrors the request. This is the
        // demo-flow scenario: tendering on VL-1003 must NOT swap the
        // screen to VL-1004 mid-tap (or any other ID).
        for loadID in ["VL-1003", "VL-1008", "VL-1009"] {
            var req = URLRequest(url: URL(string: "https://mock.local/loads/\(loadID)/tender")!)
            req.httpMethod = "POST"
            let (data, status) = try await dispatch(req)
            XCTAssertEqual(status, 200, "CR-02: action POST on \(loadID) should return 200")
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let load = obj["load"] as? [String: Any] else {
                XCTFail("CR-02: success body should be JSON object with `load` key for \(loadID)")
                return
            }
            XCTAssertEqual(load["id"] as? String, loadID,
                           "CR-02: response.load.id MUST mirror the request loadID '\(loadID)' — the action handler used to hardcode VL-1004 for every action against every load, corrupting the post-action .loaded(response.load,…) state in the VM.")
        }
    }

    func test_conflict409Flag_actionRequest_returns409Body() async throws {
        DebugActionFailureOverride.conflict409Active = { true }
        let (data, status) = try await dispatch(makeActionRequest())
        XCTAssertEqual(status, 409, "conflict409 toggle should yield 409")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("conflict409 body should be JSON object")
            return
        }
        XCTAssertEqual(obj["error_code"] as? String, "load.stale_state",
                       "conflict409 body must mirror load-action-conflict-409.json error_code")
    }

    func test_validation422Flag_actionRequest_returns422Body() async throws {
        DebugActionFailureOverride.validation422Active = { true }
        let (data, status) = try await dispatch(makeActionRequest())
        XCTAssertEqual(status, 422, "validation422 toggle should yield 422")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("validation422 body should be JSON object")
            return
        }
        XCTAssertEqual(obj["error_code"] as? String, "load.invalid_transition",
                       "validation422 body must mirror load-action-validation-422.json error_code")
    }

    func test_serverError500Flag_actionRequest_returns500Body() async throws {
        DebugActionFailureOverride.serverError500Active = { true }
        let (data, status) = try await dispatch(makeActionRequest())
        XCTAssertEqual(status, 500, "serverError500 toggle should yield 500")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("server500 body should be JSON object")
            return
        }
        XCTAssertEqual(obj["error_code"] as? String, "server.internal",
                       "server500 body must mirror load-action-server-error-500.json error_code")
    }

    func test_latencySlowFlag_actionRequest_isDelayed_thenReturnsSuccess() async throws {
        DebugActionFailureOverride.latencySlowActive = { true }
        let start = Date()
        let (data, status) = try await dispatch(makeActionRequest())
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 1.4,
                                    "latencySlow toggle should delay >= 1.4s (target 1.5s) — got \(elapsed)s")
        XCTAssertEqual(status, 200, "latencySlow defers — falls through to the success handler")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("latencySlow body should be JSON object (success fixture)")
            return
        }
        XCTAssertNotNil(obj["load"], "latency-deferred body should still be the success envelope")
    }

    func test_latencySlow_andConflict409_combined_conflictWinsImmediately_noDelay() async throws {
        // DOCUMENTED COMBINED BEHAVIOR per registration order
        // (conflict409 → validation422 → serverError500 → latencySlow → success):
        // when BOTH conflict409 and latencySlow are active, conflict409 registers
        // FIRST in the handler array and matches immediately — the latency
        // handler never runs, so no delay occurs. The 409 body wins.
        //
        // This is intentional: QA workflow guidance is "set exactly ONE failure
        // flag at a time"; combining is defensive, and the precedence order
        // makes the deterministic outcome equivalent to "conflict409 alone".
        // If the human eye wants delay-then-409, they set ONLY latencySlow and
        // the success handler returns — they wouldn't combine to get the 409.
        DebugActionFailureOverride.latencySlowActive = { true }
        DebugActionFailureOverride.conflict409Active = { true }
        let start = Date()
        let (data, status) = try await dispatch(makeActionRequest())
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.5,
                          "combined: conflict409 registers BEFORE latencySlow — no delay incurred (got \(elapsed)s)")
        XCTAssertEqual(status, 409, "combined: conflict409 still wins (it's first in registration order)")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("combined body should be JSON object")
            return
        }
        XCTAssertEqual(obj["error_code"] as? String, "load.stale_state",
                       "combined: conflict409 fixture body must surface")
    }

    func test_precedenceOrder_conflict409beforeValidation422() async throws {
        // Both flags true. Per documented order (conflict409 registers FIRST),
        // the conflict409 handler matches first and the 422 handler never runs.
        // This is the Pitfall 2 regression guard.
        DebugActionFailureOverride.conflict409Active = { true }
        DebugActionFailureOverride.validation422Active = { true }
        let (data, status) = try await dispatch(makeActionRequest())
        XCTAssertEqual(status, 409,
                       "precedence: conflict409 registers BEFORE validation422 → 409 wins")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("precedence body should be JSON object")
            return
        }
        XCTAssertEqual(obj["error_code"] as? String, "load.stale_state",
                       "precedence: conflict409 body, not validation422")
    }

    func test_releaseSafety_DEBUGGuard() {
        // Compile-time-checked assertion: this whole test class is `#if DEBUG`
        // wrapped, which is only legal if `DebugActionFailureOverride` exists
        // in DEBUG. If a future refactor accidentally promotes the toggle into
        // Release (`#if DEBUG` removed), this test still runs in DEBUG (no
        // regression). If a future refactor REMOVES the toggle entirely, this
        // file fails to compile — fail loudly, not silently.
        XCTAssertEqual(DebugActionFailureOverride.conflict409Flag, "-MockActionConflict409")
        XCTAssertEqual(DebugActionFailureOverride.validation422Flag, "-MockActionValidation422")
        XCTAssertEqual(DebugActionFailureOverride.serverError500Flag, "-MockActionServerError500")
        XCTAssertEqual(DebugActionFailureOverride.latencySlowFlag, "-MockActionLatencySlow")
        // ~1.5s is the documented interval; tolerate a tiny test-tweak deviation.
        XCTAssertEqual(DebugActionFailureOverride.latencySlowInterval, 1.5, accuracy: 0.001)
    }
}
#endif
