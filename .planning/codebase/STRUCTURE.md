# Codebase Structure

**Analysis Date:** 2026-04-21

## Directory Layout

```
validationLedger/
├── validationLedger/              # Main app source and resources
│   ├── validationLedgerApp.swift   # @main entry point
│   ├── ContentView.swift           # Root view scaffold
│   └── Assets.xcassets/            # App icons, colors, images
├── validationLedger.xcodeproj/     # Xcode project metadata
└── .planning/                      # Documentation and planning
    └── codebase/                   # Codebase analysis docs
```

## Directory Purposes

**validationLedger/validationLedger/**
- Purpose: Main application source code and resources
- Contains: Swift source files (.swift), asset catalogs, configuration
- Key files: 
  - `validationLedgerApp.swift` (entry point)
  - `ContentView.swift` (root view)
  - `Assets.xcassets/` (app icon, colors)

**validationLedger.xcodeproj/**
- Purpose: Xcode project configuration and metadata
- Contains: Build settings, scheme definitions, workspace state
- Note: Xcode-managed; not typically edited manually

**Assets.xcassets/**
- Purpose: Asset catalog for images, icons, colors
- Contains: 
  - `AppIcon.appiconset/` (app icon variants)
  - `AccentColor.colorset/` (app accent color)

**.planning/codebase/**
- Purpose: Architecture and structure documentation
- Contains: ARCHITECTURE.md, STRUCTURE.md (this file)

## Key File Locations

**Entry Points:**
- `validationLedger/validationLedger/validationLedgerApp.swift`: App initialization; uses @main; creates WindowGroup and loads ContentView()

**Configuration:**
- `validationLedger.xcodeproj/project.pbxproj`: Build configuration, target settings (Xcode-managed)

**Core Logic:**
- Not yet present. Currently contains only view hierarchy.

**Testing:**
- Not yet created. XCTest framework available in Xcode template but no test targets configured.

## Naming Conventions

**Files:**
- PascalCase for Swift files (e.g., `ContentView.swift`, `validationLedgerApp.swift`)
- camelCase for asset identifiers within xcassets

**Directories:**
- PascalCase for feature/component directories (established convention; not yet present beyond root)
- Xcode manages .xcodeproj/ and .xcassets/ naming

## Where to Add New Code

**New Feature (e.g., validation UI, ledger views):**
- Primary code: Create feature-specific files in `validationLedger/validationLedger/` (e.g., `ValidationView.swift`, `LedgerView.swift`)
- Tests: Create corresponding test files in a `Tests/` subdirectory or separate test target

**New Component/Module:**
- Implementation: Add new .swift file in `validationLedger/validationLedger/`
- Group related components in subdirectories if needed (e.g., `validationLedger/validationLedger/Views/`, `validationLedger/validationLedger/Models/`)

**Utilities:**
- Shared helpers: `validationLedger/validationLedger/Utilities/` or similar (recommended as codebase grows)

**Assets:**
- Icons, images, colors: Add to `validationLedger/validationLedger/Assets.xcassets/`

## Special Directories

**validationLedger.xcodeproj/**
- Purpose: Xcode project bundle
- Generated: Yes (by Xcode)
- Committed: Yes (required for project integrity)
- Note: Contains build settings, schemes, workspace state; managed via Xcode UI

**xcuserdata/**, **UserInterfaceState.xcuserstate**
- Purpose: Local Xcode user settings and window state
- Committed: Typically in .gitignore (local to developer machine)

**Assets.xcassets/**
- Purpose: Xcode asset catalog
- Generated: No (manually managed via Asset Catalog editor in Xcode)
- Committed: Yes (required for app resources)

## Current Stage

This is a **brand-new Xcode SwiftUI template scaffold**. It contains:
- Minimal @main entry point
- One root view with placeholder UI
- Standard Xcode project structure

**No architectural layers are present yet.** As features are developed, organize code into appropriate subdirectories (Views, Models, Services, ViewModels, Utilities) based on the patterns that emerge.

---

*Structure analysis: 2026-04-21*
