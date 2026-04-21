# Cert Rotation Runbook

**Status:** STUB — full content ships in Phase 2 alongside SEC-01 cert pinning implementation.
**Phase 1 scope:** Reserves the path + documents the 30-day rotation pattern at outline depth per PITFALLS.md P3.

## Why This File Exists in Phase 1

FOUND-05 maps to Phase 1 in ROADMAP.md traceability, but the full runbook depends on Phase 2's `PinningSessionDelegate` implementation (the skeleton-only version ships in Phase 1 Plan 03 under `Core/Networking/CertificatePinning/`). This file is committed now so the path is reserved and the 30-day rotation pattern is captured at outline depth — CRITICAL for preventing self-brick DoS (PITFALLS.md P3).

## 30-Day Rotation Window (outline)

1. **Dual-pin deployment:** Backup SPKI hash is deployed alongside the primary SPKI hash in every release. Both are valid simultaneously.
2. **Primary approaches expiry (≥30 days before):**
   - Rotate the primary pin in source (`Core/Networking/CertificatePinning/PinningSessionDelegate.swift`) to the next-gen cert's SPKI hash.
   - Backup pin remains as fallback.
   - Ship the release; wait for TestFlight adoption baseline (target ≥ 95% active installs).
3. **Primary expires:**
   - Old backup pin becomes the new primary.
   - Next-gen cert's SPKI hash moves to backup slot.
   - Ship the release.
4. **Emergency revoke path (if primary cert is compromised before rotation window):**
   - Phase 2 deliverable — full step-by-step procedure + user-facing messaging.

## Phase 2 To-Do (FOUND-05 full scope)

- Step-by-step script-driven rotation (commands with exact file paths, commit messages, review checklist)
- Backup-pin source-of-truth decision (separate file? embedded in release build-config? TBD in Phase 2 context gather)
- Rollback procedure if a rotation ships a bad pin
- CI check: SwiftLint custom rule or unit test that fails if only one SPKI hash is declared (both must be present)
- Integration with TestFlight adoption analytics (when available — note this may slip to M2 if crash-vendor not chosen)

## Related

- `.planning/research/PITFALLS.md` — P3 (cert pinning without rotation = self-brick DoS)
- `.planning/REQUIREMENTS.md` — FOUND-05, SEC-01
- `docs/ci.md` — Device CI security-path filter includes `Core/Networking/CertificatePinning/**`
