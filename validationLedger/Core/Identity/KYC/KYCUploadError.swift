// validationLedger/Core/Identity/KYC/KYCUploadError.swift
// Phase 5 Plan 04 (UPL-01..04 / SC-5): the typed error surface of `KYCUploader`.
//
// `KYCUploader` composes the shipped `APIClient` (which throws exclusively
// `NetworkError`). This enum is the uploader's *own* failure vocabulary — it
// wraps or replaces `NetworkError` at the boundary so callers (the KYC review
// view-model in plan 05-06) pattern-match a stable, upload-specific surface
// rather than the generic transport errors.

import Foundation

/// Errors surfaced by `KYCUploader`.
public enum KYCUploadError: Error, Sendable, Equatable {

    /// A chunk POST failed every retry attempt — the 5-attempt cap (UPL-03) was
    /// reached. The associated value is the 0-based index of the failing chunk.
    case retriesExhausted(chunkIndex: Int)

    /// The final `POST /kyc/upload/commit` did not succeed.
    case commitFailed

    /// `upload(artifactType:)` was called but no local `Data` exists for that
    /// artifact in the `KYCSessionStore` — it was never captured, or the local
    /// copy was already deleted post-commit (D-02).
    case artifactDataMissing(KYCUploadInitEndpoint.ArtifactType)

    /// A non-retryable transport failure (a 4xx other than 429, a decoding
    /// failure, an encoding failure) — surfaced immediately, no retry.
    case nonRetryable(NetworkError)

    public static func == (lhs: KYCUploadError, rhs: KYCUploadError) -> Bool {
        switch (lhs, rhs) {
        case let (.retriesExhausted(l), .retriesExhausted(r)):
            return l == r
        case (.commitFailed, .commitFailed):
            return true
        case let (.artifactDataMissing(l), .artifactDataMissing(r)):
            return l == r
        case let (.nonRetryable(l), .nonRetryable(r)):
            // NetworkError is not Equatable — compare by case + the comparable
            // associated values that matter for assertions (status codes).
            switch (l, r) {
            case let (.httpError(ls, _), .httpError(rs, _)):
                return ls == rs
            case let (.rateLimited(lr), .rateLimited(rr)):
                return lr == rr
            case (.decodingFailed, .decodingFailed),
                 (.encodingFailed, .encodingFailed),
                 (.retriesExhausted, .retriesExhausted),
                 (.pinningFailed, .pinningFailed),
                 (.baseURLMissing, .baseURLMissing),
                 (.unexpectedResponseType, .unexpectedResponseType):
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}
