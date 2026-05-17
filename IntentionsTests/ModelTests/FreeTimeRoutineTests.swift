//
//  FreeTimeRoutineTests.swift
//  IntentionsTests
//
//  Replaces FreeTimeIntervalTests. Validates the new single-day, recurring
//  routine model that replaces the old minute-of-week interval form.
//

import XCTest
@testable import Intentions

final class FreeTimeRoutineTests: XCTestCase {

    // MARK: - Helpers

    private func makeRoutine(
        startMinute: Int = 9 * 60,
        durationMinutes: Int = 8 * 60,
        days: Set<Weekday> = [.monday],
        sortIndex: Int = 0,
        name: String? = nil
    ) -> FreeTimeRoutine {
        FreeTimeRoutine(
            id: UUID(),
            name: name,
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            days: days,
            sortIndex: sortIndex
        )
    }

    // MARK: - Derived values

    func test_endMinute_isStartPlusDuration() {
        let r = makeRoutine(startMinute: 60, durationMinutes: 120)
        XCTAssertEqual(r.endMinute, 180)
    }

    func test_endMinute_atMidnight_equalsMinutesPerDay() {
        // Late-evening routine ending exactly at midnight.
        let r = makeRoutine(startMinute: 23 * 60, durationMinutes: 60)
        XCTAssertEqual(r.endMinute, FreeTimeRoutine.minutesPerDay)
    }

    func test_minutesPerDay_is1440() {
        XCTAssertEqual(FreeTimeRoutine.minutesPerDay, 1440)
    }

    // MARK: - isActive(weekday:minuteOfDay:)

    func test_isActive_returnsTrueInsideWindowOnConfiguredDay() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, days: [.monday])
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 9 * 60))      // exact start
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 9 * 60 + 30))
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 10 * 60 - 1)) // last minute
    }

    func test_isActive_returnsFalseAtExclusiveEnd() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, days: [.monday])
        XCTAssertFalse(r.isActive(weekday: .monday, minuteOfDay: 10 * 60)) // exclusive end
    }

    func test_isActive_returnsFalseBeforeStart() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, days: [.monday])
        XCTAssertFalse(r.isActive(weekday: .monday, minuteOfDay: 9 * 60 - 1))
    }

    func test_isActive_returnsFalseOnNonConfiguredDay() {
        let r = makeRoutine(days: [.monday, .wednesday])
        XCTAssertFalse(r.isActive(weekday: .tuesday, minuteOfDay: 12 * 60))
        XCTAssertFalse(r.isActive(weekday: .sunday, minuteOfDay: 12 * 60))
    }

    func test_isActive_multipleDays() {
        let r = makeRoutine(days: [.monday, .wednesday, .friday])
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 12 * 60))
        XCTAssertTrue(r.isActive(weekday: .wednesday, minuteOfDay: 12 * 60))
        XCTAssertTrue(r.isActive(weekday: .friday, minuteOfDay: 12 * 60))
        XCTAssertFalse(r.isActive(weekday: .tuesday, minuteOfDay: 12 * 60))
    }

    // MARK: - Edge cases — start at 0, end at 1440

    func test_isActive_routineStartsAtMidnight() {
        let r = makeRoutine(startMinute: 0, durationMinutes: 60, days: [.monday])
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 0))
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 59))
        XCTAssertFalse(r.isActive(weekday: .monday, minuteOfDay: 60))
    }

    func test_isActive_routineEndsAtMidnight() {
        // 23:00 → 24:00 (exclusive). Last covered minute is 23:59 (1439).
        let r = makeRoutine(startMinute: 23 * 60, durationMinutes: 60, days: [.monday])
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 23 * 60))
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 1439))
        // 1440 isn't a legitimate minute-of-day input; do not assert.
    }

    func test_isActive_fullDayRoutine() {
        let r = makeRoutine(startMinute: 0, durationMinutes: FreeTimeRoutine.minutesPerDay, days: [.monday])
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 0))
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 720))
        XCTAssertTrue(r.isActive(weekday: .monday, minuteOfDay: 1439))
    }

    // MARK: - Display strings

    func test_startTimeOfDayString_zeroPads() {
        let r = makeRoutine(startMinute: 8 * 60 + 5, durationMinutes: 60)
        XCTAssertEqual(r.startTimeOfDayString, "08:05")
    }

    func test_endTimeOfDayString_zeroPads() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 95)
        // 09:00 + 95min = 10:35
        XCTAssertEqual(r.endTimeOfDayString, "10:35")
    }

    func test_endTimeOfDayString_midnightFormat() {
        // End-of-day routine ending exactly at midnight renders as "24:00" because
        // we display the absolute minute-of-day. Lock current behavior so display
        // changes are explicit.
        let r = makeRoutine(startMinute: 23 * 60, durationMinutes: 60)
        XCTAssertEqual(r.endTimeOfDayString, "24:00")
    }

    // MARK: - Codable round-trip

    func test_codable_roundTripPreservesAllFields() throws {
        let original = FreeTimeRoutine(
            id: UUID(),
            name: "Morning",
            startMinute: 6 * 60 + 30,
            durationMinutes: 90,
            days: [.tuesday, .thursday, .saturday],
            sortIndex: 3
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FreeTimeRoutine.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.startMinute, original.startMinute)
        XCTAssertEqual(decoded.durationMinutes, original.durationMinutes)
        XCTAssertEqual(decoded.days, original.days)
        XCTAssertEqual(decoded.sortIndex, original.sortIndex)
    }

    func test_codable_nilNameRoundTrips() throws {
        let original = makeRoutine(name: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FreeTimeRoutine.self, from: data)
        XCTAssertNil(decoded.name)
    }

    // MARK: - Hashable

    func test_hashable_sameValuesProduceSameHash() {
        let id = UUID()
        let a = FreeTimeRoutine(id: id, name: "a", startMinute: 60, durationMinutes: 60, days: [.monday], sortIndex: 0)
        let b = FreeTimeRoutine(id: id, name: "a", startMinute: 60, durationMinutes: 60, days: [.monday], sortIndex: 0)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_hashable_differentIdProducesInequality() {
        let a = makeRoutine()
        let b = makeRoutine()
        XCTAssertNotEqual(a, b)
    }

    // MARK: - title(for:) resolution

    func test_title_returnsNameWhenSet() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, name: "Morning")
        XCTAssertEqual(FreeTimeRoutine.title(for: r), "Morning")
    }

    func test_title_returnsTimeRangeWhenNameNil() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, name: nil)
        XCTAssertEqual(FreeTimeRoutine.title(for: r), "09:00–10:00")
    }

    func test_title_returnsTimeRangeWhenNameEmpty() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, name: "")
        XCTAssertEqual(FreeTimeRoutine.title(for: r), "09:00–10:00")
    }

    func test_title_returnsTimeRangeWhenNameWhitespaceOnly() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, name: "   \t\n ")
        XCTAssertEqual(FreeTimeRoutine.title(for: r), "09:00–10:00")
    }

    func test_title_trimsSurroundingWhitespaceFromName() {
        let r = makeRoutine(name: "  Focus  ")
        XCTAssertEqual(FreeTimeRoutine.title(for: r), "Focus")
    }

    // MARK: - editorGuards

    /// Build a fixed Date in the local calendar (Gregorian, firstWeekday=2)
    /// so weekday/time-of-day assertions don't depend on wall-clock.
    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)!
    }

    func test_editorGuards_createOnToday_disablesPastDays() {
        // 2026-05-13 was a Wednesday.
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 10, minute: 0)
        let spec = editorGuards(now: now, isNewRoutine: true, currentStart: 10 * 60, daysSelected: [.wednesday])
        XCTAssertEqual(spec.disabledDays, [.monday, .tuesday])
        XCTAssertEqual(spec.minStartMinute, 10 * 60)
        XCTAssertEqual(spec.minEndMinute, 10 * 60 + 1)
    }

    func test_editorGuards_createOnSunday_disablesWholeWeek() {
        // 2026-05-17 is a Sunday.
        let now = makeDate(year: 2026, month: 5, day: 17, hour: 14, minute: 30)
        let spec = editorGuards(now: now, isNewRoutine: true, currentStart: nil, daysSelected: [.sunday])
        XCTAssertEqual(spec.disabledDays, [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
    }

    func test_editorGuards_createOnMonday_disablesNothing() {
        // 2026-05-11 is a Monday.
        let now = makeDate(year: 2026, month: 5, day: 11, hour: 9, minute: 0)
        let spec = editorGuards(now: now, isNewRoutine: true, currentStart: nil, daysSelected: [.monday])
        XCTAssertTrue(spec.disabledDays.isEmpty)
    }

    func test_editorGuards_editInProgressRoutine_noGuards() {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 10, minute: 0)
        let spec = editorGuards(now: now, isNewRoutine: false, currentStart: 9 * 60, daysSelected: [.wednesday])
        XCTAssertTrue(spec.disabledDays.isEmpty)
        XCTAssertNil(spec.minStartMinute)
        XCTAssertEqual(spec.minEndMinute, 9 * 60 + 1)
    }

    func test_editorGuards_createTodayNotSelected_noTimeGuard() {
        // Wed, today; user only picks Fri.
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 10, minute: 0)
        let spec = editorGuards(now: now, isNewRoutine: true, currentStart: 8 * 60, daysSelected: [.friday])
        XCTAssertNil(spec.minStartMinute)
        XCTAssertEqual(spec.disabledDays, [.monday, .tuesday])
    }

    func test_editorGuards_endAlwaysGreaterThanStart() {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 10, minute: 0)
        let spec = editorGuards(now: now, isNewRoutine: true, currentStart: 9 * 60, daysSelected: [.wednesday])
        XCTAssertEqual(spec.minEndMinute, 9 * 60 + 1)

        let spec2 = editorGuards(now: now, isNewRoutine: true, currentStart: nil, daysSelected: [.wednesday])
        XCTAssertEqual(spec2.minEndMinute, 1)
    }

    func test_editorGuards_minStartMatchesNowMinute() {
        let now = makeDate(year: 2026, month: 5, day: 13, hour: 14, minute: 27)
        let spec = editorGuards(now: now, isNewRoutine: true, currentStart: 0, daysSelected: [.wednesday])
        XCTAssertEqual(spec.minStartMinute, 14 * 60 + 27)
    }

    // MARK: - Pure isActive(routine:now:)

    /// Build a UTC calendar so weekday + minute-of-day come out deterministically.
    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 2026-05-18 (Mon) 09:30 UTC.
    private func mondayAt(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 18
        comps.hour = hour
        comps.minute = minute
        return utcCalendar.date(from: comps)!
    }

    /// 2026-05-19 (Tue) at given time.
    private func tuesdayAt(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 19
        comps.hour = hour
        comps.minute = minute
        return utcCalendar.date(from: comps)!
    }

    func test_pureIsActive_matchingDayAndTime_isTrue() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, days: [.monday])
        XCTAssertTrue(isActive(routine: r, now: mondayAt(hour: 9, minute: 30), calendar: utcCalendar))
    }

    func test_pureIsActive_matchingDayOutsideTime_isFalse() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, days: [.monday])
        XCTAssertFalse(isActive(routine: r, now: mondayAt(hour: 8, minute: 59), calendar: utcCalendar))
        XCTAssertFalse(isActive(routine: r, now: mondayAt(hour: 11, minute: 0), calendar: utcCalendar))
    }

    func test_pureIsActive_nonMatchingDay_isFalse() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, days: [.monday])
        XCTAssertFalse(isActive(routine: r, now: tuesdayAt(hour: 9, minute: 30), calendar: utcCalendar))
    }

    func test_pureIsActive_inclusiveStart() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, days: [.monday])
        XCTAssertTrue(isActive(routine: r, now: mondayAt(hour: 9, minute: 0), calendar: utcCalendar))
    }

    func test_pureIsActive_exclusiveEnd() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, days: [.monday])
        XCTAssertFalse(isActive(routine: r, now: mondayAt(hour: 10, minute: 0), calendar: utcCalendar))
    }

    /// Highlight reactivity: at the last minute inside the window the row is active,
    /// at the very next minute (the exclusive end) it flips to inactive. Same routine,
    /// same calendar — only `now` advances one minute.
    func test_pureIsActive_minuteBoundaryFlipsHighlight() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, days: [.monday])
        let lastInside = mondayAt(hour: 9, minute: 59)
        let firstOutside = mondayAt(hour: 10, minute: 0)
        XCTAssertTrue(isActive(routine: r, now: lastInside, calendar: utcCalendar))
        XCTAssertFalse(isActive(routine: r, now: firstOutside, calendar: utcCalendar))
    }

    /// Boundary at start: T = startMinute - 1 inactive, T+1 active.
    func test_pureIsActive_startBoundaryFlipsHighlight() {
        let r = makeRoutine(startMinute: 9 * 60, durationMinutes: 60, days: [.monday])
        XCTAssertFalse(isActive(routine: r, now: mondayAt(hour: 8, minute: 59), calendar: utcCalendar))
        XCTAssertTrue(isActive(routine: r, now: mondayAt(hour: 9, minute: 0), calendar: utcCalendar))
    }

    // MARK: - RoutineOrdering.reorder

    private func makeSortedTriple() -> [FreeTimeRoutine] {
        [
            makeRoutine(sortIndex: 0, name: "A"),
            makeRoutine(sortIndex: 1, name: "B"),
            makeRoutine(sortIndex: 2, name: "C")
        ]
    }

    func test_reorder_moveFirstToLast_producesContiguousIndices() {
        let input = makeSortedTriple()
        // SwiftUI: moving index 0 to "end" passes destination == count.
        let result = RoutineOrdering.reorder(sortedRoutines: input, from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(result.map(\.name), ["B", "C", "A"])
        XCTAssertEqual(result.map(\.sortIndex), [0, 1, 2])
    }

    func test_reorder_moveLastToFirst_producesContiguousIndices() {
        let input = makeSortedTriple()
        let result = RoutineOrdering.reorder(sortedRoutines: input, from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(result.map(\.name), ["C", "A", "B"])
        XCTAssertEqual(result.map(\.sortIndex), [0, 1, 2])
    }

    func test_reorder_moveMiddleToMiddle_producesContiguousIndices() {
        let input = [
            makeRoutine(sortIndex: 0, name: "A"),
            makeRoutine(sortIndex: 1, name: "B"),
            makeRoutine(sortIndex: 2, name: "C"),
            makeRoutine(sortIndex: 3, name: "D")
        ]
        // Move "B" (idx 1) to just after "C" — destination idx 3 means insert before original idx 3.
        let result = RoutineOrdering.reorder(sortedRoutines: input, from: IndexSet(integer: 1), to: 3)
        XCTAssertEqual(result.map(\.name), ["A", "C", "B", "D"])
        XCTAssertEqual(result.map(\.sortIndex), [0, 1, 2, 3])
    }

    func test_reorder_isPure_doesNotMutateInput() {
        let input = makeSortedTriple()
        let originalSortIndices = input.map(\.sortIndex)
        _ = RoutineOrdering.reorder(sortedRoutines: input, from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(input.map(\.sortIndex), originalSortIndices)
    }

    func test_reorder_preservesAllRoutineFields() {
        let r = FreeTimeRoutine(
            id: UUID(), name: "Keep", startMinute: 7 * 60, durationMinutes: 30,
            days: [.tuesday], sortIndex: 5
        )
        let other = makeRoutine(sortIndex: 99, name: "Other")
        let result = RoutineOrdering.reorder(sortedRoutines: [r, other], from: IndexSet(integer: 1), to: 0)
        let moved = result.first { $0.id == other.id }!
        XCTAssertEqual(moved.name, "Other")
        let kept = result.first { $0.id == r.id }!
        XCTAssertEqual(kept.startMinute, 7 * 60)
        XCTAssertEqual(kept.durationMinutes, 30)
        XCTAssertEqual(kept.days, [.tuesday])
    }
}
