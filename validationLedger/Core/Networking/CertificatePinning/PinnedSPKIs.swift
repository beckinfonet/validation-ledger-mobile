// validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift
// SEC-01 + FOUND-05: compile-time pinned SPKI (SubjectPublicKeyInfo) SHA-256 Base64 hashes.
//
// Dual-pin pattern (primary + backup) is mandatory — single-pin deployment creates a self-brick
// DoS on cert rotation (Research Pitfall 6 + docs/cert-rotation.md).
//
// Hashes are COMPILE-TIME Swift constants baked into the binary, NOT JSON/Info.plist.
// App repackaging would be required to tamper — stronger trust model than NSPinnedDomains
// (which Apple's docs underspecify for URLSession + are tamperable by plist edit).
// See Research §Alternatives Considered — NSPinnedDomains row + Guardsquare analysis.
//
// Phase 2 ships PHASE2-TODO placeholders for release values — the backend is a separate GSD
// project and real SPKIs don't exist yet. `docs/cert-rotation.md` documents the openssl
// extraction pipeline for when real hashes become available. A unit test (noReleasePlaceholders)
// is gated to non-DEBUG builds to prevent shipping release with placeholders.

import Foundation

public struct PinnedSPKIs: Sendable {
    /// Base64-encoded SHA-256 of SubjectPublicKeyInfo (DER) for the primary (current) cert.
    public let primary: String
    /// Base64-encoded SHA-256 of SubjectPublicKeyInfo (DER) for the backup (next-rotation) cert.
    public let backup: String

    public init(primary: String, backup: String) {
        self.primary = primary
        self.backup = backup
    }

    /// Staging pins — used when DEBUG build configuration is active.
    /// Replace PHASE2-TODO placeholders with real staging-cert hashes once backend ships.
    public static let staging = PinnedSPKIs(
        primary: "PHASE2-TODO-STAGING-LEAF-SPKI-SHA256-BASE64",
        backup:  "PHASE2-TODO-STAGING-BACKUP-SPKI-SHA256-BASE64"
    )

    /// Release pins — used when DEBUG build configuration is NOT active.
    /// A CI gate (`noReleasePlaceholders` test) catches shipping release builds with placeholders.
    public static let release = PinnedSPKIs(
        primary: "PHASE2-TODO-RELEASE-LEAF-SPKI-SHA256-BASE64",
        backup:  "PHASE2-TODO-RELEASE-BACKUP-SPKI-SHA256-BASE64"
    )

    /// Current pins selected by build configuration.
    /// AppContainer (Plan 07) constructs PinningSessionDelegate with `PinnedSPKIs.current`.
    public static var current: PinnedSPKIs {
        #if DEBUG
        return .staging
        #else
        return .release
        #endif
    }
}
