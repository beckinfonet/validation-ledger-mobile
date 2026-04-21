# Testing Patterns

**Analysis Date:** 2026-04-21

## Current State: Testing Infrastructure Absent

This project currently has **no test target, no test files, and no testing framework configured**. This is expected in a brand-new Xcode SwiftUI scaffold and represents a gap that should be addressed as development progresses.

## Test Framework

**Status:** Not configured

**Next Steps:** iOS Swift projects should use one of:
- **XCTest** (Apple's built-in framework, included with Xcode)
  - Native to iOS, integrates with Xcode Test Navigator
  - Synchronous and asynchronous test support
  - Built-in mocking and performance testing tools
  - Recommended for this project due to zero setup overhead

- **Swift Testing** (new, introduced in Swift 5.9+)
  - Modern Swift-native testing with `@Test` macro syntax
  - Concurrent test execution
  - Rich assertion library
  - Requires Swift 5.9+ (check Xcode version)

**Recommended:** Start with **XCTest** for compatibility and simplicity.

## Test File Organization

**Current Structure:**
```
validationLedger/
├── validationLedger/
│   ├── validationLedgerApp.swift
│   ├── ContentView.swift
│   └── Assets.xcassets/
├── validationLedgerTests/        ← MISSING
│   └── (would contain test files)
└── validationLedger.xcodeproj/
```

**Test Target Status:** Not created by default Xcode template.

**Recommended Naming Pattern (when added):**
- Unit tests: `ContentViewTests.swift` (matches source file)
- Integration tests: `ContentViewIntegrationTests.swift`
- Location: dedicated `validationLedgerTests/` target directory

## Setting Up Tests

**To add XCTest target:**

1. In Xcode: File → New → Target
2. Choose "Unit Testing Bundle" → iOS
3. Name: `validationLedgerTests`
4. Select your app as target to test

**Basic test file structure (after setup):**
```swift
import XCTest
@testable import validationLedger

class ContentViewTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Per-test setup
    }
    
    override func tearDownWithError() throws {
        // Per-test cleanup
    }
    
    func testContentViewRenders() throws {
        // Arrange
        let view = ContentView()
        
        // Act
        // (no direct assertions for SwiftUI views without helper library)
        
        // Assert
        // Will require snapshot testing or preview verification
    }
}
```

## Test Patterns (When Implemented)

**Test Organization:**
- One test class per source file
- Group tests by functionality: `testValidation()`, `testDataParsing()`
- Arrange-Act-Assert (AAA) pattern required
- One primary assertion per test (multiple assertions OK if related)

**Async Testing (recommended for network/database calls):**
```swift
func testAsyncOperation() async throws {
    // Use async/await syntax
    let result = try await someAsyncFunction()
    XCTAssertEqual(result, expected)
}
```

**Error Testing:**
```swift
func testInvalidInputThrows() throws {
    XCTAssertThrows(try functionThatShouldThrow(invalid))
}
```

## Mocking for SwiftUI

**Challenge:** SwiftUI views are difficult to unit test directly.

**Recommended Approaches:**
1. **Extract logic into ViewModels** — Test logic separately from views
2. **Use Preview testing** — Leverage `#Preview` with mock data
3. **Third-party libraries** — Consider:
   - SwiftUI Testing (Pointfree's library)
   - ViewInspector (for view hierarchy testing)
4. **Integration testing** — Test actual app flows via XCTest UI tests

**Example (ViewModel pattern):**
```swift
// Testable logic
class ContentViewModel {
    @Published var text = "Hello"
}

// Views become thin presentation layers
struct ContentView: View {
    @StateObject var viewModel = ContentViewModel()
    var body: some View {
        Text(viewModel.text)
    }
}

// Tests focus on ViewModel
class ContentViewModelTests: XCTestCase {
    func testTextInitialValue() {
        let vm = ContentViewModel()
        XCTAssertEqual(vm.text, "Hello")
    }
}
```

## Test Coverage

**Status:** Not enforced

**Recommendation:** Start with critical paths:
1. Data models and validation
2. Network/API logic (when added)
3. Business rules and state management
4. Views become covered indirectly via integration tests

**Coverage tools:**
- Xcode provides code coverage reports
- Enable in Xcode: Product → Scheme → Edit Scheme → Test → Code Coverage
- View coverage: Product → Generate Code Coverage Report

## Test Types to Implement

**Unit Tests (highest priority):**
- Test ViewModel logic, data models, utilities
- Mock external dependencies (network, storage)
- Fast execution (target: <100ms per test)
- Location: `validationLedgerTests/` target

**Integration Tests (second priority):**
- Test ViewModel + View together
- May use real preview data or fixtures
- Slower than unit tests (OK if <1s)

**UI Tests (future, optional):**
- Test full user workflows via XCTest UI
- Requires `validationLedgerUITests/` target
- Slowest, most fragile—use sparingly
- Not needed until app has complex flows

## Commands (When XCTest Configured)

```bash
# Run all tests (via Xcode)
xcodebuild test -scheme validationLedger -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test class
xcodebuild test -scheme validationLedger -only-testing validationLedgerTests/ContentViewTests

# Generate coverage report
xcodebuild test -scheme validationLedger -enableCodeCoverage YES
```

Or use Xcode UI:
- Product → Test (Cmd+U)
- Product → Test Plan → [select tests to run]
- View results in Test Navigator (Cmd+9)

## Critical Gaps to Address

| Gap | Impact | Action |
|-----|--------|--------|
| No test target | Cannot write tests | Create `validationLedgerTests` target |
| No test framework | Cannot run tests | Add XCTest (built-in) or Swift Testing |
| No CI pipeline | No automated testing | Add GitHub Actions or similar (future phase) |
| Views not testable | Hard to verify UI | Extract ViewModels, test logic separately |
| No fixtures/mocks | Can't test without real dependencies | Create factory functions for test data |

## Next Steps

**Before adding features:**
1. Add `validationLedgerTests/` target
2. Create one test file per source file as they're added
3. Write tests for business logic (ViewModels, data models)
4. Use Preview for quick visual verification during development
5. Plan ViewModel extraction architecture early to keep code testable

**Recommended Reading:**
- Apple's Testing Fundamentals: https://developer.apple.com/documentation/xctest
- XCTest Framework Overview: https://developer.apple.com/documentation/xctest
- SwiftUI Testing Best Practices: https://www.pointfree.co/episodes/ep141-spotlight-on-swiftui-testing

---

*Testing analysis: 2026-04-21*
*Update when test patterns change*
