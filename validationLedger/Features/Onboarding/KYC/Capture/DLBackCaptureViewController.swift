// validationLedger/Features/Onboarding/KYC/Capture/DLBackCaptureViewController.swift
// Phase 5 Plan 05 — KYC-04 / D-06: the driver's-license BACK capture screen.
//
// D-06: the DL back is a PLAIN FRAMED PHOTO — there is NO PDF417/AAMVA barcode
// scan. KYC-03's optical text extraction is satisfied by the front-side OCR
// (DLFrontScanViewController); the back is documentary. Keeping it a plain photo
// keeps the capture screen consistent across 5 of the 6 artifacts and avoids
// per-state AAMVA parsing quirks.
//
// Because the DL back is captured exactly like the three vehicle artifacts
// (plain framed photo, GPS injected at capture — the same still-capture path),
// this VC reuses `VehicleCaptureViewController` (the shared plain-photo screen)
// driven by a `VehicleCaptureViewModel` whose `artifactType` is `.dlBack`. It is
// a distinct named type so the KYC-01 push chain reads
// `pushDLBack()` explicitly and so a future DL-back-specific affordance has a
// home — but it deliberately adds NO barcode scanning (D-06).

import UIKit

/// The DL-back plain-photo capture screen (KYC-04 / D-06). No barcode scan.
final class DLBackCaptureViewController: VehicleCaptureViewController {
    // Intentionally empty — the DL back is a plain framed photo (D-06), captured
    // through the identical still-capture path as the vehicle artifacts. The
    // `VehicleCaptureViewModel` is constructed with `artifactType: .dlBack`, so
    // the instruction header reads "Photograph the back of your license." and
    // the persisted artifact key is `dl_back`.
}
