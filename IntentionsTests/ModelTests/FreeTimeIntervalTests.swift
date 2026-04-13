import XCTest
@testable import Intentions

@MainActor
final class FreeTimeIntervalTests: XCTestCase {

    // MARK: - Basic construction

    func testMinuteOfWeekConstantsMatchExpectations() {
        XCTAssertEqual(FreeTimeInterval.minutesPerDay, 1440)
        XCTAssertEqual(FreeTimeInterval.minutesPerWeek, 10080)
    }

    // MARK: - Containment (non-wrapping)

    func testContainsWithinNonWrappingInterval() {
        // Mon 09:00 → Mon 17:00
        let interval = FreeTimeInterval(
            id: UUID(),
            startMinuteOfWeek: 9 * 60,
            durationMinutes: 8 * 60
        )
        XCTAssertTrue(interval.contains(minuteOfWeek: 9 * 60))       // start edge
        XCTAssertTrue(interval.contains(minuteOfWeek: 12 * 60))      // middle
        XCTAssertFalse(interval.contains(minuteOfWeek: 17 * 60))     // end edge (exclusive)
        XCTAssertFalse(interval.contains(minuteOfWeek: 9 * 60 - 1))  // before
        XCTAssertFalse(interval.contains(minuteOfWeek: 17 * 60 + 1)) // after
    }

    // MARK: - Containment (wrapping)

    func testContainsWithinWrappingInterval() {
        // Sun 22:00 → Mon 02:00
        // Sun = day 6 (Mon-origin), 22:00 = 22*60 = 1320
        // startMinuteOfWeek = 6 * 1440 + 1320 = 9960
        // duration = 4h = 240
        let interval = FreeTimeInterval(
            id: UUID(),
            startMinuteOfWeek: 9960,
            durationMinutes: 240
        )
        XCTAssertTrue(interval.contains(minuteOfWeek: 9960))       // Sun 22:00
        XCTAssertTrue(interval.contains(minuteOfWeek: 10079))      // Sun 23:59
        XCTAssertTrue(interval.contains(minuteOfWeek: 0))          // Mon 00:00
        XCTAssertTrue(interval.contains(minuteOfWeek: 119))        // Mon 01:59
        XCTAssertFalse(interval.contains(minuteOfWeek: 120))       // Mon 02:00 (end, exclusive)
        XCTAssertFalse(interval.contains(minuteOfWeek: 9959))      // Sun 21:59
    }

    // MARK: - Overlap

    func testOverlapsSimple() {
        let a = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 100, durationMinutes: 200)
        let b = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 200, durationMinutes: 200)
        let c = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 400, durationMinutes: 50)
        XCTAssertTrue(a.overlaps(b))
        XCTAssertFalse(a.overlaps(c))
        XCTAssertFalse(b.overlaps(c))
    }

    func testOverlapsAdjacentIntervalsDoNotOverlap() {
        // `a` ends (exclusive) exactly where `b` begins (inclusive) — they touch but share no minute.
        let a = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 100, durationMinutes: 200) // 100..<300
        let b = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 300, durationMinutes: 200) // 300..<500
        XCTAssertFalse(a.overlaps(b))
        XCTAssertFalse(b.overlaps(a))
    }

    func testOverlapsTwoWrappingIntervals() {
        // Both intervals wrap the week boundary.
        // `a`: Sun 22:00 → Mon 02:00
        // `b`: Sun 23:30 → Mon 01:00
        let a = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 6 * 1440 + 22 * 60, durationMinutes: 4 * 60)
        let b = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 6 * 1440 + 23 * 60 + 30, durationMinutes: 90)
        XCTAssertTrue(a.overlaps(b))
        XCTAssertTrue(b.overlaps(a))
    }

    func testOverlapsWrappingAndNonWrappingIntervals() {
        // `a` wraps: Sun 22:00 → Mon 02:00
        // `b` does not wrap: Mon 01:00 → Mon 03:00
        // They share the Mon 01:00..Mon 02:00 minute range.
        let a = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 6 * 1440 + 22 * 60, durationMinutes: 4 * 60)
        let b = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 1 * 60, durationMinutes: 2 * 60)
        XCTAssertTrue(a.overlaps(b))
        XCTAssertTrue(b.overlaps(a))

        // A wrap-tail-only interval that does NOT overlap the non-wrap interval.
        // `c` does not wrap: Mon 03:00 → Mon 05:00 (after `a`'s wrap tail ends at 02:00)
        let c = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 3 * 60, durationMinutes: 2 * 60)
        XCTAssertFalse(a.overlaps(c))
        XCTAssertFalse(c.overlaps(a))
    }

    // MARK: - Derived day/time

    func testStartDayOfWeekAndTime() {
        // Wed = day 2 (Mon-origin), 14:30
        let mow = 2 * 1440 + 14 * 60 + 30
        let interval = FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: 60)
        XCTAssertEqual(interval.startDayOfWeek, .wednesday)
        XCTAssertEqual(interval.startHour, 14)
        XCTAssertEqual(interval.startMinute, 30)
    }

    func testEndDayOfWeekAndTimeForWrappingInterval() {
        // Fri 22:00 → Sat 02:00
        let mow = 4 * 1440 + 22 * 60
        let interval = FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: 4 * 60)
        XCTAssertEqual(interval.startDayOfWeek, .friday)
        XCTAssertEqual(interval.endDayOfWeek, .saturday)
        XCTAssertEqual(interval.endHour, 2)
        XCTAssertEqual(interval.endMinute, 0)
        XCTAssertTrue(interval.wrapsWeekBoundary == false) // wraps a day, not the week
    }

    func testWrapsWeekBoundary() {
        // Sun 22:00 → Mon 02:00 (wraps the week edge)
        let mow = 6 * 1440 + 22 * 60
        let interval = FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: 4 * 60)
        XCTAssertTrue(interval.wrapsWeekBoundary)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 1234, durationMinutes: 567)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FreeTimeInterval.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
