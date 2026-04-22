// validationLedgerTests/Roles/RoleCoordinatorTests.swift
// Phase-1 contract tests for ARCH-06: each of the 5 TabBarController subclasses
// instantiates with the exact D-09 tab inventory (no deviation, no reorder).
// Phase 3 Plan 11 (D-03): tab bars now require a `logoutService` in init so the
// avatar-tap affordance can present ProfileViewController modally. A no-op stub
// satisfies the protocol without exercising the notification-center teardown path.

import Testing
import UIKit
@testable import validationLedger

/// No-op stub — the tab inventory contract tests don't exercise logout, so a minimal
/// stub satisfies the init requirement without pulling in AppContainer or Keychain I/O.
@MainActor
private final class NoOpLogoutService: LogoutService, @unchecked Sendable {
    func logout(reason: LogoutReason) async {
        // Intentionally empty — tab-inventory tests never invoke logout.
    }
}

@Suite("RoleCoordinator — 5 TabBarController contract (ARCH-06, D-07..D-09)")
@MainActor
struct RoleCoordinatorTests {
    private func stubLogout() -> any LogoutService { NoOpLogoutService() }

    @Test("ShipperTabBarController has tabs: Loads, Brokers, BOL, Assistant")
    func shipperTabs() {
        let vc = ShipperTabBarController(logoutService: stubLogout())
        vc.loadViewIfNeeded()
        let titles: [String?] = (vc.viewControllers ?? []).map { $0.title }
        #expect(titles == ["Loads", "Brokers", "BOL", "Assistant"])
        #expect(vc.role == .shipper)
    }

    @Test("BrokerTabBarController has tabs: Loads, Carriers, Network, Assistant")
    func brokerTabs() {
        let vc = BrokerTabBarController(logoutService: stubLogout())
        vc.loadViewIfNeeded()
        let titles: [String?] = (vc.viewControllers ?? []).map { $0.title }
        #expect(titles == ["Loads", "Carriers", "Network", "Assistant"])
        #expect(vc.role == .broker)
    }

    @Test("CarrierTabBarController has tabs: Loads, Drivers, Documents, Assistant")
    func carrierTabs() {
        let vc = CarrierTabBarController(logoutService: stubLogout())
        vc.loadViewIfNeeded()
        let titles: [String?] = (vc.viewControllers ?? []).map { $0.title }
        #expect(titles == ["Loads", "Drivers", "Documents", "Assistant"])
        #expect(vc.role == .carrier)
    }

    @Test("DispatchTabBarController has tabs: Loads, Fleet, Drivers, Assistant")
    func dispatchTabs() {
        let vc = DispatchTabBarController(logoutService: stubLogout())
        vc.loadViewIfNeeded()
        let titles: [String?] = (vc.viewControllers ?? []).map { $0.title }
        #expect(titles == ["Loads", "Fleet", "Drivers", "Assistant"])
        #expect(vc.role == .dispatch)
    }

    @Test("FactoringTabBarController has tabs: Invoices, Carriers, Chain, Assistant")
    func factoringTabs() {
        let vc = FactoringTabBarController(logoutService: stubLogout())
        vc.loadViewIfNeeded()
        let titles: [String?] = (vc.viewControllers ?? []).map { $0.title }
        #expect(titles == ["Invoices", "Carriers", "Chain", "Assistant"])
        #expect(vc.role == .factoring)
    }

    @Test("Role.allCases has all 5 roles in TechStack.md §4 order")
    func roleOrder() {
        #expect(Role.allCases == [.shipper, .broker, .carrier, .dispatch, .factoring])
    }
}
