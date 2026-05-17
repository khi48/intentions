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
