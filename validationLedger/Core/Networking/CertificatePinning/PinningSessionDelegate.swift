// validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift
// SKELETON — Phase 2 lands dual-pin SPKI hash validation (SEC-01 + FOUND-05 full runbook).
// Present in Phase 1 so:
//   (a) Security-path CI trigger (D-05 paths filter) has a file to detect
//   (b) URLSession composition in AppContainer can reference the type
//   (c) Tests for Phase 2 have an import target ready

import Foundation

public final class PinningSessionDelegate: NSObject, URLSessionDelegate {
    public override init() { super.init() }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Phase 1: perform default handling — no pinning yet.
        // Phase 2 replaces this with dual-SPKI-hash validation per PITFALLS.md P3.
        completionHandler(.performDefaultHandling, nil)
    }
}
