// validationLedgerTests/Loads/Snapshot/VerificationBasisSheetViewControllerSnapshotTests.swift
//
// Phase 9 Plan 07 Task 1 — TRUST-03 verification-basis sheet snapshot suite.
//
// === Plan 02 Wave-0 shell → Plan 07 population ===
// The four scenarios pinned by D-09 + D-11 + UI-SPEC § Verification-basis
// sheet lines 410-457:
//   1. clean × Carrier  — 5+ priors, USDOT row present, no implicated block.
//   2. clean × Shipper  — USDOT row ABSENT (D-09 — entirely hidden, no
//                         "Not applicable" placeholder).
//   3. caution × Broker (implicated) — D-11 inline block with yellow tint.
//   4. compromised × Carrier (implicated, empty priors) — D-14 chameleon
//                         archetype empty-state line + red-tinted implicated
//                         block.
//
// Locked targets:
//   - 09-07-PLAN.md Acceptance Criteria — 4 real assertions; zero
//     test-method skip stubs.
//   - 09-UI-SPEC.md § Modal Sheets lines 406-477 (sheet content order) +
//     § Copywriting Verification-basis sheet lines 699-722.
//   - 09-PATTERNS.md table row 23 — VerificationBasisSheetViewController
//     mirrors the KYCStatusViewController sectioned-stack VC shape.
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`. Sheet
// snapshots render the VC's `view` at the medium-detent representative
// size (~393×500 pt) — NOT the floating presentation chrome.
//
// === T-09-04 (PII) ===
// Synthetic `ChainOfTrustFactory` fixtures only. No real party names, no
// real freight reference numbers. Production fixtures are not loaded here.

import XCTest
@testable import validationLedger

class VerificationBasisSheetViewControllerSnapshotTests: XCTestCase {

    // MARK: - Constants

    /// iPhone medium-detent representative canvas — 393pt wide × 500pt tall.
    private static let sheetCanvasSize = CGSize(width: 393, height: 500)

    // MARK: - Helpers

    /// Layout the VC at the sheet canvas size and return the rendered view.
    private func renderedView(_ vc: VerificationBasisSheetViewController) -> UIView {
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(origin: .zero, size: Self.sheetCanvasSize)
        vc.view.layoutIfNeeded()
        return vc.view
    }

    /// Walk the entire subview tree and collect every descendant.
    private func collectAllSubviews(_ root: UIView) -> [UIView] {
        var result: [UIView] = []
        var stack: [UIView] = [root]
        while let v = stack.popLast() {
            result.append(v)
            stack.append(contentsOf: v.subviews)
        }
        return result
    }

    /// Look up a node by partyID inside the factory's clean chain.
    private func node(forPartyID partyID: String, in chain: ChainOfTrust) -> TrustNode {
        guard let node = chain.nodes.first(where: { $0.partyID == partyID }) else {
            preconditionFailure("test fixture missing party '\(partyID)'")
        }
        return node
    }

    // MARK: - 1. clean × Carrier — 5 rows present, USDOT included

    func test_cleanCarrier_rendersFiveRows() {
        // Build a clean chain; replace the carrier's empty priors with 5
        // synthetic prior loads so the "Prior relationships (5)" header
        // renders.
        let baseChain = ChainOfTrustFactory.fiveNodeClean()
        let baseCarrier = node(forPartyID: "party-carrier", in: baseChain)
        let priors: [PriorRelationship] = (0..<5).map { idx in
            PriorRelationship(
                loadID: "VL-90\(idx)",
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                counterpartyRole: .broker,
                counterpartyDisplayName: "Synthetic Broker"
            )
        }
        let carrier = TrustNode(
            partyID: baseCarrier.partyID,
            role: baseCarrier.role,
            displayName: baseCarrier.displayName,
            verificationState: baseCarrier.verificationState,
            kycCompletedAt: baseCarrier.kycCompletedAt,
            deviceBindingStatus: baseCarrier.deviceBindingStatus,
            usdotNumber: baseCarrier.usdotNumber,
            usdotAuthorityStatus: baseCarrier.usdotAuthorityStatus,
            priorRelationships: priors
        )

        let vc = VerificationBasisSheetViewController(node: carrier, integrity: baseChain.integrity)
        let view = renderedView(vc)
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.sheetCanvasSize),
            name: "VerificationBasisSheet-cleanCarrier", to: self
        )

        let all = collectAllSubviews(view)

        // Root identifier — UI-SPEC line 776.
        XCTAssertEqual(view.accessibilityIdentifier, "load-detail.verification-basis-sheet",
                       "root view must carry the locked sheet identifier")

        // Header + 4 fact-region identifiers must be present (KYC + device
        // + USDOT + prior-relationships). USDOT row IS present for carriers.
        XCTAssertNotNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.header" },
                        "header row must be present")
        XCTAssertNotNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.kyc-row" },
                        "KYC row must be present (always rendered, every role)")
        XCTAssertNotNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.device-binding-row" },
                        "device-binding row must be present (always rendered, every role)")
        XCTAssertNotNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.usdot-row" },
                        "D-09 — USDOT row MUST be present for Carrier")
        XCTAssertNotNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.prior-relationships" },
                        "prior-relationships section must be present (always rendered)")

        // 5 prior-relationship row identifiers.
        let priorRows = all.filter { ($0.accessibilityIdentifier ?? "").hasPrefix("load-detail.verification-basis-sheet.prior-relationships.row.") }
        XCTAssertEqual(priorRows.count, 5,
                       "5 priors → 5 list rows with `prior-relationships.row.<loadID>` identifiers")

        // Clean verdict → NO implicated block.
        XCTAssertNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.implicated-block" },
                     "D-11 — clean chain MUST NOT render the implicated block")
    }

    // MARK: - 2. clean × Shipper — USDOT row absent (D-09)

    func test_cleanShipper_rendersFourRowsNoUSDOT() {
        let baseChain = ChainOfTrustFactory.fiveNodeClean()
        let shipper = node(forPartyID: "party-shipper", in: baseChain)

        let vc = VerificationBasisSheetViewController(node: shipper, integrity: baseChain.integrity)
        let view = renderedView(vc)
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.sheetCanvasSize),
            name: "VerificationBasisSheet-cleanShipper", to: self
        )

        let all = collectAllSubviews(view)

        // KYC + device + prior-relationships still present.
        XCTAssertNotNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.kyc-row" })
        XCTAssertNotNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.device-binding-row" })
        XCTAssertNotNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.prior-relationships" })

        // D-09 — USDOT row entirely ABSENT for Shipper. No "Not applicable"
        // placeholder row either.
        XCTAssertNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.usdot-row" },
                     "D-09 — USDOT row MUST NOT be rendered for Shipper (no placeholder either)")

        // Clean chain → no implicated block.
        XCTAssertNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.implicated-block" })
    }

    // MARK: - 3. caution × Broker (implicated) — yellow-tinted implicated block

    func test_cautionImplicatedBroker_rendersImplicatedBlock() {
        // Caution verdict with the broker implicated. Broker has no USDOT
        // row (D-09) but DOES get the implicated block (D-11).
        let chain = ChainOfTrustFactory.fiveNodeClean(
            verdict: .caution,
            implicatedNodeIDs: ["party-broker"]
        )
        let broker = node(forPartyID: "party-broker", in: chain)

        let vc = VerificationBasisSheetViewController(node: broker, integrity: chain.integrity)
        let view = renderedView(vc)
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.sheetCanvasSize),
            name: "VerificationBasisSheet-cautionImplicatedBroker", to: self
        )

        let all = collectAllSubviews(view)

        // D-11 — implicated block MUST render.
        guard let implicated = all.first(where: { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.implicated-block" }) else {
            return XCTFail("D-11 — implicated block MUST render when partyID ∈ implicatedNodeIDs")
        }

        // UI-SPEC line 454 — caution → 0.15 yellow tint background.
        let bg = implicated.backgroundColor
        XCTAssertNotNil(bg, "implicated block must have a tinted background")
        // Probe the resolved RGBA in light mode against systemYellow @ 0.15.
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)
        let resolved = bg!.resolvedColor(with: lightTrait)
        let yellow = UIColor.systemYellow
            .withAlphaComponent(0.15)
            .resolvedColor(with: lightTrait)
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        yellow.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        XCTAssertEqual(Double(red), Double(r2), accuracy: 0.05, "implicated block tint must be ~yellow R")
        XCTAssertEqual(Double(green), Double(g2), accuracy: 0.05, "implicated block tint must be ~yellow G")
        XCTAssertEqual(Double(alpha), Double(a2), accuracy: 0.05, "implicated block alpha must be ~0.15")

        // Broker has no USDOT row (D-09 — only Carrier + Dispatch render USDOT).
        XCTAssertNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.usdot-row" },
                     "D-09 — USDOT row MUST NOT be rendered for Broker")
    }

    // MARK: - 4. compromised × Carrier (implicated, empty priors) — red tint + empty-state line

    func test_compromisedImplicatedCarrier_rendersChameleonEmptyPriorState() {
        // D-14 chameleon archetype: implicated carrier with priorRelationships == [].
        // The fiveNodeClean factory already builds priors=[]; we override the
        // verdict + implicated list to compromised.
        let chain = ChainOfTrustFactory.fiveNodeClean(
            verdict: .compromised,
            implicatedNodeIDs: ["party-carrier"]
        )
        let carrier = node(forPartyID: "party-carrier", in: chain)
        XCTAssertTrue(carrier.priorRelationships.isEmpty,
                      "precondition: chameleon archetype carries no prior relationships (D-14)")

        let vc = VerificationBasisSheetViewController(node: carrier, integrity: chain.integrity)
        let view = renderedView(vc)
        UIKitSnapshot.attach(
            UIKitSnapshot.image(of: view, size: Self.sheetCanvasSize),
            name: "VerificationBasisSheet-compromisedImplicatedCarrier", to: self
        )

        let all = collectAllSubviews(view)

        // D-11 — implicated block MUST render with red tint.
        guard let implicated = all.first(where: { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.implicated-block" }) else {
            return XCTFail("D-11 — implicated block MUST render for compromised implicated carrier")
        }
        let bg = implicated.backgroundColor
        XCTAssertNotNil(bg)
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)
        let resolved = bg!.resolvedColor(with: lightTrait)
        let red = DS.Colors.destructive
            .withAlphaComponent(0.15)
            .resolvedColor(with: lightTrait)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        resolved.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        red.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        XCTAssertEqual(Double(r1), Double(r2), accuracy: 0.05, "implicated block tint must be ~red R")
        XCTAssertEqual(Double(b1), Double(b2), accuracy: 0.05, "implicated block tint must be ~red B")
        XCTAssertEqual(Double(a1), Double(a2), accuracy: 0.05, "implicated block alpha must be ~0.15")

        // D-14 empty-state line "First time working together." MUST render
        // somewhere inside the prior-relationships section.
        let emptyStateText = "First time working together."
        let matchingLabels = all.compactMap { $0 as? UILabel }.filter { $0.text == emptyStateText }
        XCTAssertFalse(matchingLabels.isEmpty,
                       "D-14 chameleon — empty priors must surface 'First time working together.' empty-state line (UI-SPEC line 716)")

        // No prior-relationship row identifiers (empty priors).
        let priorRows = all.filter { ($0.accessibilityIdentifier ?? "").hasPrefix("load-detail.verification-basis-sheet.prior-relationships.row.") }
        XCTAssertEqual(priorRows.count, 0,
                       "empty priors → no list rows; the empty-state line is the only rendered child")

        // USDOT row IS present for the carrier (D-09 — carriers always get USDOT).
        XCTAssertNotNil(all.first { $0.accessibilityIdentifier == "load-detail.verification-basis-sheet.usdot-row" },
                        "Carrier role → USDOT row MUST be present (D-09)")
    }
}
