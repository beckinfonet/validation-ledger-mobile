// validationLedger/Core/Identity/KYC/RejectionReasonCode.swift
// Phase 5 Plan 02 (KYC-05 / D-11): the rejection-reason controlled vocabulary.
//
// D-11 — the division of ownership: the BACKEND owns the stable code string
// vocabulary; iOS owns the human-facing COPY. The backend sends a snake_case
// code on `KYCStatusEndpoint.Response.Artifact.rejectionReason`; this enum maps
// each known code to a finalized, action-oriented English sentence, and degrades
// any unknown/future code to a fixed generic sentence — the raw code string
// NEVER reaches the UI (threat T-05-02-03).
//
// === BACKEND CONTRACT — coordinate this vocabulary with the backend team ===
// The cases below ARE the iOS-side contract. The backend MUST emit exactly
// these snake_case codes for the copy mapping to hit; any code outside this set
// silently degrades to `kyc.reject.generic`. Current controlled vocabulary:
//   dl_front_glare, dl_front_blurry, dl_expired, dl_back_unreadable,
//   face_not_centered, face_obscured, face_low_light,
//   vehicle_plate_unreadable, vehicle_photo_unclear
// Adding a new rejection reason is a two-sided change: the backend adds the
// code AND iOS adds the case + the `kyc.reject.<code>` string.
//
// Pattern analogs: `Core/Storage/Keychain/KeychainScope.swift` (typed-vocabulary
// enum + pure `switch self` resolver) and `LogoutReason` in `LogoutService.swift`
// (a `String`-raw `Sendable` enum).

import Foundation

/// The D-11 controlled vocabulary of KYC artifact rejection reasons. `String`-
/// raw so the backend code decodes directly; `Decodable` so it can be used where
/// a code string is decoded; `CaseIterable` so the full vocabulary is reviewable.
public enum RejectionReasonCode: String, Decodable, Sendable, CaseIterable {
    case dlFrontGlare = "dl_front_glare"
    case dlFrontBlurry = "dl_front_blurry"
    case dlExpired = "dl_expired"
    case dlBackUnreadable = "dl_back_unreadable"
    case faceNotCentered = "face_not_centered"
    case faceObscured = "face_obscured"
    case faceLowLight = "face_low_light"
    case vehiclePlateUnreadable = "vehicle_plate_unreadable"
    case vehiclePhotoUnclear = "vehicle_photo_unclear"

    /// The finalized, localized, action-oriented copy for this rejection reason
    /// (KYC-05 — "copy finalized in M1"). Pure `switch self` resolver: one
    /// `NSLocalizedString` per case, keyed `kyc.reject.<rawValue>`.
    public var localizedCopy: String {
        switch self {
        case .dlFrontGlare:
            return NSLocalizedString(
                "kyc.reject.dl_front_glare",
                value: "There's glare on your license. Retake it away from direct light.",
                comment: "KYC rejection reason — glare on the front of the driver's license"
            )
        case .dlFrontBlurry:
            return NSLocalizedString(
                "kyc.reject.dl_front_blurry",
                value: "The front of your license is blurry. Hold steady and retake it.",
                comment: "KYC rejection reason — front of the driver's license is out of focus"
            )
        case .dlExpired:
            return NSLocalizedString(
                "kyc.reject.dl_expired",
                value: "This license looks expired. Use a current, valid license.",
                comment: "KYC rejection reason — the driver's license is expired"
            )
        case .dlBackUnreadable:
            return NSLocalizedString(
                "kyc.reject.dl_back_unreadable",
                value: "The back of your license can't be read. Retake it in better light.",
                comment: "KYC rejection reason — the back of the driver's license is unreadable"
            )
        case .faceNotCentered:
            return NSLocalizedString(
                "kyc.reject.face_not_centered",
                value: "Center your face in the frame and take the photo again.",
                comment: "KYC rejection reason — the face is not centered in the frame"
            )
        case .faceObscured:
            return NSLocalizedString(
                "kyc.reject.face_obscured",
                value: "Something is covering your face. Remove it and retake the photo.",
                comment: "KYC rejection reason — the face is partially covered or obscured"
            )
        case .faceLowLight:
            return NSLocalizedString(
                "kyc.reject.face_low_light",
                value: "It's too dark to see your face clearly. Move to better light and retake it.",
                comment: "KYC rejection reason — the face photo was taken in low light"
            )
        case .vehiclePlateUnreadable:
            return NSLocalizedString(
                "kyc.reject.vehicle_plate_unreadable",
                value: "The license plate can't be read. Move closer and retake the photo.",
                comment: "KYC rejection reason — the vehicle license plate is unreadable"
            )
        case .vehiclePhotoUnclear:
            return NSLocalizedString(
                "kyc.reject.vehicle_photo_unclear",
                value: "This vehicle photo is unclear. Retake it with the whole vehicle in frame.",
                comment: "KYC rejection reason — the vehicle photo is unclear"
            )
        }
    }

    /// Resolve a raw backend code string to human copy. A known code maps to its
    /// finalized sentence; an unknown/future code degrades to a fixed generic
    /// sentence. The raw `rawCode` string is NEVER returned — an unrecognized
    /// code can never surface in the UI (D-11 / threat T-05-02-03).
    public static func copy(for rawCode: String) -> String {
        RejectionReasonCode(rawValue: rawCode)?.localizedCopy
            ?? NSLocalizedString(
                "kyc.reject.generic",
                value: "This photo needs to be retaken. Tap to try again.",
                comment: "KYC rejection reason — generic fallback for an unrecognized backend code"
            )
    }
}
