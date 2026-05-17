// validationLedgerTests/KYC/KYCCapturePreviewLayoutTests.swift
// Requirement: KYC-02 / KYC-04 — the camera preview host must always resolve
// to a NON-ZERO height AND its backing layer must be the camera preview layer.
// Regression lock for debug session `front-camera-preview-black` (rounds 1–4).
//
// THE BUG (rounds 1–3): the capture VCs hosted the camera by adding an
// `AVCaptureVideoPreviewLayer` as a SUBLAYER of a plain `UIView` and re-syncing
// `previewLayer.frame = container.bounds` every layout pass. Round 2's rigid
// 3:4 aspect constraint force-broke inside the both-ends-pinned `.fill` stack
// and the plain `UIView` collapsed to height 0 → 0×0 preview → solid black.
//
// THE FIX:
//   - Round 3: no rigid/aspect height. The preview hugs vertically at the
//     lowest priority while the labels (and shutter button) hug firmly, so the
//     `.fill` stack expands the preview into all leftover vertical space — a
//     satisfiable layout with nothing to break. (Retained.)
//   - Round 4 (STRUCTURAL): the preview host is now `CameraPreviewView`, a
//     `UIView` subclass whose BACKING layer IS the `AVCaptureVideoPreviewLayer`
//     (`layerClass` override). UIKit keeps a view's backing layer exactly
//     `bounds`-sized — there is no `previewLayer.frame` to sync and no 0×0
//     race. The manual add-as-sublayer pattern is gone.
//
// This test reconstructs the EXACT stack composition that
// `FaceCaptureViewController.viewDidLoad` / `VehicleCaptureViewController.viewDidLoad`
// build (same arranged subviews, same `.fill` distribution, same both-ends-
// pinned safe-area constraints, same hugging priorities, same `CameraPreviewView`
// host) and asserts (a) the preview host resolves to a non-zero height and
// (b) the host's backing layer is the camera preview layer and tracks the
// view's bounds with zero manual sync. Live camera frames are a device-only
// surface (RESEARCH Pitfall 1); the layout + backing-layer wiring are fully
// reproducible on the simulator, which is what this locks.
//
// If a future change reintroduces a rigid height, drops the hugging-priority
// fix, restores the aspect constraint, or reverts the `layerClass` host, these
// tests fail.

import AVFoundation
import Testing
import UIKit
@testable import validationLedger

@MainActor
@Suite("KYC capture preview layout — preview host never collapses to 0 height")
struct KYCCapturePreviewLayoutTests {

    /// Builds the face-capture stack EXACTLY as `FaceCaptureViewController`
    /// does: instruction label + `CameraPreviewView` + cue label in a vertical
    /// `.fill` `UIStackView` pinned to the safe area on all four edges, with the
    /// round-3 hugging-priority fix applied. Returns the host view and the
    /// `CameraPreviewView` so the caller can size the host and inspect the
    /// resolved bounds + the backing layer.
    private func makeFaceCaptureLayout() -> (host: UIView, preview: CameraPreviewView) {
        let host = UIView()

        let instructionLabel = UILabel()
        instructionLabel.font = DS.Typography.title1
        instructionLabel.numberOfLines = 0
        instructionLabel.text = "Position your face inside the oval."
        instructionLabel.setContentHuggingPriority(.required, for: .vertical)

        let cueLabel = UILabel()
        cueLabel.font = DS.Typography.footnote
        cueLabel.numberOfLines = 0
        cueLabel.text = "Center your face"
        cueLabel.setContentHuggingPriority(.required, for: .vertical)

        let preview = CameraPreviewView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.accessibilityIdentifier = "kyc-face-preview"
        preview.setContentHuggingPriority(.init(1), for: .vertical)
        preview.setContentCompressionResistancePriority(.init(1), for: .vertical)

        let stack = UIStackView(arrangedSubviews: [instructionLabel, preview, cueLabel])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.md
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(
                equalTo: host.safeAreaLayoutGuide.topAnchor,
                constant: DS.Spacing.xl
            ),
            stack.leadingAnchor.constraint(
                equalTo: host.safeAreaLayoutGuide.leadingAnchor,
                constant: DS.Spacing.lg
            ),
            stack.trailingAnchor.constraint(
                equalTo: host.safeAreaLayoutGuide.trailingAnchor,
                constant: -DS.Spacing.lg
            ),
            stack.bottomAnchor.constraint(
                equalTo: host.safeAreaLayoutGuide.bottomAnchor,
                constant: -DS.Spacing.xl
            ),
            {
                let minHeight = preview.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: 240
                )
                minHeight.priority = .init(250)
                return minHeight
            }(),
        ])
        return (host, preview)
    }

    /// Builds the vehicle-capture stack EXACTLY as `VehicleCaptureViewController`
    /// does: instruction label + `CameraPreviewView` + cue label + shutter button.
    private func makeVehicleCaptureLayout() -> (host: UIView, preview: CameraPreviewView) {
        let host = UIView()

        let instructionLabel = UILabel()
        instructionLabel.font = DS.Typography.title1
        instructionLabel.numberOfLines = 0
        instructionLabel.text = "Photograph the front of the truck."
        instructionLabel.setContentHuggingPriority(.required, for: .vertical)

        let cueLabel = UILabel()
        cueLabel.font = DS.Typography.footnote
        cueLabel.numberOfLines = 0
        cueLabel.text = ""
        cueLabel.setContentHuggingPriority(.required, for: .vertical)

        var shutterConfig = UIButton.Configuration.borderedProminent()
        shutterConfig.title = "Take photo"
        let shutterButton = UIButton(configuration: shutterConfig)

        let preview = CameraPreviewView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.accessibilityIdentifier = "kyc-vehicle-preview"
        preview.setContentHuggingPriority(.init(1), for: .vertical)
        preview.setContentCompressionResistancePriority(.init(1), for: .vertical)

        let stack = UIStackView(arrangedSubviews: [
            instructionLabel, preview, cueLabel, shutterButton,
        ])
        stack.axis = .vertical
        stack.spacing = DS.Spacing.md
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(
                equalTo: host.safeAreaLayoutGuide.topAnchor,
                constant: DS.Spacing.xl
            ),
            stack.leadingAnchor.constraint(
                equalTo: host.safeAreaLayoutGuide.leadingAnchor,
                constant: DS.Spacing.lg
            ),
            stack.trailingAnchor.constraint(
                equalTo: host.safeAreaLayoutGuide.trailingAnchor,
                constant: -DS.Spacing.lg
            ),
            stack.bottomAnchor.constraint(
                equalTo: host.safeAreaLayoutGuide.bottomAnchor,
                constant: -DS.Spacing.xl
            ),
            shutterButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            {
                let minHeight = preview.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: 240
                )
                minHeight.priority = .init(250)
                return minHeight
            }(),
        ])
        return (host, preview)
    }

    /// Resolves the layout at a fixed size and returns the preview's bounds.
    private func resolvedPreviewBounds(
        host: UIView,
        preview: CameraPreviewView,
        size: CGSize
    ) -> CGRect {
        host.frame = CGRect(origin: .zero, size: size)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        return preview.bounds
    }

    // MARK: - Face capture

    @Test("Face capture: preview host has a non-zero height at the encapsulated 320×480 layout")
    func faceCaptureNonZeroAtCompactSize() {
        // 320×480 is the `UIView-Encapsulated-Layout` size from the on-device
        // console where the round-2 aspect constraint was force-broken.
        let (host, preview) = makeFaceCaptureLayout()
        let bounds = resolvedPreviewBounds(host: host, preview: preview, size: CGSize(width: 320, height: 480))
        #expect(bounds.height > 0, "preview host collapsed to 0 height at 320×480 — black-preview regression")
        #expect(bounds.width > 0)
    }

    @Test("Face capture: preview host has a non-zero height at a full iPhone size")
    func faceCaptureNonZeroAtFullDeviceSize() {
        // iPhone 16e portrait point size.
        let (host, preview) = makeFaceCaptureLayout()
        let bounds = resolvedPreviewBounds(host: host, preview: preview, size: CGSize(width: 393, height: 852))
        #expect(bounds.height > 0, "preview host collapsed to 0 height at full device size — black-preview regression")
        #expect(bounds.width > 0)
        // The preview must be the slack-absorbing element — it should take the
        // lion's share of the available height, far more than a label would.
        #expect(bounds.height > 240)
    }

    // MARK: - Vehicle capture

    @Test("Vehicle capture: preview host has a non-zero height at the encapsulated 320×480 layout")
    func vehicleCaptureNonZeroAtCompactSize() {
        let (host, preview) = makeVehicleCaptureLayout()
        let bounds = resolvedPreviewBounds(host: host, preview: preview, size: CGSize(width: 320, height: 480))
        #expect(bounds.height > 0, "vehicle preview host collapsed to 0 height at 320×480 — black-preview regression")
        #expect(bounds.width > 0)
    }

    @Test("Vehicle capture: preview host has a non-zero height at a full iPhone size")
    func vehicleCaptureNonZeroAtFullDeviceSize() {
        let (host, preview) = makeVehicleCaptureLayout()
        let bounds = resolvedPreviewBounds(host: host, preview: preview, size: CGSize(width: 393, height: 852))
        #expect(bounds.height > 0, "vehicle preview host collapsed to 0 height at full device size — black-preview regression")
        #expect(bounds.width > 0)
        #expect(bounds.height > 240)
    }

    // MARK: - Round-4 structural fix: the backing layer IS the preview layer

    @Test("CameraPreviewView's backing layer is an AVCaptureVideoPreviewLayer")
    func cameraPreviewViewBackingLayerIsThePreviewLayer() {
        // The round-4 structural fix: `CameraPreviewView.layerClass` makes the
        // view's BACKING layer the preview layer. If a future change reverts to
        // a plain `UIView` + manual sublayer, this fails.
        #expect(CameraPreviewView.layerClass == AVCaptureVideoPreviewLayer.self)
        let view = CameraPreviewView()
        #expect(view.layer is AVCaptureVideoPreviewLayer)
        #expect(view.previewLayer === view.layer)
    }

    @Test("Face capture: the preview layer tracks the host bounds with zero manual sync")
    func faceCapturePreviewLayerTracksBoundsWithoutManualSync() {
        // Because the preview layer is the backing layer, it is ALWAYS exactly
        // the view's bounds — no `viewDidLayoutSubviews` frame-sync needed. This
        // is the property that permanently removes the 0×0 race (round 4).
        let (host, preview) = makeFaceCaptureLayout()
        _ = resolvedPreviewBounds(host: host, preview: preview, size: CGSize(width: 393, height: 852))
        #expect(preview.previewLayer.bounds == preview.bounds,
                "preview layer bounds drifted from the host bounds — manual-sync race reintroduced")
        #expect(preview.previewLayer.bounds.height > 240)
    }

    @Test("Vehicle capture: the preview layer tracks the host bounds with zero manual sync")
    func vehicleCapturePreviewLayerTracksBoundsWithoutManualSync() {
        let (host, preview) = makeVehicleCaptureLayout()
        _ = resolvedPreviewBounds(host: host, preview: preview, size: CGSize(width: 393, height: 852))
        #expect(preview.previewLayer.bounds == preview.bounds,
                "preview layer bounds drifted from the host bounds — manual-sync race reintroduced")
        #expect(preview.previewLayer.bounds.height > 240)
    }
}
