---
phase: 06-close-gap-dev-04-app-attest-at-first-login-trusttier-consume
slug: close-gap-dev-04-app-attest-at-first-login-trusttier-consume
status: verified
threats_open: 0
asvs_level: 1
created: 2026-05-18
---

# Phase 06 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> State B audit — SECURITY.md created at audit time; threat register sourced from
> the four `<threat_model>` blocks in 06-01/02/03/04-PLAN.md (19 threats).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| backend → iOS (`/device/register` response) | `trustTier` arrives as untrusted wire data, decoded by a typed `Decodable` endpoint; persisted to Keychain by `OTPViewModel`. | `trustTier` (closed-set enum), `deviceID`, `registeredAt` |
| backend → iOS (`/device/challenge` response) | Server-issued challenge transits the wire; base64-decoded before `attestKey`. | `challenge` (base64 string), `expiresAt`, `nonce` |
| backend → iOS (`/device/register` / `/kyc/status` error body) | Untrusted JSON error body parsed for `error_code` / `overall_status`. | `error_code` string, `overall_status` string |
| client → backend (`POST /device/register`) | Attestation payload + DeviceFingerprint crosses the untrusted network. | `attestationObject`, `attestedKeyId`, public keys, fingerprint |
| App Attest service (Apple `DCAppAttestService`) → app | `attestKey` / `generateKeyIfNeeded` cross into Apple-managed crypto; errors may carry diagnostic `NSError.userInfo`. | keyId, attestationObject, NSError |
| iOS process → Keychain | `device.trustTier` (write/seed-read) and `session.kycStatus` (refresh write) cross the process↔Keychain boundary. | `trustTier` rawValue, `kycStatus` string |
| Release vs DEBUG build surface | Deletion of `uiTestTrustTierOverride` removes a DEBUG seam — affects what ships in Release. | n/a (compile-time surface) |
| planning artifacts → human reviewer | `04-VERIFICATION.md` is a `.planning/` doc consumed by a human / verifier. | verification claims (no runtime data) |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-06-01-01 | Tampering | `device.trustTier` Keychain item — client-tampered tier could suppress the limited-trust banner | accept | Backend-driven (Phase 4 D-12); written only from a `/device/register` response; `.afterFirstUnlockThisDeviceOnly` items not user-editable on a non-jailbroken device; banner is informational, not an access gate. See Accepted Risks Log RISK-06-01. | closed |
| T-06-01-02 | Information Disclosure | `trustTier` value in Keychain / logs | mitigate | `TrustTier` is a closed-set `String` enum (`TrustTier.swift:12-15`, no PII). No `Logger` call references trustTier. Stored only in Keychain via `AttestedKeyStore.writeTrustTier` with `.afterFirstUnlockThisDeviceOnly` (`AttestedKeyStore.swift:127-133`) — never `UserDefaults` / plain file. | closed |
| T-06-01-03 | Tampering | Unknown/garbage wire value re-hydrated as a forged tier | mitigate | `AttestedKeyStore.readTrustTier()` (`AttestedKeyStore.swift:115-123`) decodes via `TrustTier(rawValue: raw)`; an unknown string yields `nil`. `AppContainer.swift:421` resolves `nil → .softwareOnly` — fail-safe, never `.hardwareAttested`. | closed |
| T-06-01-SC | Tampering | npm/pip/cargo installs | mitigate | Phase 6 installs zero packages. `git log 3f03152~1..a69e497 -- Package.swift Podfile Cartfile package.json` returns no commits; `Package.swift` holds only the two CLAUDE.md-allowlisted deps (Nuke, SwiftLintPlugins). | closed |
| T-06-02-01 | Information Disclosure | New attestation `catch`/log calls in `OTPViewModel.verify()` STEP 5 leaking `attestationObject` / challenge bytes / `NSError.userInfo` | mitigate | The three new attestation log calls — `OTPViewModel.swift:264` (`attestation_first_login_challenge_expired_retry`, `fields: [:]`), `:353` (`attestation_first_login_skipped_no_key`, `fields: [.event: status.rawValue]`), `:362`/`:378` (`attestation_first_login_degraded`, `fields: [:]`) — carry only the event name + the closed-set `AttestationStatus.rawValue`. The build-failing source-grep test `OTPViewModelTests.swift:299-322` asserts no `String(describing:` token near any `attestation_first_login` log line. | closed |
| T-06-02-02 | Denial of Service | First-login attestation failure used to block a legitimate login | mitigate | `buildAttestationFields()` (`OTPViewModel.swift:346-381`) never throws — a non-`.attested` status (`:352-356`) or a transient failure (challenge fetch / base64-decode / `attestKey` throw, `:360-380`) both resolve to a graceful tuple with `status = .error` and nil fields; STEP 5 STILL POSTs `/device/register` (`:249-280`). App Attest is never a login gate. | closed |
| T-06-02-03 | Tampering / Spoofing | Stale/replayed challenge accepted by `/device/register` | mitigate | `OTPViewModel.swift:258-273` — a `catch let NetworkError.httpError(_, data) where AttestationErrorResponseInterceptor.extractErrorCode(from: data) == "challengeExpired"` arm re-runs `buildAttestationFields()` (fresh `GET /device/challenge` + re-`attestKey`) and retries the register POST exactly once; a second consecutive failure falls through to `state = .registerFailed` (`:274-280`) — no loop. | closed |
| T-06-02-04 | Repudiation | Register POST replayed (e.g. via `retryRegister()`) creating duplicate device records | accept | `/device/register` is `Idempotency-Key`-protected (NET-04); backend dedupes. `generateKeyIfNeeded` is once-per-install (D-01). `retryRegister()` (`OTPViewModel.swift:432-435`) only re-runs the idempotent `verify()`. See Accepted Risks Log RISK-06-02. | closed |
| T-06-02-05 | Tampering | Malformed `challengeExpired` error body crashing the parse | mitigate | The body parse reuses `AttestationErrorResponseInterceptor.extractErrorCode` (`AttestationErrorResponseInterceptor.swift:132-140`) — a tolerant `JSONSerialization` parse guarded by `data.isEmpty` and `try?`, returning `nil` on empty/non-JSON/non-string input. A `nil` result fails the `where` clause → no retry, no crash. | closed |
| T-06-02-SC | Tampering | npm/pip/cargo installs | mitigate | Phase 6 installs zero packages (see T-06-01-SC evidence). App Attest uses Apple's `DeviceCheck`, already on the CLAUDE.md pre-approved shortlist. | closed |
| T-06-03-01 | Elevation of Privilege / Tampering | `uiTestTrustTierOverride` DEBUG static could, if compiled into Release, forge `trustTier` and suppress the banner | mitigate | `grep -rn 'uiTestTrustTierOverride' validationLedger/ validationLedgerTests/` returns 0 matches — the seam is deleted at all 3 sites. The remaining `-MockOTPTrustTierForUITest` launch arg is parsed in `SceneDelegate.swift:164-184` and drives the real consumer via `MockOTPRoleFixtureRegistry.registerForRole` — no Release forge path. | closed |
| T-06-03-02 | Tampering | A client-tampered `device.trustTier` Keychain seed suppressing the banner | accept | Backend-driven; written only from a `/device/register` response; `.afterFirstUnlockThisDeviceOnly` items not user-editable on a non-jailbroken device; banner is informational, not a gate. Same disposition as T-06-01-01. See Accepted Risks Log RISK-06-03. | closed |
| T-06-03-03 | Correctness — fail-closed integrity | Stale `kycStatus` causing a fail-closed cold-boot misroute | mitigate | `KYCStatusViewModel.fetchStatus()` calls `refreshCachedKYCStatus(response.overallStatus)` (`KYCStatusViewModel.swift:155, 173-186`) after a successful `GET /kyc/status`. Routing logic is unchanged — `OTPViewModel.swift:311` still gates on `kycStatus == "verified"`, any other value (incl. `nil`) routes to the KYC gate. The refresh only freshens the cached value; fail-closed semantics preserved. | closed |
| T-06-03-04 | Information Disclosure | `kycStatus` written to insecure storage | mitigate | `refreshCachedKYCStatus` (`KYCStatusViewModel.swift:173-186`) writes via `keychain.set(..., for: .kycStatus, accessibility: .afterFirstUnlockThisDeviceOnly)` — Keychain only, never `UserDefaults`/plain file (SEC-03). The value is a controlled-vocabulary status string (no PII); the write-failure log carries only the event name (`:181-185`). | closed |
| T-06-03-05 | Spoofing | The observable-trustTier notification/closure spoofed to flip the banner | accept | The observation mechanism is an in-process `Notification.Name` (`.trustTierDidChange`, `AppSession.swift:47-52`) posted from a `trustTier` `didSet` and scoped to the `AppSession` instance as the post `object`. Only in-process code can post it; cross-process spoofing of an in-process notification is not a realistic iOS vector. See Accepted Risks Log RISK-06-04. | closed |
| T-06-03-SC | Tampering | npm/pip/cargo installs | mitigate | Phase 6 installs zero packages (see T-06-01-SC evidence). | closed |
| T-06-04-01 | Repudiation | A verification report that overstates coverage (claims SATISFIED without evidence) | mitigate | `04-VERIFICATION.md` (created in commit `a69e497`) cites named existing artifacts for every verdict (Phase 6 plan SUMMARYs with commit hashes, `AppAttestRoundTripTests.swift`, the 2026-05-16 device run, `ci-device.yml`, `docs/ci.md`, `DeviceRegisterOmissionTests.swift`); `status: human_needed` with the 5 unverified device-UAT items carried in `human_verification:` rather than marked passed. | closed |
| T-06-04-02 | Tampering | Editing ROADMAP.md unintentionally flips other checkboxes / SC text | mitigate | The `04-10-PLAN.md` checkbox was already `[x]` (ticked at planning, commit `07af505`); Plan 06-04 Task 2 made zero edits to `ROADMAP.md` — `git status` confirms the file unmodified after the plan. No checkbox or SC text changed. | closed |
| T-06-04-SC | Tampering | npm/pip/cargo installs | mitigate | Phase 6 is documentation-only for Plan 04; zero packages installed (see T-06-01-SC evidence). | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| RISK-06-01 | T-06-01-01 | `device.trustTier` is backend-driven (Phase 4 D-12) — written only from a `/device/register` response. `.afterFirstUnlockThisDeviceOnly` Keychain items are not user-editable on a non-jailbroken device. The LimitedTrustBanner is informational, not an access gate (Phase 4 D-11); a tampered tier at worst suppresses an advisory banner. Re-hydration is fail-safe (T-06-01-03). Impact is bounded; no implementation control added. | gsd-security-auditor (PLAN 06-01 `<threat_model>`) | 2026-05-18 |
| RISK-06-02 | T-06-02-04 | `/device/register` is `Idempotency-Key`-protected (NET-04) and the backend dedupes duplicate device records. `generateKeyIfNeeded` is once-per-install (Phase 4 D-01). `retryRegister()` re-running the idempotent `verify()` is therefore safe. Repudiation/duplication is mitigated server-side; no client control needed. | gsd-security-auditor (PLAN 06-02 `<threat_model>`) | 2026-05-18 |
| RISK-06-03 | T-06-03-02 | Identical disposition to RISK-06-01 — `device.trustTier` is backend-driven, the Keychain item is not user-editable on a non-jailbroken device, and the banner is informational, not a gate. The consumer-side seed read (`AppContainer`) inherits the same bounded impact. | gsd-security-auditor (PLAN 06-03 `<threat_model>`) | 2026-05-18 |
| RISK-06-04 | T-06-03-05 | The trustTier observation channel is an in-process `Notification.Name` (`.trustTierDidChange`) posted from `AppSession`'s `trustTier` `didSet`, scoped to the posting `AppSession` instance. Only in-process code can post it, and `trustTier` mutation is itself confined to the first-login / heartbeat consumers. Cross-process spoofing of an in-process `NotificationCenter` post is not a realistic iOS attack vector. | gsd-security-auditor (PLAN 06-03 `<threat_model>`) | 2026-05-18 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-05-18 | 19 | 19 | 0 | gsd-security-auditor |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-05-18
