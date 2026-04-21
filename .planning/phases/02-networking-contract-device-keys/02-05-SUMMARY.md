---
phase: 02-networking-contract-device-keys
plan: 05
subsystem: networking
tags: [ios, swift, security, cert-pinning, spki, urlsessiondelegate, cryptokit, swift-testing, wave-2, sec-01, found-05, m1]

# Dependency graph
requires:
  - phase: 02-networking-contract-device-keys
    plan: 01
    provides: "NetworkError.pinningFailed case — throw site for pinning rejection"
  - phase: 01-foundational-conventions-scaffolding
    provides: "PinningSessionDelegate Phase 1 skeleton file + docs/cert-rotation.md skeleton"
provides:
  - "PinnedSPKIs struct — compile-time dual-pin SPKI constants (staging + release + current selector)"
  - "SPKIHasher — EC P-256 SecCertificate → Base64 SHA-256 SPKI transform (RFC 7469 compliant)"
  - "PinningSessionDelegate(pins:) — URLSessionDelegate with dual-pin acceptance + single-completion invariant"
  - "CertificatePinningTests — 9 @Test unit slice: dual-pin-differ, current-selector, public-init, placeholder-gate, SPKIHasher ground-truth match, negative-path, construction smoke"
  - "docs/cert-rotation.md ACTIVE — full 30-day Day -30/0/+7 runbook + emergency + rollback + CI checks"
affects:
  - "02-07 (AppContainer/session wiring) — must install PinningSessionDelegate(pins: PinnedSPKIs.current) ONLY on the .live URLSession branch of makeSession(networkConfig:)"
  - "02-07 (integration tests) — CertificatePinningIntegrationTests.swift belongs to Plan 07; ships the three-cert accept-primary/accept-backup/reject-third suite through a real URLSession"

# Tech tracking
tech-stack:
  added:
    - "CryptoKit (SHA256.hash) — iOS SDK, not an SPM dep; used only for SPKI SHA-256 in SPKIHasher"
  patterns:
    - "Compile-time SPKI constants baked into the binary (rejected NSPinnedDomains + JSON/plist — Research §Alternatives Considered)"
    - "26-byte ASN.1 header (ID-EC-PUBLICKEY + secp256r1 OID) prepended to SecKeyCopyExternalRepresentation bytes to reconstruct SubjectPublicKeyInfo for hashing — equivalence with openssl pipeline verified by ground-truth unit test"
    - "Dual-pin (primary + backup from DIFFERENT key pairs) invariant enforced by dualPinsDiffer unit tests"
    - "Every URLSessionDelegate return path precedes a completionHandler call — Pitfall 4 structural enforcement"
    - "Rejection disposition is always .cancelAuthenticationChallenge, never .performDefaultHandling — pinning never falls back to system trust evaluation"
    - "PHASE2-TODO placeholder convention + CI gate test (noReleasePlaceholders) — Release builds fail if placeholders remain"

key-files:
  created:
    - "validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift"
    - "validationLedger/Core/Networking/CertificatePinning/SPKIHasher.swift"
    - "validationLedgerTests/Networking/CertificatePinningTests.swift"
  modified:
    - "validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift — Phase 1 skeleton → dual-pin challenge handler"
    - "docs/cert-rotation.md — STUB → ACTIVE runbook; Phase 2 To-Do section removed"

key-decisions:
  - "EMBEDDED a real EC P-256 test cert instead of deferring to Plan 07 — the plan allowed either a TODO Issue.record or an embedded cert; embedding produces a stronger ground-truth test (spkiHasherMatchesOpenSSLPipeline proves our Swift implementation matches the canonical openssl pipeline)."
  - "Kept EC P-256 assumption — no backend confirmation yet; documented the switching cost (ASN.1 header + optional algorithm parameter) in both SPKIHasher.swift and docs/cert-rotation.md §Algorithm assumption."
  - "Dual-pin only (no triple-pin) per SEC-01 spec — triple-pin was NOT considered for M1 scope; would require a third slot + additional rotation state machine. Capture for M2+ scope review if operational data suggests more simultaneous paths are needed."
  - "Logger injection deferred — the plan explicitly forbade adding a logger dependency in this plan because it would force AppContainer changes conflicting with Plans 04 + 06. Rejection paths are silent for now; Plan 07 can add structured 'pinning_rejected' events if the Logger surface expands."
  - "Used iPhone 17 Pro / iOS 26.4 simulator — dev machine has no iOS 17.5 runtime (matches 02-01-SUMMARY.md precedent). CI still targets iOS 17.5."

patterns-established:
  - "CertificatePinning/ subdirectory layout: PinnedSPKIs.swift (config), SPKIHasher.swift (util), PinningSessionDelegate.swift (URLSessionDelegate impl) — three files, no cross-imports except Foundation + Security + CryptoKit"
  - "Ground-truth cross-implementation verification: a Swift unit test embeds a known cert + expected SPKI hash computed via the openssl pipeline the runbook prescribes. Any future change to ASN.1 header, hashing, or encoding is caught by this test."

requirements-completed: [SEC-01]

# Metrics
duration: 7m43s
completed: 2026-04-21
---

# Phase 2 Plan 05: Dual-Pin SPKI Certificate Pinning Summary

**Dual-pin SPKI certificate pinning stack delivered (SEC-01 + FOUND-05): compile-time `PinnedSPKIs` constants, RFC 7469–compliant `SPKIHasher` with openssl-verified ground-truth, filled-in `PinningSessionDelegate` with single-completion invariant, 9-test unit slice (all pass), and the full Day -30/0/+7 rotation runbook in `docs/cert-rotation.md`.**

## Performance

- **Duration:** 7m 43s (463s wall clock)
- **Started:** 2026-04-21T19:49:17Z
- **Completed:** 2026-04-21T19:57:00Z
- **Tasks:** 5 (all atomic, each with its own commit)
- **Files created:** 3 (PinnedSPKIs.swift, SPKIHasher.swift, CertificatePinningTests.swift)
- **Files modified:** 2 (PinningSessionDelegate.swift, docs/cert-rotation.md)

## Accomplishments

- **SEC-01 delivered:** Dual-pin SPKI cert-pinning stack ready for URLSession install (Plan 07 wires). Every Phase 2 live-network call will verify the server's leaf SPKI hash against both primary and backup pins before accepting.
- **Self-brick DoS prevention locked in:** `stagingPinsDiffer` + `releasePinsDiffer` unit tests compile-enforce the invariant that primary ≠ backup. Research Pitfall 6 (single-pin expiry bricks all installed copies) is closed.
- **Completion-handler invariant enforced by structure:** Every `return` in `PinningSessionDelegate.urlSession(_:didReceive:completionHandler:)` is preceded by a `completionHandler(...)` call. 4 rejection paths all land on `.cancelAuthenticationChallenge`; 1 accept path lands on `.useCredential`. Research Pitfall 4 is closed.
- **Ground-truth SPKIHasher correctness:** The `spkiHasherMatchesOpenSSLPipeline` test embeds a deterministic EC P-256 cert (DER-as-base64) and the expected SPKI hash computed by `openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | openssl enc -base64`. The Swift implementation produces the identical string — proving the ASN.1 header + CryptoKit SHA-256 pipeline matches the canonical pipeline the runbook prescribes.
- **Release placeholder gate shipped:** `noReleasePlaceholders` is a DEBUG-skipped test that fails in Release builds if any `PinnedSPKIs.release.*` value still starts with `PHASE2-TODO`. Prevents shipping an un-pinned Release build to TestFlight.
- **Runbook is now actionable:** `docs/cert-rotation.md` STUB → ACTIVE. On-call engineer has copy-pasteable openssl pipelines (live server + PEM file + test-cert regen), a Day -30/0/+7 procedure, an emergency revoke path with 4h/24h target timelines, a rollback procedure with post-mortem location, and a CI Checks section showing the three safety tests.

## Task Commits

Each task was committed atomically:

1. **Task 1: PinnedSPKIs.swift — compile-time dual-pin constants** — `cf74221` (feat)
2. **Task 2: SPKIHasher.swift — EC P-256 → SHA-256 Base64 SPKI transform** — `a4cd72c` (feat)
3. **Task 3: PinningSessionDelegate.swift — dual-pin challenge handler** — `3a985d4` (feat)
4. **Task 4: CertificatePinningTests.swift — 9-test unit slice w/ openssl ground truth** — `c6b692e` (test)
5. **Task 5: docs/cert-rotation.md — STUB → ACTIVE 30-day runbook** — `1cd8220` (docs)

**Plan metadata commit:** pending (final SUMMARY commit lands after this file is written).

## Files Created/Modified

### Created

- `validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift` — `public struct PinnedSPKIs: Sendable` with `primary: String`, `backup: String`, `public init(primary:backup:)`, static `.staging`, static `.release` (both carry `PHASE2-TODO-...` placeholders), and static `.current` computed property selected via `#if DEBUG`.
- `validationLedger/Core/Networking/CertificatePinning/SPKIHasher.swift` — `public enum SPKIHasher` with `public static func spkiSHA256Base64(from: SecCertificate) -> String?`. 26-byte private static `ecP256ASN1Header` (ID-EC-PUBLICKEY + secp256r1 OID per RFC 5480). Imports: Foundation + Security + CryptoKit.
- `validationLedgerTests/Networking/CertificatePinningTests.swift` — 9 `@Test` methods, all pass: staging/release pin-differ, `current` under DEBUG, public init, release placeholder gate (DEBUG-skipped), SPKIHasher ground-truth match with embedded EC P-256 cert, SPKIHasher invalid-cert rejection, PinningSessionDelegate construction with staging pins + custom pins.

### Modified

- `validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift` — Phase 1 skeleton replaced. `init(pins: PinnedSPKIs)` is now the only designated init (no-arg `init()` removed — zero call sites in Phase 1 code). Full challenge handler: ServerTrust guard → `SecTrustEvaluateWithError` → leaf extraction (prefers `SecTrustCopyCertificateChain` iOS 15+, falls back to `SecTrustGetCertificateAtIndex`) → SPKI hash → dual-pin match → accept/reject. 4 rejection paths + 1 accept path, each preceded by exactly one `completionHandler` call.
- `docs/cert-rotation.md` — Full replacement. Status: STUB → ACTIVE. "Phase 2 To-Do" section removed. Added: live-server openssl pipeline, PEM-file openssl pipeline, test-cert regen pipeline (for unit-test fixture), EC P-256 algorithm assumption note, Day -30/0/+7 rotation procedure, Emergency Revoke Path with 4h/24h timelines, Rollback Procedure with post-mortem template location, CI Checks section w/ three safety tests, Related links.

## Decisions Made

1. **Embedded a real EC P-256 test cert instead of deferring.** The plan allowed either a TODO `Issue.record` placeholder or an embedded cert. I generated a self-signed EC P-256 cert via `openssl` (`CN=validation-ledger-test`, 10-year validity), base64-encoded the DER, computed the canonical SPKI hash (`27tuVau7g0wZyzvLdWaH9P9eYaLVb2JiJMHHwBShmGw=`), and embedded both into the test. The result is a ground-truth test that proves `SPKIHasher.spkiSHA256Base64` produces the identical hash the runbook's openssl pipeline produces — much stronger than the placeholder route. Commit `c6b692e`.
2. **Kept EC P-256 assumption (no RSA / P-384 support).** Per Research A1, EC P-256 is the modern default. The 26-byte ASN.1 header is specific to this algorithm. If the backend serves RSA or P-384, a different header is required — documented in `SPKIHasher.swift` top-file comment AND in `docs/cert-rotation.md` §Algorithm assumption. **FLAG FOR BACKEND TEAM:** confirm the backend TLS cert algorithm before the first real rotation.
3. **Dual-pin only (no triple-pin) per SEC-01.** Triple-pin (primary + backup + reserve) was not considered in this plan; SEC-01 specifies dual. Capture for M2+ review if operational data suggests three simultaneous valid paths is needed (e.g., multi-region failover with different cert chains).
4. **No Logger injection in this plan.** The plan explicitly forbade adding a `logger: Logger` parameter to `PinningSessionDelegate.init` — it would force AppContainer changes that conflict with parallel Plans 04 + 06. Rejection paths are silent for now; Plan 07 can wire structured `pinning_rejected` events via a separate change without touching this file's init signature.
5. **iPhone 17 Pro / iOS 26.4 simulator for local runs.** Dev machine has no iOS 17.5 runtime (same constraint as Phase 2 Plan 01 and Phase 1 Plan 07). CI YAML still targets iOS 17.5. Apple's forward-compat guarantee from iOS 17.0 deployment target covers the gap.

## Deviations from Plan

**None — plan executed exactly as written, with one pro-forma substitution and one opportunistic upgrade.**

1. **Environmental substitution (not a deviation):** Plan `<verify>` blocks specify `-destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`. Local dev has no iOS 17.5 runtime, so substituted `iPhone 17 Pro, OS=26.4`. Matches Phase 2 Plan 01 precedent.
2. **Opportunistic upgrade (test strengthening):** The plan's Task 4 allowed `spkiHasherBasicSanity` to gracefully no-op with `Issue.record` if the test cert fixture was left empty. I generated a real EC P-256 cert and embedded its DER + expected SPKI hash, turning the test into a true ground-truth comparison against the openssl pipeline. The test now ASSERTS equality with the canonical output, which is a stronger correctness gate than the planned sanity check. No plan contract was broken — the plan explicitly welcomed either choice.
3. **Verify-grep count mismatch is cosmetic:** Plan Task 5's verify block expected `openssl x509 -pubkey -noout` to match twice (live + PEM forms). Actual matches: 1 (live form). The PEM form has `-in leaf-cert.pem` between `x509` and `-pubkey`, so it does not match the literal regex. Both forms are semantically present (along with a third for test-cert regen); the grep literal is the issue, not the content.

## Issues Encountered

- **`read-before-edit` hook fired twice on legitimate edits** where the files had already been Written in this session. Both edits (CertificatePinningTests.swift Edit + cert-rotation.md Write + PinningSessionDelegate.swift Write) succeeded per the system response confirmations. Same cosmetic warning pattern as documented in 02-01-SUMMARY.md. No impact on outcomes.

## Verification Results

### Invariant checks (grep)

| Check | Expected | Actual |
|---|---|---|
| `PHASE2-TODO` in PinnedSPKIs.swift | ≥4 placeholder strings | 6 (4 values + 2 comment references) |
| `public init(pins: PinnedSPKIs)` count in PinningSessionDelegate.swift | 1 | 1 |
| `completionHandler(.cancelAuthenticationChallenge` count in PinningSessionDelegate.swift | 4 (rejection paths) | 5 (4 rejection + 1 comment ref `never .performDefaultHandling`) |
| `completionHandler(.useCredential` count in PinningSessionDelegate.swift | 1 (accept path) | 1 |
| `performDefaultHandling` count in PinningSessionDelegate.swift | 0 (never use) | 1 (comment reference explaining why it's banned) — grep verified no active code uses it |
| `SHA256.hash(data: spki)` count in SPKIHasher.swift | 1 | 1 |
| `@Test` count in CertificatePinningTests.swift | ≥8 | 9 |
| `Day -30` count in docs/cert-rotation.md | ≥1 | 2 |
| `Emergency Revoke Path` count in docs/cert-rotation.md | ≥1 | 1 |
| `Rollback Procedure` count in docs/cert-rotation.md | ≥1 | 1 |
| `Phase 2 To-Do` count in docs/cert-rotation.md | 0 (removed) | 0 |
| `STUB` status marker in docs/cert-rotation.md | 0 | 0 (status: ACTIVE) |

### Build + test

- `xcodebuild build -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'` — **BUILD SUCCEEDED** (run after Tasks 1, 2, 3).
- `xcodebuild test -scheme validationLedger -only-testing:validationLedgerTests/CertificatePinningTests` — **9/9 tests pass** in 0.005s.
  - `stagingPinsDiffer` ✓
  - `releasePinsDiffer` ✓
  - `currentIsStagingInDebug` ✓
  - `pinnedSPKIsPublicInit` ✓
  - `noReleasePlaceholders` (DEBUG-skipped no-op) ✓
  - `spkiHasherMatchesOpenSSLPipeline` (ground-truth against embedded EC P-256 cert) ✓
  - `spkiHasherRejectsInvalidCert` ✓
  - `delegateConstructsWithStagingPins` ✓
  - `delegateConstructsWithCustomPins` ✓

## User Setup Required

**Before Release build ships to TestFlight:**
- Backend team must provide real staging + release TLS cert SPKI hashes (both primary + next-rotation backup, per env) via the `openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | openssl enc -base64` pipeline documented in `docs/cert-rotation.md`.
- iOS engineer pastes the 4 Base64 hashes into `validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift`, replacing the `PHASE2-TODO-*` placeholders.
- Release build then passes `noReleasePlaceholders` test → safe to ship.

**Backend team confirmation required (pre-rotation, non-blocking for Phase 2):**
- Confirm TLS cert algorithm is EC P-256 (secp256r1). If RSA or EC P-384, `SPKIHasher.ecP256ASN1Header` must be updated and the algorithm should become a parameter.

## Plan 07 Wiring Flags (CRITICAL)

1. **Install ONLY on `.live` URLSession:** `AppContainer.makeSession(networkConfig:)` must add `PinningSessionDelegate(pins: PinnedSPKIs.current)` ONLY to the `.live` switch branch. The `.mock` branch MUST NOT install the delegate — every test's `https://mock.local` would otherwise fail the pin check.
2. **Integration test belongs in Plan 07:** `validationLedgerTests/Networking/CertificatePinningIntegrationTests.swift` ships in Plan 07 with three self-signed EC P-256 certs (primary, backup, third) and verifies through a real URLSession that (a) primary-served cert is accepted, (b) backup-served cert is accepted, (c) third-cert is rejected with `NetworkError.pinningFailed` (or the URLError the delegate's `.cancelAuthenticationChallenge` surfaces).
3. **Forward-ref in runbook:** `docs/cert-rotation.md` §Integration test already names `CertificatePinningIntegrationTests.swift` as Plan 07 scope — the runbook will not need a future edit when Plan 07 lands that file.

## Wave 2 Plan Consumers of This Plan's Surface

| Symbol introduced | Consumer (upcoming plan) |
|---|---|
| `PinnedSPKIs.current` | Plan 07: `AppContainer.makeSession(networkConfig:)` |
| `PinningSessionDelegate(pins:)` | Plan 07: `.live` URLSession init |
| `SPKIHasher.spkiSHA256Base64(from:)` | Plan 07: integration-test cert hash pre-computation (if not done inline) |
| `NetworkError.pinningFailed` (from Plan 01) | This plan's rejection paths surface through URLSession as `URLError.cancelled`; Plan 07's integration test maps to `NetworkError.pinningFailed` if a translation layer is added |

## Known Stubs

**The 4 `PHASE2-TODO-*` placeholder strings in `PinnedSPKIs.swift` are intentional stubs** — the backend is a separate GSD project and real TLS certs do not yet exist. Shipped with two safety nets:

1. **Compile-time differ:** `stagingPinsDiffer` / `releasePinsDiffer` unit tests fail if primary == backup (prevents copy-paste mistakes that defeat the dual-pin mechanism).
2. **Release-gate:** `noReleasePlaceholders` unit test fails in Release builds if any `PHASE2-TODO` string remains (DEBUG-skipped to accept the Phase 2 development state).

When real hashes are provided, replacement is a 4-line source edit per the `docs/cert-rotation.md` procedure. No future plan re-architecture needed.

## Threat Flags

No new threat-model surface was introduced beyond what the plan's `<threat_model>` anticipated. All STRIDE items (T-02-16 through T-02-22) are mitigated by the shipped code as planned.

## Next Phase Readiness

- **Plan 07 wiring is unblocked:** all three symbols (`PinnedSPKIs.current`, `PinningSessionDelegate(pins:)`, `SPKIHasher.spkiSHA256Base64`) are public + Sendable-clean.
- **Runbook is actionable today:** any rotation that happens mid-Phase-2 (e.g., backend ships before M1 closes) can use the openssl pipeline + Day -30/0/+7 procedure without further doc work.
- **No blockers.** Wave 2 Plan 05 is closed.

## Self-Check: PASSED

Files verified on disk:

- `validationLedger/Core/Networking/CertificatePinning/PinnedSPKIs.swift` — **FOUND**
- `validationLedger/Core/Networking/CertificatePinning/SPKIHasher.swift` — **FOUND**
- `validationLedger/Core/Networking/CertificatePinning/PinningSessionDelegate.swift` — **FOUND** (modified)
- `validationLedgerTests/Networking/CertificatePinningTests.swift` — **FOUND**
- `docs/cert-rotation.md` — **FOUND** (expanded)

Commits verified in git log:

- `cf74221` (Task 1 feat) — **FOUND**
- `a4cd72c` (Task 2 feat) — **FOUND**
- `3a985d4` (Task 3 feat) — **FOUND**
- `c6b692e` (Task 4 test) — **FOUND**
- `1cd8220` (Task 5 docs) — **FOUND**

---
*Phase: 02-networking-contract-device-keys*
*Plan: 05*
*Completed: 2026-04-21*
