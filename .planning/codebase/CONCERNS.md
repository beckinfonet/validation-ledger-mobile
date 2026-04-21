# Codebase Concerns

**Analysis Date:** 2026-04-21

## Overview

This is an early-stage SwiftUI iOS scaffold (default Xcode template). No technical debt exists yet, but the following gaps and forward-looking risks need early-stage planning to prevent future issues.

## Missing Test Infrastructure

**Issue:** No test target configured in Xcode project.

- Files: `validationLedger.xcodeproj/project.pbxproj` (no test target defined)
- Impact: As business logic grows (validation rules, data persistence, ledger calculations), untested code will create maintenance risk. Testing decisions made late are expensive to retrofit.
- Action: Establish testing strategy now before features are written.
  - Decide between XCTest (built-in) or third-party framework (Quick/Nimble)
  - Create Unit Tests target in Xcode project
  - Establish test file organization conventions (co-located or separate `Tests/` directory)
  - Set up code coverage CI gate early

## No Data Persistence Layer

**Issue:** No database or persistence framework chosen.

- Files: `validationLedger/validationLedgerApp.swift`, `validationLedger/ContentView.swift` (only placeholder UI)
- Impact: Validation Ledger will require persistent storage (audit trail of validations, user data, state). Choosing the wrong persistence approach late blocks features and causes migration pain.
- Decision required:
  - Core Data (built-in, complex schema, Swift concurrency support needed)
  - SwiftData (newer, simpler, iOS 17+ only)
  - Realm (performant, non-native, licensing)
  - SQLite (lightweight, low-level)
  - UserDefaults (only suitable for small settings)
- Action: Model the validation ledger schema first, then choose persistence layer that fits your query patterns.

## No Dependency Management Strategy

**Issue:** No package manager or dependency injection framework defined.

- Files: `validationLedger.xcodeproj/project.pbxproj` (no Package.swift or Podfile)
- Impact: As external integrations grow (analytics, networking, payments if applicable), ad-hoc dependency management creates fragility.
- Decision required:
  - Swift Package Manager (recommended, native)
  - CocoaPods (legacy, still used)
  - Carthage (less common now)
- Action: Lock this decision before adding first external dependency. Retrofitting SPM into CocoaPods project or vice versa is painful.

## Uncommitted Changes

**Issue:** `validationLedger/ContentView.swift` has uncommitted modifications.

- Files: `validationLedger/ContentView.swift` (modified, not staged)
- Status: Changes are in working directory only; branch is otherwise clean
- Action: Review changes ("VL" text change) and commit or discard intentionally. Establish commit discipline early to avoid divergence.

## No Bundle Identifier / Code Signing Review

**Issue:** Default bundle identifier from Xcode template not reviewed for production readiness.

- Files: `validationLedger.xcodeproj/project.pbxproj` (likely contains default bundle ID)
- Impact: Bundle identifier must be unique in App Store and match code signing provisioning profiles. Changing it late requires App Store resubmission.
- Action:
  - Review and lock bundle identifier early (`com.yourcompany.validationledger`)
  - Set up code signing certificates and provisioning profiles before first test flight or submission
  - If using CI/CD, encrypt provisioning profiles and manage signing keys securely

## No CI/CD Pipeline

**Issue:** No automated build, test, or deployment pipeline.

- Impact: Manual builds and releases introduce human error. Validation ledger may require audit trails; CI/CD ensures builds are traceable and reproducible.
- Action:
  - Choose CI platform (GitHub Actions, Fastlane + GitHub Actions, Xcode Cloud, or Firebase CI)
  - Configure automated builds on every push to main
  - Add automated testing gate before merging
  - Set up automated release builds/code signing

## No Project Structure / Code Organization

**Issue:** Only default Xcode scaffold with two files at root of app target.

- Files: `validationLedger/validationLedgerApp.swift`, `validationLedger/ContentView.swift`
- Impact: As features grow (validation logic, ledger models, networking, UI screens), a flat file structure causes navigation overhead and naming collisions.
- Action: Establish directory structure now while minimal:
  ```
  validationLedger/
  ├── App/                  # Entry point (validationLedgerApp.swift)
  ├── Features/             # Feature modules
  │   ├── Ledger/
  │   │   ├── Views/
  │   │   ├── Models/
  │   │   ├── ViewModels/
  │   │   └── Services/
  │   ├── Validation/
  │   └── Settings/
  ├── Core/                 # Shared utilities
  │   ├── Models/           # Data models
  │   ├── Services/         # Reusable services
  │   ├── Networking/
  │   └── Persistence/
  └── Resources/            # Assets, strings
  ```

## No Error Handling / Logging Strategy

**Issue:** No centralized error handling or logging framework.

- Impact: Validation ledger failures (validation errors, data corruption, sync issues) need clear logging for debugging. Ad-hoc error handling leads to missed edge cases.
- Action:
  - Choose logging framework (built-in `os.log`, or third-party like Sentry for production)
  - Define error types and handling patterns early
  - Establish logging levels (debug, info, warning, error) per module

## No Environment Configuration

**Issue:** No separation of dev/staging/production environments.

- Impact: Validation ledger may need different API endpoints, database URLs, or feature flags per environment. Hardcoding URLs creates deployment risk.
- Action:
  - Create configuration file structure (e.g., `Config/Environment.swift` with dev/staging/prod variants)
  - Use build configurations or scheme-based environment switching
  - Externalize API endpoints and feature flags

## Security: No Authentication / Authorization Framework

**Issue:** No auth system or access control defined.

- Impact: Validation ledger implies data ownership and audit trails. Unauthenticated requests are a security risk if this becomes multi-user.
- Action:
  - Decide on auth provider (Apple Sign-In, custom backend, Firebase)
  - Implement KeyChain access for token storage
  - Define authorization model (who can view/edit/audit validations)

## Performance: No Analytics / Monitoring

**Issue:** No visibility into app performance or user behavior.

- Impact: Validation ledger success depends on knowing: Are validations working? Are users completing workflows? Where do they abandon?
- Action:
  - Choose analytics provider (Firebase, Amplitude, custom)
  - Define key metrics to track early (validation success rate, user engagement, error rates)
  - Instrument code for monitoring before shipping

---

*Concerns audit: 2026-04-21*
