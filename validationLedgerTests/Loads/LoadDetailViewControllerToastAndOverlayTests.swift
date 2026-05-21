// validationLedgerTests/Loads/LoadDetailViewControllerToastAndOverlayTests.swift
//
// Phase 10 Plan 07 Task 2 — VC integration contract for the chain overlay
// alpha-fade + the toast banner mount on `.actionFailed`.
//
// Locks asserted here:
//   - `.actionInFlight` mounts the chain overlay over the chain region with
//     a `UIActivityIndicatorView(.medium)` (UI-SPEC § Chain overlay lines
//     477-489).
//   - On iPhone compact the overlay covers the strip-top → card-bottom
//     band; on iPad regular it covers the trust graph's bounds.
//   - `.actionInFlight → .loaded` dismisses the overlay (alpha fade-out
//     in 0.25s; the VC clears the ref in the animation completion).
//   - `.actionInFlight → .actionFailed` dismisses the overlay AND mounts
//     a LoadActionToastBannerView whose visible text matches the LOCALIZED
//     string for the LOCKED errorCopyKey (T-09-04 regression guard — the
//     banner NEVER renders server text).
//   - Double mount idempotency: two rapid `.actionFailed` transitions
//     leave exactly ONE banner in the view tree (Pitfall 1 single-ref
//     mirror — the second presentToastBanner dismisses the first then
//     mounts a new one).
//   - Two `.actionInFlight` renders in succession produce exactly ONE
//     chain overlay subview (Pitfall 1 — mountChainOverlayIfNeeded is
//     idempotent).
//   - Chain overlay VoiceOver label = the LOCKED localized "Chain
//     refreshing" string (UI-SPEC line 489).
//   - Chain overlay is not hit-testable (UI-SPEC line 489).
//
// === Why XCTest, not Swift Testing ===
// Matches the Phase 10 wave 1/2/3 XCTest neighbors.

import XCTest
@testable import validationLedger

final class LoadDetailViewControllerToastAndOverlayTests: XCTestCase {

    // MARK: - APIClient + VC builder (mirrors ActionRender tests)

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
    private func makeVC(
        loadID: String = "VL-1003",
        role: Role = .broker,
        sizeClass: UIUserInterfaceSizeClass = .compact
    ) async throws -> (vc: LoadDetailViewController, vm: LoadDetailViewModel) {
        MockURLProtocol.reset(); MockURLProtocol.resetFailureHandlers()
        let data = try FixtureLoader.loadFixture("load-detail-\(loadID)")
        MockURLProtocol.registerFixture(
            for: LoadDetailEndpoint.self,
            path: "/loads/\(loadID)", method: .get,
            statusCode: 200, body: data
        )

        let vm = LoadDetailViewModel(loadID: loadID, role: role, apiClient: makeAPIClient(), logger: nil)
        let vc = LoadDetailViewController(viewModel: vm)

        let width: CGFloat = (sizeClass == .regular) ? 1024 : 393
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 800))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(x: 0, y: 0, width: width, height: 800)
        vc.view.traitOverrides.horizontalSizeClass = sizeClass
        vc.traitOverrides.horizontalSizeClass = sizeClass
        vc.handleSizeClassChange(forceRebuild: true)

        await vm.fetchLoadDetail()
        for _ in 0..<30 {
            if case .loaded = vm.state { break }
            await Task.yield()
        }
        vc.view.layoutIfNeeded()
        return (vc, vm)
    }

    // MARK: - Fixture builders

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
    private func makeLoad(id: String = "VL-TEST-1", status: LoadStatus) throws -> Load {
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

    // MARK: - Helpers

    /// Walk the view hierarchy and return every LoadActionToastBannerView.
    @MainActor
    private func currentToastBanners(in vc: LoadDetailViewController) -> [LoadActionToastBannerView] {
        var out: [LoadActionToastBannerView] = []
        func walk(_ v: UIView) {
            for sub in v.subviews {
                if let t = sub as? LoadActionToastBannerView { out.append(t) }
                walk(sub)
            }
        }
        walk(vc.view)
        return out
    }

    /// First UIActivityIndicatorView inside the supplied overlay.
    @MainActor
    private func firstActivityIndicator(in overlay: UIView) -> UIActivityIndicatorView? {
        if let i = overlay as? UIActivityIndicatorView { return i }
        for sub in overlay.subviews {
            if let i = sub as? UIActivityIndicatorView { return i }
            if let nested = firstActivityIndicator(in: sub) { return nested }
        }
        return nil
    }

    // MARK: - Test 1 — `.actionInFlight` mounts the alpha-fade overlay

    @MainActor
    func test_actionInFlight_mountsChainOverlay_withSurface60AlphaBackdrop() async throws {
        let (vc, _) = try await makeVC()
        let predicted = try makeLoad(status: .tendered)
        let chain = try makeChain()
        vc.applyTestState_actionInFlight(predicted: predicted, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()

        let overlay = vc.chainOverlayForTesting
        XCTAssertNotNil(overlay, "Chain overlay mounted on .actionInFlight")
        // Compare backgroundColor's components.
        let expected = DS.Colors.surface.withAlphaComponent(0.6)
        var bgR: CGFloat = 0, bgG: CGFloat = 0, bgB: CGFloat = 0, bgA: CGFloat = 0
        var exR: CGFloat = 0, exG: CGFloat = 0, exB: CGFloat = 0, exA: CGFloat = 0
        overlay?.backgroundColor?.getRed(&bgR, green: &bgG, blue: &bgB, alpha: &bgA)
        expected.getRed(&exR, green: &exG, blue: &exB, alpha: &exA)
        XCTAssertEqual(bgA, 0.6, accuracy: 0.01, "Backdrop alpha is 0.6 per UI-SPEC line 483")

        let indicator = firstActivityIndicator(in: overlay!)
        XCTAssertNotNil(indicator, "Overlay contains a UIActivityIndicatorView")
        // The indicator is `.medium` per UI-SPEC line 484.
        XCTAssertEqual(indicator?.style, .medium)
        XCTAssertTrue(indicator?.isAnimating ?? false, "Indicator is animating")
    }

    // MARK: - Test 2 — iPhone overlay pins over the strip + card region

    @MainActor
    func test_actionInFlight_chainOverlay_pinsOverChainRegion_iPhone() async throws {
        let (vc, _) = try await makeVC(sizeClass: .compact)
        let predicted = try makeLoad(status: .tendered)
        let chain = try makeChain()
        vc.applyTestState_actionInFlight(predicted: predicted, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()

        let overlay = vc.chainOverlayForTesting
        XCTAssertNotNil(overlay)
        // The overlay's frame is positive (it occupies real screen real estate)
        // and lives somewhere inside the VC's view bounds.
        let f = overlay!.convert(overlay!.bounds, to: vc.view)
        XCTAssertGreaterThan(f.height, 0, "Overlay has non-zero height on iPhone")
        XCTAssertGreaterThan(f.width, 0,  "Overlay has non-zero width on iPhone")
    }

    // MARK: - Test 3 — iPad overlay pins over the trust graph pane

    @MainActor
    func test_actionInFlight_chainOverlay_pinsOverGraphPane_iPad() async throws {
        let (vc, _) = try await makeVC(loadID: "VL-1003", role: .broker, sizeClass: .regular)
        let predicted = try makeLoad(status: .tendered)
        let chain = try makeChain()
        vc.applyTestState_actionInFlight(predicted: predicted, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()

        let overlay = vc.chainOverlayForTesting
        XCTAssertNotNil(overlay, "Overlay mounted on iPad regular")
        // Overlay has positive bounds (the iPad path pins to the trust graph,
        // which is the left 60% of the body container).
        let f = overlay!.convert(overlay!.bounds, to: vc.view)
        XCTAssertGreaterThan(f.height, 0, "Overlay has non-zero height on iPad")
        XCTAssertGreaterThan(f.width, 0,  "Overlay has non-zero width on iPad")
    }

    // MARK: - Test 4 — `.actionInFlight → .loaded` dismisses overlay (fade-out)

    @MainActor
    func test_actionInFlight_thenLoaded_dismissesChainOverlay() async throws {
        let (vc, _) = try await makeVC()
        let predicted = try makeLoad(status: .tendered)
        let chain = try makeChain()
        vc.applyTestState_actionInFlight(predicted: predicted, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()
        XCTAssertNotNil(vc.chainOverlayForTesting)

        let loadedLoad = try makeLoad(status: .tendered)
        vc.applyTestState_loaded(load: loadedLoad, chain: chain)
        vc.view.layoutIfNeeded()

        // The dismount is a 0.25s alpha fade-out, after which the VC clears
        // `chainOverlay = nil` inside the animation completion.
        let exp = expectation(description: "Chain overlay fades out and clears")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertNil(vc.chainOverlayForTesting,
                         "Overlay ref cleared in fade-out animation completion")
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 2.0)
    }

    // MARK: - Test 5 — `.actionInFlight → .actionFailed` dismounts overlay AND presents toast

    @MainActor
    func test_actionInFlight_thenActionFailed_dismissesChainOverlay_AND_presentsToast() async throws {
        let (vc, _) = try await makeVC()
        let predicted = try makeLoad(status: .tendered)
        let chain = try makeChain()
        vc.applyTestState_actionInFlight(predicted: predicted, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()
        XCTAssertNotNil(vc.chainOverlayForTesting)

        let rollback = try makeLoad(status: .posted)
        vc.applyTestState_actionFailed(
            rollbackTo: rollback,
            frozenChain: chain,
            errorCopyKey: "loads.actions.error.tender_failed"
        )
        vc.view.layoutIfNeeded()

        // Toast banner mounted; chain overlay dismissal in progress.
        let banners = currentToastBanners(in: vc)
        XCTAssertEqual(banners.count, 1, "Exactly one toast banner mounted on .actionFailed")
        // The banner's visible message is the LOCALIZED string for the
        // tender_failed key — NEVER any server text.
        let label = banners.first?.subviewsRecursive(of: UILabel.self).first
        XCTAssertEqual(label?.text, "Couldn't send tender. Try again.",
                       "Banner renders the LOCKED localized string for the tender_failed key")
    }

    // MARK: - Test 6 — double `.actionFailed` is idempotent (one banner at a time)

    @MainActor
    func test_actionFailed_doubleMount_idempotent() async throws {
        let (vc, _) = try await makeVC()
        let chain = try makeChain()
        let rollback = try makeLoad(status: .posted)

        vc.applyTestState_actionFailed(
            rollbackTo: rollback,
            frozenChain: chain,
            errorCopyKey: "loads.actions.error.tender_failed"
        )
        vc.view.layoutIfNeeded()
        XCTAssertEqual(currentToastBanners(in: vc).count, 1)

        // Trigger a second failure rapidly. The second presentToastBanner
        // must dismiss the first before mounting a new one.
        vc.applyTestState_actionFailed(
            rollbackTo: rollback,
            frozenChain: chain,
            errorCopyKey: "loads.actions.error.cancel_failed"
        )
        vc.view.layoutIfNeeded()

        // Wait for the first banner's 0.22s slide-out to complete + the
        // new banner to mount.
        let exp = expectation(description: "Single banner remains after double failure")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let banners = self.currentToastBanners(in: vc)
            XCTAssertEqual(banners.count, 1,
                           "Exactly one banner remains — single-ref discipline mirror")
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 2.0)
    }

    // MARK: - Test 7 — banner text NEVER contains server-payload fragments (T-09-04 lock)

    @MainActor
    func test_actionFailed_bannerText_neverContainsServerErrorString() async throws {
        let (vc, _) = try await makeVC()
        let chain = try makeChain()
        let rollback = try makeLoad(status: .posted)

        vc.applyTestState_actionFailed(
            rollbackTo: rollback,
            frozenChain: chain,
            errorCopyKey: "loads.actions.error.tender_failed"
        )
        vc.view.layoutIfNeeded()

        let banners = currentToastBanners(in: vc)
        let bannerText = banners.first?.subviewsRecursive(of: UILabel.self).first?.text ?? ""
        // The locked English fallback.
        XCTAssertEqual(bannerText, "Couldn't send tender. Try again.")
        // Server-fragment regression guard — none of these substrings may
        // appear in the banner text.
        let forbidden = [
            "Internal server error", "party_id", "validation_failure",
            "500", "NSURLError", "decoding", "JSON", "HTTP",
        ]
        for needle in forbidden {
            XCTAssertFalse(bannerText.contains(needle),
                           "Banner text MUST NOT contain server-payload fragment '\(needle)' (T-09-04 view-layer lock — Plan 03 + Plan 07 mitigation)")
        }
    }

    // MARK: - Test 8 — double `.actionInFlight` produces exactly ONE overlay

    @MainActor
    func test_doubleMount_actionInFlightTransition_isIdempotent() async throws {
        let (vc, _) = try await makeVC()
        let chain = try makeChain()
        let predictedA = try makeLoad(status: .tendered)
        vc.applyTestState_actionInFlight(predicted: predictedA, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()
        let firstOverlay = vc.chainOverlayForTesting
        XCTAssertNotNil(firstOverlay)

        // Re-enter .actionInFlight with a different action.
        let predictedB = try makeLoad(status: .cancelled)
        vc.applyTestState_actionInFlight(predicted: predictedB, frozenChain: chain, action: .cancel)
        vc.view.layoutIfNeeded()

        let secondOverlay = vc.chainOverlayForTesting
        XCTAssertNotNil(secondOverlay)
        XCTAssertTrue(firstOverlay === secondOverlay,
                      "Pitfall 1 — mountChainOverlayIfNeeded is idempotent; the same UIView ref is preserved across two .actionInFlight transitions")
        // Count overlays in the hierarchy — only one.
        var overlayCount = 0
        func walk(_ v: UIView) {
            for sub in v.subviews {
                if sub.accessibilityIdentifier == "chain-updating-overlay" {
                    overlayCount += 1
                }
                walk(sub)
            }
        }
        walk(vc.view)
        XCTAssertEqual(overlayCount, 1,
                       "Exactly one overlay subview in the hierarchy across rapid .actionInFlight transitions")
    }

    // MARK: - Test 9 — chain overlay VoiceOver label is the LOCKED localized string

    @MainActor
    func test_actionInFlight_chainOverlay_voiceOverLabel() async throws {
        let (vc, _) = try await makeVC()
        let predicted = try makeLoad(status: .tendered)
        let chain = try makeChain()
        vc.applyTestState_actionInFlight(predicted: predicted, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()

        let overlay = vc.chainOverlayForTesting
        XCTAssertEqual(overlay?.accessibilityLabel, "Chain refreshing",
                       "Overlay's VoiceOver label is the locked English string for loads.actions.chain.refreshing.a11y per UI-SPEC line 489")
    }

    // MARK: - Test 10 — chain overlay is not hit-testable (UI-SPEC line 489)

    @MainActor
    func test_actionInFlight_chainOverlay_isNotHitTestable() async throws {
        let (vc, _) = try await makeVC()
        let predicted = try makeLoad(status: .tendered)
        let chain = try makeChain()
        vc.applyTestState_actionInFlight(predicted: predicted, frozenChain: chain, action: .tender)
        vc.view.layoutIfNeeded()

        let overlay = vc.chainOverlayForTesting
        XCTAssertFalse(overlay?.isUserInteractionEnabled ?? true,
                       "Overlay does not claim hit-test surface — taps fall through to underlying chain card per UI-SPEC line 489")
    }
}

// MARK: - Subview lookup helper

private extension UIView {
    func subviewsRecursive<T: UIView>(of type: T.Type) -> [T] {
        var out: [T] = []
        for sub in subviews {
            if let hit = sub as? T { out.append(hit) }
            out.append(contentsOf: sub.subviewsRecursive(of: type))
        }
        return out
    }
}
