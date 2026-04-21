# Coding Conventions

**Analysis Date:** 2026-04-21

## Current State

This is a brand-new SwiftUI iOS scaffold with only default Xcode template files. Coding conventions are minimal and follow Xcode's standard Swift template style. As the project grows, conventions should be formally established from these foundations.

## Naming Patterns

**Files:**
- PascalCase for Swift files (`validationLedgerApp.swift`, `ContentView.swift`)
- File name matches primary type declared (e.g., `ContentView.swift` contains `ContentView` struct)

**Types:**
- PascalCase for all struct and type names (`validationLedgerApp`, `ContentView`)
- No prefix for types (not `IContentView` or `_ContentView`)

**Variables:**
- camelCase for computed properties and local variables (e.g., `body`)
- No underscore prefix observed in current code

**Functions:**
- No custom functions in current scaffold—only implicit computed properties via `body`
- Xcode template does not yet show function naming patterns

## Code Style

**Formatting:**
- 4-space indentation (observed in `validationLedgerApp.swift` and `ContentView.swift`)
- Xcode default formatting rules apply
- No Prettier or equivalent formatter detected

**Linting:**
- No linter (SwiftLint, etc.) configured
- Xcode compiler warnings/errors are the implicit standard

## Import Organization

**Order:**
1. Framework imports (`import SwiftUI`)

**Pattern:**
- Single import at top of file
- No path aliases or relative imports in current scaffold

## SwiftUI Patterns

**View Structure:**
- Struct-based views conforming to `View` protocol
- Computed `body` property returning view hierarchy
- Property syntax: `var body: some View { ... }`

**Layout:**
- Container views like `VStack` with `.padding()` modifiers
- System image references via `Image(systemName:)`
- Direct modifier chaining on views

**Preview:**
```swift
#Preview {
    ContentView()
}
```
- Preview declarations at end of view files using `#Preview` macro
- Used for live canvas in Xcode

## App Entry Point

**Pattern:**
- `@main` struct attribute on app entry point (`validationLedgerApp`)
- App conforms to `App` protocol
- `WindowGroup` wrapping root view (`ContentView`)

## Comments & Documentation

**Current State:**
- Only auto-generated file headers present:
  ```swift
  //
  //  [FileName].swift
  //  [ProjectName]
  //
  //  Created by Beck Maldin VL on 4/20/26.
  //
  ```
- No JSDoc, documentation comments, or inline comments in scaffold

## Error Handling

**Current State:**
- Not applicable—no error handling in template scaffold
- Pattern will be established as business logic is added

## Module Design

**Exports:**
- No explicit exports or module organization yet
- Default access (implicit internal) for all current code
- Single file per view convention established

## Notes for Future Development

As the project grows beyond this template:

1. **Establish linting rules** — Consider SwiftLint with `.swiftlint.yml` for consistency
2. **Define folder structure** — Plan Views/, Models/, Services/, Utilities/ hierarchy early
3. **Create code review guidelines** — Document mutation patterns, state management approach
4. **Standardize error types** — Define custom Error conformances early
5. **Add documentation** — SwiftUI views benefit from clear purpose comments

---

*Convention analysis: 2026-04-21*
*Update when patterns change*
