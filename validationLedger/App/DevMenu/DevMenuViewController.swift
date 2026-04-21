// validationLedger/App/DevMenu/DevMenuViewController.swift
// DEBUG-only composition-root concern. Presents a table view with 3 sections:
//   1. Role Switcher (D-07)
//   2. Keychain Inspector (D-11 / FOUND-02 visual verification)
//   3. Log Viewer (LOG-03)
//
// D-13: entire file body is wrapped in #if DEBUG so Release builds compile
// zero bytes of DevMenu code — `strings` of a Release .app binary returns
// empty for DevMenu|RoleSwitcher|KeychainInspector|LogViewer.

#if DEBUG

import UIKit

final class DevMenuViewController: UITableViewController {
    private unowned let container: AppContainer
    private unowned let appCoordinator: AppCoordinator

    private enum Row: Int, CaseIterable {
        case roleSwitcher
        case keychainInspector
        case logViewer

        var title: String {
            switch self {
            case .roleSwitcher:      return "Role Switcher"
            case .keychainInspector: return "Keychain Inspector"
            case .logViewer:         return "Log Viewer (OSLogStore)"
            }
        }

        var subtitle: String {
            switch self {
            case .roleSwitcher:      return "Swap to any of the 5 roles (D-07)"
            case .keychainInspector: return "Enumerate Keychain items under app service (D-11)"
            case .logViewer:         return "Last 15 min of OSLog entries (LOG-03)"
            }
        }
    }

    init(container: AppContainer, appCoordinator: AppCoordinator) {
        self.container = container
        self.appCoordinator = appCoordinator
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "DevMenu"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissSelf)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    @objc private func dismissSelf() { dismiss(animated: true) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let row = Row(rawValue: indexPath.row)!
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.subtitle
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = Row(rawValue: indexPath.row) else { return }
        switch row {
        case .roleSwitcher:
            let vc = RoleSwitcherViewController { [weak self] role in
                self?.dismiss(animated: true) {
                    // Ask the parent SceneDelegate to swap root. We access it via
                    // the window scene to avoid coupling through AppCoordinator.
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let sceneDelegate = scene.delegate as? SceneDelegate {
                        sceneDelegate.presentRoot(.role(role))
                    }
                }
            }
            navigationController?.pushViewController(vc, animated: true)

        case .keychainInspector:
            let vc = KeychainInspectorViewController(store: container.keychainStore)
            navigationController?.pushViewController(vc, animated: true)

        case .logViewer:
            let vc = LogViewerViewController()
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

#endif
