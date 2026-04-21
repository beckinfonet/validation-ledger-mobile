# Technology Stack

**Analysis Date:** 2026-04-21

## Languages

**Primary:**
- Swift 5.0 - All application code

**Secondary:**
- None currently

## Runtime

**Environment:**
- iOS 26.4 (deployment target)
- Xcode 26.4 (build toolchain)

**Package Manager:**
- None (uses Xcode's native dependency management)
- No CocoaPods, Carthage, or Swift Package Manager dependencies configured

## Frameworks

**Core:**
- SwiftUI - iOS user interface framework (imported in `validationLedgerApp.swift` and `ContentView.swift`)

**Testing:**
- Not configured yet

**Build/Dev:**
- Xcode 26.4 - Build and development environment

## Key Dependencies

**Critical:**
- SwiftUI (part of iOS SDK) - Native declarative UI framework
- Foundation (iOS standard library) - Core functionality

**Infrastructure:**
- None (vanilla iOS app, no third-party SDKs)

## Configuration

**Build Settings:**
- Bundle Identifier: `com.maldin.validationLedger`
- iOS Deployment Target: 26.4
- Swift Language Version: 5.0
- Development Region: en (English)

**Build Files:**
- `validationLedger.xcodeproj/project.pbxproj` - Xcode project configuration

## Platform Requirements

**Development:**
- macOS with Xcode 26.4 installed
- iOS SDK 26.4

**Production:**
- iOS 26.4 or later (deployment target)
- Apple App Store (typical distribution)

---

*Stack analysis: 2026-04-21*
*Early-stage scaffold with minimal dependencies*
