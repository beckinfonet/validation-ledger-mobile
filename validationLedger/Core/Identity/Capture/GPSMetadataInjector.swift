// validationLedger/Core/Identity/Capture/GPSMetadataInjector.swift
// Phase 5 Plan 03 — KYC-04 / SC-1: the capture-time GPS-EXIF trust boundary.
//
// === WHY THIS FILE IS A TRUST BOUNDARY ===
// The product's entire fraud-detection premise depends on a verifiable
// location tag travelling WITH each captured artifact. RESEARCH Pitfall 6 is
// dedicated to one failure mode: routing capture bytes through a UIKit image
// decode/re-encode (image-from-data then jpeg-data) silently STRIPS the EXIF
// GPS dictionary. This injector therefore NEVER touches that UIKit type — it
// operates on `AVCapturePhoto` / raw `Data` directly via ImageIO, which is
// lossless and EXIF-preserving. A `grep` gate in the plan asserts that the
// UIKit image type appears zero times in this file.
//
// Two injection paths (RESEARCH Pattern 3):
//   1. PRIMARY  — `AVCapturePhoto.fileDataRepresentation(withReplacementMetadata:)`:
//      used when the bytes come straight from `AVCapturePhotoOutput`. No
//      recompression; starts from the photo's own metadata so orientation/EXIF
//      are preserved.
//   2. FALLBACK — `CGImageSource` → `CGImageDestination`: used when we only
//      hold `Data` (e.g. a `DataScanner`-produced image). Copies the source
//      properties, merges GPS, re-emits via the same source UTI.
//
// === PII ROUTING (GEO-03 / D-23) ===
// A `CLLocationCoordinate2D` may travel ONLY as a `PlatformPayloadField` for
// any logging/payload purpose. This file embeds coordinates into image EXIF —
// it MUST NOT log a raw coordinate (RESEARCH Pitfall 1/6). There is no logger
// dependency here precisely so a coordinate cannot accidentally reach one.
//
// CLAUDE.md pre-approves `CoreImage`/`ImageIO` for this work; no new package.

import AVFoundation
import CoreLocation
import Foundation
import ImageIO

/// Injects EXIF GPS metadata into captured image bytes without ever converting
/// through a UIKit image decode/re-encode. The KYC-04 trust boundary — see the
/// file header.
public struct GPSMetadataInjector {

    public init() {}

    // MARK: - GPS dictionary construction

    /// Build the `kCGImagePropertyGPSDictionary` payload for a `CLLocation`.
    ///
    /// CoreGraphics stores GPS coordinates as **unsigned magnitudes** plus a
    /// reference letter (`N`/`S` for latitude, `E`/`W` for longitude). A
    /// negative latitude becomes `abs(latitude)` + `"S"`; a negative longitude
    /// becomes `abs(longitude)` + `"W"`. The location timestamp and the
    /// horizontal positioning error are recorded so the backend can corroborate
    /// the fix quality.
    public func buildGPSDictionary(from location: CLLocation) -> [String: Any] {
        let coordinate = location.coordinate
        var gps: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(coordinate.latitude),
            kCGImagePropertyGPSLatitudeRef as String: coordinate.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(coordinate.longitude),
            kCGImagePropertyGPSLongitudeRef as String: coordinate.longitude >= 0 ? "E" : "W",
        ]

        // EXIF GPS splits the fix instant into a UTC date stamp (yyyy:MM:dd) and
        // a time stamp (HH:mm:ss). Both are derived from the location timestamp.
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyy:MM:dd"
        gps[kCGImagePropertyGPSDateStamp as String] = dateFormatter.string(from: location.timestamp)

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = TimeZone(identifier: "UTC")
        timeFormatter.dateFormat = "HH:mm:ss"
        gps[kCGImagePropertyGPSTimeStamp as String] = timeFormatter.string(from: location.timestamp)

        // Horizontal positioning error (meters) — only recorded when valid.
        // A negative `horizontalAccuracy` means the fix is invalid; omit it.
        if location.horizontalAccuracy >= 0 {
            gps[kCGImagePropertyGPSHPositioningError as String] = location.horizontalAccuracy
        }

        return gps
    }

    // MARK: - Primary path — AVCapturePhoto

    /// PRIMARY injection path: produce upload-ready `Data` from an
    /// `AVCapturePhoto`, merging GPS into the photo's own metadata.
    ///
    /// Starts from `photo.metadata` so EXIF/orientation are preserved, merges
    /// the GPS dictionary, and re-emits the file representation WITH the
    /// replacement metadata — no UIKit image decode, no recompression. Returns
    /// `nil` only if the photo cannot produce a file representation.
    public func uploadData(from photo: AVCapturePhoto, location: CLLocation) -> Data? {
        var metadata = photo.metadata
        metadata[kCGImagePropertyGPSDictionary as String] = buildGPSDictionary(from: location)
        return photo.fileDataRepresentation(
            withReplacementMetadata: metadata,
            replacementEmbeddedThumbnailPhotoFormat: nil,
            replacementEmbeddedThumbnailPixelBuffer: nil,
            replacementDepthData: nil
        )
    }

    // MARK: - Fallback path — CGImageSource / CGImageDestination

    /// FALLBACK injection path: merge GPS into existing image `Data`.
    ///
    /// Used when the bytes did not come from an `AVCapturePhoto` (e.g. a
    /// `DataScanner`-produced image). Copies the source's existing properties
    /// — preserving any EXIF/orientation already present — merges the GPS
    /// dictionary, and re-emits via the same source UTI. Returns `nil` if the
    /// data is not a decodable image or the destination cannot be finalized.
    public func injectGPS(into imageData: Data, location: CLLocation) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let uti = CGImageSourceGetType(source) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, uti, 1, nil
        ) else {
            return nil
        }

        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [String: Any]) ?? [:]
        properties[kCGImagePropertyGPSDictionary as String] = buildGPSDictionary(from: location)

        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }

    // MARK: - Read-back helper

    /// Read the EXIF GPS dictionary back out of image `Data`.
    ///
    /// Used by the SC-1 round-trip test and by `KYCUploader` verification to
    /// confirm the GPS tag survived into the bytes that will be uploaded.
    /// Returns `nil` when the data is not a decodable image or carries no GPS
    /// dictionary.
    public func readGPSDictionary(from imageData: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [String: Any] else {
            return nil
        }
        return properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
    }
}
