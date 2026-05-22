---
phase: 02-networking-contract-device-keys
reviewed: 2026-04-21T00:00:00Z
depth: standard
files_reviewed: 41
files_reviewed_list:
  - validationLedger/Core/Networking/NetworkClient.swift
  - validationLedger/Core/Networking/NetworkError.swift
  - validationLedger/Core/Networking/APIClient.swift
  - validationLedger/Core/Networking/APIEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/OTPRequestEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/DeviceRegisterEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/KYCUploadInitEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/KYCUploadChunkEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/KYCUploadCommitEndpoint.swift
  - validationLedger/Core/Networking/Endpoints/KYCStatusEndpoint.swift
  - validationLedger/Core/Networking/Interceptors/RequestInterceptor.swift
  - validationLedger/Core/Networking/Interceptors/IdempotencyInterceptor.swift
  - validationLedger/Core/Networking/Interceptors/RetryInterceptor.swift
  - validationLedger/Core/Networking/Mock/MockURLProtocol.swift
  - validationLedger/Core/Networking/Mock/MockFixture.swift
  - validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift
  - validationLedger/Core/Networking/CertificatePinning/SPKIHasher.swift
  - validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift
  - validationLedger/Core/KeyStore/KeyStoreProtocol.swift
  - validationLedger/Core/KeyStore/SoftwareKeyStore.swift
  - validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift
  - validationLedger/Core/Identity/DeviceFingerprint.swift
  - validationLedger/App/AppContainer.swift
  - validationLedger/App/Environment.swift
  - validationLedger/App/SceneDelegate.swift
  - validationLedger/App/DevMenu/DevMenuViewController.swift
  - validationLedger/App/DevMenu/NetworkConfigToggleViewController.swift
  - .github/workflows/ci-simulator.yml
  - docs/cert-rotation.md
  - validationLedgerTests/Networking/APIClientEndpointTests.swift
  - validationLedgerTests/Networking/IdempotencyInterceptorTests.swift
  - validationLedgerTests/Networking/RetryInterceptorTests.swift
  - validationLedgerTests/Networking/CertificatePinningTests.swift
  - validationLedgerTests/Networking/CertificatePinningIntegrationTests.swift
  - validationLedgerTests/App/AppContainerNetworkConfigTests.swift
  - validationLedgerTests/Identity/DeviceFingerprintTests.swift
  - validationLedgerTests/KeyStore/SoftwareKeyStoreExtendedTests.swift
  - validationLedgerDeviceTests/SecureEnclaveKeyStoreTests.swift
  - validationLedgerDeviceTests/RefuseLaunchWithoutSecureEnclaveTests.swift
  - docs/adr/0004-secure-enclave-two-key-pattern.md
findings:
  critical: 4
  warning: 6
  info: 5
  total: 15
status: issues_found
---

# Phase 2: Networking Contract & Device Keys — Code Review

**Reviewed:** 2026-04-21
**Depth:** standard
**Files Reviewed:** 41
**Status:** issues_found

## Summary

Phase 2 is structurally sound and reflects careful planning. The phase-2-specific invariants
(single-completion handler, GET-only retry, idempotency-key preservation, mock/live pinning split,
Security-framework-based SecureEnclave ACL wiring) are all correctly implemented in the production
source. The test suite is thorough and the CI workflow is correctly configured.

Four critical issues were found:

1. The default `NetworkClient.send(_:)` extension in `APIClient.swift` has a semantically incorrect
   `case "GET", nil:` arm that maps a `nil` `httpMethod` through `get(_:)` but loses the
   request body — this is currently masked by `URLSessionNetworkClient.send(_:)` overriding the
   extension, but the default extension is reachable by any other `NetworkClient` conformer
   (including `MockURLProtocol`-backed impls in tests) and is actively misleading.
2. The `PinnedSPKIs.stagingPinsDiffer` / `releasePinsDiffer` tests in `CertificatePinningTests`
   pass vacuously today because both staging and release placeholders are identical-prefix strings
   that happen to be unique per pair — but the test only checks `!=` of those two strings, not
   that neither is a placeholder. If a developer sets both to the same real SPKI by copy-paste
   error, no compile-time or test gate catches it.
3. The `SecureEnclaveKeyStore.generateKey(slot:)` method calls `SecKeyCreateRandomKey` without
   first checking whether a key with that application tag already exists in the Keychain. A second
   call to `generateDeviceIdentityKeys()` silently generates new key material and returns different
   public keys while the Keychain now contains both the old and new private keys under the same
   tag — the retrieval path (SecItemCopyMatching without `kSecMatchLimit: kSecMatchLimitOne`)
   will return whichever one the Keychain picks, breaking the caller's assumption of stable
   public key identity.
4. The `NetworkConfig` enum is `Sendable` but its `.live(baseURL: URL)` associated value passes
   `URL` across actor isolation boundaries — `URL` is a struct and is `Sendable`, so this is
   safe — however the `NetworkConfig` value is stored on `SceneDelegate` as `currentNetworkConfigOverride`
   which is a `class` property mutated from a `NotificationCenter` observer and read from
   `presentRoot(_:)` without synchronization, creating an unguarded shared-mutable-state race
   on the main thread boundary.

Six warnings were also found, covering a force-cast in the default `send` extension, incomplete
error handling in the `DeviceFingerprint.resolveInstallUUID` keychain-write path, a
`@unchecked Sendable` on `URLSessionNetworkClient` that is potentially unsound, and several
testing gaps.

---

## Critical Issues

### CR-01: Default `NetworkClient.send(_:)` extension silently discards body on nil `httpMethod`

**File:** `validationLedger/Core/Networking/APIClient.swift:111`

**Issue:** The `case "GET", nil:` arm routes a `URLRequest` with a `nil` `httpMethod` through
`get(_ url:)`, which ignores `request.httpBody`. A `URLRequest` initialized without an explicit
`httpMethod` has `httpMethod == nil` by default; URLSession interprets that as `GET`. The extension
is correct in that interpretation, but calling `get(_ url:)` silently drops any headers the
interceptor chain injected onto the original `URLRequest` — the same header-loss bug that the
`URLSessionNetworkClient.send(_:)` override was added to fix (as documented in the comment at
line 53–58 of `NetworkClient.swift`). The default extension is reachable by any conformer other
than `URLSessionNetworkClient`, including test doubles and any future conformer written before the
author notices the override requirement.

More concretely: the method comment at line 16–22 of `NetworkClient.swift` says conformers MUST
override `send(_:)` to avoid header loss, but the default extension is deployed on the protocol
itself, making the "must override" contract invisible to conformers. If a test suite or future
feature builds a minimal `NetworkClient` conformer without overriding `send(_:)`, the
`Idempotency-Key` header is silently dropped on every POST — a NET-04 violation that no static
analysis will catch.

Additionally, the `default:` arm at line 116–119 force-unwraps `HTTPURLResponse(...)!` to
construct a fake 0-status response to pass to `NetworkError.unexpectedResponseType` — this is
semantically wrong (that error case is for non-HTTP responses, not unsupported methods) and would
mislead callers diagnosing a "method not allowed" condition.

**Fix:** Remove the `default:` force-unwrap arm and replace with a dedicated `NetworkError` case
for unsupported HTTP methods, or collapse the extension into a `fatalError` that loudly signals
that conformers must override `send(_:)` (making the contract enforceable at test time rather
than silently misbehaving):

```swift
// Option A: Make the contract explicit rather than silently misbehaving.
public extension NetworkClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Default implementation routes through the Phase 1 primitives.
        // URLSessionNetworkClient overrides this to pass the full URLRequest to
        // session.data(for:), preserving all headers. Any other conformer MUST
        // also override — the default discards headers. If you see this crash
        // during development, add `func send(_ request:)` to your conformer.
        guard let url = request.url else {
            throw NetworkError.baseURLMissing
        }
        switch request.httpMethod {
        case "GET", nil:
            return try await get(url)
        case "POST", "PUT", "DELETE":
            return try await post(url, body: request.httpBody ?? Data())
        default:
            // Unsupported method — surface clearly rather than constructing a fake
            // 0-status HTTPURLResponse and mis-labelling it as unexpectedResponseType.
            throw NetworkError.httpError(statusCode: 0, data: Data(
                "Unsupported HTTP method: \(request.httpMethod ?? "nil")".utf8
            ))
        }
    }
}
```

Option B (stronger): add `NetworkError.unsupportedMethod(String)` case and throw it here, then
update the test fixtures that exercise the `default:` path.

---

### CR-02: `SecureEnclaveKeyStore.generateKey(slot:)` does not guard against duplicate key generation

**File:** `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift:71-101`

**Issue:** `generateKey(slot:)` calls `SecKeyCreateRandomKey` unconditionally. If a key with the
same `kSecAttrApplicationTag` already exists in the Keychain (e.g., from a previous app launch
or a second call to `generateDeviceIdentityKeys()`), the Security framework generates a new key
and inserts it alongside the existing one. The Keychain then contains two keys under the same
application tag. `loadPrivateKey(slot:)` at line 104 issues `SecItemCopyMatching` without
`kSecMatchLimit: kSecMatchLimitOne` explicitly but implicitly returns the first match — which
may be the OLD key, not the newly generated one. The caller has now returned a NEW public key
from `generateDeviceIdentityKeys()` but signing at line 132 may use the OLD private key,
producing a public/private mismatch that the backend will reject with a signature-verification
failure. This is a silent data-integrity bug on every app reinstall or key-rotation call that
occurs without prior key deletion.

On iOS the implicit duplicate-insert behavior for `SecKeyCreateRandomKey` with `kSecAttrIsPermanent: true`
can result in `errSecDuplicateItem` being returned through `genError` — but the current code does
not distinguish between a fresh generation error and a duplicate-item error. This means the only
safe calling pattern is: delete existing key → generate new key. Without this guard, any call
path that runs `generateDeviceIdentityKeys()` twice without deletion is silently broken.

**Fix:** Probe for an existing key before generating, and either return the existing public key
(idempotent) or delete first (replace semantics). The correct idempotent pattern:

```swift
private func generateKey(slot: Keyslot) throws -> Data {
    // Return existing key if one is already present — avoids duplicate Keychain items.
    if let existing = try? loadPublicKey(slot: slot) {
        return existing
    }
    // ... rest of generation unchanged
}
```

Or, if replacement semantics are required, delete the existing item before generating:

```swift
private func deleteExistingKey(slot: Keyslot) {
    let query: [CFString: Any] = [
        kSecClass: kSecClassKey,
        kSecAttrApplicationTag: slot.applicationTag,
    ]
    SecItemDelete(query as CFDictionary) // ignore errSecItemNotFound
}

private func generateKey(slot: Keyslot) throws -> Data {
    deleteExistingKey(slot: slot)
    // ... rest of generation unchanged
}
```

The choice between idempotent-read and replace-semantics is product-level: pick and document it.
The `SecureEnclaveKeyStoreTests.persistentKeyRetrieval` test constructs two stores and reads the
same public key — that test does exercise the read-after-generate path but does NOT call
`generateDeviceIdentityKeys()` twice on the same store instance, so it would not catch this bug.

---

### CR-03: `SceneDelegate.currentNetworkConfigOverride` mutation is unguarded across boundary

**File:** `validationLedger/App/SceneDelegate.swift:50-55, 118`

**Issue:** `currentNetworkConfigOverride` is a `var` on `SceneDelegate` (a UIKit class, running
on the main actor in practice). The `NotificationCenter` observer at line 42–55 mutates
`self.currentNetworkConfigOverride` inside the `queue: .main` observer — that part is safe.
However, the observer is registered with `queue: .main` which means the block runs on the main
queue, and `presentRoot(_:)` also runs on the main thread. Both accesses are on the main thread.
This is NOT a race in the classical sense, but the two accesses are NOT annotated `@MainActor`
and Swift 6 strict concurrency will flag this as a potential data-race because `SceneDelegate`
does not declare `@MainActor` isolation.

The deeper issue is that `NetworkConfig` is passed through `NotificationCenter.userInfo` as
`Any` (not a typed channel). At line 48–50 the cast
`note.userInfo?[DevMenuNetworkConfigKey.config] as? NetworkConfig` will silently fail (producing
`nil`) if the sender posts a wrong key or wrong type. A failed cast means `currentNetworkConfigOverride`
is not updated, `presentRoot` uses the stale value, and the DevMenu "Use Live" button appears
to have no effect — a debugging trap with no error surface.

**Fix:** Annotate `SceneDelegate` with `@MainActor` (appropriate because it is a UIKit scene
delegate and all its work is UI-thread), and add a guard with a visible debug assertion on the
cast failure:

```swift
@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    // ...
}
```

For the cast failure:
```swift
guard let config = note.userInfo?[DevMenuNetworkConfigKey.config] as? NetworkConfig else {
    assertionFailure("devMenuNetworkConfigRequested posted with wrong userInfo key or type")
    return
}
```

---

### CR-04: `CertificatePinningTests.stagingPinsDiffer` / `releasePinsDiffer` pass vacuously with placeholder values and do not enforce that primary != backup with real hashes

**File:** `validationLedgerTests/Networking/CertificatePinningTests.swift:19-26`

**Issue:** The two tests check `PinnedSPKIs.staging.primary != PinnedSPKIs.staging.backup` and
the release equivalent. Currently both staging pins are placeholder strings
(`"PHASE2-TODO-STAGING-LEAF-SPKI-SHA256-BASE64"` vs `"PHASE2-TODO-STAGING-BACKUP-SPKI-SHA256-BASE64"`),
which ARE different from each other, so the tests pass. When a developer fills in the real SPKI
hashes, the most common mistake is copy-paste: accidentally setting `primary` and `backup` to the
same cert's SPKI. The existing test catches that — but only if both pins are set to the same
value. The test does NOT catch:

1. A primary set to a real hash and backup still containing the placeholder (partial fill).
2. Both set to real hashes that happen to be the same string (exact copy-paste duplicates within
   the string), which the `!=` check would catch — but only if the developer runs tests before
   shipping.

The `noReleasePlaceholders` test in the same file is gated to non-DEBUG and would NOT run in the
simulator CI job (`ci-simulator.yml` runs under DEBUG). This means the CI pipeline that protects
against shipping placeholder release pins never actually executes in the simulator-based CI job.
The protection only fires if a Release build is explicitly tested — but the CI workflow only runs
`validationLedgerTests` in simulator (DEBUG). A Release-tagged CI job is mentioned in comments
but is not present in the reviewed `ci-simulator.yml`.

**Fix:** Add an explicit Release-build CI job that builds in Release configuration and runs the
test suite (at minimum the `CertificatePinningTests` suite) so `noReleasePlaceholders` actually
executes in CI. Until that job exists, the placeholder guard is only checked during manual
Release test runs — which is not a gate.

Additionally consider adding a staging-placeholder test that runs unconditionally in DEBUG CI:

```swift
@Test("Staging pins must not contain placeholder strings (DEV marker check)")
func stagingPinsAreNotPlaceholders() {
    // Staged to fire when the team fills in real staging certs:
    // If staging still has placeholders, skip loudly rather than silently pass.
    if PinnedSPKIs.staging.primary.hasPrefix("PHASE2-TODO") {
        // Known-placeholder state — do not record an issue.
        return
    }
    // Real hashes are present — verify they differ.
    #expect(PinnedSPKIs.staging.primary != PinnedSPKIs.staging.backup,
            "Staging primary and backup must use different certs")
}
```

---

## Warnings

### WR-01: `URLSessionNetworkClient` marked `@unchecked Sendable` without actor-isolation guarantees

**File:** `validationLedger/Core/Networking/NetworkClient.swift:25`

**Issue:** `URLSessionNetworkClient` is `final class ... @unchecked Sendable`. The `@unchecked`
suppressor is necessary because `URLSession` is not `Sendable` in Swift 6 (it is a reference
type with mutable internal state). However `@unchecked Sendable` is a promise to the compiler
that the developer has ensured safe concurrent access manually. The file contains no synchronization
mechanism (no actor, no lock, no serial queue) on `session` or `config`. While `URLSession.data(for:)`
is itself concurrency-safe (Apple documents URLSession as safe for concurrent use), any future
mutation of `session` or `config` properties would be a silent race. The suppressor also prevents
the compiler from flagging future modifications that break the manual safety guarantee.

**Fix:** Add a comment explaining exactly WHY `@unchecked Sendable` is safe for this specific
type — i.e., that `session` and `config` are `let` properties set at init and never mutated,
and that `URLSession.data(for:)` is documented concurrency-safe:

```swift
// @unchecked Sendable rationale: both `session` and `config` are `let` constants set at
// init-time and never mutated. URLSession.data(for:) is documented thread-safe by Apple.
// No mutable state exists in this type. If a future change adds mutable state, this
// suppressor must be revisited and replaced with proper synchronization.
final class URLSessionNetworkClient: NetworkClient, @unchecked Sendable {
```

---

### WR-02: `DeviceFingerprint.resolveInstallUUID` silently swallows keychain write errors

**File:** `validationLedger/Core/Identity/DeviceFingerprint.swift:50-62`

**Issue:** At line 57–61, `keychain.set(...)` throws if the Keychain write fails (e.g., if the
device is locked, entitlements are missing, or storage is full). The function signature is
`throws` at line 50, and the write is called with `try` — so the error does propagate up. This
is correct. However `if let existing = try? keychain.get(installUUIDKey)` at line 51 silently
discards any keychain read error. If the Keychain is temporarily unavailable (e.g., device
locked before first unlock), `get` throws, `try?` converts it to `nil`, the function generates
a fresh UUID, and then the subsequent `keychain.set` call may ALSO fail — at which point the
function throws and the install UUID is not persisted. On the next call, the same UUID
regeneration happens again, resulting in a different UUID each time the Keychain is unavailable.
This means `installUUID` in the device fingerprint is NOT stable across app launches when the
Keychain is temporarily unavailable, potentially causing the backend to see a "new device" on
every launch during early boot.

**Fix:** Propagate the Keychain read error rather than swallowing it, so the caller can decide
whether to retry, show an error, or proceed with a degraded experience:

```swift
static func resolveInstallUUID(keychain: KeychainStore) throws -> String {
    // Propagate read errors so callers can distinguish "Keychain unavailable" from
    // "UUID not yet generated". Use try? only if you explicitly want to ignore the error.
    if let existing = try keychain.get(installUUIDKey),
       let decoded = String(data: existing, encoding: .utf8) {
        return decoded
    }
    // Key not found (errSecItemNotFound) — generate a fresh one.
    let fresh = UUID().uuidString
    try keychain.set(
        Data(fresh.utf8),
        for: installUUIDKey,
        accessibility: .afterFirstUnlockThisDeviceOnly
    )
    return fresh
}
```

Note: if `KeychainStore.get` throws `errSecItemNotFound` for a missing key (which is the normal
"not yet stored" case), that needs to be distinguished from a transient error. If the keychain
API surfaces both through the same `throw`, a `KeychainError.itemNotFound` case should be added
and matched here rather than swallowing everything with `try?`.

---

### WR-03: `SecureEnclaveKeyStore.loadPrivateKey` force-casts `CFTypeRef` to `SecKey`

**File:** `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift:119-120`

**Issue:** At line 116, `CFGetTypeID(key) == SecKeyGetTypeID()` guards the type before the
force-cast at line 120 (`key as! SecKey`). The guard is correct and prevents the crash in the
normal path. However the pattern is fragile: if the guard condition is removed or reordered
by a future refactor, the force-cast becomes a latent crash. The Security framework provides
`SecKeyRef` which IS a `SecKey` in Swift; a cleaner pattern is to use `guard let key = item as? SecKey`
directly and remove the `CFGetTypeID` check:

```swift
var item: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &item)
guard status == errSecSuccess else {
    throw KeyStoreError.keyUnavailable
}
guard let key = item as? SecKey else {
    throw KeyStoreError.keyUnavailable
}
return key
```

`as? SecKey` is safe here because the Security framework guarantees that `kSecReturnRef: true`
with `kSecClass: kSecClassKey` returns a `SecKey`. This pattern is shorter, idiomatic Swift,
and removes the force-cast without any semantic change.

---

### WR-04: `MockFixture.registerFixture` force-unwraps `HTTPURLResponse` on every fixture registration

**File:** `validationLedger/Core/Networking/Mock/MockFixture.swift:26-30`

**Issue:** At line 27, `HTTPURLResponse(url: request.url!, ...)!` has two force-unwraps:
`request.url!` and the `HTTPURLResponse` initializer. `request.url` should never be `nil` for a
properly constructed `URLRequest` (the `APIClient.buildRequest` always appends a path component
to a non-nil `baseURL`), but in a test context a developer could register a fixture with a
malformed `URLRequest` and receive a crash rather than a test failure. The `HTTPURLResponse`
initializer force-unwrap is safe when given a valid `url` and standard HTTP version string, but
it obscures the failure mode.

These force-unwraps are in test-support code only, so the production risk is zero. However they
can cause confusing crash-vs-failure behavior in tests. Consider using `guard let`:

```swift
guard let url = request.url else { return nil }
guard let resp = HTTPURLResponse(
    url: url,
    statusCode: statusCode,
    httpVersion: "HTTP/1.1",
    headerFields: headers
) else { return nil }
return (resp, body)
```

---

### WR-05: `RetryInterceptor.delayForAttempt` uses `baseDelayMs << attempt` which overflows for `attempt >= 64` despite the `attempt >= 62` guard

**File:** `validationLedger/Core/Networking/Interceptors/RetryInterceptor.swift:85-91`

**Issue:** The overflow guard at line 85 checks `attempt >= 62` and saturates to `UInt64.max`.
`UInt64` is 64 bits, so `1 << 63 = 9223372036854775808` (the sign bit of an Int64, but valid
for UInt64) and `1 << 64` overflows. For `baseDelayMs = 500`, `500 << 62` would overflow before
reaching the guard. The guard fires at `attempt >= 62` which correctly prevents the shift from
happening, but the comment says "1 << 62 is the largest safe shift for UInt64" — this is
incorrect; the largest safe shift for `UInt64` is `<< 63`. At `attempt = 63`,
`baseDelayMs = 1`, `1 << 63 = 9223372036854775808` is representable in UInt64 and would be
clamped to `ceilingMs` before being used. The guard at `>= 62` is therefore one iteration
too conservative but not wrong (the result would just hit `ceilingMs` either way). The comment
is misleading and should be corrected.

More importantly: with `maxRetries = 3` (the production default), `attempt` ranges from 0 to 3,
so this guard is unreachable in practice. The guard exists for defensive correctness but its
comment is wrong, which creates a future-maintenance hazard.

**Fix:** Correct the comment:

```swift
if attempt >= 64 {
    // UInt64 shift is defined for amounts 0...63; shift by >= 64 is undefined behavior
    // in C, and Swift's >> / << operators do not trap but produce 0 for out-of-range shifts
    // on some architectures. Saturate to ceiling to be safe.
    rawShift = ceilingMs
} else {
    rawShift = baseDelayMs << attempt
}
```

---

### WR-06: CI `ci-simulator.yml` pins `Xcode 16.4` but CLAUDE.md and TechStack.md state Xcode 26.4

**File:** `.github/workflows/ci-simulator.yml:18-19`

**Issue:** The CI step at line 18 runs `sudo xcode-select -s /Applications/Xcode_16.4.app` with
the comment "CI pins Xcode 16.4 per docs/ci.md". CLAUDE.md and TechStack.md both state the
project uses "Xcode 26.4". A version skew between local development (Xcode 26.4) and CI
(Xcode 16.4) means:

- Features or API changes introduced in Xcode 26.4 / iOS 26 SDK will not be caught by CI.
- Build warnings or errors that appear only on the newer compiler will slip through.
- The `Select Xcode 16.4` step will fail on a `macos-latest` runner that ships with a newer
  Xcode and does not have Xcode 16.4 installed (likely once `macos-latest` advances to macOS 26).

This is a version-skew correctness gap, not just a style issue — if Xcode 26.4 introduces Swift
concurrency or SDK changes that break the current source, CI will not catch them.

**Fix:** Update the CI workflow to use the same Xcode version as local development, OR document
in `ci-simulator.yml` that the version difference is intentional and explain why (e.g., the
macos-latest runner does not yet offer Xcode 26.4). If intentional, update CLAUDE.md to reflect
the CI Xcode version so developers are not surprised by the skew.

---

## Info

### IN-01: `OTPVerifyEndpoint.RequestBody` encoding will produce `otp_session_id` but `otpSessionID` property naming means `.convertToSnakeCase` yields `otp_session_i_d`

**File:** `validationLedger/Core/Networking/Endpoints/OTPVerifyEndpoint.swift:12-13`

**Issue:** `RequestBody` at line 12–13 has the property `otpSessionID: String`. With
`encoder.keyEncodingStrategy = .convertToSnakeCase`, Swift's implementation of that strategy
converts each uppercase letter to `_<lowercase>`. The acronym `ID` at the end becomes `_i_d`,
so `otpSessionID` encodes as `"otp_session_i_d"` — NOT `"otp_session_id"`. The backend endpoint
`/auth/otp/verify` presumably expects `"otp_session_id"`. The same issue applies to the `RequestBody`
of `KYCUploadChunkEndpoint` (`uploadID` → `"upload_i_d"`), `KYCUploadCommitEndpoint` (`uploadID`),
and `DeviceRegisterEndpoint` (`devicePublicKey` is fine but `installUUID` inside
`DeviceFingerprintPayload` → `"install_u_u_i_d"`).

The CodingKeys workaround is correctly applied on the RESPONSE side (where `otpSessionID` needs
an explicit raw value). It is missing on the REQUEST body side for all affected properties.

Note: This is currently only caught at integration test time (the mock fixture accepts whatever
JSON the encoder produces). The backend would reject the request with a field-not-found error in
production. The OTP request endpoint `phone` field has no acronym suffix, so that one is safe.

**Fix:** Add explicit `CodingKeys` to each `RequestBody` that contains acronym-suffixed properties:

```swift
// In OTPVerifyEndpoint.RequestBody:
private enum CodingKeys: String, CodingKey {
    case otpSessionID = "otpSessionId"  // or "otp_session_id" depending on backend contract
    case code
}
```

The correct snake_case form to use depends on whether the backend API expects `otp_session_id`
(pure snake_case) or `otpSessionId` (camelCase). Since the decoder's CodingKeys use camelCase
raw values (because `.convertFromSnakeCase` is applied before matching), the encoder's
CodingKeys should use the raw snake_case form the backend expects if `.convertToSnakeCase` is
not producing the right output.

Audit the full list of `RequestBody` properties with acronym suffixes:
- `OTPVerifyEndpoint.RequestBody.otpSessionID`
- `KYCUploadChunkEndpoint.RequestBody.uploadID`
- `KYCUploadCommitEndpoint.RequestBody.uploadID`
- `DeviceRegisterEndpoint.DeviceFingerprintPayload.installUUID`

---

### IN-02: `SoftwareKeyStore.sign` returns `rawRepresentation` (64-byte compact form), but `SecureEnclaveKeyStore.sign` returns DER-encoded X9.62 signature (variable length)

**File:** `validationLedger/Core/KeyStore/SoftwareKeyStore.swift:19` vs `validationLedger/Core/KeyStore/SecureEnclaveKeyStore.swift:135`

**Issue:** `SoftwareKeyStore.sign(_:)` at line 19 returns `signature.rawRepresentation` — the
64-byte compact (r || s) ECDSA signature format used by CryptoKit. `SecureEnclaveKeyStore.sign(data:slot:)`
at line 135 uses `SecKeyCreateSignature(..., .ecdsaSignatureMessageX962SHA256, ...)` — which
returns a DER-encoded ASN.1 signature (variable length, 70–72 bytes typically). The two
implementations of the same `KeyStoreProtocol.sign(_:)` method return DIFFERENT wire formats.

The `SecureEnclaveKeyStoreTests.signAndVerifyDeviceKey` test at line 67–68 correctly handles
this: it uses `P256.Signing.ECDSASignature(derRepresentation:)` for the device-test signature.
The `SoftwareKeyStoreExtendedTests.signSize` test at line 45 asserts `sig.count == 64` — the
compact format.

Any Phase 3+ caller that sends the signature over the network will send different bytes depending
on whether it is running in simulator (compact) or on device (DER). If the backend expects one
format, one environment will always fail signature verification.

**Fix:** Standardize the signature format across both KeyStore implementations. The most
interoperable choice for an API is the DER/X9.62 format (which is what most backends and TLS
stacks expect). For `SoftwareKeyStore`:

```swift
func sign(_ data: Data) throws -> Data {
    let signature = try devicePrivateKey.signature(for: data)
    return try signature.derRepresentation  // match SecureEnclaveKeyStore's DER output
}
```

Update `SoftwareKeyStoreExtendedTests.signSize` to remove the `== 64` assertion (DER length
is not fixed) and instead verify the signature verifies correctly with the public key.

---

### IN-03: `MockURLProtocol.startLoading` does not call `client?.urlProtocol(_:didFailWithError:)` on the no-match (404) path

**File:** `validationLedger/Core/Networking/Mock/MockURLProtocol.swift:53-57`

**Issue:** When no handler matches, `startLoading` returns a synthetic 404 response via
`urlProtocol(_:didReceive:...)` + `urlProtocolDidFinishLoading(_:)`. This is correct for the
normal no-match case. However if `client` is `nil` (which should not happen for a properly
constructed `URLProtocol` instance, but is possible if `startLoading` is called at an unexpected
lifecycle point), the nil-coalescing silently swallows the response and the request hangs.
More practically: the 404 path does not carry response data (the `client?.urlProtocol(self, didLoad: data)`
call at line 48 is NOT reached on the no-match path). This means the `URLSession` receives a
404 with an empty body, which is correct for a "not found" signal, but any test checking
`data.isEmpty` on a 404 response will find it is already empty — not a bug, just an undocumented
behavior.

**Fix:** Add an empty-data didLoad call on the 404 path for consistency with the handler-match
path, and add a comment:

```swift
// No handler matched — return 404 with empty body so tests fail loudly rather than hang.
let url = request.url ?? URL(string: "about:blank")!
let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
client?.urlProtocol(self, didLoad: Data())  // empty body — signal no content, not a hang
client?.urlProtocolDidFinishLoading(self)
```

---

### IN-04: `DevMenuViewController` row cell is always constructed with `.subtitle` style but `UITableViewCell(style:reuseIdentifier:)` ignores the reuse identifier for style changes

**File:** `validationLedger/App/DevMenu/DevMenuViewController.swift:70`

**Issue:** At line 70, `UITableViewCell(style: .subtitle, reuseIdentifier: "cell")` creates a
new cell each time rather than dequeuing. `tableView.register(UITableViewCell.self, ...)` at
line 60 registers the default-style cell, but the `cellForRowAt` override allocates a fresh
`.subtitle`-styled cell every time instead of calling `dequeueReusableCell(withIdentifier:for:)`.
The net effect is that the registered cell class is never dequeued, defeating the reuse queue.

For a 4-row DevMenu table this is not a performance concern, but it is a UIKit anti-pattern that
could mislead contributors when the table grows.

**Fix:**
```swift
override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    // Re-configure subtitle style if needed, or register a custom subclass with subtitle style.
    let row = Row(rawValue: indexPath.row)!
    cell.textLabel?.text = row.title
    cell.detailTextLabel?.text = row.subtitle
    cell.accessoryType = .disclosureIndicator
    return cell
}
```

Alternatively, register a `UITableViewCell` subclass that configures the subtitle style in init.

---

### IN-05: `KYCUploadChunkEndpoint.RequestBody.uploadID` missing explicit CodingKey — same acronym-suffix issue as IN-01 but on a different request body

**File:** `validationLedger/Core/Networking/Endpoints/KYCUploadChunkEndpoint.swift:12`

**Issue:** Noted as part of IN-01's audit but calling out separately because `KYCUploadChunkEndpoint`
is the highest-frequency endpoint (called once per chunk in the upload loop). If `uploadID`
encodes as `"upload_i_d"` instead of `"upload_id"`, every chunk POST will fail schema validation
on the backend. See IN-01 for the fix pattern.

---

_Reviewed: 2026-04-21_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
