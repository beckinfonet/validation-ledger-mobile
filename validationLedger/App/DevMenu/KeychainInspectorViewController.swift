// validationLedger/App/DevMenu/KeychainInspectorViewController.swift
// DEBUG-only. Lists every Keychain item under the app's service +
// access group. Used to visually prove that FOUND-02 wipe ran on first
// install (0 items on a fresh install post-launch).

#if DEBUG

import UIKit

final class KeychainInspectorViewController: UITableViewController {
    private unowned let store: KeychainStore
    private var items: [(KeychainKey, Data)] = []

    init(store: KeychainStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Keychain Inspector"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refresh)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        refresh()
    }

    @objc private func refresh() {
        do {
            items = try store.enumerateAll()
        } catch {
            items = []
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(items.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        if items.isEmpty {
            cell.textLabel?.text = "(empty — 0 items)"
            cell.detailTextLabel?.text = "If this is a fresh install, FOUND-02 wipe worked."
            cell.textLabel?.textColor = .secondaryLabel
        } else {
            let (key, data) = items[indexPath.row]
            cell.textLabel?.text = key.rawValue
            cell.detailTextLabel?.text = "\(data.count) bytes"
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Items: \(items.count)"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "FOUND-02 verification: install → this screen should show 0 items. Plant a key via set() before delete-reinstall to verify wipe."
    }
}

#endif
