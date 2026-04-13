import XCTest
@testable import Intentions

@MainActor
final class WeeklyScheduleTests: XCTestCase {

    // MARK: - Test helpers

    /// 2024-01-01 is a Monday — offsets from there give deterministic weekdays.
    private func date(weekday: Weekday, hour: Int, minute: Int = 0) -> Date {
        let offset = FreeTimeInterval.mondayDayIndex(for: weekday)
        let calendar = Calendar.current
        let monday = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let day = calendar.date(byAdding: .day, value: offset, to: monday)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func interval(start day: Weekday, _ hour: Int, duration minutes: Int) -> FreeTimeInterval {
        let mow = FreeTimeInterval.mondayDayIndex(for: day) * 1440 + hour * 60
        return FreeTimeInterval(id: UUID(), startMinuteOfWeek: mow, durationMinutes: minutes)
    }

    // MARK: - isFreeTime

    func testIsFreeTimeWithSingleWeekdayInterval() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)] // Mon 09:00-17:00

        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .monday, hour: 10)))
        XCTAssertFalse(schedule.isFreeTime(at: date(weekday: .monday, hour: 18)))
        XCTAssertFalse(schedule.isFreeTime(at: date(weekday: .tuesday, hour: 10)))
    }

    func testIsFreeTimeWithWrappingInterval() {
        let schedule = WeeklySchedule()
        // Fri 22:00 → Sat 02:00
        schedule.intervals = [interval(start: .friday, 22, duration: 4 * 60)]

        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .friday, hour: 23)))
        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .saturday, hour: 1)))
        XCTAssertFalse(schedule.isFreeTime(at: date(weekday: .saturday, hour: 3)))
    }

    func testIsFreeTimeWhenDisabled() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 0, duration: 10080)] // all week
        schedule.isEnabled = false

        // Disabled schedule means blocking is off entirely — treat as "always free"
        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .monday, hour: 12)))
    }

    // MARK: - isBlocking

    func testIsBlockingIsInverseOfIsFreeTimeWhenEnabled() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)]

        XCTAssertFalse(schedule.isBlocking(at: date(weekday: .monday, hour: 10)))
        XCTAssertTrue(schedule.isBlocking(at: date(weekday: .monday, hour: 18)))
    }

    func testIsBlockingWhenDisabled() {
        let schedule = WeeklySchedule()
        schedule.isEnabled = false
        schedule.intervals = []
        XCTAssertFalse(schedule.isBlocking(at: date(weekday: .monday, hour: 10)))
    }

    // MARK: - protectedMinutes

    func testProtectedMinutesDaytimeWindow() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)] // Mon 09-17

        // Mon 20:00: 9h blocked morning + 3h blocked evening = 12h = 720
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .monday, hour: 20)), 12 * 60)
        // Mon 08:00: all 8h of morning blocked
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .monday, hour: 8)), 8 * 60)
        // Mon 12:00 (inside free window): 9h protected so far
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .monday, hour: 12)), 9 * 60)
    }

    func testProtectedMinutesOnDayWithNoFreeTime() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)]
        // Tuesday has no free time → entire elapsed day is blocked
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .tuesday, hour: 12)), 12 * 60)
    }

    // MARK: - nextBoundary

    func testNextBoundaryReturnsStartOfNextInterval() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)] // Mon 09-17

        let now = date(weekday: .monday, hour: 8)
        let next = schedule.nextBoundary(after: now)
        XCTAssertEqual(next, date(weekday: .monday, hour: 9))
    }

    func testNextBoundaryReturnsEndOfCurrentInterval() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)]

        let now = date(weekday: .monday, hour: 12)
        let next = schedule.nextBoundary(after: now)
        XCTAssertEqual(next, date(weekday: .monday, hour: 17))
    }

    func testNextBoundaryWrapsToFollowingWeek() {
        let schedule = WeeklySchedule()
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)]

        // Sun 20:00: no boundary left this week after this moment; wrap to next Mon 09:00
        let now = date(weekday: .sunday, hour: 20)
        let next = schedule.nextBoundary(after: now)
        XCTAssertNotNil(next)
        // The wrapped boundary should be 7 days − (19h) = 6 days 5h away approximately.
        // Easier assertion: the wall-clock hour of the returned date is 9.
        let hour = Calendar.current.component(.hour, from: next!)
        XCTAssertEqual(hour, 9)
    }

    func testNextBoundaryReturnsNilWhenDisabled() {
        let schedule = WeeklySchedule()
        schedule.isEnabled = false
        schedule.intervals = [interval(start: .monday, 9, duration: 8 * 60)]
        XCTAssertNil(schedule.nextBoundary(after: date(weekday: .monday, hour: 10)))
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = WeeklySchedule()
        original.intervals = [
            interval(start: .monday, 9, duration: 8 * 60),
            interval(start: .friday, 22, duration: 4 * 60)
        ]
        original.intentionQuote = "Test"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WeeklySchedule.self, from: data)
        XCTAssertEqual(decoded.intervals.count, 2)
        XCTAssertEqual(decoded.intentionQuote, "Test")
        XCTAssertEqual(decoded.isEnabled, true)
    }
}
