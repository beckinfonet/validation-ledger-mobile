// validationLedgerTests/KYC/KYCStatusViewControllerBackButtonTests.swift
// Requirement: debug session `kyc-status-under-review-trap` — Root Cause A.
//
// The KYC status screen is terminal-by-design: post-submit (and from the
// role-shell Profile re-entry) it is the SOLE escape via the D-14 Sign-out
// affordance — no other nav affordance is allowed. The fix is the one-line
// `navigationItem.hidesBackButton = true` in `KYCStatusViewController.viewDidLoad`,
// mirroring `NotAvailableInRegionViewController.swift:23` (T-03-10-05).
//
// This is a regression test for that contract. The test instantiates the VC
// with real (test-support) collaborators, drives `viewDidLoad` via
// `loadViewIfNeeded()`, and asserts `navigationItem.hidesBackButton == true`.
// Mirrors the `loadViewIfNeeded() / view.bounds / view.layoutIfNeeded()`
// pattern in `VerificationBasisSheetViewControllerSnapshotTests`.

import Testing
import UIKit
@testable import validationLedger

@Suite("KYCStatusViewController — terminal-screen contract (D-14)", .serialized)
@MainActor
struct KYCStatusViewControllerBackButtonTests {

    @Test("viewDidLoad sets navigationItem.hidesBackButton = true — terminal screen, no back path")
    func hidesBackButtonAfterViewDidLoad() throws {
        let store = try KYCUploaderTestSupport.makeStore()
        let keychain = KeychainStore(
            service: "vl.test.kyc.status.backbutton.\(UUID().uuidString)"
        )
        let viewModel = KYCStatusViewModel(
            apiClient: KYCUploaderTestSupport.makeClient(),
            store: store,
            keychain: keychain,
            logger: KYCUploaderTestSupport.makeLogger()
        )
        let vc = KYCStatusViewController(viewModel: viewModel)

        // `loadViewIfNeeded()` drives `viewDidLoad`.
        vc.loadViewIfNeeded()

        // The terminal-screen contract: the user MUST NOT be able to nav-back
        // into the Review screen and bounce-loop Submit. Verified by the
        // hidesBackButton flag (mirrors NotAvailableInRegionViewController:23).
        #expect(
            vc.navigationItem.hidesBackButton,
            "KYCStatusViewController must hide the system back button — D-14 says the only intended escape is the Sign-out affordance."
        )
    }
}
