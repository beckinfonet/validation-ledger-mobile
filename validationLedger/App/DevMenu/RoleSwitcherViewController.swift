// validationLedger/App/DevMenu/RoleSwitcherViewController.swift
// DEBUG-only. Presents a table of 5 roles; selection triggers D-10 root swap.

#if DEBUG

import UIKit

final class RoleSwitcherViewController: UITableViewController {
    private let onSelect: (Role) -> Void

    init(onSelect: @escaping (Role) -> Void) {
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Role Switcher"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Role.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "cell")
        cell.textLabel?.text = Role.allCases[indexPath.row].displayName
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let role = Role.allCases[indexPath.row]
        onSelect(role)
    }
}

#endif
