---
status: partial
phase: 08-role-filtered-load-list
source: [08-VERIFICATION.md]
started: 2026-05-20T00:15:00Z
updated: 2026-05-20T00:15:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. 5-role load list visual rendering
expected: All 5 roles render their role-filtered lists; each row shows all 7 freight fields; the verification badge displays the UI-SPEC locked color ramp (blue=verified, yellow=pending, grey=unverified, red=flagged); no visual glitches.
test: Tap 'Loads' tab in each of the 5 role shells on a real device or simulator and confirm the list renders with freight rows (reference #, origin → destination, dates, equipment, weight, rate), the verification badge shows the correct color state for each counterparty, the status badge shows the correct state, and the list scrolls smoothly.
why_human: Cell layout, badge visual accuracy, and freight-field formatting (number formatting, date formatting, equipment label) require visual inspection. Automated snapshot tests use synthetic data and small fixed sizes; real scroll behavior on an actual device can surface layout constraint ambiguities not caught by unit tests.
result: [pending]

### 2. Factoring "Invoices" title — tab + nav bar
expected: Tab bar button: 'Invoices'. Nav bar title: 'Invoices'. At least one row visible from the factoring fixture.
test: On the Factoring role shell, tap the 'Invoices' tab and confirm (a) the tab bar button reads 'Invoices', (b) the in-screen nav bar also reads 'Invoices', and (c) the list renders factoring loads.
why_human: BL-02 was fixed in code and the XCUITest now asserts navigationBars['Invoices'] via the helper, but visual confirmation of the nav bar vs tab bar title matching on a real device is worthwhile after the double-explicit tabBarItem fix introduced in Task 2 of Plan 04.
result: [pending]

### 3. Pull-to-refresh visual behavior
expected: Spinner appears, list refreshes without flicker, spinner disappears inside the apply completion block. No duplicate animations.
test: Pull to refresh on any loaded role list and observe the refresh control spinner appears briefly then the list updates (or stays the same if the fixture has not changed).
why_human: Pull-to-refresh race safety (Pitfall 4 / WR-06 fix) is unit-tested but the visual interaction — spinner timing, row update animation — requires a human to observe against the real UIRefreshControl lifecycle.
result: [pending]

### 4. iPad split-view readable content insets
expected: In iPad regular-width split view, the list content is inset to the readable content guide (not filling the full width). Loads rows are legible.
test: On an iPad in both portrait and split-view multitasking, confirm the load list renders with readable-content insets (not edge-to-edge).
why_human: contentInsetsReference = .readableContent is set in code (RESEARCH Pitfall 5) but the actual visual rendering in iPad multitasking cannot be verified programmatically.
result: [pending]

### 5. VoiceOver fail-closed semantics for flagged counterparty
expected: Red badge background (DS.Colors.destructive), 'FLAGGED' uppercase label, VoiceOver: 'Counterparty flagged'.
test: On the Broker role, scroll the list to a row with a flagged counterparty (VL-1010 / PhantomLine Logistics) and confirm the verification badge renders red with 'FLAGGED' label and VoiceOver speaks 'Counterparty flagged' (not 'Counterparty verified').
why_human: VoiceOver accessibility label correctness for the fail-closed and flagged paths (T-08-06 security requirement) requires manual VoiceOver testing. Unit tests assert the accessibilityLabel string programmatically but the actual VoiceOver speech output can differ from the label string in edge cases (e.g. combining traits).
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
