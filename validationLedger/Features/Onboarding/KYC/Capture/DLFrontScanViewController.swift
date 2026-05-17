// validationLedger/Features/Onboarding/KYC/Capture/DLFrontScanViewController.swift
// Phase 5 Plan 05 — KYC-03: the driver's-license front DataScanner OCR screen.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md hard constraint). Hosts a
// `VisionKit.DataScannerViewController` as a child VC with the `.text`
// recognized-data type. On a successful scan it extracts name / DL number /
// expiry and bubbles a `DLExtraction` to the coordinator, which pushes the
// read-only confirmation screen (D-05).
//
// === SIMULATOR GATE (RESEARCH Pitfall 1) ===
// `DataScannerViewController` returns `ScanningUnavailable` on the simulator.
// Entry into the scanner surface is gated on
// `DataScannerViewController.isSupported && .isAvailable` — when unavailable the
// screen shows an inline notice instead of trapping. The live OCR is verified
// on the device lane (DLExtractionScannerDeviceTests) + HUMAN-UAT.

import UIKit
import VisionKit

/// The three driver's-license fields extracted from a front-side scan (KYC-03).
/// The uploaded artifact is the captured photo `Data` (GPS-injected), not this
/// text — these fields drive only the D-05 read-only confirmation + format gate.
public struct DLExtraction: Equatable, Sendable {
    public let name: String
    public let dlNumber: String
    public let expiry: String

    public init(name: String, dlNumber: String, expiry: String) {
        self.name = name
        self.dlNumber = dlNumber
        self.expiry = expiry
    }
}

/// The DL-front scanner screen (KYC-03). Hosts `DataScannerViewController`.
final class DLFrontScanViewController: UIViewController {

    /// Fired with the extracted fields when a scan completes. `KYCCoordinator`
    /// wires this to `pushDLFrontExtraction(_:)`.
    var onScanComplete: ((DLExtraction) -> Void)?

    // MARK: - UI components

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.title1
        label.textColor = DS.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-dlfront-instruction"
        return label
    }()

    /// Shown when the scanner surface is unavailable (e.g. the simulator).
    private let unavailableLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.footnote
        label.textColor = DS.Colors.labelSecondary
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.isHidden = true
        label.accessibilityIdentifier = "kyc-dlfront-unavailable"
        return label
    }()

    private let scannerContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "kyc-dlfront-scanner"
        return view
    }()

    /// The DataScanner child VC — built lazily and only when the surface is
    /// available, so the simulator never instantiates it.
    private var dataScanner: DataScannerViewController?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DS.Colors.background
        title = NSLocalizedString(
            "kyc.start.title",
            value: "Verify identity",
            comment: "KYC nav title"
        )

        instructionLabel.text = NSLocalizedString(
            "kyc.dlfront.instruction",
            value: "Fit your license inside the frame.",
            comment: "DL-front capture instruction header"
        )
        unavailableLabel.text = NSLocalizedString(
            "kyc.error.camera_unavailable",
            value: "The camera isn't available on this device.",
            comment: "KYC camera-unavailable error"
        )

        let stack = UIStackView(arrangedSubviews: [instructionLabel, scannerContainer, unavailableLabel])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.md
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: DS.Spacing.xl
            ),
            stack.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: DS.Spacing.lg
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -DS.Spacing.lg
            ),
            stack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -DS.Spacing.xl
            ),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScannerIfAvailable()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dataScanner?.stopScanning()
    }

    // MARK: - DataScanner (KYC-03 — RESEARCH Pitfall 1 availability gate)

    /// Build + start the `DataScannerViewController`, but ONLY when the scanner
    /// surface is available. On the simulator (`isSupported`/`isAvailable` false)
    /// the inline unavailable notice is shown instead — no trap (Pitfall 1).
    private func startScannerIfAvailable() {
        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable else {
            scannerContainer.isHidden = true
            unavailableLabel.isHidden = false
            return
        }
        guard dataScanner == nil else {
            try? dataScanner?.startScanning()
            return
        }

        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = self
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        scannerContainer.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.topAnchor.constraint(equalTo: scannerContainer.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: scannerContainer.bottomAnchor),
            scanner.view.leadingAnchor.constraint(equalTo: scannerContainer.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: scannerContainer.trailingAnchor),
        ])
        scanner.didMove(toParent: self)
        self.dataScanner = scanner
        try? scanner.startScanning()
    }

    /// Map the recognized text items to the three DL fields and bubble the
    /// extraction. The field isolation is a best-effort heuristic — the
    /// authoritative artifact is the photo (D-05), and the read-only extraction
    /// screen runs `DLFieldFormatValidator` to catch a bad scan early.
    fileprivate func extract(from items: [RecognizedItem]) {
        var texts: [String] = []
        for item in items {
            if case let .text(text) = item {
                texts.append(text.transcript)
            }
        }
        let extraction = Self.fields(from: texts)
        onScanComplete?(extraction)
    }

    /// Heuristically isolate name / DL number / expiry from recognized text
    /// lines. DL layouts vary by US state (RESEARCH Assumption A5) — this is a
    /// loose first pass; the format validator + read-only confirm are the gate.
    static func fields(from lines: [String]) -> DLExtraction {
        var name = ""
        var dlNumber = ""
        var expiry = ""
        let dateRegex = try? NSRegularExpression(
            pattern: #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#
        )
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if expiry.isEmpty,
               let match = dateRegex?.firstMatch(in: line, range: range),
               let r = Range(match.range, in: line) {
                expiry = String(line[r])
                continue
            }
            // A line that is mostly digits/letters with no spaces is a likely
            // DL-number candidate.
            let compact = line.replacingOccurrences(of: " ", with: "")
            if dlNumber.isEmpty,
               compact.count >= 4, compact.count <= 20,
               compact.allSatisfy({ $0.isLetter || $0.isNumber }),
               compact.contains(where: { $0.isNumber }) {
                dlNumber = compact
                continue
            }
            // Otherwise the first alphabetic, spaced line is a likely name.
            if name.isEmpty,
               line.contains(" "),
               line.allSatisfy({ $0.isLetter || $0.isWhitespace || "-'.".contains($0) }) {
                name = line
            }
        }
        return DLExtraction(name: name, dlNumber: dlNumber, expiry: expiry)
    }
}

// MARK: - DataScannerViewControllerDelegate

extension DLFrontScanViewController: DataScannerViewControllerDelegate {

    func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        // A reasonable batch of text recognized — extract and advance.
        guard allItems.count >= 3 else { return }
        dataScanner.stopScanning()
        extract(from: allItems)
    }
}
