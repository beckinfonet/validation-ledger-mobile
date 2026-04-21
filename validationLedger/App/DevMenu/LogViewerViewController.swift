// validationLedger/App/DevMenu/LogViewerViewController.swift
// DEBUG-only per LOG-03. Pulls last 15 min of OSLog entries via LogExporter.
// Entries are already scrubbed (PIIScrubber ran before OSLog.log).

#if DEBUG

import UIKit

final class LogViewerViewController: UIViewController {
    private let textView = UITextView()
    private let exporter = LogExporter()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Log Viewer (15 min)"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(reload)
        )

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .label
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        reload()
    }

    @objc private func reload() {
        do {
            let entries = try exporter.fetch(since: 15 * 60)
            if entries.isEmpty {
                textView.text = "(no log entries in last 15 min)"
            } else {
                textView.text = entries.joined(separator: "\n")
            }
        } catch {
            textView.text = "Log fetch failed: \(error)"
        }
    }
}

#endif
