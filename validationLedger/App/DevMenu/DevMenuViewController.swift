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
        case networkConfig  // Phase 2 Plan 07 addition — NET-03 SC-2 demonstrator
        case reattestNow    // Phase 4 Plan 07 addition — D-04 manual re-attestation trigger

        var title: String {
            switch self {
            case .roleSwitcher:      return "Role Switcher"
            case .keychainInspector: return "Keychain Inspector"
            case .logViewer:         return "Log Viewer (OSLogStore)"
            case .networkConfig:     return "Network Config"
            case .reattestNow:       return "Re-attest now"
            }
        }

        var subtitle: String {
            switch self {
            case .roleSwitcher:      return "Swap to any of the 5 roles (D-07)"
            case .keychainInspector: return "Enumerate Keychain items under app service (D-11)"
            case .logViewer:         return "Last 15 min of OSLog entries (LOG-03)"
            case .networkConfig:     return "Toggle mock ↔ live (NET-03)"
            case .reattestNow:       return "Force-rotate App Attest key (D-04 re-attestation test path)"
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

        case .networkConfig:
            // NET-03 SC-2 demonstrator — posts a notification; SceneDelegate observes and
            // performs a root-swap with a fresh AppContainer constructed with the new config.
            let vc = NetworkConfigToggleViewController()
            navigationController?.pushViewController(vc, animated: true)

        case .reattestNow:
            // Phase 4 Plan 07 / D-04 manual re-attestation trigger (DEBUG-only — inherits
            // file-top #if DEBUG gate). Wipes the persisted attestedKeyId (D-04) and
            // re-runs generateKeyIfNeeded which forces the next /device/register to use
            // a freshly-attested key. Presents a UIAlert with the first 16 chars of the
            // new keyId + the AttestationStatus rawValue so the operator can visually
            // confirm rotation. No full keyId is displayed and nothing is logged — DEBUG
            // build is the only place this row exists, but PII discipline still applies.
            Task { @MainActor in
                do {
                    try container.attestationService.clearPersistedKeyId()
                    let (keyId, status) = try await container.attestationService.generateKeyIfNeeded()
                    let prefix = String(keyId.prefix(16))
                    let summary = "D-04 re-attest complete.\nnew keyId prefix: \(prefix)…\nstatus: \(status.rawValue)"
                    let alert = UIAlertController(
                        title: "Re-attested",
                        message: summary,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                } catch {
                    let alert = UIAlertController(
                        title: "Re-attest failed",
                        message: String(describing: error),
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
}

#endif
