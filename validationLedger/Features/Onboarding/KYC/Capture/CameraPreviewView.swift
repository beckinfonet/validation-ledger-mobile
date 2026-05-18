// validationLedger/Features/Onboarding/KYC/Capture/CameraPreviewView.swift
// Phase 5 Plan 05 — KYC-02 / KYC-04: the live camera-preview host view.
//
// Debug session `front-camera-preview-black` (round 4): the KYC capture screens
// previously hosted the camera by manually adding an `AVCaptureVideoPreviewLayer`
// as a SUBLAYER of a plain `UIView` and re-syncing `previewLayer.frame =
// container.bounds` on every `viewDidLayoutSubviews` pass. That pattern has an
// inherent 0×0 race: the layer is added (and its frame copied) before the host
// view ever reaches a real size, and if any later layout pass is missed — or the
// container itself resolves to 0 height — the preview renders a 0×0 rect and the
// screen shows solid black.
//
// === THE STRUCTURAL FIX (round 4) ===
// `CameraPreviewView` overrides `layerClass` so its BACKING layer IS the
// `AVCaptureVideoPreviewLayer`. UIKit keeps a view's backing layer exactly
// `bounds`-sized at all times with zero manual work — there is no `.frame` to
// sync, no sublayer to add, and no window where the layer is sized differently
// from the view. The preview layer can NEVER be a different size than the view.
// This permanently removes the manual-frame-sync failure mode.

import AVFoundation
import UIKit

/// A `UIView` whose backing layer is an `AVCaptureVideoPreviewLayer`.
///
/// Because the preview layer is the view's backing layer, it is always exactly
/// the view's `bounds` — UIKit guarantees that with no manual frame-syncing.
/// Host this view with Auto Layout like any other view; the live camera feed
/// fills it automatically.
final class CameraPreviewView: UIView {

    /// Make the view's backing layer an `AVCaptureVideoPreviewLayer`. UIKit
    /// instantiates the backing layer from this type and keeps it `bounds`-sized.
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    /// The backing layer, typed. Always exactly `self.bounds`-sized.
    var previewLayer: AVCaptureVideoPreviewLayer {
        // Safe force-cast: `layerClass` guarantees the backing layer's type.
        layer as! AVCaptureVideoPreviewLayer
    }

    /// The `AVCaptureSession` whose feed this view renders. Setting it wires the
    /// session into the backing preview layer. The preview is render-only — it is
    /// never the upload byte source (RESEARCH Pitfall 6).
    var session: AVCaptureSession? {
        get { previewLayer.session }
        set { previewLayer.session = newValue }
    }

    /// The preview-layer video gravity. Defaults to `.resizeAspectFill` so the
    /// live feed fills the view regardless of the view's aspect ratio.
    var videoGravity: AVLayerVideoGravity {
        get { previewLayer.videoGravity }
        set { previewLayer.videoGravity = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
