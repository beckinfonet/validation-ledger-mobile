// validationLedgerTests/Loads/LoadDetailViewControllerDebug2DOverrideTests.swift
//
// Phase 9.1 Plan 05 Task 2 (suite C) — assert D-12 + D-14 invariants on the
// DEBUG-only -Mock2DTrustGraphOnIPhone launch flag.
//
// === Locked test surface ===
//   (i)  test_debug2DGraphOverride_launchFlagLiteral — the launch-flag
//        literal equals exactly "-Mock2DTrustGraphOnIPhone" (D-12).
//   (ii) test_debug2DGraphOverride_offByDefault_inUnitTestProcess — the
//        flag is OFF by default in the unit-test process (D-14).
//
// Mirrors the MockDefaultFixtures.verifiedKYCStatusOverrideActive default-off
// unit-test shape (-MockKYCStatusVerified precedent locked at 2026-05-20).
//
// === Why XCTest, not Swift Testing ===
// Matches the in-repo convention for VC + launch-flag tests.
//
// === #if DEBUG ===
// The Debug2DGraphOverride enum lives inside a `#if DEBUG ... #endif` block
// in LoadDetailViewController.swift; this entire test file is also wrapped
// in `#if DEBUG ... #endif` so the test target compiles in both DEBUG and
// Release CI configurations.

#if DEBUG
import XCTest
@testable import validationLedger

final class LoadDetailViewControllerDebug2DOverrideTests: XCTestCase {

    // MARK: - (i) launch-flag literal LOCKED — D-12

    func test_debug2DGraphOverride_launchFlagLiteral() {
        XCTAssertEqual(
            Debug2DGraphOverride.launchFlag,
            "-Mock2DTrustGraphOnIPhone",
            "DEBUG 2D-graph override flag literal is locked per D-12. Any rename re-opens the marketing-screenshots contract."
        )
    }

    // MARK: - (ii) default-off in the unit-test process — D-14

    func test_debug2DGraphOverride_offByDefault_inUnitTestProcess() {
        XCTAssertFalse(
            Debug2DGraphOverride.isActive,
            "Flag MUST default to OFF in the unit-test process — D-14 default-off contract. If this test fails, somebody added -Mock2DTrustGraphOnIPhone to the validationLedgerTests scheme's launch arguments."
        )
    }
}
#endif
