# Roadmap: Validation Ledger — iOS Client

## Milestones

- ✅ **v1.0 M1 Foundation** — Phases 1-6 (shipped 2026-05-18)
- ✅ **v1.1 Load Flows** — Phases 7-10 (shipped 2026-05-21)
- 📋 **Next milestone** — undecided; start with `/gsd-new-milestone`

## Phases

<details>
<summary>✅ v1.0 M1 Foundation (Phases 1-6) — SHIPPED 2026-05-18</summary>

- [x] Phase 1: Foundational Conventions & Scaffolding (7/7 plans) — completed 2026-04-21
- [x] Phase 2: Networking Contract & Device Keys (7/7 plans) — completed 2026-04-21
- [x] Phase 3: OTP Auth + Role Shell + Session (13/13 plans) — completed 2026-04-22
- [x] Phase 4: App Attest & Physical-Device CI Hardening (11/11 plans) — completed 2026-05-16
- [x] Phase 5: KYC Capture & Upload Pipeline (13/13 plans) — completed 2026-05-18
- [x] Phase 6: Close gap — DEV-04 App Attest at first login + trustTier consumer + Phase 4 verification (4/4 plans) — completed 2026-05-18

Full phase detail, success criteria, and milestone summary archived at `.planning/milestones/v1.0-ROADMAP.md`.

</details>

<details>
<summary>✅ v1.1 Load Flows (Phases 7-10) — SHIPPED 2026-05-21</summary>

**Milestone Goal:** Deliver the freight load domain end-to-end on iOS — a role-filtered load list, a load detail screen with an interactive chain-of-trust graph, and per-role tender/accept/reject — built entirely against `MockURLProtocol` fixtures, with zero backend, real-time, or push dependency.

- [x] Phase 7: Load Domain Model & Mock Contract (6/6 plans) — completed 2026-05-20
- [x] Phase 8: Role-Filtered Load List (4/4 plans) — completed 2026-05-20
- [x] Phase 9: Load Detail & Chain-of-Trust Graph (10/10 plans) — completed 2026-05-20
- [x] Phase 9.1: Chain-of-Vouches Redesign — vertical attribution tree (INSERTED — device UAT) (5/5 plans) — completed 2026-05-21
- [x] Phase 10: Per-Role Tender / Accept / Reject (10/10 plans) — completed 2026-05-21

Closed with a `tech_debt` milestone audit — 20/22 requirements satisfied (2 partial, 0 unsatisfied), 5/5 phases verified. Full phase detail, success criteria, and milestone summary archived at `.planning/milestones/v1.1-ROADMAP.md`; audit at `.planning/milestones/v1.1-MILESTONE-AUDIT.md`.

</details>

### 📋 Next Milestone (Planned)

Undecided. Start with `/gsd-new-milestone` — questioning → research → requirements → roadmap. Candidate scope: the remainder of the original M2 "Core Flows" — real backend integration, real-time load updates (WebSocket/SSE), APNs push — all of which need a running server.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundational Conventions & Scaffolding | v1.0 | 7/7 | Complete | 2026-04-21 |
| 2. Networking Contract & Device Keys | v1.0 | 7/7 | Complete | 2026-04-21 |
| 3. OTP Auth + Role Shell + Session | v1.0 | 13/13 | Complete | 2026-04-22 |
| 4. App Attest & Physical-Device CI Hardening | v1.0 | 11/11 | Complete | 2026-05-16 |
| 5. KYC Capture & Upload Pipeline | v1.0 | 13/13 | Complete | 2026-05-18 |
| 6. Close gap: DEV-04 + trustTier + Phase 4 verification | v1.0 | 4/4 | Complete | 2026-05-18 |
| 7. Load Domain Model & Mock Contract | v1.1 | 6/6 | Complete | 2026-05-20 |
| 8. Role-Filtered Load List | v1.1 | 4/4 | Complete | 2026-05-20 |
| 9. Load Detail & Chain-of-Trust Graph | v1.1 | 10/10 | Complete | 2026-05-20 |
| 9.1. Chain-of-Vouches Redesign (INSERTED — device UAT) | v1.1 | 5/5 | Complete | 2026-05-21 |
| 10. Per-Role Tender / Accept / Reject | v1.1 | 10/10 | Complete | 2026-05-21 |

---
*Milestone v1.0 "M1 Foundation" shipped 2026-05-18. Milestone v1.1 "Load Flows" shipped 2026-05-21. See `.planning/MILESTONES.md` for summaries and `.planning/milestones/` for full archives. Roadmap created 2026-04-20.*
