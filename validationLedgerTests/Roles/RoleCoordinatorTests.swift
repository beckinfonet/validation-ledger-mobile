// validationLedgerTests/Roles/RoleCoordinatorTests.swift
// Phase-1 contract tests for ARCH-06: each of the 5 TabBarController subclasses
// instantiates with the exact D-09 tab inventory (no deviation, no reorder).

import Testing
import UIKit
@testable import validationLedger

@Suite("RoleCoordinator — 5 TabBarController contract (ARCH-06, D-07..D-09)")
@MainActor
struct RoleCoordinatorTests {
    @Test("ShipperTabBarController has tabs: Loads, Brokers, BOL, Assistant")
    func shipperTabs() {
        let vc = ShipperTabBarController()
        vc.loadViewIfNeeded()
        let titles = (vc.viewControllers ?? []).map { $0.title }
        #expect(titles == ["Loads", "Brokers", "BOL", "Assistant"])
        #expect(vc.role == .shipper)
    }

    @Test("BrokerTabBarController has tabs: Loads, Carriers, Network, Assistant")
    func brokerTabs() {
        let vc = BrokerTabBarController()
        vc.loadViewIfNeeded()
        let titles = (vc.viewControllers ?? []).map { $0.title }
        #expect(titles == ["Loads", "Carriers", "Network", "Assistant"])
        #expect(vc.role == .broker)
    }

    @Test("CarrierTabBarController has tabs: Loads, Drivers, Documents, Assistant")
    func carrierTabs() {
        let vc = CarrierTabBarController()
        vc.loadViewIfNeeded()
        let titles = (vc.viewControllers ?? []).map { $0.title }
        #expect(titles == ["Loads", "Drivers", "Documents", "Assistant"])
        #expect(vc.role == .carrier)
    }

    @Test("DispatchTabBarController has tabs: Loads, Fleet, Drivers, Assistant")
    func dispatchTabs() {
        let vc = DispatchTabBarController()
        vc.loadViewIfNeeded()
        let titles = (vc.viewControllers ?? []).map { $0.title }
        #expect(titles == ["Loads", "Fleet", "Drivers", "Assistant"])
        #expect(vc.role == .dispatch)
    }

    @Test("FactoringTabBarController has tabs: Invoices, Carriers, Chain, Assistant")
    func factoringTabs() {
        let vc = FactoringTabBarController()
        vc.loadViewIfNeeded()
        let titles = (vc.viewControllers ?? []).map { $0.title }
        #expect(titles == ["Invoices", "Carriers", "Chain", "Assistant"])
        #expect(vc.role == .factoring)
    }

    @Test("Role.allCases has all 5 roles in TechStack.md §4 order")
    func roleOrder() {
        #expect(Role.allCases == [.shipper, .broker, .carrier, .dispatch, .factoring])
    }
}
