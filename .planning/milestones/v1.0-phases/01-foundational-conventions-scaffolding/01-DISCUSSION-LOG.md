# Phase 1: Foundational Conventions & Scaffolding — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `01-CONTEXT.md` — this log preserves the alternatives considered and the verbatim user selections.

**Date:** 2026-04-20
**Phase:** 01-foundational-conventions-scaffolding
**Areas discussed:** CI provider pick, Role scaffolding depth

---

## Gray-area selection

| Gray area | Presented | Selected by user |
|-----------|-----------|------------------|
| Module/target layout | ✓ | |
| PII scrubber API shape | ✓ | |
| CI provider pick | ✓ | ✓ |
| Role scaffolding depth | ✓ | ✓ (added mid-discussion after CI completed) |

Not presented (trimmed to 4-option AskUserQuestion limit): ADR layout, Dev-menu scope in Phase 1, SwiftLint custom rule coverage. The user opted to let these default to Claude's Discretion — captured in CONTEXT.md D-15..D-21.

---

## CI provider pick

### Q1 — Simulator pipeline provider

| Option | Description | Selected |
|--------|-------------|----------|
| GitHub Actions (Recommended) | macOS-latest runner. Standard tooling. Good secrets management. ~$0.08/min on private repos; free on public. | ✓ |
| Xcode Cloud | Apple-native. 25 compute hours/month free per Apple Developer Program. TestFlight integration. Constrained scripting. | |
| Self-hosted Mac for both sim + device | One runner type. Fastest iteration. More ops burden. | |

**User's path:** First answered *"what is this provider for?"* — Claude unpacked what CI is, what the sim vs. device pipeline split is for, and what the provider choice decides. User then selected **GitHub Actions**.

**Notes:** User previously unfamiliar with CI provider options at this level of detail. Clarification loop was productive; user made an informed pick.

### Q2 — Physical-device runner ownership

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated Mac mini + iPhone (Recommended) | Always-on, predictable. ~$600 one-time. | |
| Developer MacBook as self-hosted runner | Free upfront; blocks dev machine 5–15 min per device-CI run; single-point-of-failure for merges. | ✓ |
| Cloud-hosted Mac (e.g., MacStadium) | ~$100–200/month. No hardware ownership. | |

**User's choice:** Developer MacBook as self-hosted runner.
**Notes:** Deliberate M1 cost-saver. Flagged in CONTEXT.md (D-04) with re-evaluation trigger at M2 boundary or second-engineer onboarding.

### Q3 — Phase 1 CI test scope

| Option | Description | Selected |
|--------|-------------|----------|
| Build + lint + unit-test Core/ (Recommended) | Full `Core/` unit tests + ≥70% coverage target per CI-01. Device CI = SE-available smoke test only. | ✓ |
| Just build + lint | Fastest; CI-01 coverage target slides to Phase 2. | |
| Build + lint + unit + E2E smoke on sim | Adds UI test; would require throwaway screens; CI-02 is Phase 3. | |

**User's choice:** Build + lint + unit-test Core/.

### Q4 — Device CI trigger policy

| Option | Description | Selected |
|--------|-------------|----------|
| Merge-to-main only (spec default) | Strict FOUND-04. Simple config. Main can break then be fixed-forward. | |
| Merge + security-path PR gate (Recommended) | Also gate PRs touching `Core/Auth/`, `Core/KeyStore/`, `Core/Identity/`, `Core/Networking/CertificatePinning/`. | ✓ |
| Every PR, every path | Maximum safety; too slow given dev-MacBook-as-runner. | |

**User's choice:** Merge + security-path PR gate.
**Notes:** Aligns with `.planning/research/PITFALLS.md` Pitfall 5 guidance.

---

## Role scaffolding depth

### Q1 — Phase 1 depth

| Option | Description | Selected |
|--------|-------------|----------|
| Pattern only — ADR + empty directory | Phase 1 ships doc + empty dir; Phase 3 writes everything. Smallest P1; biggest P3. | |
| Protocol + enum + empty subdirs (Recommended) | P1 ships Role enum + RoleCoordinator protocol + 5 empty subdirs. Clear seam. | |
| Recommended + placeholder tab bar stubs | + 5 concrete UITabBarController stubs with empty tabs per §4. P3 becomes wiring. | |
| Full dev-menu demo | All of above + DEBUG-only dev menu that swaps root on tap. Validates ARCH-06 end-to-end before P3 demo. | ✓ |

**User's path:** First answer attempted — user clarified "what is ADR?" Claude explained Architecture Decision Records (ADR format, template, why it matters for FOUND-03 / ARCH-06 / the role scaffolding choice). Question was re-asked with inline clarifications of ADR / protocol / placeholder VC / empty subdir. User then selected **Full dev-menu demo**.

**Notes:** Biggest Phase 1 scope choice. Deliberate — user prioritized validating the root-swap mechanism before Phase 3's fixed visible-win demo depends on it. Auto-answered the "Dev-menu scope in Phase 1" gray area (centralized DevMenu required).

### Q2 — Tab inventory source

| Option | Description | Selected |
|--------|-------------|----------|
| Full TechStack.md §4 inventory (Recommended) | Every tab per role exactly per §4. Placeholder VCs with icon + title, no content. | ✓ |
| One-tab-per-role minimum | Only 'Home'. Weaker dev-menu demo. | |
| Categories only, no specific names | Right tab count with generic names. Temporary, definitely renamed. | |

**User's choice:** Full TechStack.md §4 inventory.
**Notes:** Claude cited §4 verbatim during the question; verified against `TechStack.md:96-106` after selection. A §4-vs-AUTH-04 Profile-tab inconsistency was surfaced and captured in CONTEXT.md `<deferred>` for Phase 3 resolution.

### Q3 — DevMenu invocation + release safety

| Option | Description | Selected |
|--------|-------------|----------|
| Shake gesture, `#if DEBUG` compiled out (Recommended) | `UIResponder.motionEnded(_:with:)`; whole DevMenu target absent from Release binaries. | ✓ |
| Hidden 10-tap on app icon area at launch | Launch-screen Easter egg; harder to rediscover. | |
| Runtime feature flag (env var + Info.plist) | Visible in all builds if flag set; weaker guarantee for security-first product. | |

**User's choice:** Shake gesture, `#if DEBUG` compile-out.

---

## Claude's Discretion

User explicitly deferred the following gray areas (or they were not presented within the 4-option AskUserQuestion limit and user chose not to open them). Captured as D-15..D-21 in CONTEXT.md:

- Module/target layout → Single Xcode target with directory groups (D-15)
- PII scrubber API shape → Hybrid, structured preferred (D-16)
- Logging subsystems → One OSLog subsystem per top-level `Core/` module with categories (D-17)
- ADR layout → `docs/adr/NNNN-title.md` numbered + immutable (D-18)
- SwiftLint custom rules → 4 rules ship in Phase 1; raw-coordinate ban deferred to Phase 3 (D-19)
- First-launch Keychain wipe implementation path → `AppDelegate` before `AppContainer` resolves (D-20)
- `PrivacyInfo.xcprivacy` declared APIs → UserDefaults + CA92.1, empty SDK list (D-21)

---

## Deferred Ideas

Captured in CONTEXT.md `<deferred>` section. Summary:

- **Open clarifications (not scope changes):** Profile tab reconciliation (Phase 3); Cert rotation runbook full content (Phase 2)
- **Future re-evaluation triggers:** Dev-MacBook-as-device-runner (M2 boundary / second-engineer); single-target vs. SPM packages (~15 Features / lint slippage)
- **Out of Phase 1 scope — existing phase assignments:** raw-coordinate lint (P3), networking/keys (P2), auth/session/shell (P3), App Attest (P4), KYC/upload (P5)
- **Scope-creep parking lot:** none — discussion stayed within Phase 1 boundary
