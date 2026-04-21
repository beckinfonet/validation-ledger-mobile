# Cert Rotation Runbook

**Status:** ACTIVE — Phase 2 SEC-01 / FOUND-05 runbook. Review before every cert rotation.
**Canonical file to edit during rotation:** `validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift`

## Why Dual-Pin Rotation Is Not Optional

Single-pin deployment means the day the pinned cert expires or is compromised, every installed
app version is bricked — no network, no recovery except a point-release through App Store review
(1–2 days minimum, 7+ days if Apple flags anything). Dual-pin (primary + backup) keeps a backup
path live so rotation is a planned event, not a crisis. See `.planning/research/PITFALLS.md` P3
and the Phase 2 research doc §Pitfall 6.

Both pins MUST be from DIFFERENT key pairs. A common mistake: setting the "backup" to the same
cert's SPKI "for redundancy." That defeats the mechanism — there's nothing to fall back to.
The `stagingPinsDiffer` + `releasePinsDiffer` unit tests in
`validationLedgerTests/Networking/CertificatePinningTests.swift` are the compile-time safety net.

## SPKI Hash Extraction

The backend team (or iOS team, coordinating) extracts the Base64-encoded SHA-256 of the
SubjectPublicKeyInfo for each cert. These hashes go into `PinnedSPKIs.swift`.

### From a live server

```bash
openssl s_client -connect api.validationledger.com:443 \
                 -servername api.validationledger.com </dev/null 2>/dev/null | \
  openssl x509 -pubkey -noout | \
  openssl pkey -pubin -outform DER | \
  openssl dgst -sha256 -binary | \
  openssl enc -base64
```

### From a PEM cert file (pre-deployment)

```bash
openssl x509 -in leaf-cert.pem -pubkey -noout | \
  openssl pkey -pubin -outform DER | \
  openssl dgst -sha256 -binary | \
  openssl enc -base64
```

The output is a 44-character Base64 string (32-byte SHA-256 + Base64 padding). Paste this into
`PinnedSPKIs.staging.primary` (staging deployment) or `PinnedSPKIs.release.primary`
(production deployment). The backup slot holds the NEXT rotation's pin.

### Generating a test cert (for unit tests)

The `spkiHasherMatchesOpenSSLPipeline` test in `CertificatePinningTests.swift` uses a
deterministic EC P-256 test cert. If the test cert is regenerated, update both the base64 DER
blob AND the expected SPKI hash. Generation pipeline:

```bash
openssl ecparam -name prime256v1 -genkey -noout -out key.pem
openssl req -new -x509 -key key.pem -out cert.pem -days 3650 \
        -subj "/CN=validation-ledger-test"
openssl x509 -in cert.pem -outform DER -out cert.der
base64 -i cert.der               # paste into syntheticTestCertDERBase64
openssl x509 -in cert.pem -pubkey -noout | \
  openssl pkey -pubin -outform DER | \
  openssl dgst -sha256 -binary | \
  openssl enc -base64            # paste into syntheticExpectedSPKIHash
```

### Algorithm assumption

Phase 2 SPKIHasher assumes EC P-256 (secp256r1) certs — the modern default. If the backend
serves RSA (2048 or 4096) or EC P-384, the ASN.1 header in `SPKIHasher.swift` must be updated
to match. Reach out to the backend team before the first rotation to confirm.

## 30-Day Rotation Window Procedure

### Day -30 (preparation)

1. Backend team generates the NEXT-generation cert with a NEW key pair.
2. Backend team (or iOS team) extracts the SPKI hash via the openssl pipeline above.
3. iOS: update `validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift`:
   - Move current `primary` to `backup`.
   - Set NEW cert's SPKI as `primary`.
4. Run `swiftlint lint` + full test suite — `stagingPinsDiffer` and `releasePinsDiffer` must pass.
5. Ship iOS release with the new pair. Wait for TestFlight adoption ≥ 95% active installs
   (tracked via M2 analytics once vendor is chosen; until then: manual device-count estimation).

### Day 0 (cert swap)

1. Backend team swaps the live server cert from OLD to NEW.
2. Monitor for pin-mismatch crash reports (none expected if Day -30 preparation was correct).
3. Verify via `openssl s_client` that the live server now serves the NEW cert.

### Day +7 (cleanup)

1. Backend team generates NEXT-next-generation cert (the new "backup").
2. iOS: update `PinnedSPKIs.swift` again:
   - `primary` stays (current live cert's SPKI).
   - Update `backup` to the next-next cert's SPKI.
3. Ship iOS release.

## Emergency Revoke Path

If the current primary cert is compromised before the planned rotation window:

1. Backend team immediately swaps the live server cert to the current BACKUP (which iOS already pins).
2. iOS users with the current release continue working (backup pin is still valid).
3. iOS: ship an emergency release rotating `primary` to the previously-backup cert's SPKI and a new `backup`.
4. **Target timelines:** emergency release to TestFlight within 4 hours; App Store expedited review within 24 hours (cite "security regression blocking users" in the submission notes).
5. Monitor crash reports + `NetworkError.pinningFailed` counts in logs.

## Rollback Procedure

If a rotation release ships a bad pin (e.g., typo in `primary` or `backup`):

1. Emergency release with both pins restored to the PRIOR working cert's SPKIs.
2. Submit to App Store expedited review (cite "security regression blocking users").
3. Backend team DOES NOT rotate the server cert until iOS adoption of the restored pins is ≥ 95%.
4. Root-cause the typo: was it a copy-paste error? A wrong algorithm's ASN.1 header? A missing backup? Document in a post-mortem at `.planning/incidents/NNNN-cert-rotation-rollback.md`.

## CI Checks (ship with Phase 2)

### Compile-time safety tests in `validationLedgerTests/Networking/CertificatePinningTests.swift`:

```swift
@Test("Staging primary and backup differ — prevents self-brick DoS")
func stagingPinsDiffer() {
    #expect(PinnedSPKIs.staging.primary != PinnedSPKIs.staging.backup)
}

@Test("Release primary and backup differ — prevents self-brick DoS")
func releasePinsDiffer() {
    #expect(PinnedSPKIs.release.primary != PinnedSPKIs.release.backup)
}

@Test("Release builds must not ship with PHASE2-TODO placeholders")
func noReleasePlaceholders() {
    #if DEBUG
    // Accepted in DEBUG — placeholders are the Phase 2 starting state.
    #else
    #expect(!PinnedSPKIs.release.primary.hasPrefix("PHASE2-TODO"))
    #expect(!PinnedSPKIs.release.backup.hasPrefix("PHASE2-TODO"))
    #endif
}
```

The `noReleasePlaceholders` test is the safety gate that prevents a Release build from
shipping to TestFlight with the `PHASE2-TODO-*` placeholders still in place. When the backend
cert is ready and the placeholders are filled in, this test passes in both DEBUG and Release.

The `spkiHasherMatchesOpenSSLPipeline` test proves the Swift implementation in
`SPKIHasher.swift` produces identical output to the canonical openssl pipeline shown above —
so the hash the unit test computes is the same hash the operator extracts when rotating.

### Integration test (ships with Plan 07)

`validationLedgerTests/Networking/CertificatePinningIntegrationTests.swift` exercises the
dual-pin acceptance + third-cert rejection through a real URLSession configured with
`PinningSessionDelegate`. It uses three self-signed EC P-256 certs embedded as DER blobs in the
test file. See Plan 07 for that test.

## Related

- `.planning/research/PITFALLS.md` P3 (self-brick DoS without rotation)
- `.planning/phases/02-networking-contract-device-keys/02-RESEARCH.md` §Pattern 4 (dual-pin validation)
- `.planning/phases/02-networking-contract-device-keys/02-RESEARCH.md` §Pitfall 6 (cert rotation self-brick)
- `.planning/REQUIREMENTS.md` FOUND-05, SEC-01
- `docs/ci.md` Device CI security-path filter (includes `Core/Networking/CertificatePinning/**`)
- Apple docs: [Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave), [Identity Pinning](https://developer.apple.com/news/?id=g9ejcf8y)
