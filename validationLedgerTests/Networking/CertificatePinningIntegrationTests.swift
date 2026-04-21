// validationLedgerTests/Networking/CertificatePinningIntegrationTests.swift
// SEC-01 SC-5: Dual-pin cert pinning accepts primary + backup, rejects a third un-pinned cert.
//
// Approach (Research Option C / Plan 07 §action):
//   Synthesize URLAuthenticationChallenge with a mocked URLProtectionSpace whose serverTrust
//   returns a SecTrust built from embedded DER certs. Drive PinningSessionDelegate directly —
//   the delegate's contract IS the completion-handler call, so a real URLSession is not required
//   to validate the accept/reject logic.
//
// Three self-signed EC P-256 test certs are embedded as base64 DER strings. Generated locally via
// `openssl ecparam + req + x509` (see docs/cert-rotation.md §SPKI extraction). These certs are
// test-only; their private keys are discarded and never deployed. If regenerated, update:
//   - certADERBase64 / certBDERBase64 / certRogueDERBase64 (base64-DER)
//   - certASPKIHash / certBSPKIHash (44-char Base64 SHA-256 SPKI hash)

import Testing
import Foundation
import Security
@testable import validationLedger

/// Protection space subclass that lets tests inject a synthetic SecTrust.
/// Required because URLProtectionSpace's public init does NOT accept a serverTrust;
/// without this override, PinningSessionDelegate would see a nil serverTrust and
/// hit the .cancelAuthenticationChallenge early-return (obscuring the pin-match logic).
private final class MockServerTrustProtectionSpace: URLProtectionSpace, @unchecked Sendable {
    private let injectedTrust: SecTrust
    init(host: String, trust: SecTrust) {
        self.injectedTrust = trust
        super.init(
            host: host,
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
    }
    required init?(coder: NSCoder) { fatalError("unused") }
    override var serverTrust: SecTrust? { injectedTrust }
}

/// Dummy challenge sender — URLAuthenticationChallenge's public init requires one, but
/// PinningSessionDelegate never calls back through it (it uses the completionHandler closure).
private final class DummyChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

@Suite("PinningSessionDelegate — dual-pin integration (SEC-01 SC-5)", .serialized)
struct CertificatePinningIntegrationTests {

    // MARK: - Test certs (base64 DER) — self-signed EC P-256, 10-year validity
    //
    // Regenerate via docs/cert-rotation.md §Test-cert regeneration:
    //   for name in cert-a cert-b cert-rogue; do
    //     openssl ecparam -name prime256v1 -genkey -noout -out $name.key
    //     openssl req -new -x509 -key $name.key -out $name.pem -days 3650 \
    //       -subj "/CN=$name.validationledger.test"
    //     openssl x509 -in $name.pem -outform DER | base64 | tr -d '\n'
    //   done

    private static let certADERBase64 =
        "MIIBojCCAUmgAwIBAgIUF2Zmfe/awzflbc6Svrz5P3DC6bQwCgYIKoZIzj0EAwIw" +
        "JzElMCMGA1UEAwwcY2VydC1hLnZhbGlkYXRpb25sZWRnZXIudGVzdDAeFw0yNjA0" +
        "MjEyMDE4NDdaFw0zNjA0MTgyMDE4NDdaMCcxJTAjBgNVBAMMHGNlcnQtYS52YWxp" +
        "ZGF0aW9ubGVkZ2VyLnRlc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQ6+PAc" +
        "ozyVEcqxtX2Po2P9jkyUvOJPoQUbwlQ7pFtrCrtPKeC/8eL1UlpCQfwnbeYXVx1Z" +
        "73drxPEMebBjqGUYo1MwUTAdBgNVHQ4EFgQUZBCxFBOLxaDniGt9FSSOP7C3OW8w" +
        "HwYDVR0jBBgwFoAUZBCxFBOLxaDniGt9FSSOP7C3OW8wDwYDVR0TAQH/BAUwAwEB" +
        "/zAKBggqhkjOPQQDAgNHADBEAiARqen1zOZOfTuA/ax5UsE0LEY/hUjxZrR6txKP" +
        "mWrl+gIgZ7/5GbkWejJD1iazq2Tis9pvWmHVhoGKMnmZJp2F8s4="

    private static let certBDERBase64 =
        "MIIBozCCAUmgAwIBAgIUZvyGKCx7tRiWL7y02iHetJO5GgcwCgYIKoZIzj0EAwIw" +
        "JzElMCMGA1UEAwwcY2VydC1iLnZhbGlkYXRpb25sZWRnZXIudGVzdDAeFw0yNjA0" +
        "MjEyMDE4NDdaFw0zNjA0MTgyMDE4NDdaMCcxJTAjBgNVBAMMHGNlcnQtYi52YWxp" +
        "ZGF0aW9ubGVkZ2VyLnRlc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARON2VG" +
        "XIgTovOEuetsdSp5m7eWjFbxGzfUEA0eJNJ9rKZ5Me4AYe8qlfr+3FqdkrkJs1BY" +
        "mJVl08QX/G+p5XGTo1MwUTAdBgNVHQ4EFgQUO02GuhHp/nZK/R2LG/jMHAlb3zEw" +
        "HwYDVR0jBBgwFoAUO02GuhHp/nZK/R2LG/jMHAlb3zEwDwYDVR0TAQH/BAUwAwEB" +
        "/zAKBggqhkjOPQQDAgNIADBFAiBXCiOSzNgaJ+dOeyNIGMHcRYRdEQg3827U12GW" +
        "eiXFDgIhAKsOYp76fzjMju6ZHg9TWqGAAIGNTJvfTYhmTOv/iP7b"

    private static let certRogueDERBase64 =
        "MIIBqzCCAVGgAwIBAgIUZGb/OleOkNAU6kbpUV8MUSdJGYIwCgYIKoZIzj0EAwIw" +
        "KzEpMCcGA1UEAwwgY2VydC1yb2d1ZS52YWxpZGF0aW9ubGVkZ2VyLnRlc3QwHhcN" +
        "MjYwNDIxMjAxODQ3WhcNMzYwNDE4MjAxODQ3WjArMSkwJwYDVQQDDCBjZXJ0LXJv" +
        "Z3VlLnZhbGlkYXRpb25sZWRnZXIudGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEH" +
        "A0IABNaccnGUVvxx8iFcd+v0g6hUV2sx08W5n8fSDz82O3XQ+hyfogIw5Mbw8qMr" +
        "BgMbUdHb2hJ2neiBw78kn953K3ejUzBRMB0GA1UdDgQWBBSuYuNxBIVphPUdtaro" +
        "tJjntTLxxTAfBgNVHSMEGDAWgBSuYuNxBIVphPUdtarotJjntTLxxTAPBgNVHRMB" +
        "Af8EBTADAQH/MAoGCCqGSM49BAMCA0gAMEUCIQDA0ZjwKi8ZtEv6iQbyqVVrYcdk" +
        "CQ4fcbXct3Yah1VHEwIgEhTrDI9vqiuHD0k8dDdoj2SnybD7lLbccy8dC99BKbE="

    /// SPKI Base64 SHA-256 hash for cert-a. Computed via:
    ///   openssl x509 -in cert-a.pem -pubkey -noout | openssl pkey -pubin -outform DER |
    ///   openssl dgst -sha256 -binary | openssl enc -base64
    private static let certASPKIHash = "Rqe/g1mCb8yAciSypDcqhcMlDVBehqPNMglGwHYV+jE="

    /// SPKI Base64 SHA-256 hash for cert-b. Same pipeline as cert-a.
    private static let certBSPKIHash = "uE04n2FSYLV75/QkKUPtm8DpKaEjbjPhW9EzGfEC+qU="

    // MARK: - Helpers

    private func secCert(fromBase64 der: String) -> SecCertificate? {
        guard let derData = Data(base64Encoded: der) else { return nil }
        return SecCertificateCreateWithData(nil, derData as CFData)
    }

    private func secTrust(with cert: SecCertificate) -> SecTrust? {
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        // SecTrustCreateWithCertificates accepts either a single SecCertificate or a CFArray.
        // Wrap in an array to pass a chain (even a 1-element chain) explicitly.
        let status = SecTrustCreateWithCertificates([cert] as CFArray, policy, &trust)
        guard status == errSecSuccess else { return nil }
        return trust
    }

    private func challenge(with trust: SecTrust) -> URLAuthenticationChallenge {
        let protectionSpace = MockServerTrustProtectionSpace(
            host: "mock.validationledger.test",
            trust: trust
        )
        return URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: DummyChallengeSender()
        )
    }

    /// Drive the delegate's challenge method and capture the (disposition, credential) result.
    /// Uses a continuation because PinningSessionDelegate is URLSessionDelegate — its completion
    /// handler is a closure, not an async return.
    private func invokeDelegate(
        _ delegate: PinningSessionDelegate,
        with challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await withCheckedContinuation { cont in
            delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, credential in
                cont.resume(returning: (disposition, credential))
            }
        }
    }

    // MARK: - Tests

    @Test("Delegate accepts primary-pin certificate (self-signed EC P-256 chain-eval skip)")
    func acceptsPrimary() async throws {
        // Plan 05's PinningSessionDelegate calls SecTrustEvaluateWithError which rejects
        // self-signed certs — the chain eval runs BEFORE the SPKI match. For this integration
        // test, we configure the SecTrust with anchor certs = our test cert itself so the
        // chain evaluation succeeds; the SPKI match path is what we actually want to exercise.
        guard let cert = secCert(fromBase64: Self.certADERBase64),
              let trust = secTrust(with: cert) else {
            Issue.record("Failed to construct SecCertificate/SecTrust for cert-A")
            return
        }
        // Anchor the trust to the cert itself so chain-eval accepts the self-signed cert.
        SecTrustSetAnchorCertificates(trust, [cert] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)

        let pins = PinnedSPKIs(primary: Self.certASPKIHash, backup: Self.certBSPKIHash)
        let delegate = PinningSessionDelegate(pins: pins)
        let (disposition, credential) = await invokeDelegate(delegate, with: challenge(with: trust))
        #expect(disposition == .useCredential, "Primary pin must accept — cert-A's SPKI matches pins.primary")
        #expect(credential != nil)
    }

    @Test("Delegate accepts backup-pin certificate (rotation-safety invariant)")
    func acceptsBackup() async throws {
        guard let cert = secCert(fromBase64: Self.certBDERBase64),
              let trust = secTrust(with: cert) else {
            Issue.record("Failed to construct SecCertificate/SecTrust for cert-B")
            return
        }
        SecTrustSetAnchorCertificates(trust, [cert] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)

        let pins = PinnedSPKIs(primary: Self.certASPKIHash, backup: Self.certBSPKIHash)
        let delegate = PinningSessionDelegate(pins: pins)
        let (disposition, credential) = await invokeDelegate(delegate, with: challenge(with: trust))
        #expect(disposition == .useCredential, "Backup pin must accept — cert-B's SPKI matches pins.backup")
        #expect(credential != nil)
    }

    @Test("Delegate rejects a third un-pinned certificate (SEC-01 SC-5 primary assertion)")
    func rejectsRogue() async throws {
        guard let cert = secCert(fromBase64: Self.certRogueDERBase64),
              let trust = secTrust(with: cert) else {
            Issue.record("Failed to construct SecCertificate/SecTrust for rogue cert")
            return
        }
        SecTrustSetAnchorCertificates(trust, [cert] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)

        // Pin only against cert-A + cert-B — the rogue cert's SPKI hash matches NEITHER.
        let pins = PinnedSPKIs(primary: Self.certASPKIHash, backup: Self.certBSPKIHash)
        let delegate = PinningSessionDelegate(pins: pins)
        let (disposition, credential) = await invokeDelegate(delegate, with: challenge(with: trust))
        #expect(
            disposition == .cancelAuthenticationChallenge,
            "Rogue cert must reject — its SPKI matches neither primary nor backup"
        )
        #expect(credential == nil)
    }

    @Test("Delegate rejects non-ServerTrust authentication methods")
    func rejectsNonServerTrust() async throws {
        // Any authenticationMethod != NSURLAuthenticationMethodServerTrust should reject
        // immediately — pinning scope is ONLY ServerTrust challenges (Plan 05 invariant).
        let protectionSpace = URLProtectionSpace(
            host: "mock.test",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodDefault
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: DummyChallengeSender()
        )
        let pins = PinnedSPKIs(primary: "a", backup: "b")
        let delegate = PinningSessionDelegate(pins: pins)
        let (disposition, credential) = await invokeDelegate(delegate, with: challenge)
        #expect(disposition == .cancelAuthenticationChallenge)
        #expect(credential == nil)
    }
}
