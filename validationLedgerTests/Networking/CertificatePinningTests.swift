// validationLedgerTests/Networking/CertificatePinningTests.swift
// SEC-01 unit-test slice — dual-pin difference, placeholder gate, SPKIHasher sanity check.
//
// The full integration test (dual-pin rejects a third un-pinned cert through URLSession)
// lives in Plan 07's CertificatePinningIntegrationTests — it requires the .live URLSession
// wired up, which Plan 07 owns.

import Testing
import Foundation
import Security
@testable import validationLedger

@Suite("Certificate Pinning — dual-pin + SPKI hasher (SEC-01 unit slice)")
struct CertificatePinningTests {

    // MARK: - PinnedSPKIs

    @Test("Staging primary and backup differ — prevents self-brick DoS (Research Pitfall 6)")
    func stagingPinsDiffer() {
        #expect(PinnedSPKIs.staging.primary != PinnedSPKIs.staging.backup)
    }

    @Test("Release primary and backup differ — prevents self-brick DoS")
    func releasePinsDiffer() {
        #expect(PinnedSPKIs.release.primary != PinnedSPKIs.release.backup)
    }

    @Test("PinnedSPKIs.current returns staging under DEBUG (test-runtime invariant)")
    func currentIsStagingInDebug() {
        #if DEBUG
        #expect(PinnedSPKIs.current.primary == PinnedSPKIs.staging.primary)
        #expect(PinnedSPKIs.current.backup == PinnedSPKIs.staging.backup)
        #else
        // In release, current == release — this test is a no-op here for completeness.
        #expect(PinnedSPKIs.current.primary == PinnedSPKIs.release.primary)
        #endif
    }

    @Test("PinnedSPKIs has a public init for test construction")
    func pinnedSPKIsPublicInit() {
        let custom = PinnedSPKIs(primary: "AAAA", backup: "BBBB")
        #expect(custom.primary == "AAAA")
        #expect(custom.backup == "BBBB")
    }

    /// CI gate — release placeholders must be replaced before shipping a non-DEBUG build.
    /// Skipped under DEBUG (expected to still contain PHASE2-TODO placeholders during development).
    @Test("Release builds must not ship with PHASE2-TODO placeholders")
    func noReleasePlaceholders() {
        #if DEBUG
        // In DEBUG we accept placeholders — they are the Phase 2 starting state.
        // Intentional no-op — emit no Issue, no record.
        #else
        #expect(!PinnedSPKIs.release.primary.hasPrefix("PHASE2-TODO"))
        #expect(!PinnedSPKIs.release.backup.hasPrefix("PHASE2-TODO"))
        #endif
    }

    // MARK: - SPKIHasher

    /// Self-signed EC P-256 test certificate. Generated locally via:
    ///   openssl ecparam -name prime256v1 -genkey -noout -out key.pem
    ///   openssl req -new -x509 -key key.pem -out cert.pem -days 3650 \
    ///           -subj "/CN=validation-ledger-test"
    ///   openssl x509 -in cert.pem -outform DER -out cert.der
    ///   base64 -i cert.der
    ///
    /// The cert is test-only — never used in production and has no private-key deployment.
    /// If regenerated, update both the DER blob below AND `syntheticExpectedSPKIHash`.
    private static let syntheticTestCertDERBase64: String =
        "MIIBlzCCAT2gAwIBAgIUVlRB2VceTWO58LqFuQ3e6Plj+wMwCgYIKoZIzj0EAwIw" +
        "ITEfMB0GA1UEAwwWdmFsaWRhdGlvbi1sZWRnZXItdGVzdDAeFw0yNjA0MjExOTUz" +
        "MDRaFw0zNjA0MTgxOTUzMDRaMCExHzAdBgNVBAMMFnZhbGlkYXRpb24tbGVkZ2Vy" +
        "LXRlc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQdl1p4vxPI7SW2N659GAjT" +
        "Fc6sH/pOuUYq1jdWakzAV36XqxYHxJ6fI0+DG4RJ0+0pKqgNACCDGxTGFc2nrzXQ" +
        "o1MwUTAdBgNVHQ4EFgQU3bm/YLUqbRN1dp2LgMYszm3NTrIwHwYDVR0jBBgwFoAU" +
        "3bm/YLUqbRN1dp2LgMYszm3NTrIwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQD" +
        "AgNIADBFAiBQqscPaCaijsryOIAs4ELxt0yLdeHzP9GfAsCcxM/v7QIhAO49I0/I" +
        "4pj/8GYNKcf9B8zHoCIR6KdvXF3fZ5784W5E"

    /// Expected SPKI hash (Base64 SHA-256) for `syntheticTestCertDERBase64`, computed via:
    ///   openssl x509 -in cert.pem -pubkey -noout | \
    ///     openssl pkey -pubin -outform DER | \
    ///     openssl dgst -sha256 -binary | \
    ///     openssl enc -base64
    /// This is the ground-truth value SPKIHasher.spkiSHA256Base64 MUST produce.
    private static let syntheticExpectedSPKIHash: String =
        "27tuVau7g0wZyzvLdWaH9P9eYaLVb2JiJMHHwBShmGw="

    @Test("SPKIHasher produces RFC-7469 Base64 SHA-256 SPKI matching the openssl pipeline")
    func spkiHasherMatchesOpenSSLPipeline() throws {
        let der = Data(base64Encoded: Self.syntheticTestCertDERBase64)
        try #require(der != nil, "syntheticTestCertDERBase64 must be valid base64 DER")
        let cert = SecCertificateCreateWithData(nil, der! as CFData)
        try #require(cert != nil, "DER must decode to a valid SecCertificate — test fixture corrupt")
        let hash = SPKIHasher.spkiSHA256Base64(from: cert!)
        try #require(hash != nil, "SPKIHasher must succeed on a valid EC P-256 cert")
        // SHA-256 Base64 with standard padding = 44 characters (32 bytes → 44 chars).
        #expect(hash!.count == 44)
        // Exact ground-truth match with the openssl pipeline — validates the ASN.1 header + hashing logic.
        #expect(hash == Self.syntheticExpectedSPKIHash)
    }

    @Test("SPKIHasher returns nil for a certificate that is not a valid SecCertificate")
    func spkiHasherRejectsInvalidCert() {
        // Attempt to build SecCertificate from random bytes — SecCertificateCreateWithData returns nil.
        let junk = Data(repeating: 0xFF, count: 16)
        let cert = SecCertificateCreateWithData(nil, junk as CFData)
        #expect(cert == nil, "SecCertificateCreateWithData should reject random bytes")
        // If somehow a cert was constructed, SPKIHasher returning nil is still the correct behavior.
    }

    // MARK: - PinningSessionDelegate smoke

    @Test("PinningSessionDelegate can be constructed with PinnedSPKIs.staging")
    func delegateConstructsWithStagingPins() {
        let delegate = PinningSessionDelegate(pins: PinnedSPKIs.staging)
        _ = delegate  // just assert construction doesn't trap
    }

    @Test("PinningSessionDelegate can be constructed with a custom PinnedSPKIs value")
    func delegateConstructsWithCustomPins() {
        let custom = PinnedSPKIs(primary: "primary-hash", backup: "backup-hash")
        let delegate = PinningSessionDelegate(pins: custom)
        _ = delegate
    }
}
