// validationLedgerTests/Components/RoleAvatarViewSnapshotTests.swift
//
// Phase 9.1 Plan 02 Task 3 — RoleAvatarView snapshot matrix (40 attachments).
//
// === Matrix shape (UI-SPEC § Snapshot Test Matrix → Avatar row) ===
// 5 roles × 4 verification states × 2 size variants = 40 snapshot
// attachments per CI run. Each attachment is keyed by the template
// `"RoleAvatar-<roleRawValue>-<stateRawValue>-<variantToken>"` so the
// human reviewer can scan the Xcode test report and spot-check any
// visual drift (e.g. a future palette refinement, a Pitfall-8 regression
// where the avatar reads as a slab instead of a circle).
//
// === Why attachment-only, no on-disk PNG baseline ===
// VALIDATION.md A1 + Phase 8 08-RESEARCH.md Assumption A2: this project
// uses `UIKitSnapshot.attach(...)` for visual triage in the CI artefact
// bundle, NOT pixel-diff snapshot comparison via swift-snapshot-testing.
// CLAUDE.md "Dependencies: Pre-approved shortlist only" — swift-snapshot-
// testing is not on the list. The attachment-only flow is the locked
// pattern; the human reviewer signs off via Xcode's test navigator.
//
// === Why a single canvas size (80×80pt) ===
// UI-SPEC § Snapshot Test Matrix → Avatar row pins the canvas at 80×80pt.
// Large enough to render the 40pt avatar + the 12pt bottom-right status
// dot's protruding 2pt stroke ring without clipping; the tree variant's
// 32pt avatar centers inside the same canvas with extra padding visible
// (so visual drift between variants is easy to spot side-by-side in the
// test report).
//
// === Why no Dynamic Type variation ===
// The avatar abbreviation is a LITERAL POINT SIZE (NOT Dynamic Type) —
// a deliberate documented exception per UI-SPEC § Accessibility Contract.
// Dynamic Type cannot change this view's rendering, so a single content-
// size category per (role, state, variant) cell is sufficient. (Avatar
// circle scaling with Dynamic Type is deferred per 09.1-CONTEXT.md
// <deferred>.)
//
// === T-08-05 / T-09.1-02 (PII) ===
// Tests construct views with synthetic enum values only — no party names,
// no IDs ever reach the rendered image. CLAUDE.md "Zero PII in analytics
// or crash logs" extended to "zero PII in CI snapshot artefacts."

import XCTest
@testable import validationLedger

final class RoleAvatarViewSnapshotTests: XCTestCase {

    // MARK: - Canvas

    /// Locked canvas size per UI-SPEC § Snapshot Test Matrix → Avatar row.
    /// 80×80pt accommodates the 40pt avatar + the 12pt status dot's 2pt
    /// stroke ring (max extent ~52pt) without clipping.
    private static let canvasSize = CGSize(width: 80, height: 80)

    // MARK: - Helper

    /// Render a single (role, state, variant) cell to a UIImage and attach
    /// it to the running XCTestCase under the locked snapshot-name template.
    private func render(
        role: Role,
        state: VerificationState,
        variant: RoleAvatarView.Variant,
        name: String
    ) {
        let view = RoleAvatarView(role: role, state: state, variant: variant)
        view.bounds = CGRect(origin: .zero, size: Self.canvasSize)
        view.layoutIfNeeded()
        let image = UIKitSnapshot.image(of: view, size: Self.canvasSize)
        UIKitSnapshot.attach(image, name: name, to: self)
    }

    // MARK: - Shipper × 4 states × 2 variants (8 attachments)

    func test_shipper_verified_strip_rendersExpected() {
        render(role: .shipper, state: .verified, variant: .strip,
               name: "RoleAvatar-shipper-verified-strip")
    }

    func test_shipper_pending_strip_rendersExpected() {
        render(role: .shipper, state: .pending, variant: .strip,
               name: "RoleAvatar-shipper-pending-strip")
    }

    func test_shipper_unverified_strip_rendersExpected() {
        render(role: .shipper, state: .unverified, variant: .strip,
               name: "RoleAvatar-shipper-unverified-strip")
    }

    func test_shipper_flagged_strip_rendersExpected() {
        render(role: .shipper, state: .flagged, variant: .strip,
               name: "RoleAvatar-shipper-flagged-strip")
    }

    func test_shipper_verified_tree_rendersExpected() {
        render(role: .shipper, state: .verified, variant: .tree,
               name: "RoleAvatar-shipper-verified-tree")
    }

    func test_shipper_pending_tree_rendersExpected() {
        render(role: .shipper, state: .pending, variant: .tree,
               name: "RoleAvatar-shipper-pending-tree")
    }

    func test_shipper_unverified_tree_rendersExpected() {
        render(role: .shipper, state: .unverified, variant: .tree,
               name: "RoleAvatar-shipper-unverified-tree")
    }

    func test_shipper_flagged_tree_rendersExpected() {
        render(role: .shipper, state: .flagged, variant: .tree,
               name: "RoleAvatar-shipper-flagged-tree")
    }

    // MARK: - Broker × 4 states × 2 variants (8 attachments)

    func test_broker_verified_strip_rendersExpected() {
        render(role: .broker, state: .verified, variant: .strip,
               name: "RoleAvatar-broker-verified-strip")
    }

    func test_broker_pending_strip_rendersExpected() {
        render(role: .broker, state: .pending, variant: .strip,
               name: "RoleAvatar-broker-pending-strip")
    }

    func test_broker_unverified_strip_rendersExpected() {
        render(role: .broker, state: .unverified, variant: .strip,
               name: "RoleAvatar-broker-unverified-strip")
    }

    func test_broker_flagged_strip_rendersExpected() {
        render(role: .broker, state: .flagged, variant: .strip,
               name: "RoleAvatar-broker-flagged-strip")
    }

    func test_broker_verified_tree_rendersExpected() {
        render(role: .broker, state: .verified, variant: .tree,
               name: "RoleAvatar-broker-verified-tree")
    }

    func test_broker_pending_tree_rendersExpected() {
        render(role: .broker, state: .pending, variant: .tree,
               name: "RoleAvatar-broker-pending-tree")
    }

    func test_broker_unverified_tree_rendersExpected() {
        render(role: .broker, state: .unverified, variant: .tree,
               name: "RoleAvatar-broker-unverified-tree")
    }

    func test_broker_flagged_tree_rendersExpected() {
        render(role: .broker, state: .flagged, variant: .tree,
               name: "RoleAvatar-broker-flagged-tree")
    }

    // MARK: - Carrier × 4 states × 2 variants (8 attachments)

    func test_carrier_verified_strip_rendersExpected() {
        render(role: .carrier, state: .verified, variant: .strip,
               name: "RoleAvatar-carrier-verified-strip")
    }

    func test_carrier_pending_strip_rendersExpected() {
        render(role: .carrier, state: .pending, variant: .strip,
               name: "RoleAvatar-carrier-pending-strip")
    }

    func test_carrier_unverified_strip_rendersExpected() {
        render(role: .carrier, state: .unverified, variant: .strip,
               name: "RoleAvatar-carrier-unverified-strip")
    }

    func test_carrier_flagged_strip_rendersExpected() {
        render(role: .carrier, state: .flagged, variant: .strip,
               name: "RoleAvatar-carrier-flagged-strip")
    }

    func test_carrier_verified_tree_rendersExpected() {
        render(role: .carrier, state: .verified, variant: .tree,
               name: "RoleAvatar-carrier-verified-tree")
    }

    func test_carrier_pending_tree_rendersExpected() {
        render(role: .carrier, state: .pending, variant: .tree,
               name: "RoleAvatar-carrier-pending-tree")
    }

    func test_carrier_unverified_tree_rendersExpected() {
        render(role: .carrier, state: .unverified, variant: .tree,
               name: "RoleAvatar-carrier-unverified-tree")
    }

    func test_carrier_flagged_tree_rendersExpected() {
        render(role: .carrier, state: .flagged, variant: .tree,
               name: "RoleAvatar-carrier-flagged-tree")
    }

    // MARK: - Dispatch × 4 states × 2 variants (8 attachments)

    func test_dispatch_verified_strip_rendersExpected() {
        render(role: .dispatch, state: .verified, variant: .strip,
               name: "RoleAvatar-dispatch-verified-strip")
    }

    func test_dispatch_pending_strip_rendersExpected() {
        render(role: .dispatch, state: .pending, variant: .strip,
               name: "RoleAvatar-dispatch-pending-strip")
    }

    func test_dispatch_unverified_strip_rendersExpected() {
        render(role: .dispatch, state: .unverified, variant: .strip,
               name: "RoleAvatar-dispatch-unverified-strip")
    }

    func test_dispatch_flagged_strip_rendersExpected() {
        render(role: .dispatch, state: .flagged, variant: .strip,
               name: "RoleAvatar-dispatch-flagged-strip")
    }

    func test_dispatch_verified_tree_rendersExpected() {
        render(role: .dispatch, state: .verified, variant: .tree,
               name: "RoleAvatar-dispatch-verified-tree")
    }

    func test_dispatch_pending_tree_rendersExpected() {
        render(role: .dispatch, state: .pending, variant: .tree,
               name: "RoleAvatar-dispatch-pending-tree")
    }

    func test_dispatch_unverified_tree_rendersExpected() {
        render(role: .dispatch, state: .unverified, variant: .tree,
               name: "RoleAvatar-dispatch-unverified-tree")
    }

    func test_dispatch_flagged_tree_rendersExpected() {
        render(role: .dispatch, state: .flagged, variant: .tree,
               name: "RoleAvatar-dispatch-flagged-tree")
    }

    // MARK: - Factoring × 4 states × 2 variants (8 attachments)

    func test_factoring_verified_strip_rendersExpected() {
        render(role: .factoring, state: .verified, variant: .strip,
               name: "RoleAvatar-factoring-verified-strip")
    }

    func test_factoring_pending_strip_rendersExpected() {
        render(role: .factoring, state: .pending, variant: .strip,
               name: "RoleAvatar-factoring-pending-strip")
    }

    func test_factoring_unverified_strip_rendersExpected() {
        render(role: .factoring, state: .unverified, variant: .strip,
               name: "RoleAvatar-factoring-unverified-strip")
    }

    func test_factoring_flagged_strip_rendersExpected() {
        render(role: .factoring, state: .flagged, variant: .strip,
               name: "RoleAvatar-factoring-flagged-strip")
    }

    func test_factoring_verified_tree_rendersExpected() {
        render(role: .factoring, state: .verified, variant: .tree,
               name: "RoleAvatar-factoring-verified-tree")
    }

    func test_factoring_pending_tree_rendersExpected() {
        render(role: .factoring, state: .pending, variant: .tree,
               name: "RoleAvatar-factoring-pending-tree")
    }

    func test_factoring_unverified_tree_rendersExpected() {
        render(role: .factoring, state: .unverified, variant: .tree,
               name: "RoleAvatar-factoring-unverified-tree")
    }

    func test_factoring_flagged_tree_rendersExpected() {
        render(role: .factoring, state: .flagged, variant: .tree,
               name: "RoleAvatar-factoring-flagged-tree")
    }
}
