// validationLedger/Core/Networking/CertificatePinning/SPKIHasher.swift
// SEC-01 / FOUND-05: transform a SecCertificate into the Base64-encoded SHA-256 of its
// SubjectPublicKeyInfo (SPKI) per RFC 7469.
//
// SPKI survives certificate renewal as long as the same keypair is used — unlike full-cert
// hashing, which breaks on every renewal. RFC-7469 is the recommended pinning format.
//
// IMPLEMENTATION NOTE: The 26-byte ASN.1 header below is specific to EC P-256
// (secp256r1 / prime256v1). If the backend serves RSA or EC P-384 certs, a different
// header is required. Phase 2 assumes EC P-256 per Research §Assumption A1 (modern default);
// if the backend team confirms otherwise, extend with an algorithm parameter.

import Foundation
import Security
import CryptoKit

public enum SPKIHasher {

    /// 26-byte ASN.1 DER header prefixing the raw EC P-256 public key bytes returned by
    /// SecKeyCopyExternalRepresentation to reconstruct the SubjectPublicKeyInfo structure.
    /// This exact byte sequence is the ID-EC-PUBLICKEY / secp256r1 OID prefix per RFC 5480.
    private static let ecP256ASN1Header: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]

    /// Extract, hash, and Base64-encode the SPKI of an EC P-256 certificate.
    /// Returns nil if SecCertificateCopyKey / SecKeyCopyExternalRepresentation fail —
    /// caller should treat nil as a pinning failure (reject the connection).
    public static func spkiSHA256Base64(from certificate: SecCertificate) -> String? {
        // iOS 15+: SecCertificateCopyKey is the supported API (SecTrustCopyPublicKey is deprecated).
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }
        // Reconstruct the SubjectPublicKeyInfo: ASN.1 header + raw key bytes.
        var spki = Data()
        spki.append(contentsOf: Self.ecP256ASN1Header)
        spki.append(keyData)
        let hash = SHA256.hash(data: spki)
        return Data(hash).base64EncodedString()
    }
}
