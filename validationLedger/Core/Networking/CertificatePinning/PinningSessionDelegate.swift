// validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift
// SEC-01 + FOUND-05: URLSessionDelegate challenge handler enforcing dual-pin SPKI validation.
//
// Phase 1 shipped the skeleton (D-05 security-path CI trigger has a file to detect).
// Phase 2 Plan 05: FILLED IN with the actual dual-SPKI validation body.
//
// Design:
//  1. Accept the challenge only if authenticationMethod == ServerTrust.
//  2. Evaluate the full trust chain (chain + hostname + expiry) via SecTrustEvaluateWithError.
//  3. Extract the leaf cert's SPKI and Base64 SHA-256 hash via SPKIHasher.
//  4. Accept if the hash matches EITHER pins.primary OR pins.backup (dual-pin rotation-safety).
//  5. Reject otherwise (.cancelAuthenticationChallenge) — never `.performDefaultHandling`
//     as a fallback, because that opens the door to system trust evaluation and bypasses pinning.
//
// Single-completion invariant: completionHandler fires EXACTLY ONCE on every return path.
// See Research Pitfall 4 — the C-era callback contract is NOT compile-enforced, but every
// `return` in this method is preceded by `completionHandler(...)` and no early-continue paths exist.
//
// AppContainer (Plan 07) installs this delegate ONLY on the `.live` URLSession — the mock
// session must not receive pinning, else `https://mock.local` fails the pin check for every test.

import Foundation
import Security

public final class PinningSessionDelegate: NSObject, URLSessionDelegate {
    private let pins: PinnedSPKIs

    public init(pins: PinnedSPKIs) {
        self.pins = pins
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only ServerTrust challenges are within pinning scope — other auth methods (e.g.,
        // client-cert, basic auth) should be rejected here; Phase 2 does not use them.
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 1 — Evaluate the chain + hostname + expiry. A bad chain (e.g., self-signed cert,
        // expired leaf, hostname mismatch) rejects before we even extract SPKI.
        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 2 — Get the leaf cert (index 0 in the chain).
        // SecTrustGetCertificateAtIndex is deprecated in iOS 15+ in favor of
        // SecTrustCopyCertificateChain; use the modern API.
        guard let leafCert = Self.leafCertificate(from: serverTrust) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 3 — Extract the leaf SPKI hash via SPKIHasher.
        guard let leafHash = SPKIHasher.spkiSHA256Base64(from: leafCert) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 4 — Dual-pin match: accept if EITHER primary OR backup matches.
        if leafHash == pins.primary || leafHash == pins.backup {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        // Step 5 — Pin mismatch. Do NOT log the actual hash (infrastructure signal leak; also
        // not PII but noise in routine log feeds). Plan 07 wires a Logger for structured
        // "pinning_rejected" events.
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - Private helpers

    /// Return the leaf (end-entity) certificate from a SecTrust.
    /// Prefers SecTrustCopyCertificateChain (iOS 15+) and falls back to
    /// SecTrustGetCertificateAtIndex(_, 0) for defensive safety.
    private static func leafCertificate(from serverTrust: SecTrust) -> SecCertificate? {
        if #available(iOS 15.0, *), let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] {
            return chain.first
        }
        // Fallback path (also fine on iOS 17 but kept defensive)
        return SecTrustGetCertificateAtIndex(serverTrust, 0)
    }
}
