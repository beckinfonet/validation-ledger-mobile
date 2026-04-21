<!-- GSD:project-start source:PROJECT.md -->
## Project

**Validation Ledger — iOS Client**

Native iOS client (iPhone + iPad, iOS 17+) for Validation Ledger — a verified-identity freight platform that attacks fraud (double/triple brokering, chameleon carriers, factoring fraud) by making identity and the chain-of-trust between shippers, brokers, carriers, dispatch, and factoring parties verifiable in real time. The iOS app is where most verification happens physically — at the dock, in the cab, in the broker's office.

**Core Value:** **Identity that cannot be spoofed and a chain-of-trust that cannot be faked.** Every design decision on iOS serves making the person and the counterparty on the other end of a freight transaction demonstrably real.

### Constraints

- **Tech stack**: UIKit-first (SwiftUI permitted only for non-critical surfaces like Settings/static lists); all camera/KYC/scanner/BOL screens must be UIKit — Rationale: mature for sensitive-surface interaction, no SwiftUI rendering quirks on camera layers, the team's UIKit fluency.
- **Tech stack**: Swift Package Manager only — no CocoaPods, no Carthage. Rationale: shallow dependency graph, avoids the tooling split.
- **Platform**: iOS 17.0 minimum deployment — Rationale: spec requirement; enables modern Vision APIs, UIKit updates, Swift Concurrency without backports.
- **Devices**: iPhone + iPad, iPad must render natively (not just scale) — Rationale: dispatch and factoring users frequently work on iPad.
- **Security**: Zero PII in analytics or crash logs; all tokens in Keychain; all keys in Secure Enclave; no sensitive data in `UserDefaults` — Rationale: product's entire premise is trust — a security shortcut invalidates the platform.
- **Distribution**: TestFlight closed beta for v1; App Store submission is M5 — Rationale: spec-defined milestone.
- **Dependencies**: Pre-approved shortlist only (URLSession wrapper, KeychainAccess or hand-rolled, Nuke/SDWebImage for images, Sentry/Firebase for crash — TBD, CoreImage for QR generation, AVFoundation for scanning, Apple Vision for liveness). Anything outside this list requires explicit approval.
- **AI traffic**: iOS never calls Anthropic directly; all Claude assistant calls go through backend-mediated endpoints — Rationale: keeps authorization, grounding, and tool-use server-enforced.
- **Geographic**: US-only logins enforced by backend; iOS performs a client-side country pre-check via `CLLocationManager` — Rationale: regulatory scope and fraud-profile control.
- **Timeline**: M1 target is weeks 1–4 of a 24-week v1 plan — Rationale: spec §10. If engineers commit to the full M1 in <3 months, revisit scope assumptions.
- **Team size**: 1–2 iOS engineers + AI coding tools — Rationale: dictates architectural simplicity (MVVM+Coordinators over TCA, initializer DI over Swinject).
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- Swift 5.0 - All application code
- None currently
## Runtime
- iOS 26.4 (deployment target)
- Xcode 26.4 (build toolchain)
- None (uses Xcode's native dependency management)
- No CocoaPods, Carthage, or Swift Package Manager dependencies configured
## Frameworks
- SwiftUI - iOS user interface framework (imported in `validationLedgerApp.swift` and `ContentView.swift`)
- Not configured yet
- Xcode 26.4 - Build and development environment
## Key Dependencies
- SwiftUI (part of iOS SDK) - Native declarative UI framework
- Foundation (iOS standard library) - Core functionality
- None (vanilla iOS app, no third-party SDKs)
## Configuration
- Bundle Identifier: `com.maldin.validationLedger`
- iOS Deployment Target: 26.4
- Swift Language Version: 5.0
- Development Region: en (English)
- `validationLedger.xcodeproj/project.pbxproj` - Xcode project configuration
## Platform Requirements
- macOS with Xcode 26.4 installed
- iOS SDK 26.4
- iOS 26.4 or later (deployment target)
- Apple App Store (typical distribution)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Current State
## Naming Patterns
- PascalCase for Swift files (`validationLedgerApp.swift`, `ContentView.swift`)
- File name matches primary type declared (e.g., `ContentView.swift` contains `ContentView` struct)
- PascalCase for all struct and type names (`validationLedgerApp`, `ContentView`)
- No prefix for types (not `IContentView` or `_ContentView`)
- camelCase for computed properties and local variables (e.g., `body`)
- No underscore prefix observed in current code
- No custom functions in current scaffold—only implicit computed properties via `body`
- Xcode template does not yet show function naming patterns
## Code Style
- 4-space indentation (observed in `validationLedgerApp.swift` and `ContentView.swift`)
- Xcode default formatting rules apply
- No Prettier or equivalent formatter detected
- No linter (SwiftLint, etc.) configured
- Xcode compiler warnings/errors are the implicit standard
## Import Organization
- Single import at top of file
- No path aliases or relative imports in current scaffold
## SwiftUI Patterns
- Struct-based views conforming to `View` protocol
- Computed `body` property returning view hierarchy
- Property syntax: `var body: some View { ... }`
- Container views like `VStack` with `.padding()` modifiers
- System image references via `Image(systemName:)`
- Direct modifier chaining on views
#Preview {
- Preview declarations at end of view files using `#Preview` macro
- Used for live canvas in Xcode
## App Entry Point
- `@main` struct attribute on app entry point (`validationLedgerApp`)
- App conforms to `App` protocol
- `WindowGroup` wrapping root view (`ContentView`)
## Comments & Documentation
- Only auto-generated file headers present:
- No JSDoc, documentation comments, or inline comments in scaffold
## Error Handling
- Not applicable—no error handling in template scaffold
- Pattern will be established as business logic is added
## Module Design
- No explicit exports or module organization yet
- Default access (implicit internal) for all current code
- Single file per view convention established
## Notes for Future Development
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Pattern Overview
- Single-window iOS app using SwiftUI's declarative syntax
- Minimal entry point with @main App protocol
- No layered architecture yet (scaffold only)
- View-based component hierarchy
- Architecture patterns will emerge as features are implemented
## Layers
- Models layer (data structures, business logic)
- Services/ViewModels layer (state management, business operations)
- Views layer (UI components, screens)
- Utilities layer (helpers, extensions)
## Data Flow
- SwiftUI @State, @StateObject for local view state
- ObservableObject pattern for ViewModel-based state
- Possible Redux-like state management (TBD based on app complexity)
## Key Abstractions
## Entry Points
- Location: `validationLedger/validationLedger/validationLedgerApp.swift`
- Triggers: App launch (system calls @main)
- Responsibilities: 
## Error Handling
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
