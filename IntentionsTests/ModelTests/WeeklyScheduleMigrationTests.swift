import XCTest
@testable import Intentions

@MainActor
final class WeeklyScheduleMigrationTests: XCTestCase {

    func testMigrateWeekdaysOnlyDaytimeWindow() {
        let old = ScheduleSettings()
        old.isEnabled = true
        old.startHour = 9
        old.startMinute = 0
        old.endHour = 17
        old.endMinute = 0
        old.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]

        let new = WeeklySchedule.migrate(from: old)

        XCTAssertTrue(new.isEnabled)
        XCTAssertEqual(new.intervals.count, 5)

        for interval in new.intervals {
            XCTAssertEqual(interval.durationMinutes, 8 * 60)
            XCTAssertEqual(interval.startHour, 9)
            XCTAssertEqual(interval.startMinute, 0)
        }
        let days = Set(new.intervals.map { $0.startDayOfWeek })
        XCTAssertEqual(days, [.monday, .tuesday, .wednesday, .thursday, .friday])
    }

    func testMigrateAllDaysDaytimeWindow() {
        let old = ScheduleSettings()
        old.startHour = 17
        old.startMinute = 0
        old.endHour = 21
        old.endMinute = 30
        old.activeDays = Set(Weekday.allCases)

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intervals.count, 7)
        XCTAssertTrue(new.intervals.allSatisfy { $0.durationMinutes == 4 * 60 + 30 })
    }

    func testMigrateOvernightWindowProducesOvernightPerDay() {
        let old = ScheduleSettings()
        old.startHour = 22
        old.startMinute = 0
        old.endHour = 6
        old.endMinute = 0
        old.activeDays = [.friday]

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intervals.count, 1)
        let i = new.intervals[0]
        XCTAssertEqual(i.startDayOfWeek, .friday)
        XCTAssertEqual(i.startHour, 22)
        XCTAssertEqual(i.durationMinutes, 8 * 60)
        XCTAssertEqual(i.endDayOfWeek, .saturday)
        XCTAssertEqual(i.endHour, 6)
    }

    func testMigrateDisabledScheduleCarriesFlag() {
        let old = ScheduleSettings()
        old.isEnabled = false
        old.activeDays = [.monday]
        old.startHour = 9
        old.endHour = 17

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertFalse(new.isEnabled)
        XCTAssertEqual(new.intervals.count, 1)
    }

    func testMigrateEmptyActiveDaysProducesNoIntervals() {
        let old = ScheduleSettings()
        old.activeDays = []
        old.startHour = 9
        old.endHour = 17

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intervals.count, 0)
    }

    func testMigratePreservesIntentionQuoteAndLastDisabledAt() {
        let old = ScheduleSettings()
        old.activeDays = [.monday]
        old.startHour = 9
        old.endHour = 17
        old.intentionQuote = "Be present"
        old.lastDisabledAt = Date(timeIntervalSince1970: 1_700_000_000)

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intentionQuote, "Be present")
        XCTAssertEqual(new.lastDisabledAt, Date(timeIntervalSince1970: 1_700_000_000))
    }
}
