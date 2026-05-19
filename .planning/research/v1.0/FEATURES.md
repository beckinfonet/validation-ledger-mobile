# Feature Research — Validation Ledger iOS Client

**Domain:** Identity-verified freight / trucking mobile app (iOS, five roles: Shipper, Broker, Carrier, Dispatch, Factoring)
**Researched:** 2026-04-20
**Confidence:** MEDIUM-HIGH (cross-verified against 2026 industry sources — FMCSA MOTUS rollout, Highway/Verified Carrier, Trustd DIATF certification, Vector, Samsara, McLeod 26.1, Uber Freight 2025–2026 release notes, Plaid/Persona/Jumio/Alloy 2026 posture)

---

## Executive Orientation

The competitive landscape split into two camps by early 2026:

1. **Legacy TMS mobile apps** (Samsara Driver, McLeod LoadMaster Mobile, TruckLogics, Trucker Path, Truckstop ITS Dispatch, Uber Freight Carrier) that treat identity as a one-time signup step and then become utility apps for load matching, navigation, ELD, and document capture.
2. **Emerging identity-first freight stack** (Highway, Verified Carrier's "Verified Pickup" launched April 15 2026, Trustd in EU/UK, MyCarrierPortal) that treats identity and the chain-of-trust as the primary product surface, wrapping TMS functions around it.

Validation Ledger is in camp 2. The most important insight from the research: **Verified Carrier's "Verified Pickup" (shipped April 2026) validates Validation Ledger's thesis** — a shipper scans a driver's encrypted QR / DL at the dock to confirm the carrier's verification status and the driver's confirmed photo before releasing freight. That is almost exactly the eBOL + rotating-QR + dock scanner flow in TechStack §5.7–5.8. The delta for Validation Ledger is (a) iOS-first from day one, (b) a rotating/signed QR with TTL rather than an encrypted-but-static QR, (c) chain-of-trust visualization as a first-class UI surface rather than a buried attribute, (d) five roles in one app rather than separate shipper/carrier apps, (e) device-bound one-active-device enforcement rather than account-level login.

Against this backdrop, feature categorization:

---

## Feature Landscape

### Table Stakes — Users Expect These (ship or product feels broken)

These are the features that users will silently expect. Missing them does not earn a mention in reviews — they only earn a mention when absent, and then as a deal-breaker. Cross-referenced with Samsara Driver, Trucker Path, Uber Freight Carrier, TruckLogics, Vector eBOL, and Trustd (2026).

| # | Feature | Why Expected | Role(s) | Complexity | Milestone | Implementation Notes |
|---|---------|--------------|---------|------------|-----------|----------------------|
| T1 | Phone + SMS OTP auth | Every consumer app in 2026; drivers won't type passwords in a cab | All 5 | LOW | M1 | Spec'd as FR-iOS-AUTH shim. Token in Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. No "remember me" — intentional. |
| T2 | Biometric (Face ID / Touch ID) re-prompt for sensitive actions | Banking-app mental model — users assume touching a financial action requires biometrics | All 5 | LOW | M1 | `LocalAuthentication` + Keychain `.biometryCurrentSet`. Spec'd. |
| T3 | Role-switched primary navigation | Shipper, dispatcher, driver, factoring rep have zero overlap in daily flow | All 5 | MEDIUM | M1 | Role set at backend account creation; tab-bar swapped at coordinator. Spec'd (TechStack §4). |
| T4 | Live face capture + DL front/back capture | Post-FMCSA-MOTUS (Dec 2025 rollout) every freight participant expects to prove identity once, permanently | All 5 | MEDIUM | M1 | Vision + `VisionKit.DataScannerViewController`. Liveness deferred past M1 per PROJECT.md. |
| T5 | Vehicle/trailer/plate photo capture with GPS metadata | Carrier-side. Chameleon-carrier fraud crackdown made this mandatory per FMCSA | Carrier, Dispatch | LOW | M1 | Camera + CoreLocation. Spec'd FR-iOS-KYC. |
| T6 | Resumable upload pipeline with visible progress | Drivers are on LTE in truck stops. KYC uploads fail. Industry benchmark: users who must re-upload are 3× more likely to abandon | All 5 | MEDIUM | M1 | `URLSession` background config + checkpointed multipart. Exponential backoff, retry, persistent queue. Spec'd. |
| T7 | Clear KYC status with reason-for-rejection text | Industry data: generic "rejected, try again" causes 15–30% ID-step abandonment; specific rejection reasons cut re-upload abandonment by 25–30% | All 5 | LOW | M1 | Four states: Pending / Under Review / Verified / Rejected. Rejection copy comes from backend but iOS must render it prominently. Spec'd. |
| T8 | Load list filtered by role | Driver sees their loads, broker sees their tendered loads. Samsara/Uber Freight/TruckLogics all do this — not optional | All 5 | MEDIUM | M2 | List + detail via MVVM ViewModels. Backend filters by role token; client does not re-filter. |
| T9 | Load detail with status timeline | Standard Uber Freight / Convoy pattern — "Booked → Dispatched → Arrived at shipper → Loaded → In transit → Arrived at receiver → Delivered" | All 5 (read-only for Shipper/Factoring) | MEDIUM | M2 | The "chain-of-trust" visualization is the differentiator layered on top of this timeline. |
| T10 | One-tap status updates (Arrived, Loaded, Delivered) | Convoy-popularized pattern; now universal. Carriers won't adopt an app that requires more than one tap per checkpoint | Carrier, Dispatch | LOW | M2 | Geofenced pre-fill where possible (M3+). Queue offline via FR-iOS-OFF. |
| T11 | Tender → Accept/Reject flow | Broker → Carrier handoff. The single flow every TMS app has. Must be friction-light for brokers but device-signed for identity | Broker, Carrier | MEDIUM | M2 | Requires device-key signing (FR-iOS-DEV). Spec'd as FR-iOS-LOAD. |
| T12 | Real-time load status updates (WS / SSE) | Dispatchers and factoring companies check status obsessively; polling feels broken in 2026 | All 5 | MEDIUM | M2 | Abstraction over WebSocket/SSE per TechStack §5.6. |
| T13 | Push notifications with deep links | Samsara, Uber Freight, McLeod, Trucker Path, Truckstop all do this. Drivers live on the lock screen | All 5 | MEDIUM | M3 | APNs + notification categories. "Accept" action from lock screen for carriers. Critical alerts for new-device login. Spec'd FR-iOS-NOTIF. |
| T14 | eBOL rendering (read-only on mobile) | Vector, SmartBOL, J.B. Hunt, C.H. Robinson all ship it; FMCSA and E-SIGN laws make it legally enforceable. Drivers expect the BOL in the app, not on paper | Shipper, Broker, Carrier | MEDIUM | M3 | PDF generated server-side; iOS renders. Export via share sheet. Spec'd FR-iOS-BOL. |
| T15 | QR code scanner for dock | YardView, MobileDock, SmartBOL, myQ Enterprise, Verified Pickup — the check-in-by-QR pattern is universal at modern DCs in 2026 | Carrier, Shipper | LOW | M3 | AVFoundation `AVCaptureMetadataOutput`. Torch toggle. Spec'd FR-iOS-SCAN. |
| T16 | POD / delivery-confirmation signature + photo capture | Vector, SmartBOL; every freight mobile app captures a POD. E-SIGN Act compliance | Carrier | MEDIUM | M3 | UIKit canvas for signature + camera. Timestamp + GPS + device-signed payload. Not yet explicit in TechStack §5.7 — likely M3 addition. |
| T17 | In-app chat / messaging between parties | Uber Freight, Convoy, Truckstop ITS all include broker-carrier messaging. Without it, parties go to SMS and PII leaks | All 5 | MEDIUM | M4 (or defer to v2) | Must avoid third-party chat SDKs that leak PII — see Anti-Feature A4. Backend-mediated, not a dropped-in SDK. |
| T18 | Offline read-only access to active load + BOL | Drivers hit dead zones. Vector and Samsara both do this. Losing BOL visibility because of LTE kills adoption | All 5 | MEDIUM | M4 | Encrypted cache. Clear on load completion. Spec'd FR-iOS-OFF. |
| T19 | Dynamic Type + VoiceOver on primary flows | App Store submission quality; drivers over 50 rely on Dynamic Type | All 5 | LOW | M4 | UIKit native support. Audit pass per TechStack §6. Spec'd. |
| T20 | Factoring: invoice submission + BOL attach | Triumph, RTS, OTR Solutions, Cashway all ship this. A factoring mobile app without this does not exist | Factoring, Carrier | MEDIUM | M2–M3 | Scan BOL (camera + image enhancement) and attach to invoice. Factoring side gets the same BOL with chain-of-trust attached. |
| T21 | MC/DOT number entry + live FMCSA lookup | Post-2025-crackdown, brokers literally won't tender to a carrier whose MC can't be instantly validated. MOTUS phased in through 2026 | Broker, Carrier, Factoring | LOW | M1 | Backend-mediated FMCSA call (FMCSA Mobile API / QCMobile). iOS renders result. Spec'd FR-iOS-KYC SHOULD. |
| T22 | Settings: notification prefs, help, logout, delete account | App Store rejects apps without account deletion since 2022; drivers expect granular push prefs | All 5 | LOW | M1–M2 | SwiftUI-permitted surface per TechStack §3.2. |
| T23 | Cold start < 2s, screen transitions < 200ms | Drivers open the app 30+ times/day; latency is an abandonment driver | All 5 | MEDIUM | M1–M5 | Spec'd in non-functionals §6. Validates MVVM+Coordinator choice (lighter than TCA). |

### Differentiators — Validation Ledger's Competitive Advantage

These are where Validation Ledger competes. These features are not required by users-in-general; they are the reason this product exists at all. Anchored to PROJECT.md Core Value: "identity that cannot be spoofed + chain-of-trust that cannot be faked."

| # | Feature | Value Proposition | Role(s) | Complexity | Milestone | Implementation Notes |
|---|---------|-------------------|---------|------------|-----------|----------------------|
| D1 | **Chain-of-trust visualization as a primary UI surface** | The user-facing manifestation of the entire product thesis. No competitor surfaces "X → Y → Z, each verified, here's who vouched" as first-class. Trustd has the data; Highway has the data; none render it as a timeline the user can tap through. TechStack §13 calls it "the single most important screen in the product." | All 5 | HIGH | M2 | Vertical timeline: Shipper → Broker → Carrier → Driver. Each node renders: verification status, KYC timestamp, counterparty-relationship proof, tap-for-details. Must be reactive to live status. Requires design investment — this is the marketing screen. Spec'd FR-iOS-LOAD. |
| D2 | **Live rotating QR on eBOL (30s TTL, backend-signed)** | Verified Pickup uses an "encrypted QR" but it's a static encrypted payload on the driver's side. Validation Ledger's QR is fetched live from backend with a short TTL so a screenshot is worthless 30 seconds later — this closes the fraud window between "driver forwarded a screenshot" and "driver is actually at the dock." | Carrier (displays), Shipper/Broker (scans) | HIGH | M3 | Backend is signing authority; iOS only displays. Requires: 30s refresh timer, fall-back to backend round-trip on expiry, cached last-known-good for offline (flagged "offline — ask again"). Screenshot-block mandatory. Spec'd FR-iOS-BOL. Depends on: backend signing service (cross-team dep). |
| D3 | **Device-bound identity with one-active-device enforcement** | Chameleon-carrier fraud works because a fraudster can log a stolen identity into a new device. Secure Enclave + one-active-device + re-KYC-to-switch closes that loop. Samsara, Uber Freight, McLeod all allow multi-device login. | All 5 | HIGH | M1 | EC P-256 in Secure Enclave. Public key at first login. Client refuses to proceed if backend reports another active device; flow to switch requires re-KYC. Spec'd FR-iOS-DEV. Depends on backend device-registry. |
| D4 | **Refuse-to-tender-to-unverified-counterparty with inline reason** | Highway and Trustd flag unverified carriers; none *block* the action at the client level with a clear UI explanation. This moves Validation Ledger from "carrier vetting tool" to "fraud-prevention rail." | Broker, Shipper, Factoring | MEDIUM | M2 | Hard disable of Tender/Accept/Pay action when counterparty verification status ≠ Verified. Reason text from backend. Spec'd FR-iOS-LOAD. |
| D5 | **US-only login with client-side country pre-check + impossible-travel backend enforcement** | A large share of freight fraud originates from foreign IPs. Client-side `CLLocationManager` reverse-geocode + backend re-verification is a consumer-invisible hardening that competitors don't do | All 5 | MEDIUM | M1 (pre-check), M2 (impossible-travel UI) | Pre-check on client, backend authoritative. Impossible-travel downgraded to SHOULD on client per PROJECT.md. Spec'd FR-iOS-GEO. |
| D6 | **Screenshot + screen-recording block on eBOL, QR, chain-of-trust, DL capture** | The entire platform premise breaks if fraud works via screenshot forwarding. Most TMS apps have zero screenshot protection. Banking apps have it; freight apps don't. This is a credible differentiator in sales conversations. | All 5 | MEDIUM | M3 (BOL/QR), M1 (KYC) | `UIScreen.capturedDidChangeNotification` + `isSecureTextEntry`-layer trick + `UIScreen.main.isCaptured`. Four sensitive surfaces: eBOL, live QR, DL-capture screen, chain-of-trust. Spec'd FR-iOS-SEC. |
| D7 | **Role-unified app (all 5 roles in one binary) with role-specific UX** | Competitors split this: Uber Freight Carrier vs. Uber Freight Shipper are different apps; Samsara Driver is only for drivers. A broker inspecting a load sees the same chain-of-trust the driver signed into. One app = one source of truth for the verification state. | All 5 | HIGH | M1 (shell), M2 (per-role surfaces) | Shared shell, role-specific coordinators + view controllers. iPad native for dispatch/factoring. Spec'd TechStack §4. |
| D8 | **Identity-grounded messaging (no third-party chat SDK)** | If parties talk in the app, PII flows through the app. Using Intercom/SendBird/Stream means PII hits a third party. Validation Ledger running its own backend-mediated chat avoids that and lets every message be device-signed and attributed to a verified identity. Differentiator vs. the "chat SDKs in a trust app" anti-pattern. | All 5 | HIGH | M4+ (or defer to v2) | Custom implementation on the Validation Ledger backend. Not a table-stake at launch; differentiates once rolled out. |
| D9 | **Backend-mediated AI assistant scoped to role + verification state** | Every 2026 TMS has a chatbot (Samsara, McLeod RespondAI, Uber Freight). Most are generic LLMs. Validation Ledger's assistant answers only with data the user is authorized to see AND cites the chain-of-trust — e.g., "this carrier's verification lapsed on April 3; do not tender." Grounded in identity. | All 5 | HIGH | M4 | Claude Sonnet 4.5 backend-mediated. iOS never calls Anthropic directly per TechStack §5.9. Streamed rendering. |
| D10 | **KYC-as-identity (single verification, portable across counterparties)** | Trustd's core premise; Validation Ledger adopts it. A driver verified once on the platform is trusted by every broker, shipper, factoring party on the platform — no re-onboarding packet per relationship (MyCarrierPackets eliminates packet collection; Validation Ledger goes further by making identity permanent and portable). Changes the economics of broker-onboarding from "1 week" to "instant." | Broker, Carrier, Factoring | HIGH | Platform-level (iOS surfaces it in M2) | iOS surface: "This carrier has already been verified by the platform since [date]" on tender screen. Policy and data model live on backend. |
| D11 | **Device-attested login payload (App Attest + Secure Enclave signature)** | DeviceCheck/App Attest adds a "this is a genuine, unmodified iOS app on a real device" signal to every login. Almost no trucking app does this. Fraud rings that clone apps or run on emulators get rejected. | All 5 | MEDIUM | M1 | `DCAppAttestService`. Spec'd FR-iOS-DEV SHOULD. |
| D12 | **Biometric-bound device key (`.biometryCurrentSet`)** | Face-ID re-enrollment invalidates the device key, forcing re-binding. A thief who steals a phone and re-enrolls their face cannot transact. Samsara/Uber Freight do not do this. | All 5 | LOW | M1 | Keychain access control. Spec'd TechStack §8. |

### Anti-Features — Deliberately NOT Built (with rationale)

These are features competitors or users will request. Each one is a trap for a trust-first product. Rationale documented.

| # | Anti-Feature | Why Users / PMs Ask For It | Why It's Wrong for Validation Ledger | Alternative |
|---|--------------|---------------------------|--------------------------------------|-------------|
| A1 | **"Remember me" / persistent login with no re-auth** | Every consumer app has it; drivers will complain | Defeats device-binding; a stolen unlocked phone = full account access | Auto-logout on token expiry + Face ID re-prompt on foreground after 5min background (spec'd). |
| A2 | **Self-serve password reset / "forgot password" flow** | Table stakes for most apps | The whole point of the platform is identity cannot be re-established by a form. Fraud vector: attacker intercepts SMS, resets, gains account | Support-channel + re-KYC for recovery (spec'd FR-iOS-AUTH SHOULD). |
| A3 | **Multi-device simultaneous login** | Drivers ask ("my work iPhone died, I need to use my personal"). Dispatchers ask ("I use iPad in office and iPhone on the road") | Negates one-active-device enforcement, which is a core fraud control. Chameleon carriers thrive on shared credentials | One-device-per-user with a clean "switch to this device" flow requiring re-KYC (spec'd FR-iOS-DEV). Messaged as a feature, not a limitation. |
| A4 | **Drop-in third-party chat SDK (Intercom / SendBird / Stream / Twilio Conversations)** | Fastest path to shipping messaging | Every message between parties would be PII (driver name, load location, BOL number). A third-party SDK means that PII leaves the trust boundary. Most 2026 SDKs also embed analytics | Custom backend-mediated chat (D8) if messaging ships at all. Defer until M4+ or v2. |
| A5 | **Third-party analytics or ad SDKs (Mixpanel, Amplitude, Firebase Analytics, Facebook SDK)** | PM demand for funnel analytics | Every SDK is a PII exfiltration risk; App Store privacy manifests make it auditable; drivers in 2026 know when an app is tracking them | PII-scrubbed structured logging via `os_log` / `OSLogStore` (M1). Crash vendor decision deferred per PROJECT.md. Analytics vendor picked in M2 with strict PII scrubber middleware. Spec'd TechStack §8. |
| A6 | **Offline QR verification at the dock** | Shippers in rural DCs with bad WiFi will ask | The rotating-QR TTL is the fraud control; if iOS validates QR locally, screenshots work for the cache window. Fraud window too wide | Explicitly out-of-scope per TechStack §11 and PROJECT.md. Show "Waiting for connectivity — cannot verify offline." |
| A7 | **Client-side QR content validation** | Engineers will "just parse the payload" as an optimization | Client-side validation is bypassable by any attacker. Backend is sole authority | Client only transports the payload to backend per FR-iOS-SCAN. Spec'd. |
| A8 | **Hidden / always-on background location** | PM will ask "so we always know where the driver is" | Battery drain is the #1 driver complaint in 2026 trucking app reviews. Also a privacy disaster — background location for a non-carrier role (factoring, shipper) is indefensible in App Store review | Background location ("Always") only for **Carrier role with an active load**, explicit opt-in, clear banner in UI. Respect iOS background budget. Spec'd FR-iOS-GEO SHOULD. |
| A9 | **Raw GPS coordinates in analytics / crash / logging payloads** | Easy default when adding analytics | Coordinates are PII under every privacy framework in 2026; App Store privacy manifests will flag them | Coordinates only to the platform API (verified endpoint); PII-scrubber middleware in `Core/Logging`. Spec'd TechStack §8. |
| A10 | **CarPlay / Apple Watch companion / iMessage extension** | Shiny ecosystem features PMs love | Every surface is a new attack surface for an identity-verification app. CarPlay has no biometric prompts. Apple Watch can't do Secure Enclave signing. iMessage extension leaks BOL payloads to Apple's servers | Explicitly out-of-scope v1 per TechStack §11. Revisit post-PMF. |
| A11 | **Client-rendered PDF of BOL (composed on device)** | "Why round-trip to backend to make a PDF?" | The BOL PDF is a legal document. Client-composition means the client could alter it. Backend-generated PDFs are authoritative + signed | Backend composes; iOS shares via share sheet. Spec'd FR-iOS-BOL. |
| A12 | **Android app first / cross-platform (React Native, Flutter)** | Engineering leaders will propose it for "velocity" | Every security control in the spec (Secure Enclave EC P-256, App Attest, `isSecureTextEntry`-screenshot-trick, biometric-bound Keychain) has a native implementation and a weaker cross-platform one. A 10% shortcut on any of these invalidates the trust story | iOS-native v1. Android as a separate codebase + separate threat-model pass. Spec'd TechStack §11. |
| A13 | **User-editable profile fields post-verification (change name, DOB, DL)** | Users will complain ("I typo'd my name") | Mutable identity is the chameleon-carrier attack vector | Name/DOB/DL corrections require re-KYC through support. Cosmetic fields (display name, photo) may be editable in v2. |
| A14 | **"Invite a friend" / referral-style onboarding** | PM-favorite growth lever | Referrals in a trust product are a vouching mechanism. If they're ungoverned, they're social-engineering vectors (fraudster refers confederates). If governed, they're not the same thing as the core chain-of-trust | No referral in v1. Vouching is an official product feature in the chain-of-trust, not a growth feature. |
| A15 | **Email / SMS "trust this device" link for auth recovery** | Common 2FA bypass pattern | SIM-swap fraud explicitly attacks this. OPEN Q5 in TechStack §12 calls out SIM-swap recovery as unresolved | Force re-KYC for device changes. Revisit in beta data. |
| A16 | **Web-based KYC fallback / "verify on desktop"** | Engineers ask when camera quality on older iPhones fails | Desktop webcams have worse liveness signals; desktop browsers have no Secure Enclave; the whole device-binding model breaks | iOS-only KYC. Fallback for KYC failure = support channel with human review. |
| A17 | **Client-local decryption of eBOL content** | "Faster load" | eBOL content delivery = backend HTTPS render of ready-to-display payload. Local decryption opens a vector where a compromised client extracts plaintext | Backend gates delivery; iOS renders what it receives. |
| A18 | **Generic "sign in with Google / Apple"** | Fastest auth integration | Google/Apple identity ≠ FMCSA-verified freight identity. Adding social auth weakens the phone-number-bound identity model | Phone + OTP v1; passkey migration is v2 candidate per FR-iOS-AUTH MAY. |

---

## Feature Dependencies

```
[T1 Phone OTP auth] ──required by──> [T2 Biometric re-prompt]
                                  └─required by──> [T3 Role-switched nav]
                                                └─required by──> all T8–T23

[D3 Device-bound keypair] ──required by──> [D4 Refuse-to-tender]
                       └─required by──> [D11 App Attest login]
                       └─required by──> [T11 Tender/Accept signing]

[T4 Live face + DL] ──required by──> [T7 KYC status UI]
                 └─required by──> [D10 Portable identity]
                 └─required by──> [D1 Chain-of-trust viz]

[T6 Resumable upload] ──required by──> [T4 + T5] (upload pipeline underlies KYC)

[T8 Load list] ──required by──> [T9 Load detail timeline]
             └─required by──> [D1 Chain-of-trust viz]
             └─required by──> [T11 Tender flow]

[D1 Chain-of-trust viz] ──required by──> [D4 Refuse-to-tender UI]
                      └─required by──> [D9 AI assistant grounding]

[T14 eBOL render] ──required by──> [D2 Rotating QR display]
                └─required by──> [T15 QR scanner] (scan-side must know what a valid BOL-QR looks like)
                └─required by──> [T16 POD capture]

[D2 Rotating QR] ──required by──> [T15 QR scanner] (scan-side is the counterparty to display-side)
             └─requires──> backend signing service (cross-team dependency)

[T10 One-tap status] ──enhanced-by──> [T18 Offline queue]
                  └─enhanced-by──> [D8 Background location for active load]

[T13 Push notif] ──required by──> [T17 Chat/messaging] (notification of new message)

[D6 Screenshot block] ──applies-to──> [T4 DL capture, T14 eBOL, D1 chain-of-trust, D2 rotating QR]

[A3 No multi-device] ──conflicts-with──> [T11 Tender flow convenience] — resolved by D3 device-switch-requires-re-KYC UI

[D7 Role-unified app] ──required by──> all Shipper/Factoring/Dispatch-specific surfaces
                   └─constrains──> architecture choice (MVVM+Coordinator per TechStack §3.1)
```

### Critical Dependency Notes

- **D2 (Rotating QR) depends on backend signing service.** This is the single biggest cross-team dependency in M3. If backend signing is not ready, M3 slips. Flag this in the roadmap handoff as "M3 has an external dependency that M1/M2 do not."
- **D3 (Device binding) must ship in M1** because every signed-request feature in M2+ (T11 tender signing, D4 refuse-to-tender) layers on top. Deferring device-binding to M2 would require retrofitting signed headers across every endpoint.
- **T7 (KYC status UI with rejection reasons) is cheap to ship badly and expensive to re-ship.** The difference between "Rejected. Try again" and "Your DL photo has glare on the name field — please retake" is the difference between 30% abandonment and 5%. Worth prioritizing the copy + backend reason codes in M1.
- **D1 (Chain-of-trust visualization) is called out in TechStack §13 as "the single most important screen."** It depends on T8 (Load list) and T9 (Load detail) to even exist. M2 must deliver it well, not ship a placeholder that gets iterated later.
- **A4 (No third-party chat SDK) conflicts with T17 (in-app messaging).** Resolution: defer T17 to M4 or v2; when it ships, it's D8 (custom backend-mediated chat), not an SDK integration.

---

## MVP Definition

### Launch With (v1 = M1 through M5 closed beta)

Minimum viable scope for the TestFlight closed beta. Anything below the line is "doesn't ship in v1." PROJECT.md locks M1 scope; the list below extends through M5.

**M1 Foundation (weeks 1–4) — must ship:**

- [ ] T1 Phone OTP auth with Keychain storage
- [ ] T2 Biometric re-prompt on sensitive actions + 5min-background return
- [ ] T3 Role-switched tab-bar shell (all 5 roles with placeholder tabs)
- [ ] T4 Live face + DL front/back capture (Vision-based, no liveness in M1 per PROJECT.md)
- [ ] T5 Vehicle/trailer/plate capture with GPS metadata
- [ ] T6 Resumable upload pipeline
- [ ] T7 KYC status UI with rejection reasons
- [ ] T21 MC/DOT entry with backend FMCSA lookup (SHOULD — negotiable under schedule pressure)
- [ ] T22 Settings (logout, notification prefs, delete account, help)
- [ ] D3 Secure Enclave device-bound keypair + registration
- [ ] D5 Client-side US-only country pre-check
- [ ] D6 Screenshot block on DL-capture screen (KYC subset)
- [ ] D11 App Attest / DeviceCheck on login
- [ ] D12 `.biometryCurrentSet` on device key

**M2 Core flows (weeks 5–8):**

- [ ] T8 Role-filtered load list
- [ ] T9 Load detail with status timeline
- [ ] T10 One-tap status updates (Carrier)
- [ ] T11 Tender / Accept / Reject flow with device-key signing
- [ ] T12 Real-time updates (WS or SSE abstraction)
- [ ] T20 Factoring invoice submission + BOL attach (read-path; write-path M3)
- [ ] D1 **Chain-of-trust visualization** (the single most important screen)
- [ ] D4 Refuse-to-tender-to-unverified with reason UI
- [ ] D7 Role-specific surfaces instantiated per role

**M3 Dock & BOL (weeks 9–14):**

- [ ] T13 Push notifications with deep links + Critical alerts
- [ ] T14 eBOL render with PDF share
- [ ] T15 QR scanner at dock
- [ ] T16 POD signature + photo capture
- [ ] D2 **Live rotating QR (30s TTL) with backend-signed payload**
- [ ] D6 Screenshot block extended to eBOL, live QR, chain-of-trust surfaces

**M4 Intelligence & polish (weeks 15–20):**

- [ ] T18 Offline read-only + queued status updates
- [ ] T19 Accessibility pass (Dynamic Type + VoiceOver)
- [ ] D9 AI assistant UI (SHOULD-tier per TechStack §13 — app must be useful without it)
- [ ] Analytics instrumentation with PII scrubber
- [ ] (Defer decision: T17 in-app messaging → likely v2 as D8)

**M5 Beta hardening (weeks 21–24):**

- [ ] Crash-rate tuning
- [ ] Device matrix QA (iPhone 12 / 15, iPad 9th gen / Pro M-series; iOS 17 / 18)
- [ ] App Store submission prep (privacy manifest, App Store privacy labels)
- [ ] TestFlight external beta launch

### Add After Validation (v1.x = post-beta, same codebase)

- [ ] Liveness detection upgrade (decision gate from TechStack §12 Open Q1 — Vision-only vs. Jumio/Onfido/Persona buy)
- [ ] Impossible-travel pre-check on client (currently backend-only per PROJECT.md)
- [ ] Scan history with backend-confirmed outcomes (FR-iOS-SCAN SHOULD)
- [ ] Rich notifications with image previews (FR-iOS-NOTIF SHOULD)
- [ ] Voice input for AI assistant (FR-iOS-AI SHOULD)
- [ ] iPad bespoke layouts (TechStack §12 Open Q3 — depends on dispatch/factoring iPad usage data)
- [ ] Apple Business Manager enrollment for large fleets (TechStack §12 Open Q4)

### Future Consideration (v2+)

- [ ] Passkey / WebAuthn migration (TechStack §5.1 MAY)
- [ ] NFC passport read for non-US drivers (TechStack §5.2 MAY)
- [ ] Offline QR scan with delayed verification (TechStack §5.11 MAY — explicitly deferred; fraud window risk)
- [ ] Suggested quick-action chips for AI assistant (FR-iOS-AI MAY)
- [ ] D8 Custom backend-mediated messaging (if validated by user demand)
- [ ] Non-English localization (Spanish first per non-functionals)
- [ ] Android client (separate codebase, separate threat model)
- [ ] Web client (separate codebase, shared backend)

---

## Feature Prioritization Matrix

| # | Feature | User Value | Implementation Cost | Priority | Notes |
|---|---------|------------|---------------------|----------|-------|
| T1 | Phone OTP auth | HIGH | LOW | P1 | Gate-keeps everything |
| T3 | Role-switched nav | HIGH | MEDIUM | P1 | Product shape |
| T4 | Live face + DL | HIGH | MEDIUM | P1 | Gate-keeps identity |
| T6 | Resumable upload | HIGH | MEDIUM | P1 | Avoids T4/T5 data loss |
| T7 | KYC status + reasons | HIGH | LOW | P1 | Cheap abandonment win |
| T11 | Tender/Accept | HIGH | MEDIUM | P1 | Core role interaction |
| T13 | Push notif | HIGH | MEDIUM | P1 | Table-stake expectation |
| T14 | eBOL render | HIGH | MEDIUM | P1 | Core dock flow |
| T15 | QR scanner | HIGH | LOW | P1 | Core dock flow |
| D1 | Chain-of-trust viz | HIGH | HIGH | P1 | The differentiator |
| D2 | Rotating QR | HIGH | HIGH | P1 | The differentiator |
| D3 | Device-bound keypair | HIGH | HIGH | P1 | Foundation for D4/D11/T11 |
| D4 | Refuse-to-tender-unverified | HIGH | MEDIUM | P1 | Moves from vetting to fraud-rail |
| D6 | Screenshot block | HIGH | MEDIUM | P1 | Core trust story |
| T2 | Biometric re-prompt | MEDIUM | LOW | P1 | Expected by users |
| T5 | Vehicle capture | MEDIUM | LOW | P1 | Carrier-required |
| T8 | Load list | MEDIUM | MEDIUM | P1 | Must exist |
| T9 | Load detail | MEDIUM | MEDIUM | P1 | Must exist |
| T10 | One-tap status | MEDIUM | LOW | P1 | Expected |
| T12 | Real-time updates | MEDIUM | MEDIUM | P1 | Expected |
| T16 | POD capture | MEDIUM | MEDIUM | P1 | Carrier-expected |
| T20 | Factoring invoice+BOL | MEDIUM | MEDIUM | P1 | Factoring-role required |
| T21 | FMCSA lookup | MEDIUM | LOW | P1 | Broker/carrier expected |
| D5 | US-only pre-check | MEDIUM | MEDIUM | P1 | Invisible-to-user hardening |
| D7 | Role-unified app | HIGH | HIGH | P1 | Architecture choice |
| D10 | Portable identity | HIGH | (Platform) | P1 | iOS surface in M2 |
| D11 | App Attest | MEDIUM | MEDIUM | P1 | Cheap ceiling-raise |
| D12 | Biometric-bound key | MEDIUM | LOW | P1 | Cheap win |
| T17 | In-app messaging | MEDIUM | HIGH | P2 | Defer — see A4/D8 |
| T18 | Offline | MEDIUM | MEDIUM | P2 | M4 |
| T19 | Accessibility | MEDIUM | LOW | P2 | M4, App Store quality |
| T22 | Settings | MEDIUM | LOW | P1 | M1–M2 |
| D8 | Custom chat | MEDIUM | HIGH | P3 | v2 |
| D9 | AI assistant | MEDIUM | MEDIUM | P2 | M4, SHOULD-tier |

---

## Competitor Feature Analysis

| Feature | Samsara Driver | Uber Freight | McLeod Mobile | Highway / Verified Pickup | Trustd | Vector eBOL | Validation Ledger (proposed) |
|---------|---------------|--------------|---------------|---------------------------|--------|-------------|-------------------------------|
| Phone OTP auth | Yes | Yes | Yes | Yes | Yes | Yes | Yes (T1) — Keychain + biometric re-prompt |
| Face ID re-prompt on sensitive | Partial | Partial | No | Yes | Yes | Partial | Yes (T2) — on every sensitive action, backend-classified |
| One-active-device enforcement | No | No | No | No | Partial (DIATF-certified) | No | **Yes (A3+D3)** — with re-KYC switch flow |
| Secure Enclave device-bound key | No | No | No | No | Partial | No | **Yes (D3)** — EC P-256, `.biometryCurrentSet` |
| App Attest on login | No | No | No | No | No (Android primary) | No | **Yes (D11)** |
| KYC selfie + DL + vehicle | Driver-only | Carrier-only | Partial | Yes (at registration) | Yes | No (TMS-delegated) | Yes (T4/T5) — all 5 roles |
| Live rotating QR on BOL | No | No | No | **Encrypted static QR (Verified Pickup, Apr 2026)** | No | No (static digital BOL) | **Yes (D2)** — 30s TTL, backend-signed |
| eBOL render | No | Yes | Yes | No | No | **Yes (primary feature)** | Yes (T14) — backend-composed PDF |
| QR scanner at dock | No | No | No | **Yes (Verified Pickup Apr 2026)** | Yes (Secure Collect) | Yes | Yes (T15) — backend-validated |
| Chain-of-trust visualization | No | No (simple timeline) | No | Partial (carrier-relationship tree) | Partial (credential list) | No | **Yes (D1)** — first-class UI surface |
| Refuse-to-tender-unverified | No | No | No | Advisory (warn) | Partial (block) | N/A | **Yes (D4)** — hard block with reason |
| FMCSA lookup | No | Yes | Yes | **Yes (primary)** | N/A (UK) | No | Yes (T21) — backend-mediated |
| Role-unified app (all 5) | No (Driver-only) | No (Carrier vs. Shipper split) | Partial (TMS + Driver app) | No (Broker vs. Carrier) | Partial | No (facility + driver split) | **Yes (D7)** — all 5 in one binary |
| Screenshot block on sensitive | No | No | No | No | Yes (DL capture) | No | **Yes (D6)** — eBOL, QR, chain, DL |
| Background location (carrier active load) | Yes (ELD-grade) | Yes | Yes | No | Yes | No | Yes (A8 carve-out) — opt-in, carrier-role-only |
| In-app messaging | Yes (via Samsara) | Yes (SendBird-style) | Yes | No | Yes | Partial | Defer (A4) — custom (D8) in v2 |
| Analytics SDKs | Multiple | Multiple | Multiple | Minimal | Minimal (DIATF-constrained) | Multiple | **None in v1 (A5)** — os_log only in M1 |
| Offline read-only load+BOL | Yes | Partial | Yes | No | Yes | Yes | Yes (T18) — M4 |
| Passkey / WebAuthn | No | No | No | No | Partial | No | v2 (TechStack MAY) |
| Apple Watch companion | Partial | No | No | No | No | No | No (A10) — v1 out of scope |
| Push w/ deep-link + critical alerts | Yes | Yes | Yes | Partial | Yes | Yes | Yes (T13) — critical alerts for auth anomalies |
| Invoice submission + BOL (factoring) | No | No | Yes (TMS) | No | No | No | Yes (T20) — factoring role first-class |

---

## Sources

**Primary (2026 industry references):**

- [Verified Carrier Launches Verified Pickup, Closing Critical Gap in Freight Fraud Prevention — GlobeNewswire, April 15 2026](https://www.globenewswire.com/news-release/2026/04/15/3274604/0/en/Verified-Carrier-Launches-Verified-Pickup-Closing-Critical-Gap-in-Freight-Fraud-Prevention.html) — the most direct analog to Validation Ledger's dock-handoff flow; validates the thesis
- [Verified Carrier launches Verified Pickup for driver-level freight verification — FleetOwner, April 2026](https://www.fleetowner.com/safety/news/55371676/verified-carrier-launches-verified-pickup-for-driver-level-freight-verification)
- [Highway — Carrier Identity & Freight Fraud Prevention](https://highway.com/posts/the-future-of-carrier-identity-combating-fraud-and-double-brokering-in-the-freight-industry)
- [Trustd Becomes First Digital Identity Platform for Transport & Logistics Certified Under UK DIATF (April 2025)](https://trustd.net/news/trustd-becomes-first-digital-identity-platform-for-transport-logistics-certified-under-uk-digital-identity-framework/)
- [Trustd iOS app listing (Apple App Store)](https://apps.apple.com/us/app/trustd/id1626268438)
- [Chameleon Carriers, Fraud Detection, and FMCSA's Evolving Data Strategy — Trucksafe 2026](https://trucksafe.com/post/chameleon-carriers-fraud-detection-and-fmcsa-s-evolving-data-strategy)
- [FMCSA Broker Transparency Rulemaking (Overdrive)](https://www.overdriveonline.com/regulations/article/15750254/fmcsa-broker-transparency-rulemaking-part-of-illegal-brokering-crackdown)
- [New FMCSA Rule: Impact on Brokers and Dispatchers in 2026](https://idispatchhub.com/how-fmcsas-new-broker-rule-puts-brokers-and-dispatchers-on-notice/)
- [McLeod Updates TMS With Benchmark, AI Features (26.1 release, March 2026)](https://www.ttnews.com/articles/mcleod-new-tms-benchmark-ai)
- [Samsara Unveils New AI Safety Tools for 2026 Fleet Needs](https://fleet-connection.com/technology-telematics-elds/samsara-unveils-new-ai-safety-tools-for-2026-fleet-needs/)
- [Samsara Driver App (Play Store listing)](https://play.google.com/store/apps/details?id=com.samsara.driver&hl=en_US)
- [Uber Freight carrier app — searching and booking loads](https://help.uber.com/en/freight/carrier/article/using-the-uber-freight-app-to-search-and-book-loads?nodeId=dfe69814-ea0d-43e8-ad16-f77621cd2e0c)
- [Uber Freight 2025 enhancements](https://www.uberfreight.com/blog/powering-carrier-success-new-tools-and-enhancements-from-uber-freight-in-2025/)
- [Vector eBOL product page](https://www.withvector.com/connected-facilities/ebol/)
- [SmartBOL eBOL solutions](https://smartbol.com/electronic-bill-of-lading-ebol-solutions/)
- [MobileDock QR check-in features](https://www.mobiledock.com/features)
- [YardView dock appointments & QR scanning](https://www.yardview.com/dock-appointments)
- [Trucker Path + McLeod navigation integration (FleetOwner)](https://www.fleetowner.com/technology/article/55142967/mcleod-software-and-trucker-path-integrate-tms-and-navigation-app-capabilities-for-seamless-fleet-operations)
- [CarShipIO Driver eBOL ePOD (App Store)](https://apps.apple.com/us/app/carshipio-driver-ebol-epod/id1128518437)
- [DAT acquires Convoy Platform (FreightWaves, 2025)](https://www.freightwaves.com/news/load-matching-wars-escalate-as-dat-snaps-up-convoy)
- [Descartes MyCarrierPortal — carrier identity & vetting](https://www.mycarrierportal.com/features/carrier-identify-vetting/)
- [Plaid Identity Verification overview](https://plaid.com/docs/identity-verification/)
- [Plaid selfie ID verification](https://plaid.com/resources/identity/selfie-id-verification/)
- [Alloy + Plaid partnership (April 2026)](https://www.alloy.com/about/press/alloy-partners-with-plaid)
- [Onfido / Entrust Identity Verification](https://onfido.com/)
- [Jumio how-to-reduce-customer-abandonment](https://www.jumio.com/how-to-reduce-customer-abandonment/)

**KYC abandonment + UX friction research (2026):**

- [How to Reduce KYC Onboarding Drop-Off by 40% — Zyphe](https://www.zyphe.com/resources/blog/reduce-kyc-onboarding-drop-off)
- [How to Reduce KYC Abandonment in 3 Steps — UXCam](https://uxcam.com/blog/reduce-kyc-abandonment/)
- [KYC and Onboarding Friction: What Customer Research Reveals](https://www.userintuition.ai/reference-guides/kyc-onboarding-friction-research-guide/)
- [What truck drivers really think about driver apps — Scanbot SDK](https://scanbot.io/blog/trucking-apps-survey/)

**iOS security posture 2026:**

- [iOS App Security Features You Should Not Ignore in 2026](https://www.mobileappdevelopmentcompany.us/blog/ios-app-security-features-2026/)
- [Screenshot Prevention in iOS: Advanced Techniques Inspired by Banking & Authenticator Apps](https://medium.com/@thakurneeshu280/screenshot-prevention-in-ios-advanced-techniques-inspired-by-banking-authenticator-apps-0d1900c2a1bb)
- [Implement Face ID & Touch ID in iOS (Swift 2026) — Complete Guide](https://medium.com/codetodeploy/implement-face-id-touch-id-in-ios-swift-2026-complete-guide-to-biometric-authentication-with-3557f2bcf1db)
- [Seven Mobile Security Disruptions That Could Blindside You in 2026 — Approov](https://approov.io/blog/seven-mobile-security-disruptions-that-could-blindside-you-in-2026)
- [525,600 Assessments Later — Top Mobile App Risks Since 2022 — NowSecure](https://www.nowsecure.com/blog/2025/04/30/525600-assessments-later-top-mobile-app-risks-since-2022/)
- [Impossible Travel Detection — Fingerprint](https://fingerprint.com/blog/impossible-travel-detection/)

**Factoring mobile apps:**

- [OTR Solutions Freight Factoring Mobile App](https://otrsolutions.com/solutions/tools/mobile-app/)
- [Triumph Network — Freight Payments, Banking, Intelligence](https://triumph.io/)
- [RTS Factoring & Carrier Services](https://www.rtsinc.com/)

---

## Confidence Assessment

| Category | Confidence | Rationale |
|----------|------------|-----------|
| Table stakes (T1–T23) | HIGH | Cross-verified across 6+ competitors' 2026 product docs, App Store listings, and release notes. Consistent patterns. |
| Differentiators (D1–D12) | HIGH for D1/D2/D3/D6/D11/D12 — spec'd in TechStack and validated against Verified Pickup / Highway / Trustd gap analysis. MEDIUM for D4/D7/D8/D9/D10 — defensible positions but some (D8, D9) are uncommon and harder to benchmark. | Verified Pickup's April 2026 launch is the strongest external validation of D1/D2 thesis. |
| Anti-features (A1–A18) | HIGH | Grounded in 2026 iOS security guidance, FMCSA fraud patterns, App Store privacy manifest rules, and driver-review complaints. |
| Milestone mapping | HIGH | Mapped 1:1 to TechStack §10 and PROJECT.md M1 scope. |
| Role mapping | HIGH | Mapped from TechStack §4 role-tabs table. |

**Gaps / open items for phase-specific follow-up:**

- Liveness-SDK vs. Vision-only decision (TechStack §12 Open Q1) needs its own feasibility research at M2 boundary.
- Chat architecture (D8 vs. defer) needs its own decision at M4 boundary.
- iPad bespoke layouts vs. adaptive (TechStack §12 Open Q3) needs UX research after M2 launches.
- SIM-swap recovery UX (Open Q5) needs dedicated research when beta data arrives.
- The "rotating QR with 30s TTL" pattern: no published competitor does this exactly as spec'd (Verified Pickup uses a static encrypted QR; SmartBOL uses session-bound QRs). This is genuinely novel — worth confirming with a security-review pass before M3.

---

*Feature research for: Validation Ledger iOS Client (identity-verified freight, iOS 17+, five roles)*
*Researched: 2026-04-20*
*Feeds: roadmap phase structure for M1 Foundation; downstream refinement at M2–M5 boundaries*
