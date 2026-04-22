---
phase: 03-otp-auth-role-shell-session-the-fixed-phase-1-goal
reviewed: 2026-04-22T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - validationLedger/App/SceneDelegate.swift
  - validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift
findings:
  critical: 0
  warning: 3
  info: 5
  total: 8
status: issues_found
---

# Phase 3 Plan 13: Code Review Report

**Reviewed:** 2026-04-22T00:00:00Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Scoped review of plan 03-13 gap-closure, which wired `SceneDelegate` to construct and present `BiometricLockViewController` per the prior 03-VERIFICATION.md finding ("zero construction sites"). Changes are well-scoped (118/2 lines in SceneDelegate, +44 in the test file), additive, and faithful to the plan. No critical issues found.

Strengths:

- UIKit-only — no SwiftUI usage on the biometric/auth surface (ARCH-01 / CLAUDE.md "UIKit-first for all camera/KYC/scanner/BOL" constraint satisfied; `import UIKit` only).
- Closure captures use explicit capture lists (`[weak self]`, `[weak self, weak container]`) — no implicit strong self captures in escaping closures.
- Observer tokens are stored as instance properties and removed in both `sceneDidDisconnect(_:)` and `deinit`, mirroring the established Plan 11 cleanup pattern.
- `presentedLockVC` is declared `weak` (line 52) and checked for idempotency before constructing a second lock VC (lines 329, 363).
- Both present and dismiss are `animated: false` per RESEARCH §iOS API #6 (security-posture — no reveal animation).
- The cold-boot vs. post-auth distinction is correctly handled via the new `presentRoot(_:checkLockState:)` overload — a Rule 1 bugfix caught during execution that would otherwise have stacked a lock VC on top of every post-OTP role transition.
- The structural test (`biometricLockWiringIsPresent`) records 9 `#expect(source.contains(...))` landmarks that lock in the fix.

Concerns are all non-blocking: a couple of thread-safety ambiguities around `@MainActor` on the SceneDelegate class, an observer callback that calls `@MainActor` code from a potentially non-isolated closure body, an Info-level note on the structural test's strength, and a handful of style / robustness improvements.

## Warnings

### WR-01: `SceneDelegate` class is not `@MainActor`-isolated, but calls `@MainActor`-isolated `BiometricLockViewController.init`

**File:** `validationLedger/App/SceneDelegate.swift:18, 334`
**Issue:**  `BiometricLockViewController` is marked `@MainActor` (BiometricLockViewController.swift:12). `SceneDelegate` is a `UIResponder` subclass but is not explicitly annotated `@MainActor`. Under Swift 5 strict concurrency / Swift 6, constructing a `@MainActor` type from a non-isolated context requires an isolation hop and will produce warnings or errors depending on the language mode.

The observer callbacks (`NotificationCenter.default.addObserver(... queue: .main) { ... }`) dispatch the block to `OperationQueue.main`, which runs on the main thread but is not the same as being `@MainActor`-isolated at the type-system level. Scene-lifecycle methods (`scene(_:willConnectTo:)`, `sceneDidDisconnect(_:)`) are called on the main thread at runtime but, per current Apple API declarations, are not declared `@MainActor` either.

Today this compiles because `UIWindowSceneDelegate` conformance and the lack of strict-concurrency adoption let the main-thread assumption ride. As the team moves to Swift 6 / full strict concurrency, these construction sites become warnings or errors.

**Fix:** Annotate the class or the relevant methods explicitly. Lowest-friction fix is to annotate the whole class, since it is already main-thread-only in practice:

```swift
@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    // ...
}
```

Alternatively, annotate only the new helpers:

```swift
@MainActor
private func presentBiometricLockIfNeeded(container: AppContainer, over presenter: UIViewController) { ... }

@MainActor
private func handleDidBecomeActive() { ... }
```

This is a pre-existing condition (the other methods already construct `@MainActor` types like `AppCoordinator` and assign to `UIWindow.rootViewController`), but the new wiring increases the count of `@MainActor` construction sites, so it is a good time to make the isolation explicit.

### WR-02: `handleDidBecomeActive()` does not guard against the `presentedLockVC` being a currently-dismissing VC

**File:** `validationLedger/App/SceneDelegate.swift:327-365, 371-376`
**Issue:**  The idempotency guard on line 329 (`if presentedLockVC != nil { return }`) is weak-referenced (line 52), which means `presentedLockVC` goes to `nil` when the VC is deallocated — not when it is dismissed. If `didBecomeActive` fires while the previously-presented lock VC is in the middle of a dismiss animation (unlikely here because `animated: false`, but possible if a later refactor flips animation back on), `present(_:animated:)` would be called on a presenter whose `presentedViewController` is not yet `nil`. UIKit logs `"Attempt to present X on Y whose view is not in the window hierarchy"` or silently no-ops in that case.

Secondary issue: `handleDidBecomeActive()` takes `window?.rootViewController` as the presenter (line 374). If the user is inside a pushed navigation or a modal sheet (Phase 3+ features), the true top-most `UIViewController` is not `rootViewController` — UIKit will refuse to `present` a VC from a rootVC that is already showing a modal. `UIViewController` has no `topPresentedViewController` helper; you would walk `presentedViewController` chain.

Current plan scope has no nested modals from `.role` phase (tab bars present role content directly), so this is latent rather than active.

**Fix:**

```swift
private func handleDidBecomeActive() {
    guard case .role = currentPhase else { return }
    guard let container = appCoordinator?.container else { return }
    guard let rootVC = window?.rootViewController else { return }

    // Walk presented chain so we present on the top-most VC, not just rootVC.
    var presenter: UIViewController = rootVC
    while let next = presenter.presentedViewController, next !== presentedLockVC {
        presenter = next
    }
    // If the top-most is ALREADY our lock VC, idempotent no-op.
    if presenter === presentedLockVC { return }
    presentBiometricLockIfNeeded(container: container, over: presenter)
}
```

### WR-03: `onReBindRequested` closure leaves `presentedLockVC` non-nil on the early-return path when `container` has been deallocated

**File:** `validationLedger/App/SceneDelegate.swift:344-358`
**Issue:**  The closure captures `[weak self, weak container]` and early-returns on `guard let container else { return }` (line 350). On that branch, `presentedLockVC` is never reset to `nil`. ARC will eventually zero the weak reference when the VC deallocates, so this is not a retain cycle — but the state-machine invariant that `presentedLockVC == nil` implies "no lock VC on screen" is temporarily violated. If a re-entry to `presentBiometricLockIfNeeded` happens before ARC zeroes the weak ref, the idempotency guard will incorrectly no-op.

In practice this branch is unreachable (container only goes away after `presentRoot` swaps the coordinator tree, and at that point the lock VC is also being dismissed by ARC), but the code reads as if that safety case matters. Either remove the guard (document the invariant) or nil the state on both paths.

**Fix:**

```swift
onReBindRequested: { [weak self, weak container] in
    guard let self else { return }
    guard let container else {
        // Container already swapped (e.g., sessionDidInvalidate fired first).
        // Nothing to logout; ARC will drop the lock VC when the root swaps.
        self.presentedLockVC = nil
        return
    }
    Task { @MainActor in
        await container.logoutService.logout(reason: .userInitiated)
        self.presentedLockVC = nil
    }
}
```

## Info

### IN-01: Structural `#expect(source.contains(...))` test is a grep-guard, not a behavioral guard

**File:** `validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift:181-223`
**Issue:**  The new `biometricLockWiringIsPresent` test makes 9 `#expect(source.contains(...))` assertions. These guarantee the strings appear somewhere in the file — they do not guarantee the wiring is executed. Specifically:

- `source.contains("animated: false")` matches whether it is used on `present(_:animated:)`, `dismiss(animated:)`, or inside a comment.
- `source.contains("BiometricLockViewController(")` matches whether the init call is actually reached, in dead code, or behind a compile-time guard.
- If someone refactors to wrap the VC presentation in a `#if SOMETHING_TRUE_AT_BUILD_TIME_ONLY` block, the grep assertions would still pass while the runtime behavior is broken.

The test is called out explicitly in the plan as "structural assertion — the assertion is the plan's grep contract, not a runtime-behavior check." That is a valid choice for LAContext-dependent code (simulator can't exercise real biometrics), and the existing `makeRootAnotherActiveSession` / `makeRootAuth` / `makeRootRole` tests do cover the orthogonal AppCoordinator routing. But the runtime behavior of `presentBiometricLockIfNeeded` and `handleDidBecomeActive` has no unit-test coverage — those paths rely entirely on HUMAN-UAT.

**Fix:** Consider adding a `@MainActor` unit test using a fake `SessionLockService` that returns `.locked(.coldBoot)` and a fake `UIViewController` presenter that records `present(_:animated:completion:)` calls. Example:

```swift
@Test("presentBiometricLockIfNeeded presents when lockState is .locked")
@MainActor
func presentsOnLocked() {
    let fakeLock = FakeSessionLockService(state: .locked(reason: .coldBoot))
    let recorder = PresentRecordingViewController()
    // ... exercise SceneDelegate.presentBiometricLockIfNeeded (needs internal visibility)
    #expect(recorder.presentedCount == 1)
    #expect(recorder.lastPresented is BiometricLockViewController)
}
```

This would require either exposing the helper with `internal` visibility + `@testable import` or extracting it to a stand-alone class. Not blocking for M1; recommended as a follow-up.

### IN-02: Inline comments embed file + line references that will drift

**File:** `validationLedger/App/SceneDelegate.swift:84, 107, 109, 322, 347, 361`
**Issue:**  Multiple comments cite specific line numbers in OTHER files (for example: "SessionLockService.swift lines 62-83", "BiometricLockViewController.swift lines 44-47", "RESEARCH §iOS API #6 line 910"). These become stale the first time any of those files is edited. In particular `lines 72-86` is referenced three times for the `.sessionDidInvalidate` observer; the actual range in the current file is 88-102.

**Fix:** Replace line-number citations with symbol names or search-anchor comments that do not drift. Example:

```swift
// SessionLockService.swift self-subscribes to UIApplication.didEnterBackgroundNotification
// in DefaultSessionLockService.init — see the "didEnterBackground" comment block there.
```

Or, if precision matters, replace with git-anchored references or docs/ADR citations.

### IN-03: `currentPhase` is read in `handleDidBecomeActive` without guarding against the `.launch` case

**File:** `validationLedger/App/SceneDelegate.swift:47, 371-376`
**Issue:**  `AppPhase` has four cases (`.launch`, `.auth`, `.role`, `.anotherActiveSession`). `currentPhase` is an `AppPhase?` and is only written inside `presentRoot(_:checkLockState:)` (line 297), so it can only hold `.auth`, `.role`, or `.anotherActiveSession` — `.launch` is never assigned. The `guard case .role = currentPhase else { return }` correctly filters out the other cases. However, `.launch` is declared but never used as a value, which suggests either the enum has a dead case or `.launch` was intended to be set somewhere that is now missing.

**Fix:** Either remove `.launch` from the enum (if truly dead) or add a comment documenting why it is declared but unused. If kept, consider:

```swift
public enum AppPhase {
    case launch              // Reserved for Phase 1 pre-auth splash; not currently assigned.
    case auth
    case role(Role)
    case anotherActiveSession
}
```

### IN-04: `-ForceRoleForUITest` path bypasses the new lock-state gate without a DEBUG-only bypass note

**File:** `validationLedger/App/SceneDelegate.swift:122-132`
**Issue:**  The `-ForceRoleForUITest` block calls `presentRoot(.role(role))` (no-flag overload → `checkLockState: false`), so the biometric overlay is skipped on that fast-path. This is probably correct behavior (the Phase 1 DevMenu fast-path has no OTP → no session → a lock overlay would be meaningless). But the plan discusses the opposite tradeoff in its `<preservation_invariants>` section (lines 420 of the plan) and the code has no comment explaining why this DEBUG path intentionally skips the lock check.

A future engineer reading the file without the plan in hand may try to "fix" what looks like a gap.

**Fix:** Add a one-line comment:

```swift
if let role = Role(rawValue: raw) {
    // No lock check on this fast-path — DevMenu RoleSwitcher has no OTP/Keychain
    // session, so lockState() would trip .coldBoot and block the UI test harness.
    presentRoot(.role(role))
    window.makeKeyAndVisible()
    return
}
```

### IN-05: Test's `readSource` fallback uses hardcoded `#filePath`-based path-walking

**File:** `validationLedgerTests/App/AppCoordinatorPhase3RoutingTests.swift:34-58`
**Issue:**  The existing `readSource` helper walks three `deletingLastPathComponent()` steps from `#filePath` to reach the repo root (comments: `App/` → `validationLedgerTests/` → repo root). If the test file is ever moved to a different depth (for example, to `validationLedgerTests/App/Phase3/`), this path-walk silently fails the file lookup and the test throws an `NSError`. The fallback is reasonable but brittle.

**Fix:** A more robust variant is to walk up from `#filePath` until a known repo anchor (for example, `.git/`, `CLAUDE.md`, or `validationLedger.xcodeproj`) is found:

```swift
private func repoRoot() -> URL {
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while dir.path != "/" {
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("validationLedger.xcodeproj").path) {
            return dir
        }
        dir.deleteLastPathComponent()
    }
    fatalError("Could not locate repo root from \(#filePath)")
}
```

Not blocking — pre-existing pattern from Plan 11.

---

_Reviewed: 2026-04-22T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
