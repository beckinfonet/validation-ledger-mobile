// validationLedgerTests/KYC/GPSMetadataInjectorTests.swift
// Requirement: KYC-04 / SC-1 — GPS EXIF metadata is injected into captured artifacts.
// GREEN suite (plan 05-03). RED scaffold landed in Wave 0 / plan 05-01.
//
// SC-1 round-trip: a known lat/lon is injected into real JPEG bytes via the
// CGImageDestination path, then re-read from the produced data and compared.
// No UIImage anywhere — that path strips EXIF (RESEARCH Pitfall 6).

import Testing
import Foundation
import CoreLocation
import ImageIO
import UniformTypeIdentifiers
@testable import validationLedger

// MARK: - JPEG fixture builder

/// Produce a small, valid JPEG `Data` with NO GPS dictionary — the clean input
/// for the round-trip test. Built via `CGImageDestination` so no UIImage is used.
private func makeBareJPEG(
    width: Int = 8,
    height: Int = 8,
    extraEXIF: [String: Any]? = nil
) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let cgImage = context.makeImage()!

    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(
        out, UTType.jpeg.identifier as CFString, 1, nil
    )!
    var props: [String: Any] = [:]
    if let extraEXIF {
        props[kCGImagePropertyExifDictionary as String] = extraEXIF
    }
    CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
    precondition(CGImageDestinationFinalize(dest), "fixture JPEG must finalize")
    return out as Data
}

@Suite("GPSMetadataInjector — EXIF GPS round-trip (KYC-04 / SC-1)")
struct GPSMetadataInjectorTests {

    private let injector = GPSMetadataInjector()

    @Test("KYC-04 / SC-1: an injected GPS value round-trips through EXIF")
    func gpsValueRoundTrips() async throws {
        // Chicago — a known northern-hemisphere / western-hemisphere coordinate.
        let known = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
            altitude: 0,
            horizontalAccuracy: 12,
            verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let bare = makeBareJPEG()
        // The bare fixture must start with no GPS dictionary.
        #expect(injector.readGPSDictionary(from: bare) == nil)

        let injected = try #require(injector.injectGPS(into: bare, location: known))
        let gps = try #require(injector.readGPSDictionary(from: injected))

        let lat = try #require(gps[kCGImagePropertyGPSLatitude as String] as? Double)
        let lon = try #require(gps[kCGImagePropertyGPSLongitude as String] as? Double)
        let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String

        // CoreGraphics stores unsigned magnitudes + ref letters.
        #expect(abs(lat - abs(known.coordinate.latitude)) < 0.0001)
        #expect(abs(lon - abs(known.coordinate.longitude)) < 0.0001)
        #expect(latRef == "N")
        #expect(lonRef == "W")
    }

    @Test("Negative latitude/longitude yield S / W reference letters")
    func southernWesternHemisphereRefLetters() async throws {
        // Buenos Aires — southern + western hemisphere.
        let southWest = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -34.6037, longitude: -58.3816),
            altitude: 0,
            horizontalAccuracy: 30,
            verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let injected = try #require(
            injector.injectGPS(into: makeBareJPEG(), location: southWest)
        )
        let gps = try #require(injector.readGPSDictionary(from: injected))

        #expect(gps[kCGImagePropertyGPSLatitudeRef as String] as? String == "S")
        #expect(gps[kCGImagePropertyGPSLongitudeRef as String] as? String == "W")
        // Magnitudes are stored unsigned even for the southern/western case.
        let lat = try #require(gps[kCGImagePropertyGPSLatitude as String] as? Double)
        #expect(lat > 0)
    }

    @Test("Positive longitude yields the E reference letter")
    func easternHemisphereRefLetter() async throws {
        // Tokyo — northern + eastern hemisphere.
        let northEast = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            altitude: 0,
            horizontalAccuracy: 18,
            verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let injected = try #require(
            injector.injectGPS(into: makeBareJPEG(), location: northEast)
        )
        let gps = try #require(injector.readGPSDictionary(from: injected))
        #expect(gps[kCGImagePropertyGPSLatitudeRef as String] as? String == "N")
        #expect(gps[kCGImagePropertyGPSLongitudeRef as String] as? String == "E")
    }

    @Test("The GPS dictionary records the horizontal positioning error")
    func gpsDictionaryRecordsPositioningError() async throws {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
            altitude: 0,
            horizontalAccuracy: 42.5,
            verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let dict = injector.buildGPSDictionary(from: location)
        let hpe = try #require(
            dict[kCGImagePropertyGPSHPositioningError as String] as? Double
        )
        #expect(abs(hpe - 42.5) < 0.0001)
    }

    @Test("Injecting GPS preserves a pre-existing EXIF dictionary")
    func injectionPreservesExistingEXIF() async throws {
        // A bare JPEG that already carries an EXIF UserComment.
        let marker = "vl-kyc-fixture-marker"
        let withEXIF = makeBareJPEG(extraEXIF: [
            kCGImagePropertyExifUserComment as String: marker
        ])
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let injected = try #require(
            injector.injectGPS(into: withEXIF, location: location)
        )
        // GPS is present...
        #expect(injector.readGPSDictionary(from: injected) != nil)
        // ...and the original EXIF survived.
        let src = CGImageSourceCreateWithData(injected as CFData, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        let exif = props?[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(exif?[kCGImagePropertyExifUserComment as String] as? String == marker)
    }
}
