// validationLedgerTests/Loads/LoadListViewModelTests.swift
// Phase 8 Plan 03 Task 2 — LoadListViewModel state-machine test surface.
//
// Locks the 4-state machine + the refresh-from-loaded contract +
// the zero-PII log invariant (T-08-08). Drives the real APIClient through
// MockURLProtocol via the Plan 01 fixture corpus (loads-list-broker.json,
// loads-list-empty.json) + the Phase 7 LOAD-01 forced-failure injection.
//
// === .serialized requirement ===
// Every fixture-driven test mutates the global MockURLProtocol _handlers /
// _failureHandlers arrays. Per the `ios-test-suite-pitfalls` project memory,
// suites that touch the global fixture registry MUST be .serialized to avoid
// the parallel-execution race that produces ~58 false-negative 404s on full-
// suite runs. Mirrors MockURLProtocolLatencyTests + LoadListEnvelopeDecodeTests.
//
// === Why XCTest is NOT used here ===
// These tests are state-machine / log-content assertions, NOT snapshot
// rendering. Plan 02 SUMMARY locked the rule: snapshot tests = XCTest (needs
// XCTAttachment); everything else = Swift Testing. This file follows that
// precedent.
//
// === T-08-08 PII invariant ===
// `Test_fetchLoadsLogsZeroPIIOnSuccessAndFailure` injects a RecordingLogger
// double; runs success + forced-failure flows; scans every recorded
// `[LogField: Any]` dictionary across `.info / .warn / .error` calls; fails
// if ANY value mentions synthetic PII tokens (VL-/REF-/party names from the
// Plan 01 fixtures). LogField's closed-enum key channel + the VM's
// `fields: [:]` discipline make this hold by construction; the test locks it
// for regression.
//
// === T-08-09 synthetic-PII discipline ===
// All inline JSON synthesized in this file uses Plan 01 fixture corpus
// identifiers (VL-1001, REF-1001-AA, Acme Trucking Inc., FreightWise
// Brokerage) — every value already shipped in
// validationLedgerTests/Networking/Fixtures/. No real freight references reach
// CI artefacts.

import Testing
import Foundation
@testable import validationLedger

@Suite("LoadListViewModel — Phase 8 4-state machine + refresh + zero-PII log", .serialized)
struct LoadListViewModelTests {

    // MARK: - APIClient + session assembly (matches Phase 8 Plan 01 precedent)

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

    @MainActor
    private func makeViewModel(role: Role, logger: any Logger) -> LoadListViewModel {
        LoadListViewModel(role: role, apiClient: makeAPIClient(), logger: logger)
    }

    /// The locked user-facing copy (matches LoadListViewModel.userFacingMessage).
    /// Foundation's `NSLocalizedString` falls back to `value:` when the key is
    /// not present in any `.strings` table — so this test-side call yields the
    /// same string as the VM's call without needing a localization bundle.
    private static let expectedErrorCopy: String = NSLocalizedString(
        "loads.error.generic",
        value: "Check your connection and try again. Your loads are safe.",
        comment: ""
    )

    // MARK: - State recorder (NSLock-guarded; `onStateChange` fires on the
    // VM's @MainActor isolation, so callers append synchronously without
    // spinning a Task — the Task-based recorder produced ordering races where
    // the recorded array only contained the init-time .loading).

    private final class StateRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _states: [LoadListViewModel.State] = []
        func record(_ s: LoadListViewModel.State) {
            lock.withLock { _states.append(s) }
        }
        func reset() { lock.withLock { _states.removeAll() } }
        func snapshot() -> [LoadListViewModel.State] {
            lock.withLock { _states }
        }
    }

    // MARK: - RecordingLogger (T-08-08 capture surface)

    private final class RecordingLogger: Logger, @unchecked Sendable {
        struct Entry {
            let level: LogLevel
            let event: String
            let fields: [LogField: Any]
        }
        private let lock = NSLock()
        private var _entries: [Entry] = []
        var entries: [Entry] { lock.withLock { _entries } }
        func reset() { lock.withLock { _entries.removeAll() } }
        func log(_ level: LogLevel, event: LogEvent, fields: [LogField: Any]) {
            lock.withLock { _entries.append(Entry(level: level, event: event.name, fields: fields)) }
        }
        func log(_ level: LogLevel, _ message: String) {
            lock.withLock { _entries.append(Entry(level: level, event: message, fields: [:])) }
        }
    }

    // MARK: - Test 1 — loading → loaded on a populated fixture

    @Test("Test 1: state sequence is [.loading, .loaded] on a populated fixture")
    func loadingToLoadedOnPopulatedFixture() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let data = try FixtureLoader.loadFixture("loads-list-broker")
        MockURLProtocol.registerFixture(
            for: LoadListEndpoint.self,
            path: "/loads/broker", method: .get,
            statusCode: 200, body: data
        )

        let recorder = StateRecorder()
        let logger = RecordingLogger()
        let vm = await makeViewModel(role: .broker, logger: logger)
        await MainActor.run {
            vm.onStateChange = { s in recorder.record(s) }
        }

        await vm.fetchLoads()
        // Settle the recorder's queued Task before snapshotting.
        await Task.yield()
        await Task.yield()

        let recorded = recorder.snapshot()
        // The init-time state is .loading already; the first didSet fires when
        // fetchLoads re-assigns state = .loading (same value but didSet fires
        // on every assignment) — so we expect AT LEAST one loading and a
        // terminal loaded.
        #expect(recorded.contains { if case .loading = $0 { return true } else { return false } },
                "sequence must include .loading; got: \(recorded.count) entries")
        guard case .loaded(let items, _) = recorded.last else {
            Issue.record("terminal entry must be .loaded; got: \(String(describing: recorded.last))")
            return
        }
        #expect(items.count > 0, "broker fixture must have at least one row")
    }

    // MARK: - Test 2 — loading → empty on an empty fixture

    @Test("Test 2: state sequence terminates in .empty on an empty fixture")
    func loadingToEmptyOnEmptyFixture() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let data = try FixtureLoader.loadFixture("loads-list-empty")
        MockURLProtocol.registerFixture(
            for: LoadListEndpoint.self,
            path: "/loads/shipper", method: .get,
            statusCode: 200, body: data
        )

        let recorder = StateRecorder()
        let logger = RecordingLogger()
        let vm = await makeViewModel(role: .shipper, logger: logger)
        await MainActor.run {
            vm.onStateChange = { s in recorder.record(s) }
        }

        await vm.fetchLoads()
        await Task.yield(); await Task.yield()

        let recorded = recorder.snapshot()
        #expect(recorded.contains { if case .loading = $0 { return true } else { return false } },
                ".loading must be observed before terminal")
        #expect(recorded.last == .empty,
                "terminal state must be .empty on empty fixture; got: \(String(describing: recorded.last))")
    }

    // MARK: - Test 3 — loading → error on forced HTTP 500

    @Test("Test 3: forced HTTP 500 → .error with the locked loads.error.generic copy")
    func loadingToErrorOnForcedHTTP500() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        MockURLProtocol.registerForcedFailure(
            for: "/loads/carrier", method: .get,
            kind: .http(statusCode: 500, body: Data())
        )

        let recorder = StateRecorder()
        let logger = RecordingLogger()
        let vm = await makeViewModel(role: .carrier, logger: logger)
        await MainActor.run {
            vm.onStateChange = { s in recorder.record(s) }
        }

        await vm.fetchLoads()
        await Task.yield(); await Task.yield()

        let recorded = recorder.snapshot()
        guard case .error(let message) = recorded.last else {
            Issue.record("terminal must be .error on HTTP 500; got: \(String(describing: recorded.last))")
            return
        }
        #expect(message == Self.expectedErrorCopy,
                "error message must equal the locked loads.error.generic copy; got: \(message)")
    }

    // MARK: - Test 4 — loading → error on URLError.notConnectedToInternet

    @Test("Test 4: forced URLError → .error with the SAME loads.error.generic copy (decode-vs-HTTP-vs-network collapse)")
    func loadingToErrorOnNetworkFailure() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        MockURLProtocol.registerForcedFailure(
            for: "/loads/dispatch", method: .get,
            kind: .urlError(.notConnectedToInternet)
        )

        let recorder = StateRecorder()
        let logger = RecordingLogger()
        let vm = await makeViewModel(role: .dispatch, logger: logger)
        await MainActor.run {
            vm.onStateChange = { s in recorder.record(s) }
        }

        await vm.fetchLoads()
        await Task.yield(); await Task.yield()

        let recorded = recorder.snapshot()
        guard case .error(let message) = recorded.last else {
            Issue.record("terminal must be .error on URLError; got: \(String(describing: recorded.last))")
            return
        }
        #expect(message == Self.expectedErrorCopy,
                "URLError MUST collapse to the SAME loads.error.generic copy as HTTP errors")
    }

    // MARK: - Test 5 — refresh from .loaded does NOT pass through .loading

    @Test("Test 5: refresh from .loaded does NOT pass through .loading (UI-SPEC §State Machine — rows stay on screen)")
    func refreshFromLoadedDoesNotPassThroughLoading() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let data = try FixtureLoader.loadFixture("loads-list-broker")
        MockURLProtocol.registerFixture(
            for: LoadListEndpoint.self,
            path: "/loads/broker", method: .get,
            statusCode: 200, body: data
        )

        let recorder = StateRecorder()
        let logger = RecordingLogger()
        let vm = await makeViewModel(role: .broker, logger: logger)
        await MainActor.run {
            vm.onStateChange = { s in recorder.record(s) }
        }

        // First fetch → .loaded
        await vm.fetchLoads()
        await Task.yield(); await Task.yield()
        let firstTerminal = recorder.snapshot().last
        guard case .loaded = firstTerminal else {
            Issue.record("precondition: first fetch must terminate in .loaded; got: \(String(describing: firstTerminal))")
            return
        }
        recorder.reset()

        // Re-register the fixture so the second fetch finds a handler — the
        // first fetch's handler is still active (we only reset at top + defer).

        // Second fetch — refresh from .loaded
        await vm.fetchLoads()
        await Task.yield(); await Task.yield()

        let secondSequence = recorder.snapshot()
        let hasLoading = secondSequence.contains { if case .loading = $0 { return true } else { return false } }
        #expect(!hasLoading,
                "refresh from .loaded MUST NOT pass through .loading; got: \(secondSequence)")
        guard case .loaded = secondSequence.last else {
            Issue.record("refresh must still terminate in .loaded; got: \(String(describing: secondSequence.last))")
            return
        }
    }

    // MARK: - Test 6 — refresh from .error DOES pass through .loading

    @Test("Test 6: refresh from .error DOES pass through .loading (no rows to preserve)")
    func refreshFromErrorPassesThroughLoading() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        // Phase 1: forced 500 → .error
        MockURLProtocol.registerForcedFailure(
            for: "/loads/factoring", method: .get,
            kind: .http(statusCode: 500, body: Data())
        )

        let recorder = StateRecorder()
        let logger = RecordingLogger()
        let vm = await makeViewModel(role: .factoring, logger: logger)
        await MainActor.run {
            vm.onStateChange = { s in recorder.record(s) }
        }
        await vm.fetchLoads()
        await Task.yield(); await Task.yield()
        guard case .error = recorder.snapshot().last else {
            Issue.record("precondition: first fetch must terminate in .error")
            return
        }
        recorder.reset()

        // Phase 2: clear failure, register success fixture, retry.
        MockURLProtocol.resetFailureHandlers()
        let data = try FixtureLoader.loadFixture("loads-list-factoring")
        MockURLProtocol.registerFixture(
            for: LoadListEndpoint.self,
            path: "/loads/factoring", method: .get,
            statusCode: 200, body: data
        )

        await vm.fetchLoads()
        await Task.yield(); await Task.yield()

        let secondSequence = recorder.snapshot()
        let hasLoading = secondSequence.contains { if case .loading = $0 { return true } else { return false } }
        #expect(hasLoading,
                "refresh from .error MUST pass through .loading first; got: \(secondSequence)")
    }

    // MARK: - Test 7 — .loading is observable mid-flight under latency

    @Test("Test 7: .loading is observable while a request is in flight (LOAD-07 latency lock)")
    func loadingObservedWithLatency() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let data = try FixtureLoader.loadFixture("loads-list-broker")
        MockURLProtocol.registerFixtureWithLatency(
            for: LoadListEndpoint.self,
            path: "/loads/broker", method: .get,
            statusCode: 200, body: data,
            latency: 0.3
        )

        let logger = RecordingLogger()
        let vm = await makeViewModel(role: .broker, logger: logger)

        // Kick fetch off in the background; poll vm.state mid-flight.
        let fetchTask = Task { await vm.fetchLoads() }

        // Sleep ~50ms then read state — request still in flight (latency 0.3s).
        try await Task.sleep(nanoseconds: 50_000_000)
        let midState = await vm.state
        switch midState {
        case .loading:
            // expected — the latency keeps the request in flight long enough
            break
        default:
            Issue.record("vm.state was \(midState) mid-flight; expected .loading (LOAD-07)")
        }

        // Wait for the fetch to complete and assert the terminal state.
        await fetchTask.value
        let finalState = await vm.state
        guard case .loaded = finalState else {
            Issue.record("terminal must be .loaded after latency settles; got: \(finalState)")
            return
        }
    }

    // MARK: - Test 8 — zero-PII log invariant (T-08-08)

    @Test("Test 8: logger emissions on success AND on failure carry zero PII (T-08-08)")
    func fetchLoadsLogsZeroPIIOnSuccessAndFailure() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        // PII tokens that the broker fixture carries (party names + load refs)
        // — none of these may appear in any logged field value.
        let piiTokens = ["VL-", "REF-", "Acme", "FreightWise", "Pacific",
                         "PhantomLine", "party-", "Keystone", "Overland"]

        let logger = RecordingLogger()

        // --- Success leg ---
        do {
            let data = try FixtureLoader.loadFixture("loads-list-broker")
            MockURLProtocol.registerFixture(
                for: LoadListEndpoint.self,
                path: "/loads/broker", method: .get,
                statusCode: 200, body: data
            )
            let vm = await makeViewModel(role: .broker, logger: logger)
            await vm.fetchLoads()
        }

        // --- Failure leg ---
        MockURLProtocol.reset()
        MockURLProtocol.resetFailureHandlers()
        do {
            MockURLProtocol.registerForcedFailure(
                for: "/loads/broker", method: .get,
                kind: .http(statusCode: 500, body: Data())
            )
            let vm = await makeViewModel(role: .broker, logger: logger)
            await vm.fetchLoads()
        }

        // Scan every logged field value (after closing the success/failure legs
        // so all emissions have been captured under the lock).
        let entries = logger.entries
        #expect(entries.count >= 2,
                "VM must emit at least one event on success AND one on failure; got: \(entries.count)")
        for entry in entries {
            for (key, value) in entry.fields {
                let stringValue = String(describing: value)
                for token in piiTokens {
                    #expect(!stringValue.contains(token),
                            "T-08-08: PII token '\(token)' leaked into logger field \(key)=\(stringValue) for event=\(entry.event)")
                }
            }
            // Event name itself is the closed LogEvent constructor — fail loud
            // if a future edit slips a PII-bearing event name through.
            for token in piiTokens {
                #expect(!entry.event.contains(token),
                        "T-08-08: PII token '\(token)' leaked into LogEvent name '\(entry.event)'")
            }
        }
    }
}
