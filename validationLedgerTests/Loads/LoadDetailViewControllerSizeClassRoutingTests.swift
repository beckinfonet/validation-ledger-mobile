// validationLedgerTests/Loads/LoadDetailViewControllerSizeClassRoutingTests.swift
//
// Phase 9.1 Plan 05 Task 2 (suite A) — assert R5 size-class routing in
// LoadDetailViewController:
//   - .compact horizontalSizeClass → iPhone vertical-tree composition
//     (EveryoneOnLoadStripView + ChainOfVouchesView mounted; TrustGraphView
//     not in visible composition).
//   - .regular horizontalSizeClass → iPad split composition (TrustGraphView
//     mounted; EveryoneOnLoadStripView + ChainOfVouchesView NOT mounted).
//   - Trait flip in either direction rebuilds the composition without crash.
//
// === Test seam strategy ===
// The VC is constructed with a real LoadDetailViewModel backed by a
// MockURLProtocol fixture (load-detail-VL-1001.json — the all-5-roles clean
// chain used as the canonical happy path across the Phase 9 + 9.1 test
// corpus). The VM's .loaded state is achieved by calling fetchLoadDetail()
// then awaiting the recorder. After .loaded lands, the test inspects the
// view hierarchy with a recursive subview walker. The iOS 17
// `registerForTraitChanges` API picks up `traitOverrides.horizontalSizeClass`
// flips automatically.
//
// === Why XCTest, not Swift Testing ===
// Matches the in-repo convention (LoadDetailViewModelTests is Swift Testing
// for value-shape assertions, but VC + UIKit hierarchy introspection is the
// XCTest precedent — TrustGraphViewLayoutTests / ChainOfVouchesViewTests).

import XCTest
@testable import validationLedger

final class LoadDetailViewControllerSizeClassRoutingTests: XCTestCase {

    // MARK: - APIClient + session assembly (mirrors LoadDetailViewModelTests)

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

    /// Build a VC, register the VL-1001 fixture, apply the requested
    /// size-class override, drive the VM to .loaded, and force layout.
    @MainActor
    private func makeVC(sizeClass: UIUserInterfaceSizeClass) async throws -> LoadDetailViewController {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        let data = try FixtureLoader.loadFixture("load-detail-VL-1001")
        MockURLProtocol.registerFixture(
            for: LoadDetailEndpoint.self,
            path: "/loads/VL-1001", method: .get,
            statusCode: 200, body: data
        )

        // Phase 10 Plan 03 D-22: VM init now requires `role:`. The Phase 9
        // size-class routing tests are role-agnostic; `.broker` is the
        // canonical default matching the Phase 10 action-region tests.
        let vm = LoadDetailViewModel(loadID: "VL-1001", role: .broker, apiClient: makeAPIClient(), logger: nil)
        let vc = LoadDetailViewController(viewModel: vm)
        // Embed in a window so view-hierarchy + window-guard checks work.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        // Apply the size-class override + explicitly invoke
        // handleSizeClassChange — the trait-override on a view that's
        // already loaded doesn't always trigger registerForTraitChanges
        // synchronously, and we want a deterministic composition flip
        // before driving the VM to .loaded.
        // Apply the override on BOTH the view (so any subtree-level
        // traitCollection reads pick it up) AND the VC (so the VC's own
        // `traitCollection.horizontalSizeClass` — which the VC reads in
        // handleSizeClassChange — reflects the override; iOS 17
        // `traitOverrides` on a view does NOT propagate to its owning VC's
        // traitCollection automatically).
        vc.view.traitOverrides.horizontalSizeClass = sizeClass
        vc.traitOverrides.horizontalSizeClass = sizeClass
        // Force rebuild even if the trait override happens to match the
        // composition the VC inferred during viewDidLoad (the unit-test
        // window's trait collection isn't always deterministic).
        vc.handleSizeClassChange(forceRebuild: true)

        // Drive the VM through the load flow. The VC's viewWillAppear may
        // also fire a fetch when the window becomes key; we ignore that
        // and use cancel-and-replace semantics — our await waits for our
        // task to settle. Then poll briefly for the .loaded state to
        // arrive (settles the Task/MainActor continuation chain).
        await vm.fetchLoadDetail()
        for _ in 0..<30 {
            if case .loaded = vm.state { break }
            await Task.yield()
        }
        vc.view.layoutIfNeeded()
        return vc
    }

    // MARK: - Helpers

    /// Recursively walk `root.subviews` and return every descendant whose
    /// type matches `T`. Used to find the strip / card / trust graph /
    /// banner inside the VC's deep view hierarchy.
    private func descendants<T: UIView>(of root: UIView, ofType type: T.Type) -> [T] {
        var out: [T] = []
        func walk(_ v: UIView) {
            if let match = v as? T { out.append(match) }
            for child in v.subviews { walk(child) }
        }
        walk(root)
        return out
    }

    /// "Mounted in the composition" — the view is attached to `vc.view`
    /// somewhere up its superview chain AND neither it nor any non-window
    /// ancestor is hidden. We stop the walk at the window boundary because
    /// the unit-test UIWindow may or may not be visibly active (we set
    /// makeKeyAndVisible() above but UIWindow may still report isHidden in
    /// some simulator configurations).
    private func isMountedAndUnhidden(_ view: UIView, under root: UIView) -> Bool {
        guard !view.isHidden else { return false }
        var cur: UIView? = view.superview
        var reachedRoot = false
        while let v = cur {
            if v === root { reachedRoot = true; break }
            if v.isHidden { return false }
            cur = v.superview
        }
        return reachedRoot
    }

    // MARK: - Test 1: iPhone compact mounts new components, omits TrustGraphView

    @MainActor
    func test_iPhoneCompact_mounts_newComponents_and_omits_trustGraphView() async throws {
        let vc = try await makeVC(sizeClass: .compact)
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let strips = descendants(of: vc.view, ofType: EveryoneOnLoadStripView.self)
        let cards = descendants(of: vc.view, ofType: ChainOfVouchesView.self)
        let graphs = descendants(of: vc.view, ofType: TrustGraphView.self)

        XCTAssertEqual(strips.count, 1,
                       "iPhone compact MUST mount exactly one EveryoneOnLoadStripView (R5).")
        XCTAssertTrue(isMountedAndUnhidden(strips[0], under: vc.view),
                      "iPhone compact strip MUST be visible (not hidden / not alpha 0).")
        XCTAssertEqual(cards.count, 1,
                       "iPhone compact MUST mount exactly one ChainOfVouchesView (R5).")
        XCTAssertTrue(isMountedAndUnhidden(cards[0], under: vc.view),
                      "iPhone compact card MUST be visible.")
        // TrustGraphView may be a sibling property on the VC but on iPhone
        // compact it MUST NOT be in the visible composition — either it has
        // no superview, or it's hidden, or its container hides it.
        for graph in graphs {
            XCTAssertFalse(isMountedAndUnhidden(graph, under: vc.view),
                           "TrustGraphView MUST NOT be visible on iPhone compact (R5).")
        }
    }

    // MARK: - Test 2: iPad regular mounts TrustGraphView, omits new components

    @MainActor
    func test_iPadRegular_mounts_trustGraphView_and_omits_newComponents() async throws {
        let vc = try await makeVC(sizeClass: .regular)
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let strips = descendants(of: vc.view, ofType: EveryoneOnLoadStripView.self)
        let cards = descendants(of: vc.view, ofType: ChainOfVouchesView.self)
        let graphs = descendants(of: vc.view, ofType: TrustGraphView.self)

        XCTAssertEqual(graphs.count, 1,
                       "iPad regular MUST mount exactly one TrustGraphView (R5 + R10 preservation).")
        XCTAssertTrue(isMountedAndUnhidden(graphs[0], under: vc.view),
                      "iPad regular TrustGraphView MUST be visible.")
        // The new iPhone components MUST NOT appear in the iPad composition.
        for strip in strips {
            XCTAssertFalse(isMountedAndUnhidden(strip, under: vc.view),
                           "EveryoneOnLoadStripView MUST NOT be visible on iPad regular (R10).")
        }
        for card in cards {
            XCTAssertFalse(isMountedAndUnhidden(card, under: vc.view),
                           "ChainOfVouchesView MUST NOT be visible on iPad regular (R10).")
        }
    }

    // MARK: - Test 3: size-class flip iPhone → iPad rebuilds without crash

    @MainActor
    func test_sizeClassFlip_iPhoneToIPad_rebuildsWithoutCrash() async throws {
        let vc = try await makeVC(sizeClass: .compact)
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        // Pre-flip sanity: strip + card present, graph not visible.
        XCTAssertTrue(isMountedAndUnhidden(descendants(of: vc.view, ofType: EveryoneOnLoadStripView.self).first ?? UIView(), under: vc.view),
                      "Pre-flip: strip is visible on iPhone compact.")

        // Flip to iPad regular. registerForTraitChanges doesn't always
        // fire synchronously on the override change in unit tests, so we
        // call handleSizeClassChange() directly to force the rebuild.
        vc.view.traitOverrides.horizontalSizeClass = .regular
        vc.traitOverrides.horizontalSizeClass = .regular
        vc.handleSizeClassChange()
        vc.view.layoutIfNeeded()

        // Post-flip: TrustGraphView visible, strip + card no longer visible.
        let graphs = descendants(of: vc.view, ofType: TrustGraphView.self)
        XCTAssertEqual(graphs.count, 1,
                       "Post-flip to iPad MUST have TrustGraphView in the hierarchy.")
        XCTAssertTrue(isMountedAndUnhidden(graphs[0], under: vc.view),
                      "Post-flip to iPad TrustGraphView MUST be visible.")
        for strip in descendants(of: vc.view, ofType: EveryoneOnLoadStripView.self) {
            XCTAssertFalse(isMountedAndUnhidden(strip, under: vc.view),
                           "Post-flip to iPad: strip MUST NOT be visible (R10 preservation).")
        }
        for card in descendants(of: vc.view, ofType: ChainOfVouchesView.self) {
            XCTAssertFalse(isMountedAndUnhidden(card, under: vc.view),
                           "Post-flip to iPad: card MUST NOT be visible (R10 preservation).")
        }
    }

    // MARK: - Test 4: size-class flip iPad → iPhone rebuilds without crash

    @MainActor
    func test_sizeClassFlip_iPadToIPhone_rebuildsWithoutCrash() async throws {
        let vc = try await makeVC(sizeClass: .regular)
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        // Pre-flip sanity: TrustGraphView present + visible.
        let preFlipGraphs = descendants(of: vc.view, ofType: TrustGraphView.self)
        XCTAssertEqual(preFlipGraphs.count, 1, "Pre-flip on iPad: TrustGraphView mounted.")
        XCTAssertTrue(isMountedAndUnhidden(preFlipGraphs[0], under: vc.view), "Pre-flip on iPad: TrustGraphView visible.")

        // Flip to iPhone compact. registerForTraitChanges doesn't always
        // fire synchronously on the override change in unit tests, so we
        // call handleSizeClassChange() directly to force the rebuild.
        vc.view.traitOverrides.horizontalSizeClass = .compact
        vc.traitOverrides.horizontalSizeClass = .compact
        vc.handleSizeClassChange()
        vc.view.layoutIfNeeded()

        // Post-flip: strip + card visible, graph no longer visible.
        let strips = descendants(of: vc.view, ofType: EveryoneOnLoadStripView.self)
        let cards = descendants(of: vc.view, ofType: ChainOfVouchesView.self)
        XCTAssertEqual(strips.count, 1, "Post-flip to iPhone: strip mounted.")
        XCTAssertTrue(isMountedAndUnhidden(strips[0], under: vc.view), "Post-flip to iPhone: strip visible.")
        XCTAssertEqual(cards.count, 1, "Post-flip to iPhone: card mounted.")
        XCTAssertTrue(isMountedAndUnhidden(cards[0], under: vc.view), "Post-flip to iPhone: card visible.")
        for graph in descendants(of: vc.view, ofType: TrustGraphView.self) {
            XCTAssertFalse(isMountedAndUnhidden(graph, under: vc.view),
                           "Post-flip to iPhone: TrustGraphView MUST NOT be visible (R5).")
        }
    }
}
