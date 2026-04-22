// validationLedger/Features/Onboarding/Auth/NotAvailableInRegionViewController+Plan09Stub.swift
//
// TEMPORARY STUB — DELETE WHEN PLAN 10 LANDS.
//
// Plan 09 (this plan) ships AuthCoordinator + PhoneEntryVC which reference
// `NotAvailableInRegionViewController` as the D-22 non-US refusal screen.
// The canonical `NotAvailableInRegionViewController.swift` ships in Plan 10
// (sister plan in Wave 3) at
// `validationLedger/Features/Onboarding/Auth/NotAvailableInRegionViewController.swift`.
//
// Both plans land in Wave 3 via separate worktrees that merge into main. To
// let Plan 09's worktree compile standalone, this file declares a minimal
// stub with the same class name. When Plan 10's merge lands, that merge will
// see two files declaring the same class → redefinition error. The resolution
// is to DELETE THIS FILE (Plan 10's canonical file is the source of truth).
//
// The stub intentionally implements the same public init surface the
// PhoneEntryVC uses (`init()`) so the two files have compatible call sites.
// The stub's behavior is a no-op "Not available" screen with zero copy
// (acceptable for the Plan 09 compile gate only — never ships to Release).

import UIKit

public final class NotAvailableInRegionViewController: UIViewController {

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Not available"
        // Minimal placeholder label so the screen isn't blank if it ever
        // renders inside the Plan 09 worktree during manual testing.
        let label = UILabel()
        label.text = "Validation Ledger is currently available only in the United States. (Plan 10 replaces this stub.)"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }
}
