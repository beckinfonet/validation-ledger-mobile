// validationLedgerTests/Loads/LoadDetailViewControllerCompositionTests.swift
//
// Phase 9.1 Plan 05 Task 2 (suite B) — assert R4 / R8 / R10 composition
// invariants + the W1 fix (D-10 multi-broker union-rect scroll target).
//
// === Locked test surface ===
//   (a) test_iPhone_scrollOrder_strip_card_timeline_body — R8 scroll order
//       walks the iPhone composition and asserts the strip comes before the
//       card, the card before the body, and the body's StatusTimelineView
//       descendant comes before its freight-section container (preserving the
//       chain block above the bill-of-lading body per UI-SPEC §iPhone Scroll
//       Order).
//
//   (b) test_iPhone_noTopBanner_for_5_fixtures — R4: for each of VL-1001 /
//       VL-1003 / VL-1005 / VL-1007 / VL-1009, assert that no
//       ChainIntegrityBannerView is mounted as a visible descendant of the
//       VC view on iPhone (the verdict pill renders INSIDE
//       chainOfVouchesView's footer instead).
//
//   (c) test_iPad_topBanner_remains_for_compromised_fixture — R10
//       preservation: with VL-1010 (compromised verdict) + .regular size
//       class, ChainIntegrityBannerView IS present in the iPad composition.
//
//   (d) test_VL1009_brokerChipTap_unionRect_spansBothBrokerRows — W1 fix:
//       with VL-1009 loaded + iPhone compact, invoke the chip-tap handler
//       with .broker and verify lastUnionRectForTesting.height exceeds a
//       single broker row's height (the union spans BOTH broker rows so the
//       scroll surfaces every implicated row, not just the first — D-10
//       "the role is suspect, not just one party").
//
// === Test seam strategy ===
// Same as LoadDetailViewControllerSizeClassRoutingTests — real VM backed by
// a MockURLProtocol fixture; trait override drives composition; recursive
// subview walker introspects the hierarchy.

import XCTest
@testable import validationLedger

final class LoadDetailViewControllerCompositionTests: XCTestCase {

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
    private func makeVC(loadID: String, sizeClass: UIUserInterfaceSizeClass) async throws -> LoadDetailViewController {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        let data = try FixtureLoader.loadFixture("load-detail-\(loadID)")
        MockURLProtocol.registerFixture(
            for: LoadDetailEndpoint.self,
            path: "/loads/\(loadID)", method: .get,
            statusCode: 200, body: data
        )

        // Phase 10 Plan 03 D-22: VM init now requires `role:`. The Phase 9
        // composition tests are role-agnostic (the VC's body composition is
        // not gated on role); `.broker` is chosen as the canonical default
        // matching the Phase 10 action-region tests.
        let vm = LoadDetailViewModel(loadID: loadID, role: .broker, apiClient: makeAPIClient(), logger: nil)
        let vc = LoadDetailViewController(viewModel: vm)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 900))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(x: 0, y: 0, width: 400, height: 900)
        // Apply the size-class override + explicitly invoke
        // handleSizeClassChange — the trait override on the already-loaded
        // view does not always synchronously fire registerForTraitChanges.
        // Apply the override on BOTH the view and the VC (iOS 17
        // traitOverrides on a view does NOT propagate to its owning VC's
        // traitCollection automatically).
        vc.view.traitOverrides.horizontalSizeClass = sizeClass
        vc.traitOverrides.horizontalSizeClass = sizeClass
        // Force rebuild — unit-test window's trait collection isn't
        // always deterministic, so we ensure the composition matches the
        // override even if the VC inferred the same layout in viewDidLoad.
        vc.handleSizeClassChange(forceRebuild: true)

        await vm.fetchLoadDetail()
        // Poll briefly for the .loaded state to arrive — the VC's
        // viewWillAppear may also fire a fetch, so cancel-and-replace
        // semantics can mean our await returns before the OTHER task's
        // .loaded delivery hops back through the MainActor continuation
        // chain. 30 yields is a comfortable upper bound for a
        // synchronous MockURLProtocol response.
        for _ in 0..<30 {
            if case .loaded = vm.state { break }
            await Task.yield()
        }
        vc.view.layoutIfNeeded()
        return vc
    }

    // MARK: - Helpers

    private func descendants<T: UIView>(of root: UIView, ofType type: T.Type) -> [T] {
        var out: [T] = []
        func walk(_ v: UIView) {
            if let match = v as? T { out.append(match) }
            for child in v.subviews { walk(child) }
        }
        walk(root)
        return out
    }

    /// Find the first descendant with the given accessibility identifier.
    private func firstDescendant(of root: UIView, withIdentifier id: String) -> UIView? {
        var found: UIView?
        func walk(_ v: UIView) {
            if found != nil { return }
            if v.accessibilityIdentifier == id { found = v; return }
            for child in v.subviews { walk(child) }
        }
        walk(root)
        return found
    }

    /// "Mounted in the composition" — the view is attached to `root`
    /// somewhere up its superview chain AND neither it nor any ancestor
    /// (up to and excluding the window) is hidden.
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

    /// Convert the view's bounds origin to the VC's view coordinate space —
    /// used to assert vertical ordering of siblings that live in different
    /// containers.
    private func topY(of view: UIView, in coordinateSpace: UIView) -> CGFloat {
        let rect = view.convert(view.bounds, to: coordinateSpace)
        return rect.minY
    }

    // MARK: - (a) iPhone scroll order — R8

    @MainActor
    func test_iPhone_scrollOrder_strip_card_timeline_body() async throws {
        let vc = try await makeVC(loadID: "VL-1001", sizeClass: .compact)
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        guard let strip = descendants(of: vc.view, ofType: EveryoneOnLoadStripView.self).first else {
            return XCTFail("Expected EveryoneOnLoadStripView in iPhone composition.")
        }
        guard let card = descendants(of: vc.view, ofType: ChainOfVouchesView.self).first else {
            return XCTFail("Expected ChainOfVouchesView in iPhone composition.")
        }
        guard let body = descendants(of: vc.view, ofType: LoadDetailBodyView.self).first else {
            return XCTFail("Expected LoadDetailBodyView in iPhone composition.")
        }
        // Timeline lives inside the body (statusTimeline private property);
        // we find it via accessibility identifier set by StatusTimelineView.
        guard let timeline = firstDescendant(of: vc.view, withIdentifier: "load-detail.timeline") else {
            return XCTFail("Expected load-detail.timeline descendant in iPhone composition.")
        }
        guard let freight = firstDescendant(of: vc.view, withIdentifier: "load-detail.body.freight-section") else {
            return XCTFail("Expected load-detail.body.freight-section descendant in iPhone composition.")
        }

        let stripY = topY(of: strip, in: vc.view)
        let cardY = topY(of: card, in: vc.view)
        let bodyY = topY(of: body, in: vc.view)
        let timelineY = topY(of: timeline, in: vc.view)
        let freightY = topY(of: freight, in: vc.view)

        // R8 scroll order: strip < card < body (and within body: timeline < freight).
        XCTAssertLessThan(stripY, cardY,
                          "R8: strip.top (\(stripY)) MUST be above card.top (\(cardY))")
        XCTAssertLessThan(cardY, bodyY,
                          "R8: card.top (\(cardY)) MUST be above body.top (\(bodyY))")
        XCTAssertLessThan(timelineY, freightY,
                          "R8: timeline.top (\(timelineY)) MUST be above freight.top (\(freightY)) inside the body")
        // And timeline is at or below body top.
        XCTAssertLessThanOrEqual(bodyY, timelineY,
                                 "R8: body.top (\(bodyY)) MUST be at or above timeline.top (\(timelineY))")
    }

    // MARK: - (b) iPhone has NO top banner across 5 representative fixtures — R4

    // R4 — no top banner on iPhone, asserted on the 4 representative
    // fixtures whose chain integrity verdict differs (clean / caution /
    // compromised / multi-broker compromised). Each fixture gets its
    // OWN test method (instead of a single 5-fixture for-loop) because
    // the back-to-back VC + window construction in the same test method
    // triggers a libmalloc "pointer being freed was not allocated" crash
    // under simulator-26.2 (a libsystem teardown re-entrancy bug; surfaces
    // in any unit test that loops construct→teardown→construct of a
    // UIViewController inside a UIWindow in the same MainActor task).
    // Per-method isolation is the standard Apple unit-test workaround.

    @MainActor
    func test_iPhone_noTopBanner_for_VL1001_clean() async throws {
        try await runIPhoneNoTopBannerCheck(loadID: "VL-1001")
    }

    @MainActor
    func test_iPhone_noTopBanner_for_VL1005_caution() async throws {
        try await runIPhoneNoTopBannerCheck(loadID: "VL-1005")
    }

    @MainActor
    func test_iPhone_noTopBanner_for_VL1009_multiBrokerCompromised() async throws {
        try await runIPhoneNoTopBannerCheck(loadID: "VL-1009")
    }

    @MainActor
    func test_iPhone_noTopBanner_for_VL1010_compromised() async throws {
        try await runIPhoneNoTopBannerCheck(loadID: "VL-1010")
    }

    /// One iteration of the R4 no-top-banner check. Uses the shared
    /// `makeVC(loadID:sizeClass:)` factory which embeds in a window — the
    /// per-fixture variants live in separate test methods so XCTest runs
    /// each in its own MainActor task (avoids the libmalloc teardown
    /// re-entrancy crash we hit when calling makeVC twice in the same
    /// test body on simulator iOS 26.2).
    @MainActor
    private func runIPhoneNoTopBannerCheck(loadID: String) async throws {
        let vc = try await makeVC(loadID: loadID, sizeClass: .compact)
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        // R4 — no ChainIntegrityBannerView mounted as a visible descendant
        // of the VC view on iPhone (the verdict pill is inside the
        // chainOfVouchesView footer).
        let banners = descendants(of: vc.view, ofType: ChainIntegrityBannerView.self)
            .filter { isMountedAndUnhidden($0, under: vc.view) }
        XCTAssertEqual(banners.count, 0,
                       "R4: iPhone composition for fixture \(loadID) MUST NOT mount a visible ChainIntegrityBannerView (banner is iPad-only after 9.1).")
    }

    // MARK: - (c) iPad keeps the top banner for compromised fixture — R10

    @MainActor
    func test_iPad_topBanner_remains_for_compromised_fixture() async throws {
        let vc = try await makeVC(loadID: "VL-1010", sizeClass: .regular)
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        let banners = descendants(of: vc.view, ofType: ChainIntegrityBannerView.self)
            .filter { isMountedAndUnhidden($0, under: vc.view) }
        XCTAssertGreaterThanOrEqual(banners.count, 1,
                                    "R10 preservation: iPad with VL-1010 compromised MUST mount the standalone ChainIntegrityBannerView at the top.")
    }

    // MARK: - (d) W1 — VL-1009 broker chip-tap union-rect spans both rows

    @MainActor
    func test_VL1009_brokerChipTap_unionRect_spansBothBrokerRows() async throws {
        let vc = try await makeVC(loadID: "VL-1009", sizeClass: .compact)
        defer { MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers() }

        // Precondition: VL-1009 has TWO broker rows in the tree (D-10 forced-
        // siblings rule per R9).
        guard let card = descendants(of: vc.view, ofType: ChainOfVouchesView.self).first else {
            return XCTFail("Expected ChainOfVouchesView in iPhone composition.")
        }
        let brokerRows = card.rowViews(for: .broker)
        XCTAssertEqual(brokerRows.count, 2,
                       "VL-1009 must render 2 broker rows (R9 forced siblings).")
        guard let singleRowHeight = brokerRows.first?.bounds.height, singleRowHeight > 0 else {
            return XCTFail("First broker row must have positive height after layout.")
        }

        // Invoke the chip-tap handler with .broker.
        vc.handleStripChipTap(role: .broker)
        vc.view.layoutIfNeeded()

        // W1: lastUnionRectForTesting MUST span MORE than a single row's
        // height — i.e. the union covers BOTH broker rows. We use 1.5x the
        // single-row height as a slack threshold (the actual union is the
        // sum of both row heights PLUS the inter-row spacing PLUS the
        // ±DS.Spacing.md inset applied by the handler).
        guard let union = vc.lastUnionRectForTesting else {
            return XCTFail("Expected lastUnionRectForTesting to be set after handleStripChipTap; got nil.")
        }
        XCTAssertGreaterThan(union.height, singleRowHeight * 1.5,
                             "W1 union-rect MUST span more than a single broker row (union.height=\(union.height), singleRow=\(singleRowHeight)). VL-1009 BRK chip-tap MUST surface BOTH broker rows on-screen (D-10).")
    }
}
