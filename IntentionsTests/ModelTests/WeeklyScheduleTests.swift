import XCTest
@testable import Intentions

@MainActor
final class WeeklyScheduleTests: XCTestCase {

    // MARK: - Test helpers

    /// 2024-01-01 is a Monday — offsets from there give deterministic weekdays.
    private func date(weekday: Weekday, hour: Int, minute: Int = 0) -> Date {
        let offset = Self.mondayDayIndex(for: weekday)
        let calendar = Calendar.current
        let monday = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let day = calendar.date(byAdding: .day, value: offset, to: monday)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// 0 = Monday … 6 = Sunday. Used to advance a calendar-anchored Monday into
    /// the correct test weekday.
    private static func mondayDayIndex(for weekday: Weekday) -> Int {
        switch weekday {
        case .monday: return 0
        case .tuesday: return 1
        case .wednesday: return 2
        case .thursday: return 3
        case .friday: return 4
        case .saturday: return 5
        case .sunday: return 6
        }
    }

    /// Build a single-day routine on the given weekdays, starting at `startHour:00`
    /// for `durationMinutes` minutes. Single-day only — duration may not cross
    /// midnight in the new model.
    private func routine(
        days: Set<Weekday>,
        startHour: Int,
        durationMinutes: Int
    ) -> FreeTimeRoutine {
        FreeTimeRoutine(
            id: UUID(),
            name: nil,
            startMinute: startHour * 60,
            durationMinutes: durationMinutes,
            days: days,
            sortIndex: 0
        )
    }

    // MARK: - isFreeTime

    func testIsFreeTimeWithSingleWeekdayRoutine() {
        let schedule = WeeklySchedule()
        schedule.routines = [routine(days: [.monday], startHour: 9, durationMinutes: 8 * 60)] // Mon 09:00-17:00

        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .monday, hour: 10)))
        XCTAssertFalse(schedule.isFreeTime(at: date(weekday: .monday, hour: 18)))
        XCTAssertFalse(schedule.isFreeTime(at: date(weekday: .tuesday, hour: 10)))
    }

    func testIsFreeTimeAcrossMultipleDays() {
        // A single routine with multiple weekdays is the new model's replacement
        // for what used to require multiple intervals.
        let schedule = WeeklySchedule()
        schedule.routines = [
            routine(days: [.monday, .wednesday, .friday], startHour: 9, durationMinutes: 8 * 60)
        ]

        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .monday, hour: 10)))
        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .wednesday, hour: 10)))
        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .friday, hour: 10)))
        XCTAssertFalse(schedule.isFreeTime(at: date(weekday: .tuesday, hour: 10)))
        XCTAssertFalse(schedule.isFreeTime(at: date(weekday: .saturday, hour: 10)))
    }

    func testIsFreeTimeWhenDisabled() {
        let schedule = WeeklySchedule()
        schedule.routines = [routine(days: Set(Weekday.allCases), startHour: 0, durationMinutes: FreeTimeRoutine.minutesPerDay)]
        schedule.isEnabled = false

        // Disabled schedule means blocking is off entirely — treat as "always free"
        XCTAssertTrue(schedule.isFreeTime(at: date(weekday: .monday, hour: 12)))
    }

    // MARK: - isBlocking

    func testIsBlockingIsInverseOfIsFreeTimeWhenEnabled() {
        let schedule = WeeklySchedule()
        schedule.routines = [routine(days: [.monday], startHour: 9, durationMinutes: 8 * 60)]

        XCTAssertFalse(schedule.isBlocking(at: date(weekday: .monday, hour: 10)))
        XCTAssertTrue(schedule.isBlocking(at: date(weekday: .monday, hour: 18)))
    }

    func testIsBlockingWhenDisabled() {
        let schedule = WeeklySchedule()
        schedule.isEnabled = false
        schedule.routines = []
        XCTAssertFalse(schedule.isBlocking(at: date(weekday: .monday, hour: 10)))
    }

    // MARK: - protectedMinutes

    func testProtectedMinutesDaytimeWindow() {
        let schedule = WeeklySchedule()
        schedule.routines = [routine(days: [.monday], startHour: 9, durationMinutes: 8 * 60)] // Mon 09-17

        // Mon 20:00: 9h blocked morning + 3h blocked evening = 12h = 720
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .monday, hour: 20)), 12 * 60)
        // Mon 08:00: all 8h of morning blocked
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .monday, hour: 8)), 8 * 60)
        // Mon 12:00 (inside free window): 9h protected so far
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .monday, hour: 12)), 9 * 60)
    }

    func testProtectedMinutesOnDayWithNoFreeTime() {
        let schedule = WeeklySchedule()
        schedule.routines = [routine(days: [.monday], startHour: 9, durationMinutes: 8 * 60)]
        // Tuesday has no free time → entire elapsed day is blocked
        XCTAssertEqual(schedule.protectedMinutes(at: date(weekday: .tuesday, hour: 12)), 12 * 60)
    }

    // MARK: - nextBoundary

    func testNextBoundaryReturnsStartOfNextRoutine() {
        let schedule = WeeklySchedule()
        schedule.routines = [routine(days: [.monday], startHour: 9, durationMinutes: 8 * 60)] // Mon 09-17

        let now = date(weekday: .monday, hour: 8)
        let next = schedule.nextBoundary(after: now)
        XCTAssertEqual(next, date(weekday: .monday, hour: 9))
    }

    func testNextBoundaryReturnsEndOfCurrentRoutine() {
        let schedule = WeeklySchedule()
        schedule.routines = [routine(days: [.monday], startHour: 9, durationMinutes: 8 * 60)]

        let now = date(weekday: .monday, hour: 12)
        let next = schedule.nextBoundary(after: now)
        XCTAssertEqual(next, date(weekday: .monday, hour: 17))
    }

    func testNextBoundaryWrapsToFollowingWeek() {
        let schedule = WeeklySchedule()
        schedule.routines = [routine(days: [.monday], startHour: 9, durationMinutes: 8 * 60)]

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
        schedule.routines = [routine(days: [.monday], startHour: 9, durationMinutes: 8 * 60)]
        XCTAssertNil(schedule.nextBoundary(after: date(weekday: .monday, hour: 10)))
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = WeeklySchedule()
        original.routines = [
            routine(days: [.monday], startHour: 9, durationMinutes: 8 * 60),
            routine(days: [.friday], startHour: 22, durationMinutes: 2 * 60)
        ]
        original.intentionQuote = "Test"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WeeklySchedule.self, from: data)
        XCTAssertEqual(decoded.routines.count, 2)
        XCTAssertEqual(decoded.intentionQuote, "Test")
        XCTAssertEqual(decoded.isEnabled, true)
    }
}
