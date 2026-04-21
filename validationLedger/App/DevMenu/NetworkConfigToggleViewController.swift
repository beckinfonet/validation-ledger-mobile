// validationLedger/App/DevMenu/NetworkConfigToggleViewController.swift
// DEBUG-only dev-menu control for flipping NetworkConfig at runtime (NET-03 SC-2 demonstrator).
//
// Tapping a button posts `.devMenuNetworkConfigRequested`; SceneDelegate observes and
// performs a fresh-container root-swap per ADR-0002 — the same mechanism used by the role
// switcher (`SceneDelegate.presentRoot(.role(_:))`) — so no new swap logic is introduced.
//
// D-13: the entire file body is inside `#if DEBUG`, so Release builds compile ZERO bytes
// of this code; `strings build/Release-iphonesimulator/validationLedger.app/validationLedger
// | grep NetworkConfigToggle` must return 0 hits.

#if DEBUG

import UIKit

public extension Notification.Name {
    /// Posted when the DevMenu requests a NetworkConfig change.
    /// userInfo: ["config": NetworkConfig]
    /// Observed by SceneDelegate (#if DEBUG); Release builds cannot observe this.
    static let devMenuNetworkConfigRequested = Notification.Name("DevMenuNetworkConfigRequested")
}

/// NetworkConfig userInfo key — isolated to DEBUG builds.
public enum DevMenuNetworkConfigKey {
    public static let config = "config"
}

final class NetworkConfigToggleViewController: UIViewController {

    private let stack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 16
        s.alignment = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Network Config"
        view.backgroundColor = .systemBackground

        let currentLabel = UILabel()
        currentLabel.numberOfLines = 0
        currentLabel.text = currentStatusText()
        currentLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        currentLabel.textColor = .secondaryLabel

        let mockButton = makeButton(title: "Use Mock (default)", action: #selector(selectMock))
        let liveButton = makeButton(title: "Use Live", action: #selector(selectLive))

        stack.addArrangedSubview(currentLabel)
        stack.addArrangedSubview(mockButton)
        stack.addArrangedSubview(liveButton)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        var cfg = UIButton.Configuration.bordered()
        cfg.title = title
        b.configuration = cfg
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func currentStatusText() -> String {
        let env = Environment.current
        let urlStr = env.apiBaseURL?.absoluteString ?? "nil (PHASE-2-TODO — WR-06)"
        return """
        Env: \(env.name)
        apiBaseURL: \(urlStr)

        Tapping a button posts .devMenuNetworkConfigRequested;
        SceneDelegate root-swaps with a fresh AppContainer
        per ADR-0002 (D-10 abrupt replace).
        """
    }

    @objc private func selectMock() {
        NotificationCenter.default.post(
            name: .devMenuNetworkConfigRequested,
            object: nil,
            userInfo: [DevMenuNetworkConfigKey.config: NetworkConfig.mock]
        )
        // Dismiss the whole DevMenu nav stack — the root-swap replaces rootViewController entirely.
        dismiss(animated: true)
    }

    @objc private func selectLive() {
        guard let baseURL = Environment.current.apiBaseURL else {
            let alert = UIAlertController(
                title: "Cannot switch to live",
                message: "Environment.current.apiBaseURL is nil (PHASE-2-TODO — WR-06). Set a production URL in validationLedger/App/Environment.swift before switching to live mode.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        NotificationCenter.default.post(
            name: .devMenuNetworkConfigRequested,
            object: nil,
            userInfo: [DevMenuNetworkConfigKey.config: NetworkConfig.live(baseURL: baseURL)]
        )
        dismiss(animated: true)
    }
}

#endif
