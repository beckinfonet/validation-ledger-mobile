// swift-tools-version: 6.0
// Package.swift — Validation Ledger iOS Client
// Companion manifest to validationLedger.xcodeproj: declares SwiftPM external dependencies.
// The .xcodeproj remains the source-of-truth for target structure (per D-15).
//
// Dependency allowlist per STACK-01 + STACK-04 + CLAUDE.md:
//   - Nuke (images; pre-wired for later phases)
//   - SwiftLintPlugins (lint enforcement)
// Analytics / crash / third-party networking / alt-DI / alt-image SDKs are
// forbidden by STACK-04; see docs/adr and CLAUDE.md for the explicit list.

import PackageDescription

let package = Package(
    name: "validationLedger",
    platforms: [
        .iOS(.v17)
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git",                    exact: "13.0.2"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git", from: "0.63.2"),
    ]
)
