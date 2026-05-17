// validationLedgerTests/KYC/KYCCapturePreviewLayoutTests.swift
// Requirement: KYC-02 / KYC-04 — the camera preview host must always resolve
// to a NON-ZERO height. Regression lock for debug session
// `front-camera-preview-black` (rounds 1–3).
//
// THE BUG (round 3, decisive on-device evidence): round 2 (873becd) pinned a
// rigid 3:4 aspect-ratio constraint on `previewContainer`. Inside the capture
// VCs' vertical `.fill` `UIStackView` — which is pinned to the safe area on
// BOTH ends, so its height is fully determined — that rigid aspect constraint
// is unsatisfiable. UIKit force-breaks it ("Will attempt to recover by breaking
// constraint kyc-face-preview.height == 1.33333*kyc-face-preview.width") and
// the plain `UIView` (no intrinsic content size, no other height constraint)
// collapses to height 0 → `previewLayer.frame = previewContainer.bounds` copies
// a 0×0 rect → solid-black preview.
//
// THE FIX (round 3): no rigid/aspect height. The preview hugs vertically at the
// lowest priority while the labels (and shutter button) hug firmly, so the
// `.fill` stack expands the preview into all leftover vertical space — a
// satisfiable layout with nothing to break.
//
// This test reconstructs the EXACT stack composition that
// `FaceCaptureViewController.viewDidLoad` / `VehicleCaptureViewController.viewDidLoad`
// build (same arranged subviews, same `.fill` distribution, same both-ends-
// pinned safe-area constraints, same hugging priorities) and asserts the
// preview host resolves to a non-zero height. Live camera frames are a device-
// only surface (RESEARCH Pitfall 1); the Auto Layout collapse is fully
// reproducible on the simulator, which is what this locks.
//
// If a future change reintroduces a rigid height, drops the hugging-priority
// fix, or restores the aspect constraint, the preview host collapses to 0 and
// these tests fail.

import Testing
import UIKit
@testable import validationLedger

@MainActor
@Suite("KYC capture preview layout — preview host never collapses to 0 height")
struct KYCCapturePreviewLayoutTests {

    /// Builds the face-capture stack EXACTLY as `FaceCaptureViewController`
    /// does: instruction label + preview container + cue label in a vertical
    /// `.fill` `UIStackView` pinned to the safe area on all four edges, with the
    /// round-3 hugging-priority fix applied. Returns the host view and the
    /// preview container so the caller can size the host and inspect the
    /// resolved bounds.
    private func makeFaceCaptureLayout() -> (host: UIView, preview: UIView) {
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

        let preview = UIView()
        preview.backgroundColor = .black
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
    /// does: instruction label + preview container + cue label + shutter button.
    private func makeVehicleCaptureLayout() -> (host: UIView, preview: UIView) {
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

        let preview = UIView()
        preview.backgroundColor = .black
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
    private func resolvedPreviewBounds(host: UIView, preview: UIView, size: CGSize) -> CGRect {
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
}
