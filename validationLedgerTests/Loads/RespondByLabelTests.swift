// validationLedgerTests/Loads/RespondByLabelTests.swift
// Phase 10 Plan 04 Task 1 — covers the date formatter helper backing the
// carrier/dispatch respond-by inline label per UI-SPEC line 322-335.
//
// The helper is `LoadActionsView.RespondByFormatter.format(_:)` — file-
// internal, exposed for testing via `@testable import validationLedger`.
// Four cases:
//   - Today        : "5:00 PM today"
//   - Tomorrow     : "5:00 PM tomorrow"
//   - 2-6 days out : "5:00 PM, Wed"
//   - 7+ days out  : "5:00 PM, May 28"
//
// Tests use the system calendar / current locale (no fixed locale override).
// The assertion strings are framed as substring matches (date locale renders
// "PM" as "PM" in en_US, the project's development region; tests run on
// development hosts that share that locale per CI memory).

import XCTest
@testable import validationLedger

final class RespondByLabelTests: XCTestCase {

    // MARK: - Helpers

    /// Build a Date for "today at 5 PM" (assuming today is in user's calendar).
    /// If "5 PM today" is in the past, the same `5 PM today` value is still
    /// what the formatter must render — relative day component is "today".
    private func todayAtFivePM() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 17
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Build "tomorrow at 5 PM".
    private func tomorrowAtFivePM() -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = 17
        components.minute = 0
        return Calendar.current.date(from: components) ?? tomorrow
    }

    /// Build N days out at 5 PM.
    private func daysFromNowAtFivePM(_ days: Int) -> Date {
        let future = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: future)
        components.hour = 17
        components.minute = 0
        return Calendar.current.date(from: components) ?? future
    }

    // MARK: - Test 1 — today

    func test_respondByLabel_format_today_returnsTimeWithToday() {
        let date = todayAtFivePM()
        let formatted = LoadActionsView.RespondByFormatter.format(date)
        XCTAssertTrue(formatted.lowercased().contains("today"),
                      "Today date should include 'today' — got: \(formatted)")
        XCTAssertTrue(formatted.contains("5:00") || formatted.contains("17:00"),
                      "Today date should include the time 5:00 PM — got: \(formatted)")
    }

    // MARK: - Test 2 — tomorrow

    func test_respondByLabel_format_tomorrow_returnsTimeWithTomorrow() {
        let date = tomorrowAtFivePM()
        let formatted = LoadActionsView.RespondByFormatter.format(date)
        XCTAssertTrue(formatted.lowercased().contains("tomorrow"),
                      "Tomorrow date should include 'tomorrow' — got: \(formatted)")
    }

    // MARK: - Test 3 — 4 days out -> weekday short

    func test_respondByLabel_format_4daysOut_returnsTimeWithWeekday() {
        let date = daysFromNowAtFivePM(4)
        let formatted = LoadActionsView.RespondByFormatter.format(date)
        let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let hasWeekday = weekdays.contains { formatted.contains($0) }
        XCTAssertTrue(hasWeekday,
                      "4-days-out date should include a weekday short form — got: \(formatted)")
    }

    // MARK: - Test 4 — 30 days out -> month + day

    func test_respondByLabel_format_30daysOut_returnsTimeWithMonthDay() {
        let date = daysFromNowAtFivePM(30)
        let formatted = LoadActionsView.RespondByFormatter.format(date)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let hasMonth = months.contains { formatted.contains($0) }
        XCTAssertTrue(hasMonth,
                      "30-days-out date should include a month abbreviation — got: \(formatted)")
        // Should have a numeric day somewhere
        let hasNumeric = formatted.rangeOfCharacter(from: .decimalDigits) != nil
        XCTAssertTrue(hasNumeric, "30-days-out date should include a numeric day")
    }
}
