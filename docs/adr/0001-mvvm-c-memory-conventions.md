# ADR 0001: MVVM-C Memory Conventions

**Status:** Accepted
**Date:** 2026-04-20
**Supersedes:** None

## Context

MVVM + Coordinators + Combine have four canonical leak patterns (`.planning/research/PITFALLS.md` P5).
Undetected retain cycles compound through M2–M3 and force a feature freeze to fix.

## Decision

The following rules are enforced at code review for every ViewModel + Coordinator pair.
Critical rule-at-a-glance: assign(to:on:) is BANNED; every sink closure must use [weak self].

1. **Weak back-references:** `ViewModel` holds `weak var coordinator: CoordinatorProtocol?`.
   Coordinators hold children strongly, parent weakly.
2. **`[weak self]` in every `sink` closure** followed by `guard let self else { return }`.
3. **`assign(to:on:)` is BANNED.** Use explicit `.sink { [weak self] in self?.property = $0 }`
   or a custom `assignWeak(to:on:)` extension.
4. **Every `Task` created in a ViewModel is stored and cancelled in `deinit`.**
5. **`@Published` writes from background threads are forbidden.** Use `@MainActor` on VMs
   OR `.receive(on: DispatchQueue.main)` before assignment.
6. **DEBUG `assert(cancellables.isEmpty)` in VM `deinit`** — makes leaks visible in console.

## Consequences

- Code review cost: +5 min per VM PR; pays back in weeks of non-leak-hunting.
- No runtime performance impact.
- SwiftLint regex for `.assign(to:` can be added later; sink-without-weak is high false-positive.

## Related

- `.planning/research/PITFALLS.md` P5
- `.planning/research/ARCHITECTURE.md` Pattern 1 (MVVM-C with Initializer DI)
- `CLAUDE.md` (this project's instructions link here for FOUND-03 compliance)
- `REQUIREMENTS.md` FOUND-03
