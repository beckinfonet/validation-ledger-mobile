// validationLedger/Core/Identity/KYC/KYCThumbnail.swift
// Phase 5 — debug session kyc-session-store-data-race (SECONDARY decision).
//
// A tiny image-downscale helper used by `KYCUploader` at commit time. Post-commit
// the multi-MB full-resolution identity image in `KYCSession.artifactData` is
// freed (D-02 footprint control); to keep the Review grid able to render a
// thumbnail for an already-uploaded artifact, the uploader downscales the
// committed image to a small (~150 px longest-edge) JPEG and retains THAT in
// `KYCSession.thumbnailData`. A few-KB thumbnail is not the full-resolution
// identity-image exposure D-02 guards.
//
// === UIKit-first constraint ===
// The downscale is pure Core Graphics — `CGImageSource` thumbnail generation,
// `UIImage` JPEG encoding. No SwiftUI, no `Image`/`ImageRenderer`. The function
// is synchronous and free of actor isolation, so the `KYCUploader` actor can call
// it directly inside its commit critical section without an `await` hop.

import UIKit
import ImageIO

/// Downscaling for the post-commit Review thumbnail.
public enum KYCThumbnail {

    /// Longest-edge target for the downscaled Review thumbnail, in pixels.
    public static let maxPixelSize = 150

    /// JPEG compression quality for the stored thumbnail — small file, the
    /// thumbnail is a confirmation cue, not an inspection-grade image.
    public static let jpegQuality: CGFloat = 0.7

    /// Downscale `fullImageData` to a small JPEG no larger than `maxPixelSize` on
    /// its longest edge.
    ///
    /// Returns `nil` when `fullImageData` is not a decodable image — the caller
    /// (`KYCUploader`) treats a `nil` result as "no thumbnail" and proceeds; a
    /// non-image blob must never crash the commit path.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` decodes the image at the reduced
    /// size directly, so the full-resolution bitmap is never materialised in
    /// memory — important for the multi-MB identity images.
    public static func downscaledJPEG(
        from fullImageData: Data,
        maxPixelSize: Int = KYCThumbnail.maxPixelSize,
        jpegQuality: CGFloat = KYCThumbnail.jpegQuality
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(fullImageData as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgThumb).jpegData(compressionQuality: jpegQuality)
    }
}
