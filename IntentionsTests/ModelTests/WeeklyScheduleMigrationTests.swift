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

    // MARK: - v1.0 build 1 inverted migration

    /// v1 user blocked work hours 9-17 Mon-Fri (inclusive). Free time should be
    /// 0:00-9:00 + 18:00-24:00 on Mon-Fri, and full days Sat-Sun.
    func testMigrateLegacyV1WorkHoursBlocking() {
        let old = ScheduleSettings()
        old.isEnabled = true
        old.startHour = 9
        old.endHour = 17
        old.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        old.wasLegacyV1Format = true

        let new = WeeklySchedule.migrate(from: old)

        // 5 weekdays × 2 segments + 2 weekend days × 1 full-day segment = 12 intervals
        XCTAssertEqual(new.intervals.count, 12)

        let mondayIntervals = new.intervals.filter { $0.startDayOfWeek == .monday }
        XCTAssertEqual(mondayIntervals.count, 2)

        let preBlockMonday = mondayIntervals.first { $0.startHour == 0 }
        XCTAssertNotNil(preBlockMonday)
        XCTAssertEqual(preBlockMonday?.durationMinutes, 9 * 60)

        let postBlockMonday = mondayIntervals.first { $0.startHour == 18 }
        XCTAssertNotNil(postBlockMonday)
        XCTAssertEqual(postBlockMonday?.durationMinutes, 6 * 60)

        let saturdayIntervals = new.intervals.filter { $0.startDayOfWeek == .saturday }
        XCTAssertEqual(saturdayIntervals.count, 1)
        XCTAssertEqual(saturdayIntervals.first?.durationMinutes, FreeTimeInterval.minutesPerDay)
        XCTAssertEqual(saturdayIntervals.first?.startHour, 0)
    }

    /// v1 user with blocking starting at midnight (startHour == 0): no pre-blocking
    /// free segment, only post-blocking. Verify off-by-one not emitted.
    func testMigrateLegacyV1BlockingFromMidnight() {
        let old = ScheduleSettings()
        old.startHour = 0
        old.endHour = 8
        old.activeDays = [.monday]
        old.wasLegacyV1Format = true

        let new = WeeklySchedule.migrate(from: old)

        let mondayIntervals = new.intervals.filter { $0.startDayOfWeek == .monday }
        XCTAssertEqual(mondayIntervals.count, 1)
        XCTAssertEqual(mondayIntervals.first?.startHour, 9)
        XCTAssertEqual(mondayIntervals.first?.durationMinutes, 15 * 60)
    }

    /// v1 user with blocking ending at hour 23 (last hour of day): only pre-blocking
    /// free segment, no post-blocking.
    func testMigrateLegacyV1BlockingUntilEndOfDay() {
        let old = ScheduleSettings()
        old.startHour = 17
        old.endHour = 23
        old.activeDays = [.monday]
        old.wasLegacyV1Format = true

        let new = WeeklySchedule.migrate(from: old)

        let mondayIntervals = new.intervals.filter { $0.startDayOfWeek == .monday }
        XCTAssertEqual(mondayIntervals.count, 1)
        XCTAssertEqual(mondayIntervals.first?.startHour, 0)
        XCTAssertEqual(mondayIntervals.first?.durationMinutes, 17 * 60)
    }

    /// v1 user with blocking all day every day: no free intervals at all.
    func testMigrateLegacyV1BlockingAllDayAllWeek() {
        let old = ScheduleSettings()
        old.startHour = 0
        old.endHour = 23
        old.activeDays = Set(Weekday.allCases)
        old.wasLegacyV1Format = true

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intervals.count, 0)
    }

    /// v1 user with empty activeDays: no day was ever blocked → all 7 days free.
    func testMigrateLegacyV1NoActiveDaysProducesFullWeekFreeTime() {
        let old = ScheduleSettings()
        old.startHour = 9
        old.endHour = 17
        old.activeDays = []
        old.wasLegacyV1Format = true

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intervals.count, 7)
        XCTAssertTrue(new.intervals.allSatisfy { $0.durationMinutes == FreeTimeInterval.minutesPerDay })
    }

    /// Sanity: post-v94 records (flag false) still use the faithful migration unchanged.
    func testMigrateNonLegacyDefaultsToFaithful() {
        let old = ScheduleSettings()
        old.startHour = 9
        old.endHour = 17
        old.activeDays = [.monday]
        old.wasLegacyV1Format = false

        let new = WeeklySchedule.migrate(from: old)
        XCTAssertEqual(new.intervals.count, 1)
        XCTAssertEqual(new.intervals.first?.startHour, 9)
        XCTAssertEqual(new.intervals.first?.durationMinutes, 8 * 60)
    }
}
