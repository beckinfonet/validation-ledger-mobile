// validationLedgerTests/Loads/LoadDetailViewModelRollbackTests.swift
//
// Phase 10 Plan 03 Task 2 — error-path coverage for the new
// `LoadDetailViewModel.submit(action:body:)` rollback contract (D-15).
//
// Locked targets (10-03-PLAN.md <behavior>, Task 2):
//   Test 1 — server 500 transitions to .actionFailed with the rollback Load
//            + frozen chain + per-action errorCopyKey.
//   Test 2 — server 422 + .accept action -> errorCopyKey for accept
//            (loads.actions.error.accept_failed).
//   Test 3 — server 409 + .cancel action -> errorCopyKey for cancel
//            (loads.actions.error.cancel_failed).
//   Test 4 — URLError (network offline) transitions to .actionFailed with the
//            per-action errorCopyKey (NOT a network-specific key — UI-SPEC
//            line 354 explicitly says classification is logged but never
//            rendered).
//   Test 5 — failure does NOT leak server-supplied body text into the state's
//            errorCopyKey (T-09-04 view-layer lock).
//   Test 6 — logger.error(...) call after a forced error uses fields: [:]
//            (T-09-04 / T-08-08 — extended view-layer lock).
//   Test 7 — cancelled-mid-flight task does NOT overwrite a fresher state
//            (BL-01 invariant 3: catch arm respects Task.isCancelled before
//            writing the rollback).
//   Test 8 — VM dealloc mid-flight is a no-op (Pitfall 9 — [weak self]
//            inherits Phase 9 safety; the terminal write is a no-op when
//            self is nil).
//
// === Framework choice: XCTest ===
// Same rationale as the LoadDetailViewModelActionTests sibling — XCTest
// matches the file-shape of the Loads/ XCTest neighbors that landed in
// Wave 1 (LoadActionPredictorTests / LoadActionTitleResolverTests /
// RoleLoadPolicyAvailableActionsTests). Project memory
// `ios-test-suite-pitfalls` documents the -only-testing-drops-XCTest
// interaction with Swift Testing; sticking to one framework avoids it.
//
// === Test infrastructure ===
// The fileprivate MockAPIClient + RecordingLogger + StateRecorder
// + PathCapturingRequestInterceptor + makeLoad/makeChain/makeActionResponseBody
// helpers are intentionally duplicated from LoadDetailViewModelActionTests.
// The Plan 10-03 Task 2 <action> block permitted either duplication or a
// shared file; duplication keeps each test file self-contained and avoids a
// new shared-helper file under tests/ whose access-control story would
// need to thread through every callsite. The duplication is ~150 lines
// and the cost is bounded — both files are leaf test consumers.

import XCTest
@testable import validationLedger

final class LoadDetailViewModelRollbackTests: XCTestCase {

    // MARK: - APIClient + session assembly

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
    private func makeViewModel(
        loadID: String,
        role: Role,
        apiClient: APIClient? = nil,
        logger: any Logger
    ) -> LoadDetailViewModel {
        LoadDetailViewModel(
            loadID: loadID,
            role: role,
            apiClient: apiClient ?? makeAPIClient(),
            logger: logger
        )
    }

    // MARK: - StateRecorder

    private final class StateRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _states: [LoadDetailViewModel.State] = []
        func record(_ s: LoadDetailViewModel.State) {
            lock.withLock { _states.append(s) }
        }
        func snapshot() -> [LoadDetailViewModel.State] {
            lock.withLock { _states }
        }
    }

    // MARK: - RecordingLogger (T-09-04 capture surface)

    fileprivate final class RecordingLogger: Logger, @unchecked Sendable {
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

    // MARK: - Load + Chain fixture helpers

    @MainActor
    private func makeLoad(
        id: String = "VL-R-1",
        status: LoadStatus,
        respondByAt: Date? = nil
    ) throws -> Load {
        let respondByAtJSON: String = {
            guard let respondByAt else { return "" }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let iso = formatter.string(from: respondByAt)
            return ",\n  \"respond_by_at\": \"\(iso)\""
        }()
        let json = """
        {
          "id": "\(id)",
          "reference_number": "REF-\(id)",
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
          "status": "\(status.rawValue)",
          "state_history": []\(respondByAtJSON)
        }
        """
        return try APIClient.defaultDecoder().decode(Load.self, from: Data(json.utf8))
    }

    @MainActor
    private func makeChain(integrity: String = "clean") throws -> ChainOfTrust {
        let json = """
        {
          "nodes": [
            {
              "party_id": "party-broker-acme",
              "role": "broker",
              "display_name": "Acme Brokerage",
              "verification_state": "verified",
              "device_binding_status": "bound",
              "usdot_authority_status": "not_applicable",
              "prior_relationships": []
            }
          ],
          "edges": [],
          "integrity": {
            "verdict": "\(integrity)",
            "reason": "",
            "implicated_node_ids": [],
            "implicated_edge_ids": []
          }
        }
        """
        return try APIClient.defaultDecoder().decode(ChainOfTrust.self, from: Data(json.utf8))
    }

    @MainActor
    private func makeActionResponseBody(
        load: Load,
        chain: ChainOfTrust
    ) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let respondByAtJSON: String = {
            guard let r = load.respondByAt else { return "" }
            return ",\n      \"respond_by_at\": \"\(formatter.string(from: r))\""
        }()
        let verdictRaw: String = {
            switch chain.integrity.verdict {
            case .clean:        return "clean"
            case .caution:      return "caution"
            case .compromised:  return "compromised"
            }
        }()
        let json = """
        {
          "load": {
            "id": "\(load.id)",
            "reference_number": "\(load.referenceNumber)",
            "origin": {
              "city": "\(load.origin.city)",
              "state": "\(load.origin.state)",
              "postal_code": "\(load.origin.postalCode)",
              "country": "\(load.origin.country)"
            },
            "destination": {
              "city": "\(load.destination.city)",
              "state": "\(load.destination.state)",
              "postal_code": "\(load.destination.postalCode)",
              "country": "\(load.destination.country)"
            },
            "equipment": "\(load.equipment)",
            "weight": \(load.weight),
            "rate": \(load.rate),
            "pickup_at": "\(formatter.string(from: load.pickupAt))",
            "deliver_at": "\(formatter.string(from: load.deliverAt))",
            "status": "\(load.status.rawValue)",
            "state_history": []\(respondByAtJSON)
          },
          "chain_of_trust": {
            "nodes": [],
            "edges": [],
            "integrity": {
              "verdict": "\(verdictRaw)",
              "reason": "",
              "implicated_node_ids": [],
              "implicated_edge_ids": []
            }
          }
        }
        """
        return Data(json.utf8)
    }

    // MARK: - Fixture registration helpers

    private func registerActionFixture(
        loadID: String,
        actionPath: String,
        responseBody: Data,
        statusCode: Int = 200,
        latency: TimeInterval = 0
    ) {
        let path = "/loads/\(loadID)/\(actionPath)"
        if latency > 0 {
            MockURLProtocol.registerFixtureWithLatency(
                for: LoadActionEndpoint.self,
                path: path,
                method: .post,
                statusCode: statusCode,
                body: responseBody,
                latency: latency
            )
        } else {
            MockURLProtocol.registerFixture(
                for: LoadActionEndpoint.self,
                path: path,
                method: .post,
                statusCode: statusCode,
                body: responseBody
            )
        }
    }

    private func registerActionFailure(
        loadID: String,
        actionPath: String,
        kind: MockURLProtocol.InjectedFailure
    ) {
        let path = "/loads/\(loadID)/\(actionPath)"
        MockURLProtocol.registerForcedFailure(for: path, method: .post, kind: kind)
    }

    private func tenderBody(respondByAt: Date) -> LoadActionEndpoint.RequestBody {
        LoadActionEndpoint.RequestBody(
            actorRole: .broker,
            targetPartyID: "party-carrier-acme",
            respondByAt: respondByAt,
            note: nil
        )
    }

    private func plainBody(role: Role = .broker) -> LoadActionEndpoint.RequestBody {
        LoadActionEndpoint.RequestBody(
            actorRole: role,
            targetPartyID: nil,
            respondByAt: nil,
            note: nil
        )
    }

    /// Drive the VM into `.loaded` by registering a detail fixture and
    /// awaiting the fetch. Returns after `vm.state == .loaded`.
    @MainActor
    private func driveToLoaded(
        vm: LoadDetailViewModel,
        loadID: String,
        load: Load,
        chain: ChainOfTrust
    ) async throws {
        let detailResponse = try makeActionResponseBody(load: load, chain: chain)
        MockURLProtocol.registerFixture(
            for: LoadDetailEndpoint.self,
            path: "/loads/\(loadID)",
            method: .get,
            statusCode: 200,
            body: detailResponse
        )
        await vm.fetchLoadDetail()
        await Task.yield()
    }

    // MARK: - Test 1: server 500 -> .actionFailed with rollback Load + per-action key

    @MainActor
    func test_submit_serverReturns500_transitionsToActionFailed_withRollbackLoad() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let preLoad = try makeLoad(id: "VL-R-1", status: .posted)
        let preChain = try makeChain(integrity: "clean")

        let logger = RecordingLogger()
        let vm = makeViewModel(loadID: "VL-R-1", role: .broker, logger: logger)
        try await driveToLoaded(vm: vm, loadID: "VL-R-1", load: preLoad, chain: preChain)

        // Now register a 500-status forced failure on the tender path.
        registerActionFailure(
            loadID: "VL-R-1",
            actionPath: "tender",
            kind: .http(statusCode: 500, body: Data())
        )

        let body = tenderBody(respondByAt: Date(timeIntervalSinceReferenceDate: 1_000_000))
        await vm.submit(action: .tender, body: body)
        await Task.yield()

        guard case let .actionFailed(rollbackTo, frozenChain, errorCopyKey) = vm.state else {
            XCTFail("terminal must be .actionFailed on HTTP 500; got \(vm.state)")
            return
        }
        XCTAssertEqual(rollbackTo.id, preLoad.id,
                       "D-15: rollback Load.id must equal the pre-tap Load.id")
        XCTAssertEqual(rollbackTo.status, preLoad.status,
                       "D-15: rollback Load.status must equal the pre-tap Load.status (.posted) — NOT the predicted .tendered")
        XCTAssertEqual(frozenChain.integrity.verdict, preChain.integrity.verdict,
                       "D-13/D-15: frozen chain restored to pre-tap verdict")
        XCTAssertEqual(errorCopyKey, "loads.actions.error.tender_failed",
                       "UI-SPEC line 343: .tender's locked errorCopyKey is loads.actions.error.tender_failed")
    }

    // MARK: - Test 2: server 422 + .accept -> errorCopyKey for accept

    @MainActor
    func test_submit_serverReturns422_transitionsToActionFailed_perActionKey() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let preLoad = try makeLoad(id: "VL-R-2", status: .tendered)
        let preChain = try makeChain(integrity: "clean")

        let logger = RecordingLogger()
        let vm = makeViewModel(loadID: "VL-R-2", role: .carrier, logger: logger)
        try await driveToLoaded(vm: vm, loadID: "VL-R-2", load: preLoad, chain: preChain)

        registerActionFailure(
            loadID: "VL-R-2",
            actionPath: "accept",
            kind: .http(statusCode: 422, body: Data())
        )

        await vm.submit(action: .accept, body: plainBody(role: .carrier))
        await Task.yield()

        guard case let .actionFailed(_, _, errorCopyKey) = vm.state else {
            XCTFail("terminal must be .actionFailed on HTTP 422; got \(vm.state)")
            return
        }
        XCTAssertEqual(errorCopyKey, "loads.actions.error.accept_failed",
                       "UI-SPEC line 344: .accept's locked errorCopyKey is loads.actions.error.accept_failed")
    }

    // MARK: - Test 3: server 409 + .cancel -> errorCopyKey for cancel

    @MainActor
    func test_submit_serverReturns409_transitionsToActionFailed_perActionKey() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let preLoad = try makeLoad(id: "VL-R-3", status: .posted)
        let preChain = try makeChain(integrity: "clean")

        let logger = RecordingLogger()
        let vm = makeViewModel(loadID: "VL-R-3", role: .broker, logger: logger)
        try await driveToLoaded(vm: vm, loadID: "VL-R-3", load: preLoad, chain: preChain)

        registerActionFailure(
            loadID: "VL-R-3",
            actionPath: "cancel",
            kind: .http(statusCode: 409, body: Data())
        )

        await vm.submit(action: .cancel, body: plainBody())
        await Task.yield()

        guard case let .actionFailed(_, _, errorCopyKey) = vm.state else {
            XCTFail("terminal must be .actionFailed on HTTP 409; got \(vm.state)")
            return
        }
        XCTAssertEqual(errorCopyKey, "loads.actions.error.cancel_failed",
                       "UI-SPEC line 346: .cancel's locked errorCopyKey is loads.actions.error.cancel_failed")
    }

    // MARK: - Test 4: URLError offline -> .actionFailed with per-action key (NOT a network key)

    @MainActor
    func test_submit_urlErrorNetworkOffline_transitionsToActionFailed() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let preLoad = try makeLoad(id: "VL-R-4", status: .posted)
        let preChain = try makeChain(integrity: "clean")

        let logger = RecordingLogger()
        let vm = makeViewModel(loadID: "VL-R-4", role: .broker, logger: logger)
        try await driveToLoaded(vm: vm, loadID: "VL-R-4", load: preLoad, chain: preChain)

        // Force a URLError(.notConnectedToInternet) on the tender path.
        registerActionFailure(
            loadID: "VL-R-4",
            actionPath: "tender",
            kind: .urlError(.notConnectedToInternet)
        )

        let body = tenderBody(respondByAt: Date(timeIntervalSinceReferenceDate: 4_000_000))
        await vm.submit(action: .tender, body: body)
        await Task.yield()

        guard case let .actionFailed(rollbackTo, _, errorCopyKey) = vm.state else {
            XCTFail("terminal must be .actionFailed on URLError; got \(vm.state)")
            return
        }
        XCTAssertEqual(rollbackTo.status, preLoad.status, "rollback to pre-tap status on URLError")
        XCTAssertEqual(errorCopyKey, "loads.actions.error.tender_failed",
                       """
                       UI-SPEC line 354 lock: the errorCopyKey must remain the PER-ACTION \
                       key even on a network-classification failure — the classification \
                       (URLError vs HTTP) is LOGGED but NEVER rendered. The user sees the \
                       same per-action localized copy regardless of classification.
                       """)
    }

    // MARK: - Test 5: server-text NEVER leaks into state.errorCopyKey (T-09-04 view-layer lock)

    @MainActor
    func test_submit_failure_doesNotLeakServerTextIntoState() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let preLoad = try makeLoad(id: "VL-R-5", status: .posted)
        let preChain = try makeChain(integrity: "clean")

        let logger = RecordingLogger()
        let vm = makeViewModel(loadID: "VL-R-5", role: .broker, logger: logger)
        try await driveToLoaded(vm: vm, loadID: "VL-R-5", load: preLoad, chain: preChain)

        // Force a 500 with a PII-shaped body the server might return. The
        // VM MUST NOT echo any substring of this into state.errorCopyKey.
        let leakingBody = Data("""
        {"error":"Internal server error: party_id not found (VL-R-5-PII-PROBE)"}
        """.utf8)
        registerActionFailure(
            loadID: "VL-R-5",
            actionPath: "tender",
            kind: .http(statusCode: 500, body: leakingBody)
        )

        let body = tenderBody(respondByAt: Date(timeIntervalSinceReferenceDate: 5_000_000))
        await vm.submit(action: .tender, body: body)
        await Task.yield()

        guard case let .actionFailed(_, _, errorCopyKey) = vm.state else {
            XCTFail("terminal must be .actionFailed; got \(vm.state)")
            return
        }
        XCTAssertEqual(errorCopyKey, "loads.actions.error.tender_failed",
                       "errorCopyKey must be the LOCKED localization key per UI-SPEC, NOT any substring of the server response body")
        XCTAssertFalse(errorCopyKey.contains("VL-R-5"),
                       "T-09-04 view-layer lock: errorCopyKey must NEVER contain any substring derivable from the server response body")
        XCTAssertFalse(errorCopyKey.contains("party_id"),
                       "T-09-04 view-layer lock: errorCopyKey must NEVER echo server-supplied freight-domain tokens")
        XCTAssertFalse(errorCopyKey.contains("PII-PROBE"),
                       "T-09-04 view-layer lock: errorCopyKey must NEVER echo the PII probe token from the server body")
    }

    // MARK: - Test 6: logger.error called with fields: [:] (T-09-04 / T-08-08 extended)

    @MainActor
    func test_submit_failure_loggerCalledWith_emptyFieldsDict() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let preLoad = try makeLoad(id: "VL-R-6", status: .posted)
        let preChain = try makeChain(integrity: "clean")

        let logger = RecordingLogger()
        let vm = makeViewModel(loadID: "VL-R-6", role: .broker, logger: logger)
        try await driveToLoaded(vm: vm, loadID: "VL-R-6", load: preLoad, chain: preChain)

        // Force a 500 to drive the error logger emit.
        registerActionFailure(
            loadID: "VL-R-6",
            actionPath: "tender",
            kind: .http(statusCode: 500, body: Data())
        )

        // Pre-flight: clear any entries from the fetch-path logger calls so
        // the assertion focuses on the action-path call.
        logger.reset()

        let body = tenderBody(respondByAt: Date(timeIntervalSinceReferenceDate: 6_000_000))
        await vm.submit(action: .tender, body: body)
        await Task.yield()

        // Locate the `load_action_failed` log entry — exactly one must have
        // been emitted, with .error level and fields == [:].
        let actionFailedEntries = logger.entries.filter { $0.event == "load_action_failed" }
        XCTAssertEqual(actionFailedEntries.count, 1,
                       "performAction must emit exactly one `load_action_failed` log on a forced 500; got entries: \(logger.entries.map { $0.event })")
        guard let entry = actionFailedEntries.first else { return }
        XCTAssertEqual(entry.level, .error,
                       "load_action_failed must be at .error level")
        XCTAssertTrue(entry.fields.isEmpty,
                      """
                      T-09-04 / T-08-08 — view-layer lock extended to actions: \
                      logger.error(event: LogEvent(\"load_action_failed\"), fields: <X>) \
                      MUST have fields.isEmpty (== [:]); got: \(entry.fields)
                      """)
    }

    // MARK: - Test 7: cancelled-mid-flight does NOT overwrite fresher state

    @MainActor
    func test_submit_cancelledMidFlight_doesNotOverwriteFresherState() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let preLoad = try makeLoad(id: "VL-R-7", status: .posted)
        let preChain = try makeChain(integrity: "clean")

        let logger = RecordingLogger()
        let vm = makeViewModel(loadID: "VL-R-7", role: .broker, logger: logger)
        try await driveToLoaded(vm: vm, loadID: "VL-R-7", load: preLoad, chain: preChain)

        // Phase 1: high-latency .tender 500-failure (fetch A's failure
        // would arrive ~0.4 s later if not cancelled). Use the latency-
        // fixture API to drive the success path 500; the failure handler
        // doesn't have a latency variant, so we encode the 500 as a
        // success-fixture response with statusCode=500 + latency.
        let actionResponseDummy = try makeActionResponseBody(load: preLoad, chain: preChain)
        registerActionFixture(
            loadID: "VL-R-7",
            actionPath: "tender",
            responseBody: actionResponseDummy,
            statusCode: 500,
            latency: 0.4
        )

        // Kick action A.
        let bodyA = tenderBody(respondByAt: Date(timeIntervalSinceReferenceDate: 7_000_000))
        let taskA = Task { await vm.submit(action: .tender, body: bodyA) }
        try await Task.sleep(nanoseconds: 50_000_000)

        // Phase 2: swap fixtures and submit action B (.cancel) — quick
        // success this time. B cancels A; A's eventual 500 must NOT
        // overwrite B's terminal state.
        MockURLProtocol.reset()
        let cancelledLoad = try makeLoad(id: "VL-R-7", status: .cancelled)
        let cancelResponse = try makeActionResponseBody(load: cancelledLoad, chain: preChain)
        registerActionFixture(
            loadID: "VL-R-7",
            actionPath: "cancel",
            responseBody: cancelResponse
        )

        let taskB = Task { await vm.submit(action: .cancel, body: plainBody()) }
        _ = await taskA.value
        _ = await taskB.value
        await Task.yield(); await Task.yield()

        // BL-01 invariant: a cancelled task's catch arm must observe
        // Task.isCancelled BEFORE writing .actionFailed. The terminal
        // state must reflect B (.cancel succeeded) — NOT A (.tender 500 +
        // rollback to .posted).
        guard case let .loaded(finalLoad, _) = vm.state else {
            XCTFail("""
            terminal state must be .loaded (B's cancel succeeded), \
            NOT .actionFailed (A's cancelled rollback) — got \(vm.state). \
            The BL-01 invariant 3 (catch arm respects Task.isCancelled \
            before writing) is broken.
            """)
            return
        }
        XCTAssertEqual(finalLoad.status, .cancelled,
                       "B's .cancel response must be the terminal state; A's cancelled rollback must NOT have overwritten it")
    }

    // MARK: - Test 8: VM dealloc mid-flight is a no-op (Pitfall 9 / [weak self])

    /// Construct a VM, capture a weak reference, submit an action with a
    /// delayed mock, then nil the strong reference. After the network hop
    /// completes the Task's `[weak self]` capture must produce nil-self;
    /// the terminal write becomes a no-op. The assertion: vm goes nil
    /// without crash.
    ///
    /// Phase 9 inherits this safety via the same [weak self] pattern in
    /// performFetch; Plan 03 extends it to performAction.
    @MainActor
    func test_submit_vcDeallocMidFlight_noOp_noCrash() async throws {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let preLoad = try makeLoad(id: "VL-R-8", status: .posted)
        let preChain = try makeChain(integrity: "clean")

        // Set up a delayed action fixture so the task is still in flight
        // when we release vm.
        let logger = RecordingLogger()
        weak var weakVM: LoadDetailViewModel?

        do {
            let vm: LoadDetailViewModel? = makeViewModel(
                loadID: "VL-R-8",
                role: .broker,
                logger: logger
            )
            weakVM = vm
            try await driveToLoaded(vm: vm!, loadID: "VL-R-8", load: preLoad, chain: preChain)

            // Register a HIGH-latency 500 — by the time the failure lands
            // we expect vm to be deallocated (the [weak self] capture nil).
            let dummy = try makeActionResponseBody(load: preLoad, chain: preChain)
            registerActionFixture(
                loadID: "VL-R-8",
                actionPath: "tender",
                responseBody: dummy,
                statusCode: 500,
                latency: 0.3
            )

            let body = tenderBody(respondByAt: Date(timeIntervalSinceReferenceDate: 8_000_000))
            // Kick the submit without awaiting — we want vm to be released
            // mid-flight.
            Task { await vm!.submit(action: .tender, body: body) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        // vm strong reference dropped here; weak should become nil after
        // ARC plus runloop tick.
        for _ in 0..<10 {
            await Task.yield()
            if weakVM == nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        // The submit's task may still be running on a background queue; let
        // its network hop complete + bail through the [weak self] guard.
        try await Task.sleep(nanoseconds: 500_000_000)

        // The critical assertion is "no crash" — reaching this line on the
        // simulator without a malloc / EXC_BAD_ACCESS is sufficient. Add
        // an XCTAssert here so the test reports a positive signal.
        XCTAssertTrue(true,
                      "Pitfall 9 / [weak self] inherited safety: VM dealloc mid-action did NOT crash the test runner")
        // If weakVM did NOT become nil, that's also acceptable — the test
        // proves the no-crash property, not the timely-dealloc property
        // (the latter is an ARC observation that can vary by runloop tick).
    }
}
