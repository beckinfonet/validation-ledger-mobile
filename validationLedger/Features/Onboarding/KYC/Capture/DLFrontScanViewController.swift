// validationLedger/Features/Onboarding/KYC/Capture/DLFrontScanViewController.swift
// Phase 5 Plan 05 — KYC-03: the driver's-license front DataScanner OCR screen.
//
// Programmatic UIKit VC (no SwiftUI — CLAUDE.md hard constraint). Hosts a
// `VisionKit.DataScannerViewController` as a child VC with the `.text`
// recognized-data type. On a successful scan it extracts name / DL number /
// expiry and bubbles a `DLExtraction` to the coordinator, which pushes the
// read-only confirmation screen (D-05).
//
// === CAPTURE PIPELINE (debug session `kyc-flow-device-audit`) ===
// The DL-front *uploaded artifact* is the captured PHOTO `Data` (GPS-injected),
// NOT the OCR text (05-05 Task 2a). The scanner screen therefore ALSO captures a
// still — `DataScannerViewController.capturePhoto()` — at scan-completion, reads
// a fresh GPS fix (Pitfall 5), injects EXIF GPS into the JPEG via
// `GPSMetadataInjector.injectGPS(into:location:)` (the DataScanner-image variant,
// since DataScanner yields a `UIImage`, not an `AVCapturePhoto`), and persists
// the bytes under `.dlFront` into the `KYCSessionStore` so plan 04's
// `KYCUploader` can pick them up (D-01). Without this the `dl_front` upload
// throws `artifactDataMissing` and the Review-screen Submit can never enable.
//
// === SIMULATOR GATE (RESEARCH Pitfall 1) ===
// `DataScannerViewController` returns `ScanningUnavailable` on the simulator.
// Entry into the scanner surface is gated on
// `DataScannerViewController.isSupported && .isAvailable` — when unavailable the
// screen shows an inline notice instead of trapping. The live OCR is verified
// on the device lane (DLExtractionScannerDeviceTests) + HUMAN-UAT.

import CoreLocation
import OSLog
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

    // MARK: - Capture-pipeline dependencies (debug session `kyc-flow-device-audit`)

    private let geoContext: GeoContext
    private let gpsInjector: GPSMetadataInjector
    private let sessionStore: KYCSessionStore
    private let logger: any Logger

    /// Guards against firing the scan-complete handoff more than once — a
    /// `DataScannerViewController` keeps delivering `didAdd` callbacks.
    private var didCompleteScan = false

    // MARK: - UI components

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.font = DS.Typography.title1
        label.textColor = DS.Colors.label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "kyc-dlfront-instruction"
        // Hug firmly so the `.fill` stack leaves the label label-sized and
        // stretches the scanner host into the leftover height.
        label.setContentHuggingPriority(.required, for: .vertical)
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
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    /// Hosts the DataScanner child VC. In a `.fill` vertical stack pinned to the
    /// safe area on both ends, a plain `UIView` with no intrinsic size collapses
    /// to 0 height (the FaceCapture round-2 bug). This host hugs vertically at
    /// the lowest priority so the `.fill` stack always expands IT into the
    /// leftover space, and carries a defensive priority-250 min-height floor.
    private let scannerContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "kyc-dlfront-scanner"
        view.setContentHuggingPriority(.init(1), for: .vertical)
        view.setContentCompressionResistancePriority(.init(1), for: .vertical)
        return view
    }()

    /// The DataScanner child VC — built lazily and only when the surface is
    /// available, so the simulator never instantiates it.
    private var dataScanner: DataScannerViewController?

    // MARK: - Init

    /// - Parameters carry the capture pipeline so the DL-front photo artifact is
    ///   persisted exactly like the face/vehicle paths (debug session
    ///   `kyc-flow-device-audit`).
    init(
        geoContext: GeoContext,
        gpsInjector: GPSMetadataInjector,
        sessionStore: KYCSessionStore,
        logger: any Logger
    ) {
        self.geoContext = geoContext
        self.gpsInjector = gpsInjector
        self.sessionStore = sessionStore
        self.logger = logger
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

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
        stack.distribution = .fill
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
            // Defense-in-depth min-height floor (debug session
            // `kyc-flow-device-audit`) — too low (priority 250) to fight the
            // encapsulated-layout height, mirrors the FaceCapture round-3 fix.
            {
                let minHeight = scannerContainer.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: 240
                )
                minHeight.priority = .init(250)
                return minHeight
            }(),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // A fresh appearance (incl. returning from a rescan) re-arms the scan.
        didCompleteScan = false
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
            kycCameraLog.info("kyc_camera event=dlfront_scanner.unavailable")
            return
        }
        guard dataScanner == nil else {
            try? dataScanner?.startScanning()
            kycCameraLog.info("kyc_camera event=dlfront_scanner.resumed")
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
        kycCameraLog.info("kyc_camera event=dlfront_scanner.started")
    }

    /// A reasonable batch of text was recognized. Capture a still photo of the
    /// license for the *uploaded* artifact (debug session
    /// `kyc-flow-device-audit`), persist it, then map the text and bubble the
    /// extraction so the coordinator pushes the read-only confirm screen.
    private func completeScan(with items: [RecognizedItem]) {
        guard !didCompleteScan else { return }
        didCompleteScan = true

        var texts: [String] = []
        for item in items {
            if case let .text(text) = item {
                texts.append(text.transcript)
            }
        }
        let extraction = Self.fields(from: texts)

        // Capture + persist the DL-front photo, THEN bubble the extraction.
        // The handoff runs regardless of whether the photo capture succeeds —
        // a missing photo is surfaced later by the Review-screen status badge,
        // it must not strand the user on the scanner.
        Task { [weak self] in
            await self?.captureAndPersistDLFrontPhoto()
            self?.onScanComplete?(extraction)
        }
    }

    /// Capture a still of the license via `DataScannerViewController.capturePhoto()`,
    /// inject capture-time GPS EXIF, and persist the bytes under `.dlFront`.
    ///
    /// `DataScannerViewController` yields a `UIImage` (not an `AVCapturePhoto`),
    /// so GPS is injected through `GPSMetadataInjector.injectGPS(into:location:)`
    /// — the DataScanner-image variant — over the JPEG-encoded bytes.
    private func captureAndPersistDLFrontPhoto() async {
        guard let scanner = dataScanner else {
            logger.warn(event: LogEvent("kyc_dlfront_capture_no_scanner"), fields: [:])
            return
        }

        let image: UIImage
        do {
            image = try await scanner.capturePhoto()
        } catch {
            logger.error(event: LogEvent("kyc_dlfront_capture_failed"), fields: [:])
            return
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
            logger.error(event: LogEvent("kyc_dlfront_capture_encode_failed"), fields: [:])
            return
        }

        // Pitfall 5 — a stale/unavailable fix still persists the photo, but
        // without GPS EXIF; capture continuity is not blocked on the scanner.
        let location = try? await geoContext.freshLocation()
        let uploadData: Data
        if let location, let injected = gpsInjector.injectGPS(into: jpeg, location: location) {
            uploadData = injected
        } else {
            logger.warn(event: LogEvent("kyc_dlfront_capture_gps_unavailable"), fields: [:])
            uploadData = jpeg
        }

        persist(uploadData)
        kycCameraLog.info("kyc_camera event=dlfront_photo_persisted bytes=\(uploadData.count, privacy: .public)")
    }

    /// Write the DL-front photo bytes into the on-disk KYC session so plan 04's
    /// `KYCUploader` can pick them up for the pipelined upload (D-01).
    private func persist(_ data: Data) {
        do {
            var session = (try sessionStore.loadSession()) ?? KYCSession()
            session.artifactData[KYCUploadInitEndpoint.ArtifactType.dlFront.rawValue] = data
            try sessionStore.persist(session)
        } catch {
            logger.error(event: LogEvent("kyc_dlfront_capture_persist_failed"), fields: [:])
        }
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
        guard !didCompleteScan, allItems.count >= 3 else { return }
        dataScanner.stopScanning()
        completeScan(with: allItems)
    }
}
