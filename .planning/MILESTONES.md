# Milestones

## v1.0 M1 Foundation (Shipped: 2026-05-18)

**Delivered:** the M1 Foundation — all five roles OTP-authenticate into role-distinct tab shells, persist a session across cold boot, complete KYC capture, and resume a chunked upload — on a UIKit/iOS-17 base with device-bound Secure Enclave keys and App Attest.

**Scope:** 6 phases, 55 plans, 128 tasks · ~28,700 LOC Swift across 207 files · 431 commits · 2026-04-20 → 2026-05-18 (~28 days, on the 4-week target).

**Close:** `tech_debt` milestone audit — 67/67 requirements satisfied, 6/6 phases verified, 8/8 E2E flows wired, 0 critical blockers. See `milestones/v1.0-MILESTONE-AUDIT.md`.

### Key accomplishments

1. **Foundation rebuilt (Phase 1)** — replaced the Xcode SwiftUI scaffold with a UIKit/iOS-17 module layout, the 8 foundational conventions (PII-scrubbing logger, first-launch Keychain wipe, SessionLockService, DeepLinkRouter), 5 SwiftLint custom rules on a pre-commit hook, and a sim/device CI split.
2. **Contract-first networking + device keys (Phase 2)** — `APIClient` + 7 typed M1 endpoints + `MockURLProtocol` fixtures, one-line mock/live swap, idempotency + retry interceptors, dual-pin SPKI certificate pinning, and a Secure Enclave two-key (`deviceKey` / `authorizationKey`) keystore.
3. **5-role OTP auth + session (Phase 3)** — phone-entry → mocked OTP → role-distinct tab shells, session persistence across cold boot, biometric re-prompt via `SessionLockService`, clean logout teardown, and a compile-time barrier keeping raw coordinates out of logs.
4. **App Attest + physical-device CI (Phases 4 & 6)** — `Core/Attestation` with App Attest wired into the first-login `/device/register` path, and a self-hosted device-CI lane exercising Secure Enclave / Keychain-biometric / App Attest on every merge to `main`.
5. **KYC capture + resumable upload (Phase 5)** — `KYCCoordinator` capture flow (face → DL → vehicle) with capture-time EXIF GPS injection, a resumable chunked `KYCUploader` actor (disk-persisted resume, jittered backoff, BGProcessingTask continuation), and a 4-state KYC status UI.
6. **Audit-driven gap closure (Phase 6)** — the first v1.0 audit found App Attest unwired at first login and Phase 4 unverified; an inserted closure phase wired App Attest into `OTPViewModel`, the trustTier producer→Keychain→consumer chain, and produced the retroactive `04-VERIFICATION.md`. The re-audit closed `tech_debt`.

### Known deferred items at close

18 open artifacts acknowledged and deferred (see STATE.md → Deferred Items): 4 debug sessions (resolved/diagnosed but not formally closed), 16 physical-device HUMAN-UAT scenarios across Phases 1/2/4/6, 6 `VERIFICATION.md` files at `human_needed` (all carry device-UAT items, not code gaps), and 1 medium-priority todo (`device-ci-biometric-infra`). Plus Nyquist validation gaps on Phases 1–2. None blocks M2; full tail catalogued in `milestones/v1.0-MILESTONE-AUDIT.md`.

---
