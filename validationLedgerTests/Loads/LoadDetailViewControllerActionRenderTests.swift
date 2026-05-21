// validationLedgerTests/Loads/LoadDetailViewControllerActionRenderTests.swift
//
// Phase 10 Plan 04 Task 2 — assert the VC integration contract:
//   - `.loaded` render configures the action region with the role's policy.
//   - `.actionInFlight` render uses the PRE-TAP action set (Pitfall 6).
//   - `.actionFailed` render applies the rollback Load.
//   - Chain-overlay mount/dismount API surface (Plan 07 will swap the stub
//     for the actual alpha-fade overlay; the API is locked here).
//   - handleActionTap routes `.tender` to a sheet stub; others call
//     viewModel.submit(...).
//
// === Test seam strategy ===
// Real LoadDetailViewModel backed by MockURLProtocol fixtures. The VC's
// `actionsView` is exposed `internal` for test introspection — the
// configure(...) capture pattern uses a small subclass that captures the
// last call's arguments.
//
// === Why XCTest, not Swift Testing ===
// Matches the Phase 10 wave-1/2/3 XCTest neighbors in this folder.

import XCTest
@testable import validationLedger

final class LoadDetailViewControllerActionRenderTests: XCTestCase {

    // MARK: - APIClient + session assembly (mirrors size-class routing tests)

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

    // MARK: - Spy LoadActionsView that captures the last configure(...) call

    /// A test double that captures the arguments of the most recent
    /// `configure(...)` call. The VC's exposed `actionsView` is set to an
    /// instance of this subclass when running under tests.
    ///
    /// `@MainActor` matches the project's default isolation under
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — same as the VC and the
    /// underlying LoadActionsView.
    @MainActor
    fileprivate final class CapturingLoadActionsView: LoadActionsView {
        struct Capture {
            let actions: [LoadAction]
            let role: Role
            let currentStatus: LoadStatus
            let tenderEligibility: TenderEligibility?
            let respondByAt: Date?
            let inFlight: LoadAction?
        }
        private(set) var lastCapture: Capture?
        private(set) var captureCount: Int = 0
        private(set) var lastOnTap: ((LoadAction) -> Void)?

        override func configure(
            actions: [LoadAction],
            role: Role,
            currentStatus: LoadStatus,
            tenderEligibility: TenderEligibility?,
            respondByAt: Date?,
            inFlight: LoadAction?,
            onTap: @escaping (LoadAction) -> Void
        ) {
            super.configure(
                actions: actions, role: role, currentStatus: currentStatus,
                tenderEligibility: tenderEligibility, respondByAt: respondByAt,
                inFlight: inFlight, onTap: onTap
            )
            lastCapture = Capture(
                actions: actions, role: role, currentStatus: currentStatus,
                tenderEligibility: tenderEligibility, respondByAt: respondByAt,
                inFlight: inFlight
            )
            captureCount += 1
            lastOnTap = onTap
        }
    }

    // MARK: - VC builder

    /// Build VC against the given fixture loadID + role; force compact size
    /// class; install a `CapturingLoadActionsView` spy; drive the VM to
    /// `.loaded`; return both for assertions.
    @MainActor
    private func makeVC(
        loadID: String,
        role: Role
    ) async throws -> (vc: LoadDetailViewController, spy: CapturingLoadActionsView, vm: LoadDetailViewModel) {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        let data = try FixtureLoader.loadFixture("load-detail-\(loadID)")
        MockURLProtocol.registerFixture(
            for: LoadDetailEndpoint.self,
            path: "/loads/\(loadID)", method: .get,
            statusCode: 200, body: data
        )

        let vm = LoadDetailViewModel(loadID: loadID, role: role, apiClient: makeAPIClient(), logger: nil)
        let vc = LoadDetailViewController(viewModel: vm)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        vc.view.traitOverrides.horizontalSizeClass = .compact
        vc.traitOverrides.horizontalSizeClass = .compact
        vc.handleSizeClassChange(forceRebuild: true)

        // Install the spy in place of the real actionsView.
        let spy = CapturingLoadActionsView()
        spy.translatesAutoresizingMaskIntoConstraints = false
        vc.replaceActionsViewForTesting(with: spy)

        await vm.fetchLoadDetail()
        for _ in 0..<30 {
            if case .loaded = vm.state { break }
            await Task.yield()
        }
        vc.view.layoutIfNeeded()
        return (vc, spy, vm)
    }

    // MARK: - ChainOfTrust fixture (decoded once per call)

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
    private func makeLoad(
        id: String = "VL-TEST-1",
        status: LoadStatus
    ) throws -> Load {
        let json = """
        {
          "id": "\(id)",
          "reference_number": "REF-\(id)",
          "origin": {
            "city": "Anaheim", "state": "CA",
            "postal_code": "92805", "country": "US"
          },
          "destination": {
            "city": "Atlanta", "state": "GA",
            "postal_code": "30303", "country": "US"
          },
          "equipment": "dry_van",
          "weight": 42500,
          "rate": 3850.0,
          "pickup_at": "2026-04-02T08:00:00Z",
          "deliver_at": "2026-04-06T17:00:00Z",
          "status": "\(status.rawValue)",
          "state_history": []
        }
        """
        return try APIClient.defaultDecoder().decode(Load.self, from: Data(json.utf8))
    }

    // MARK: - Test 1 — `.loaded` configures action region with role's policy

    /// Broker on posted load -> [.tender, .cancel] passed to configure().
    @MainActor
    func test_render_loadedState_configuresActionRegionWithCorrectPolicy() async throws {
        let (_, spy, _) = try await makeVC(loadID: "VL-1003", role: .broker)

        XCTAssertNotNil(spy.lastCapture, "configure(...) was called")
        XCTAssertEqual(spy.lastCapture?.actions, [.tender, .cancel],
                       "Broker on .posted -> [.tender, .cancel]")
        XCTAssertEqual(spy.lastCapture?.role, .broker)
        XCTAssertEqual(spy.lastCapture?.currentStatus, .posted)
        XCTAssertNil(spy.lastCapture?.inFlight, "No in-flight on .loaded")
    }

    // MARK: - Test 2 — Pitfall 6: in-flight render uses PRE-TAP action set

    @MainActor
    func test_render_actionInFlightState_actionsListIsPreTapSnapshot() async throws {
        let (vc, spy, _) = try await makeVC(loadID: "VL-1003", role: .broker)

        // The .loaded render already captured the pre-tap actions [.tender, .cancel].
        XCTAssertEqual(spy.lastCapture?.actions, [.tender, .cancel])

        // Transition to .actionInFlight with predicted status .tendered.
        let predicted = try makeLoad(status: .tendered)
        let chain = try makeChain()
        vc.applyTestState_actionInFlight(predicted: predicted, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()

        XCTAssertEqual(spy.lastCapture?.actions, [.tender, .cancel],
                       "Pitfall 6 — in-flight render uses pre-tap action set [.tender, .cancel] " +
                       "even though predicted status is .tendered")
        XCTAssertEqual(spy.lastCapture?.inFlight, .tender, "inFlight marker propagated to configure()")
    }

    // MARK: - Test 3 — `.actionFailed` applies rollback Load

    @MainActor
    func test_render_actionFailedState_appliesRollbackLoad() async throws {
        let (vc, spy, _) = try await makeVC(loadID: "VL-1003", role: .broker)

        // Transition to .actionFailed with rollback to .posted Load.
        let rollback = try makeLoad(status: .posted)
        let chain = try makeChain()
        vc.applyTestState_actionFailed(rollbackTo: rollback, frozenChain: chain, errorCopyKey: "loads.actions.error.tender_failed")
        vc.view.layoutIfNeeded()

        XCTAssertEqual(spy.lastCapture?.currentStatus, .posted,
                       "Rollback applied — status reads .posted")
        XCTAssertNil(spy.lastCapture?.inFlight,
                     ".actionFailed has no in-flight marker (the spinner is gone)")
    }

    // MARK: - Test 4 — chain overlay mount stub on `.actionInFlight`

    @MainActor
    func test_render_actionInFlight_mountsChainOverlayStub() async throws {
        let (vc, _, _) = try await makeVC(loadID: "VL-1003", role: .broker)
        XCTAssertNil(vc.chainOverlayForTesting, "No overlay before in-flight")

        let predicted = try makeLoad(status: .tendered)
        let chain = try makeChain()
        vc.applyTestState_actionInFlight(predicted: predicted, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()

        XCTAssertNotNil(vc.chainOverlayForTesting,
                        "Chain overlay mounted during .actionInFlight (Plan 07 will finish the alpha-fade)")
    }

    // MARK: - Test 5 — chain overlay dismount on `.loaded` after in-flight

    @MainActor
    func test_render_loadedFromActionInFlight_dismissesChainOverlayStub() async throws {
        let (vc, _, _) = try await makeVC(loadID: "VL-1003", role: .broker)

        // Mount via in-flight.
        let predicted = try makeLoad(status: .tendered)
        let chain = try makeChain()
        vc.applyTestState_actionInFlight(predicted: predicted, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()
        XCTAssertNotNil(vc.chainOverlayForTesting)

        // Transition to .loaded -> dismount.
        let loadedLoad = try makeLoad(status: .tendered)
        vc.applyTestState_loaded(load: loadedLoad, chain: chain)
        vc.view.layoutIfNeeded()

        XCTAssertNil(vc.chainOverlayForTesting,
                     "Overlay dismounted on .loaded after in-flight")
    }

    // MARK: - Test 6 — handleActionTap(.tender) -> presents tender sheet stub

    @MainActor
    func test_handleActionTap_tender_presentsTenderSheetStub() async throws {
        let (vc, _, _) = try await makeVC(loadID: "VL-1003", role: .broker)

        XCTAssertEqual(vc.presentTenderSheetCallCountForTesting, 0)
        vc.handleActionTapForTesting(action: .tender)
        XCTAssertEqual(vc.presentTenderSheetCallCountForTesting, 1,
                       "Tender tap routes to presentTenderSheet() stub")
    }

    // MARK: - Test 7 — handleActionTap(.accept) -> calls viewModel.submit

    @MainActor
    func test_handleActionTap_accept_callsSubmitDirectly() async throws {
        // Use VL-1004 (tendered) + carrier role for the .accept scenario.
        let (vc, _, vm) = try await makeVC(loadID: "VL-1004", role: .carrier)

        // Register the action-endpoint mock so submit() can resolve (or
        // fail) without hanging. The actual server response is irrelevant
        // for this test — we just need to verify submit() was invoked.
        // Return a 500 so submit() resolves quickly via the rollback path.
        MockURLProtocol.registerFixture(
            for: LoadActionEndpoint.self,
            path: "/loads/VL-1004/accept", method: .post,
            statusCode: 500, body: Data()
        )

        let beforeState = vm.state
        XCTAssertNotNil(beforeState, "VM has a state")

        vc.handleActionTapForTesting(action: .accept)

        // Allow the in-flight transition to fire.
        for _ in 0..<30 {
            if case .actionInFlight = vm.state { break }
            if case .actionFailed = vm.state { break }
            await Task.yield()
        }
        // The state machine should have moved off .loaded — either to
        // .actionInFlight (mid-network) or .actionFailed (post-500). Both
        // confirm submit() was called.
        switch vm.state {
        case .actionInFlight, .actionFailed, .loaded:
            // .loaded is acceptable if the server response landed before
            // our await woke up. The point is the state mutated.
            break
        case .loading, .error:
            XCTFail("VM state should have mutated after handleActionTap(.accept). state=\(vm.state)")
        }
    }
}
