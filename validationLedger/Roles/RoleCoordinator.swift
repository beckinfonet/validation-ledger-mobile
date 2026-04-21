// validationLedger/Roles/RoleCoordinator.swift
// ARCH-06: protocol that each role's root coordinator conforms to.
// Concrete role coordinators live in later phases; Phase 1 ships only the
// UITabBarController subclasses (one per role) because that is what the
// DevMenu swap (D-07) needs to demonstrate end-to-end.
//
// SceneDelegate (Plan 05) uses this protocol to present a new root when
// the active role changes; the abrupt-replace semantics are ADR 0002.

import UIKit

public protocol RoleCoordinator: AnyObject {
    var role: Role { get }
    /// The root view controller installed as window.rootViewController.
    var rootViewController: UIViewController { get }
}
