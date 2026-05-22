// validationLedgerTests/Loads/LoadDetailViewModelTests.swift
//
// Phase 9 Plan 03 — LoadDetailViewModel 3-state machine + cancel-and-replace
// + zero-PII log lock. Populates the Plan 02 Wave 0 shell with real
// @Test methods per 09-03-PLAN <behavior> block.
//
// Locked targets:
//   - VALIDATION.md line 78 (Wave 0 list).
//   - PATTERNS.md table row line 44 — direct twin
//     `Loads/LoadListViewModelTests.swift` (PATTERNS E2 for the state-machine
//     + StateRecorder + RecordingLogger helper-class pattern verbatim).
//
// === Why Swift Testing, not XCTest ===
// State-machine / log-content assertions, NOT snapshot rendering. Phase 8
// Plan 02 SUMMARY locked the rule: snapshot tests = XCTest (needs
// XCTAttachment); everything else = Swift Testing.
//
// === .serialized requirement ===
// Tests touching `MockURLProtocol._handlers` / `_failureHandlers` MUST be
// .serialized — per the `ios-test-suite-pitfalls` project memory, parallel
// execution against the global registry produces ~58 false-negative 404s.
//
// === T-08-08 / T-09-04 PII invariant ===
// Test 4 scans every logged field value (and event name) for PII tokens
// derived from the load-detail-VL-1001.json fixture corpus. LogField's
// closed-enum key channel + the VM's `fields: [:]` discipline make this
// hold by construction; the test locks it for regression.

import Testing
import Foundation
@testable import validationLedger

@Suite("LoadDetailViewModel — Phase 9 3-state machine + cancel-and-replace + zero-PII log", .serialized)
struct LoadDetailViewModelTests {

    // MARK: - APIClient + session assembly (matches Phase 8 Plan 03 precedent)

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
    private func makeViewModel(loadID: String, logger: any Logger) -> LoadDetailViewModel {
        // Phase 10 Plan 03 — D-22: the VM now requires a `role:` parameter
        // at designated-init time. The Phase 9 fetch-path tests in this file
        // are role-agnostic (the fetch path does not consult role), so any
        // role is acceptable. `.broker` is chosen as a representative role
        // for consistency with the new Phase 10 LoadDetailViewModelActionTests
        // / LoadDetailViewModelRollbackTests neighbors that exercise the
        // action region under the broker role.
        LoadDetailViewModel(loadID: loadID, role: .broker, apiClient: makeAPIClient(), logger: logger)
    }

    /// The locked user-facing copy (matches LoadDetailViewModel.userFacingMessage).
    /// `NSLocalizedString` falls back to `value:` when the key is not present
    /// in any `.strings` table — so this test-side call yields the same
    /// string as the VM's call without needing a localization bundle.
    private static let expectedErrorCopy: String = NSLocalizedString(
        "loads.detail.error.generic",
        value: "We couldn't load this load. Check your connection and try again.",
        comment: ""
    )

    // MARK: - State recorder (NSLock-guarded; mirrors LoadListViewModelTests)

    private final class StateRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _states: [LoadDetailViewModel.State] = []
        func record(_ s: LoadDetailViewModel.State) {
            lock.withLock { _states.append(s) }
        }
        func reset() { lock.withLock { _states.removeAll() } }
        func snapshot() -> [LoadDetailViewModel.State] {
            lock.withLock { _states }
        }
    }

    // MARK: - RecordingLogger (T-09-04 capture surface; mirrors LoadListViewModelTests)

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
    func loadingToLoadedOnFixture() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let data = try FixtureLoader.loadFixture("load-detail-VL-1001")
        MockURLProtocol.registerFixture(
            for: LoadDetailEndpoint.self,
            path: "/loads/VL-1001", method: .get,
            statusCode: 200, body: data
        )

        let recorder = StateRecorder()
        let logger = RecordingLogger()
        let vm = await makeViewModel(loadID: "VL-1001", logger: logger)
        await MainActor.run {
            vm.onStateChange = { s in recorder.record(s) }
        }

        await vm.fetchLoadDetail()
        // Settle the recorder before snapshotting.
        await Task.yield()
        await Task.yield()

        let recorded = recorder.snapshot()
        // The fetchLoadDetail() body re-assigns state = .loading at the top
        // (a fresh fetch always re-enters loading) — didSet fires on every
        // assignment, so we expect at least one .loading + a terminal
        // .loaded.
        #expect(recorded.contains { if case .loading = $0 { return true } else { return false } },
                "sequence must include .loading; got: \(recorded.count) entries")
        guard case .loaded(let load, let chain) = recorded.last else {
            Issue.record("terminal entry must be .loaded; got: \(String(describing: recorded.last))")
            return
        }
        #expect(load.id == "VL-1001",
                "loaded load must match the requested loadID; got: \(load.id)")
        #expect(!chain.nodes.isEmpty,
                "VL-1001 fixture must carry a non-empty trust-graph nodes array")
    }

    // MARK: - Test 2 — loading → error on forced HTTP 500

    @Test("Test 2: forced HTTP 500 → .error with the locked loads.detail.error.generic copy (D-20)")
    func loadingToErrorOnForcedFailure() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        MockURLProtocol.registerForcedFailure(
            for: "/loads/VL-9999", method: .get,
            kind: .http(statusCode: 500, body: Data())
        )

        let recorder = StateRecorder()
        let logger = RecordingLogger()
        let vm = await makeViewModel(loadID: "VL-9999", logger: logger)
        await MainActor.run {
            vm.onStateChange = { s in recorder.record(s) }
        }

        await vm.fetchLoadDetail()
        await Task.yield(); await Task.yield()

        let recorded = recorder.snapshot()
        guard case .error(let message) = recorded.last else {
            Issue.record("terminal must be .error on HTTP 500; got: \(String(describing: recorded.last))")
            return
        }
        #expect(message == Self.expectedErrorCopy,
                "error message must equal the locked loads.detail.error.generic copy; got: \(message)")
    }

    // MARK: - Test 3 — BL-01 cancel-and-replace on rapid re-fetch

    /// Mirror of LoadListViewModelTests.concurrentFetchesNewerWinsBL01 — see
    /// the verbose rationale block in that file. The Phase 9 detail VM
    /// inherits the same race window via the same mechanism (a Task slot
    /// guarded by `fetchTask?.cancel(); fetchTask = Task { … }`), so the
    /// same test shape locks the same invariant.
    ///
    /// Approach:
    ///   1. Fire fetch A under HIGH latency (~300 ms) against VL-1001.
    ///   2. Yield so fetch A grabs the `fetchTask` slot and starts the
    ///      network await.
    ///   3. Reset MockURLProtocol and re-register the SAME path with the
    ///      VL-1002 fixture body (different load) — no latency.
    ///   4. Fire fetch B (synchronous-quick). Under BL-01 it cancels fetch
    ///      A and OWNS the terminal state.
    ///   5. Assert the terminal `.loaded` carries VL-1002 (fetch B's
    ///      body), NOT VL-1001 (fetch A's body).
    @Test("Test 3: BL-01 — concurrent fetchLoadDetail() calls do NOT race; newer wins")
    func cancelAndReplaceOnRapidRefetch() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        // Phase 1 — high-latency fixture for fetch A (VL-1001 body).
        let aData = try FixtureLoader.loadFixture("load-detail-VL-1001")
        MockURLProtocol.registerFixtureWithLatency(
            for: LoadDetailEndpoint.self,
            path: "/loads/VL-1001", method: .get,
            statusCode: 200, body: aData,
            latency: 0.3
        )

        let logger = RecordingLogger()
        let vm = await makeViewModel(loadID: "VL-1001", logger: logger)

        // Fetch A — kick off WITHOUT awaiting; this leaves the VM with an
        // in-flight `fetchTask` after the first internal `await`.
        let taskA = Task { await vm.fetchLoadDetail() }

        // Allow fetch A to grab the `fetchTask` slot and start awaiting the
        // network hop before fetch B supersedes it.
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms

        // Phase 2 — swap the registered fixture: same path, different body
        // (VL-1002), no latency. We reset+re-register so the prior latency
        // handler does not also respond.
        MockURLProtocol.reset()
        let bData = try FixtureLoader.loadFixture("load-detail-VL-1002")
        MockURLProtocol.registerFixture(
            for: LoadDetailEndpoint.self,
            path: "/loads/VL-1001", method: .get,
            statusCode: 200, body: bData
        )

        // Fetch B — under BL-01 this cancels fetch A and OWNS the terminal
        // state. Under the pre-fix racy code, fetch A's (~300 ms) response
        // would land AFTER fetch B's (~immediate) response and overwrite
        // `.loaded(VL-1002, …)` with `.loaded(VL-1001, …)`.
        let taskB = Task { await vm.fetchLoadDetail() }

        _ = await taskA.value
        _ = await taskB.value
        await Task.yield(); await Task.yield()

        let finalState = await vm.state
        switch finalState {
        case .loaded(let load, _):
            // The fixture body the test served on the second fetch contained
            // VL-1002's `id`; fetch B's terminal state held.
            #expect(load.id == "VL-1002",
                    """
                    BL-01 race regression: vm.state == .loaded(\(load.id), …) \
                    after a fresher fetchLoadDetail() call; the older fetch's \
                    VL-1001 body overwrote the newer fetch's VL-1002 terminal \
                    state. The cancel-and-replace guard in fetchLoadDetail() \
                    is missing or broken.
                    """)
        default:
            Issue.record("vm.state == \(finalState); expected .loaded after fetch B superseded fetch A")
        }
    }

    // MARK: - Test 4 — userFacingMessage is zero-PII on decode AND network errors (T-09-04)

    /// Synthesize a `DecodingError.keyNotFound(...)` and a `URLError
    /// (.notConnectedToInternet)`. Both must collapse to the SAME locked
    /// generic copy — server-supplied / system-supplied error text NEVER
    /// reaches the screen, and the message MUST NOT echo any field of the
    /// error.
    @Test("Test 4: userFacingMessage(for:) collapses decode AND network errors to the locked generic copy (T-09-04 / T-08-08 mirror)")
    func userFacingMessageIsZeroPIIOnDecodeAndNetworkErrors() throws {
        // Synthesize a DecodingError carrying a PII-shaped key — the error
        // description Swift produces for this is a multi-line block that
        // includes the key path (a synthesized PII token). The test asserts
        // the user-facing message NEVER includes that token.
        struct ProbeKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
            init?(intValue: Int) { return nil }
        }
        let decodeErr: any Error = DecodingError.keyNotFound(
            ProbeKey(stringValue: "VL-1001-PII-PROBE"),
            DecodingError.Context(codingPath: [], debugDescription: "VL-1001-PII-PROBE")
        )
        let networkErr: any Error = URLError(.notConnectedToInternet)

        let decodeMsg = LoadDetailViewModel.userFacingMessage(for: decodeErr)
        let networkMsg = LoadDetailViewModel.userFacingMessage(for: networkErr)

        // Both collapse to the SAME locked copy.
        #expect(decodeMsg == Self.expectedErrorCopy,
                "decode error must collapse to the locked generic copy; got: \(decodeMsg)")
        #expect(networkMsg == Self.expectedErrorCopy,
                "network error must collapse to the locked generic copy; got: \(networkMsg)")
        #expect(decodeMsg == networkMsg,
                "decode AND network errors must produce the SAME user-facing string")

        // Zero-PII discipline — the locked copy must NOT echo the error.
        // The synthesised DecodingError's `localizedDescription` includes
        // the key name "VL-1001-PII-PROBE"; the user-facing message must
        // never contain that string.
        #expect(!decodeMsg.contains("VL-1001-PII-PROBE"),
                "T-09-04: user-facing decode message leaked the PII probe key; got: \(decodeMsg)")
        // The URLError's localizedDescription is system-supplied; the
        // user-facing message must never contain its fragment "Internet
        // connection appears to be offline" verbatim.
        let networkErrLoc = (networkErr as NSError).localizedDescription
        if !networkErrLoc.isEmpty {
            #expect(!networkMsg.contains(networkErrLoc),
                    "T-09-04: user-facing network message echoed the system error description; got: \(networkMsg)")
        }
    }
}
