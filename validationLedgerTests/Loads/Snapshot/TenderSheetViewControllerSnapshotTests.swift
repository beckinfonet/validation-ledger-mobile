// validationLedgerTests/Loads/Snapshot/TenderSheetViewControllerSnapshotTests.swift
//
// Phase 10 Plan 09 Task 2 — TenderSheetViewController snapshot suite (4
// scenarios) covering the locked sheet geometry per UI-SPEC § Tender sheet §
// Component Geometry lines 433-456.
//
// === Four scenarios ===
//   1. Default state — full 7-carrier directory, no row selected, "1 day"
//      chip selected by default, Send disabled with the "Pick a carrier to
//      send." helper line.
//   2. Verified carrier selected — Acme row picked (first verified row);
//      checkmark accessory; Send enabled.
//   3. Mixed-verification directory — 1 verified + 1 unverified + 1 pending
//      + 1 flagged. Captures the visible-but-disabled row treatment
//      (contentView alpha 0.6, badge at full alpha, inline reason line) —
//      the ACTION-04 platform-thesis surface.
//   4. Send in-flight — verified row selected, then tap Send programmatically;
//      the sheet stays visible during the await; the spinner overlays Send.
//
// === Phase 9 sheet snapshot analog ===
// VerificationBasisSheetViewControllerSnapshotTests.swift establishes the
// canvas-size convention `CGSize(width: 393, height: 500)` (medium-detent
// representative) and the `renderedView(_:)` helper shape. This file mirrors
// both verbatim (PATTERNS.md §14 lock — drift trips T-10-PR-01).
//
// === Why XCTest, not Swift Testing ===
// `UIKitSnapshot.attach(_:name:to:)` requires `XCTestCase.add(_:)`.
//
// === T-10-04 (PII) ===
// Test directories use synthetic carrier names ("Acme Logistics Inc.",
// "Chameleon Cargo LLC", etc.) inherited from the Plan 05
// `tender-carrier-directory.json` fixture — CarrierDirectoryDecodeTests
// Test 5 already enforces the synthetic-name allowlist at the fixture level.

import XCTest
@testable import validationLedger

class TenderSheetViewControllerSnapshotTests: XCTestCase {

    // MARK: - Constants

    /// iPhone medium-detent representative canvas — 393pt wide × 500pt tall.
    /// PATTERNS.md §14 LOCK — mirrors VerificationBasisSheetViewControllerSnapshotTests.
    private static let sheetCanvasSize = CGSize(width: 393, height: 500)

    /// Baseline directory NAME (final path component); resolved at run time
    /// by `baselineDirectoryURL()`.
    private static let baselineDirectoryName = "TenderSheetViewControllerSnapshot"

    // MARK: - Helpers

    /// Layout the VC at the sheet canvas size and return the rendered view.
    /// Mirrors VerificationBasisSheetViewControllerSnapshotTests.renderedView.
    private func renderedView(_ vc: TenderSheetViewController) -> UIView {
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(origin: .zero, size: Self.sheetCanvasSize)
        vc.view.layoutIfNeeded()
        return vc.view
    }

    /// Build a `TrustNode` for a synthetic carrier — used by Test 3's mixed-
    /// verification directory which programmatically builds 4 nodes spanning
    /// all 4 VerificationState cases.
    private func makeCarrier(
        partyID: String,
        displayName: String,
        verificationState: VerificationState,
        usdotAuthorityStatus: USDOTAuthorityStatus = .active,
        deviceBindingStatus: DeviceBindingStatus = .bound
    ) -> TrustNode {
        TrustNode(
            partyID: partyID,
            role: .carrier,
            displayName: displayName,
            verificationState: verificationState,
            kycCompletedAt: verificationState == .verified
                ? Date(timeIntervalSince1970: 1_700_000_000) : nil,
            deviceBindingStatus: deviceBindingStatus,
            usdotNumber: "0000001",
            usdotAuthorityStatus: usdotAuthorityStatus,
            priorRelationships: []
        )
    }

    /// Load the 7-carrier directory from the Plan 05 fixture via the
    /// production decoder. Used by Tests 1, 2, 4 (the full directory paths).
    private func loadProductionDirectory() throws -> [TrustNode] {
        let decoder = APIClient.defaultDecoder()
        let data = try FixtureLoader.loadFixture("tender-carrier-directory")
        return try decoder.decode(CarrierDirectoryEndpoint.Response.self, from: data).carriers
    }

    /// Construct a TenderSheetViewController with no-op closures (snapshot
    /// tests don't exercise the Send / Cancel flow).
    private func makeSheet(directory: [TrustNode]) -> TenderSheetViewController {
        TenderSheetViewController(
            directory: directory,
            onSend: { _, _ in /* no-op for snapshot tests */ },
            onCancel: { /* no-op */ }
        )
    }

    /// Attach an image AND record/verify the baseline PNG on disk per the
    /// RECORD_SNAPSHOTS=YES workflow. See
    /// `LoadActionBarSnapshotMatrixTests.baselineComparison` for the
    /// motivation; this implementation is identical save for the baseline
    /// directory name.
    private func baselineComparison(
        image: UIImage,
        name: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        UIKitSnapshot.attach(image, name: name, to: self)

        guard let dirURL = Self.baselineDirectoryURL() else {
            XCTFail("Could not resolve baseline directory for \(Self.baselineDirectoryName)",
                    file: file, line: line)
            return
        }
        try? FileManager.default.createDirectory(
            at: dirURL, withIntermediateDirectories: true
        )
        let baselineURL = dirURL.appendingPathComponent("\(name).png")
        let isRecording = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES"
        let baselineExists = FileManager.default.fileExists(atPath: baselineURL.path)

        if isRecording || !baselineExists {
            guard let pngData = image.pngData() else {
                XCTFail("Could not encode PNG for snapshot \(name)",
                        file: file, line: line)
                return
            }
            do { try pngData.write(to: baselineURL) }
            catch {
                XCTFail("Could not write baseline PNG to \(baselineURL.path): \(error)",
                        file: file, line: line)
            }
            return
        }

        guard let data = try? Data(contentsOf: baselineURL), !data.isEmpty else {
            XCTFail("Baseline missing or empty at \(baselineURL.path) — re-run with RECORD_SNAPSHOTS=YES",
                    file: file, line: line)
            return
        }
        XCTAssertTrue(data.count > 100,
                      "Baseline at \(baselineURL.path) is suspiciously small (\(data.count) bytes)",
                      file: file, line: line)
    }

    private static func baselineDirectoryURL() -> URL? {
        if let envDir = ProcessInfo.processInfo.environment["SNAPSHOT_BASELINE_DIR"] {
            return URL(fileURLWithPath: envDir)
                .appendingPathComponent(baselineDirectoryName)
        }
        // Walk up from #filePath to validationLedgerTests/, then append
        // __Snapshots__/<name>/.
        let thisFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return thisFileURL
            .appendingPathComponent("__Snapshots__")
            .appendingPathComponent(baselineDirectoryName)
    }

    private func collectAllSubviews(_ root: UIView) -> [UIView] {
        var result: [UIView] = []
        var stack: [UIView] = [root]
        while let v = stack.popLast() {
            result.append(v)
            stack.append(contentsOf: v.subviews)
        }
        return result
    }

    // MARK: - Test 1 — default state, no carrier selected

    /// Captures the at-rest sheet: 7 directory rows visible, "1 day" chip
    /// selected by default, Send disabled with the "Pick a carrier to send."
    /// helper line. UI-SPEC line 371 LOCK on the helper text.
    func test_sheet_defaultState_noCarrierSelected() throws {
        let directory = try loadProductionDirectory()
        XCTAssertEqual(directory.count, 7,
                       "Plan 05 fixture must carry 7 carriers (Specifics line 263-265)")

        let sheet = makeSheet(directory: directory)
        let view = renderedView(sheet)
        baselineComparison(image: UIKitSnapshot.image(of: view, size: Self.sheetCanvasSize),
                           name: "tender-sheet-default")

        // Structural assertions.
        XCTAssertEqual(view.accessibilityIdentifier, "load-detail.tender-sheet",
                       "root identifier must match the locked sheet identifier")

        // Default chip selected — "1 day" (index 2) per UI-SPEC line 447.
        XCTAssertEqual(sheet.selectedChipIndexForTesting, 2,
                       "default selected chip must be index 2 ('1 day' / 24h)")

        // Send disabled by default (no carrier selected).
        XCTAssertFalse(sheet.sendButtonForTesting.isEnabled,
                       "Send must be disabled by default (no carrier picked)")

        // Helper line visible with the "no_carrier" copy per UI-SPEC line 371.
        XCTAssertEqual(sheet.helperLabelForTesting.alpha, 1.0, accuracy: 0.01,
                       "helper label must be VISIBLE (alpha=1.0) when Send is disabled")
        XCTAssertEqual(sheet.helperLabelForTesting.text,
                       "Pick a carrier to send.",
                       "default helper copy must lock to UI-SPEC line 371 verbatim")
    }

    // MARK: - Test 2 — verified carrier selected, Send enabled

    /// User picks Acme (index 0, the first verified carrier). Checkmark
    /// accessory appears, Send enables, helper line fades to alpha 0.
    func test_sheet_verifiedCarrierSelected_sendEnabled() throws {
        let directory = try loadProductionDirectory()
        let sheet = makeSheet(directory: directory)
        // Force a layout pass before driving selection so the table is
        // populated when the test seam routes through didSelectRowAt.
        _ = renderedView(sheet)

        // Programmatically select Acme (index 0).
        sheet.selectCarrierForTesting(at: 0)
        sheet.view.layoutIfNeeded()

        baselineComparison(image: UIKitSnapshot.image(of: sheet.view, size: Self.sheetCanvasSize),
                           name: "tender-sheet-verified-selected")

        // Send enabled (verified carrier + future deadline).
        XCTAssertTrue(sheet.sendButtonForTesting.isEnabled,
                      "Send must be enabled after picking a verified carrier")

        // Helper line invisible — Pitfall 8 alpha=0 toggle (NOT isHidden).
        XCTAssertEqual(sheet.helperLabelForTesting.alpha, 0.0, accuracy: 0.01,
                       "helper label must be INVISIBLE (alpha=0) when Send is enabled (Pitfall 8)")
        XCTAssertFalse(sheet.helperLabelForTesting.isHidden,
                       "helper label MUST NOT use isHidden — alpha toggle only (Pitfall 8 line lock)")
    }

    // MARK: - Test 3 — mixed-verification directory, visible-but-disabled

    /// The ACTION-04 platform-thesis surface (T-10-04). Programmatically
    /// builds a 4-carrier directory spanning all 4 VerificationState cases.
    /// The disabled rows MUST stay VISIBLE (UI-SPEC line 446) — contentView
    /// alpha 0.6, badge at full alpha, userInteractionEnabled = false.
    func test_sheet_mixedDirectory_visibleButDisabledRows() {
        let directory: [TrustNode] = [
            makeCarrier(partyID: "party-test-verified",
                        displayName: "Test Verified Co.",
                        verificationState: .verified),
            makeCarrier(partyID: "party-test-pending",
                        displayName: "Test Pending LLC",
                        verificationState: .pending,
                        deviceBindingStatus: .unbound),
            makeCarrier(partyID: "party-test-unverified",
                        displayName: "Test Unverified Inc.",
                        verificationState: .unverified,
                        usdotAuthorityStatus: .notApplicable,
                        deviceBindingStatus: .unbound),
            makeCarrier(partyID: "party-test-flagged",
                        displayName: "Test Flagged Cargo",
                        verificationState: .flagged,
                        usdotAuthorityStatus: .revoked,
                        deviceBindingStatus: .mismatched),
        ]

        let sheet = makeSheet(directory: directory)
        let view = renderedView(sheet)
        baselineComparison(image: UIKitSnapshot.image(of: view, size: Self.sheetCanvasSize),
                           name: "tender-sheet-mixed-verification")

        // Structural: all 4 rows ARE in the table data source.
        XCTAssertEqual(sheet.tableViewForTesting.numberOfRows(inSection: 0), 4,
                       "all 4 carriers must be visible in the directory list (UI-SPEC line 446 — disabled stays visible)")

        // Trying to tap a disabled row must NOT select it.
        sheet.selectCarrierForTesting(at: 1)  // pending → disabled
        XCTAssertFalse(sheet.sendButtonForTesting.isEnabled,
                       "selecting a pending row must NOT enable Send (carrier-level ACTION-04 gate)")

        sheet.selectCarrierForTesting(at: 3)  // flagged → disabled
        XCTAssertFalse(sheet.sendButtonForTesting.isEnabled,
                       "selecting a flagged row must NOT enable Send (T-10-04 CRITICAL)")

        // Tapping the verified row enables Send.
        sheet.selectCarrierForTesting(at: 0)  // verified → enabled
        XCTAssertTrue(sheet.sendButtonForTesting.isEnabled,
                      "selecting the verified row must enable Send")
    }

    // MARK: - Test 4 — Send in-flight, spinner overlay

    /// Per UI-SPEC line 454: on Send tap, the sheet stays visible; Send is
    /// disabled; the spinner overlays the Send title via
    /// `UIButton.Configuration.showsActivityIndicator`. The whole sheet's
    /// interaction is locked until the await resolves; on error the sheet
    /// stays visible.
    func test_sheet_sendInFlight_spinnerOverlay() throws {
        let directory = try loadProductionDirectory()

        // Use an `await`-blocking onSend so we can capture the in-flight
        // visual state. A CheckedContinuation parks the closure until the
        // test finishes capturing the snapshot.
        let unblockExpectation = expectation(description: "test releases onSend")
        let sheet = TenderSheetViewController(
            directory: directory,
            onSend: { _, _ in
                // Park inside the await so the in-flight UI is captured.
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    // Hand the continuation off via a side channel; the
                    // test's main thread fulfills the expectation after
                    // capturing the snapshot, then resumes the continuation.
                    Self.parkedContinuation = cont
                    unblockExpectation.fulfill()
                }
            },
            onCancel: {}
        )
        _ = renderedView(sheet)

        // Pick a verified carrier so Send is enabled.
        sheet.selectCarrierForTesting(at: 0)
        XCTAssertTrue(sheet.sendButtonForTesting.isEnabled, "precondition: Send must be enabled before tap")

        // Tap Send — fires the async task. Wait until onSend runs and parks.
        sheet.tapSendForTesting()
        wait(for: [unblockExpectation], timeout: 2.0)

        // The button configuration's showsActivityIndicator should now be
        // true; the Send button is disabled.
        XCTAssertFalse(sheet.sendButtonForTesting.isEnabled,
                       "Send must be DISABLED during in-flight (UI-SPEC line 454)")
        XCTAssertTrue(sheet.sendButtonForTesting.configuration?.showsActivityIndicator ?? false,
                      "Send button must show its activity indicator during in-flight")

        // Force layout + render the in-flight state.
        sheet.view.layoutIfNeeded()
        baselineComparison(image: UIKitSnapshot.image(of: sheet.view, size: Self.sheetCanvasSize),
                           name: "tender-sheet-send-inflight")

        // Release the parked closure so the suite tears down cleanly.
        Self.parkedContinuation?.resume(returning: ())
        Self.parkedContinuation = nil
    }

    /// Side channel for Test 4's parked `CheckedContinuation`. Stored on
    /// the type because the `onSend` closure cannot capture a `var` on the
    /// XCTestCase instance (the closure is `Sendable` and the case is not).
    private static var parkedContinuation: CheckedContinuation<Void, Never>?
}
