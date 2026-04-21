# ADR 0002: Role Coordinator Swap Pattern

**Status:** Accepted
**Date:** 2026-04-20
**Supersedes:** None

## Context

`Roles/RoleCoordinator` must swap the app's root coordinator when the active role changes (ARCH-06). Five roles exist: Shipper, Broker, Carrier, Dispatch, Factoring (per TechStack.md §4). Role changes must not leak state between roles — a security-sensitive app cannot risk, for example, a Shipper's in-memory cache being visible to a Carrier session.

Two viable implementations exist:
1. **Mutate `TabBarCoordinator` children:** swap the child VCs of a shared `UITabBarController`. Lightweight, no re-init cost.
2. **Recreate the root at `SceneDelegate`:** on role change, allocate a fresh `AppContainer` + `AppCoordinator`, assign to `window.rootViewController`. Heavier, but state isolation is deterministic via ARC.

`.planning/research/ARCHITECTURE.md` Amendment #3 and `.planning/research/PITFALLS.md` Anti-Pattern 4 recommend option 2.

## Decision

**Root-swap at `SceneDelegate` level (option 2).** Implementation:

```swift
func presentRoot(_ phase: AppPhase) {
    let container = AppContainer(env: .current)
    let coordinator = AppCoordinator(container: container, phase: phase)
    self.appCoordinator = coordinator          // single strong reference
    self.window?.rootViewController = coordinator.rootViewController
    // Previous coordinator tree is orphaned; ARC deallocates on next runloop.
}
```

- Fresh `AppContainer` per role change — no shared state between roles.
- `SceneDelegate` holds exactly one strong reference (`appCoordinator`). Assignment to a new value drops the old tree deterministically.
- **Abrupt replace** — no cross-dissolve animation. This is a dev affordance in Phase 1 (exercised via DevMenu shake gesture per D-07) and becomes a product flow in Phase 3 (AUTH-04 logout → phone-entry screen).

## Consequences

- **Phase 1 cost:** Near-zero. Services in the container are cheap (loggers + stub keystore + protocol stubs).
- **Phase 2+ cost:** Audit required. When `AppContainer` holds real `NetworkClient` (with URLSession caches), real `KeyStoreProtocol` (with Secure Enclave key handles), the re-create cost grows. If any service becomes expensive to re-create, add a migration step (pass the service to the new container) OR split the container into `SessionScope` (swap on role change) + `AppScope` (persistent across role changes).
- **Testing:** Role-swap must be unit-testable via `RoleCoordinator` protocol contract tests (Plan 03 or Plan 05 writes these under `validationLedgerTests/Roles/RoleCoordinatorTests.swift`).
- **Animation:** No cross-dissolve. Users see an instant swap. This is acceptable for a security-first product (the role change is an explicit dev action; users in Phase 3+ should rarely see role swaps — role is established at account creation).

## Related

- `.planning/research/ARCHITECTURE.md` Amendment #3 (root-swap at SceneDelegate)
- `.planning/research/PITFALLS.md` Anti-Pattern 4 (TabBar child mutation leaks state)
- `CONTEXT.md` D-07 (full dev-menu demo), D-10 (root-swap mechanism)
- `REQUIREMENTS.md` ARCH-06
