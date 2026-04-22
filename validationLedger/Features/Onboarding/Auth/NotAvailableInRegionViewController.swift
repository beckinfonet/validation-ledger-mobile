// validationLedger/Features/Onboarding/Auth/NotAvailableInRegionViewController.swift
// Phase 3 D-22 / GEO-02: terminal screen pushed when CountryGate confirms non-US.
// No path back to phone-entry from here — user must close the app and try in-region.
//
// Plan 10 canonical file. Supersedes Plan 09's temporary stub at
// `NotAvailableInRegionViewController+Plan09Stub.swift` (Plan 10 deletes that file
// as part of this plan's landing).

import UIKit

final class NotAvailableInRegionViewController: UIViewController {

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Not available"
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true  // terminal — no back path (T-03-10-05 mitigation)

        let titleLabel = UILabel()
        titleLabel.text = "Service area: United States"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = "Validation Ledger is currently available only in the United States."
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }
}
