// validationLedger/Features/Onboarding/Auth/PhoneEntryViewModel.swift
// Phase 3 Plan 09 — AUTH-01 + GEO-01 + GEO-02 + D-20 + D-21 + D-26.
//
// Orchestrates the D-20 5-step geo gate before POST /auth/otp/request:
//   1. requestPermission() — CLLocationManager via LocationProvider
//   2. currentLocation(maxAge:maxAccuracy:) — one-shot fix
//   3. resolveCountry(for:) — CLGeocoder reverse-geocode via CountryGate
//   4. If country != "US" → push NotAvailableInRegionViewController
//   5. If US → POST /auth/otp/request; publish otpSessionID
//
// State is exposed via `onStateChange` closure (NOT @Observable) so we
// preserve the UIKit-first stance (CLAUDE.md) — no SwiftUI observation
// machinery required at the VC layer.
//
// D-21 defense-in-depth: ALL failure paths inside the geo gate collapse to
// .nonUSCountry (same UX as "we cannot verify US residency"). Permission
// denial alone is the single exception — that surfaces .needsLocationPermission
// so the UI can offer the Open-Settings deep link.

import CoreLocation
import Foundation

@MainActor
public final class PhoneEntryViewModel {

    // MARK: - State

    public enum State: Equatable, Sendable {
        case idle
        case needsLocationPermission     // user must tap "Open Settings" (D-21)
        case verifyingLocation
        case nonUSCountry                // → push NotAvailableInRegionViewController (D-22)
        case requestingOTP
        case otpRequested(otpSessionID: String)
        case error(message: String)
    }

    public private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    // MARK: - Inputs

    /// Raw 10-digit phone string (digits only). UI formatter (`(XXX) XXX-XXXX`)
    /// is applied at the VC level via `formatDisplay(_:)` below.
    public var phoneDigits: String = "" {
        didSet { onSubmitEnabledChange?(submitEnabled) }
    }

    /// D-26: Submit enabled at exactly 10 digits.
    public var submitEnabled: Bool { phoneDigits.count == 10 }

    // MARK: - Callbacks (closures preserve UIKit-first stance)

    public var onStateChange: ((State) -> Void)?
    public var onSubmitEnabledChange: ((Bool) -> Void)?
    public var onPhoneSubmitted: ((String) -> Void)?  // (otpSessionID)

    // MARK: - Dependencies (initializer-DI per ARCH-04)

    private let apiClient: APIClient
    private let location: any LocationProvider
    private let countryGate: any CountryGate
    private let logger: any Logger

    public init(
        apiClient: APIClient,
        location: any LocationProvider,
        countryGate: any CountryGate,
        logger: any Logger
    ) {
        self.apiClient = apiClient
        self.location = location
        self.countryGate = countryGate
        self.logger = logger
    }

    // MARK: - Static format helpers (D-26)

    /// D-26 display format: progressive `(XXX) XXX-XXXX`.
    /// Accepts any input; strips non-digits; caps at 10.
    public static func formatDisplay(_ digits: String) -> String {
        let stripped = String(digits.filter { $0.isNumber }.prefix(10))
        switch stripped.count {
        case 0...3:
            return stripped
        case 4...6:
            let area = stripped.prefix(3)
            let mid = stripped.dropFirst(3)
            return "(\(area)) \(mid)"
        default:
            let area = stripped.prefix(3)
            let mid = stripped.dropFirst(3).prefix(3)
            let last = stripped.dropFirst(6)
            return "(\(area)) \(mid)-\(last)"
        }
    }

    /// D-26 wire format: `+1XXXXXXXXXX`.
    public static func formatE164(_ digits: String) -> String {
        let stripped = String(digits.filter { $0.isNumber }.prefix(10))
        return "+1\(stripped)"
    }

    // MARK: - submit() — D-20 5-step orchestration

    public func submit() async {
        guard submitEnabled else { return }

        // STEP 1: Permission
        let status = await location.requestPermission()
        switch status {
        case .denied, .restricted:
            state = .needsLocationPermission
            return
        case .notDetermined:
            // Should be impossible after requestPermission resolved; treat as denied.
            state = .needsLocationPermission
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            state = .needsLocationPermission
            return
        }

        // STEP 2: One-shot location fix (D-20: <30s age, <100m horizontal accuracy)
        state = .verifyingLocation
        let loc: CLLocation
        do {
            loc = try await location.currentLocation(maxAge: 30, maxAccuracy: 100)
        } catch {
            // D-21 defense-in-depth — treat fix failure as non-US
            logger.warn(event: .init("phone_entry_location_failed"),
                        fields: [.event: String(describing: error)])
            state = .nonUSCountry
            return
        }

        // STEP 3: Reverse-geocode via CountryGate
        let iso: String
        do {
            iso = try await countryGate.resolveCountry(for: loc)
        } catch {
            logger.warn(event: .init("phone_entry_geocode_failed"),
                        fields: [.event: String(describing: error)])
            state = .nonUSCountry
            return
        }

        // STEP 4: Country gate (D-20)
        guard iso == "US" else {
            logger.info(event: .init("phone_entry_non_us"),
                        fields: [.event: iso])
            state = .nonUSCountry
            return
        }

        // STEP 5: POST /auth/otp/request (US confirmed)
        state = .requestingOTP
        do {
            let endpoint = OTPRequestEndpoint(phone: Self.formatE164(phoneDigits))
            let resp = try await apiClient.request(endpoint)
            state = .otpRequested(otpSessionID: resp.otpSessionID)
            onPhoneSubmitted?(resp.otpSessionID)
        } catch {
            logger.error(event: .init("phone_entry_otp_request_failed"),
                         fields: [.event: String(describing: error)])
            state = .error(message: "Couldn't request a code. Try again.")
        }
    }
}
