import XCTest
@testable import Intentions

final class ScheduleSnapshotTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private func mondayMidnightUTC() -> Date {
        // 2024-01-01 was a Monday in UTC. Use it as a stable Monday 00:00 UTC anchor.
        var c = DateComponents()
        c.timeZone = utc
        c.year = 2024; c.month = 1; c.day = 1
        c.hour = 0; c.minute = 0; c.second = 0
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - isFreeTime / isBlocking

    func test_disabledSchedule_isBlockingFalse_isFreeTimeTrue() {
        let snap = ScheduleSnapshot(isEnabled: false, intervals: [], timeZoneIdentifier: utc.identifier)
        let now = mondayMidnightUTC()
        XCTAssertFalse(snap.isBlocking(at: now))
        XCTAssertTrue(snap.isFreeTime(at: now))
    }

    func test_enabledNoIntervals_isAlwaysBlocking() {
        let snap = ScheduleSnapshot(isEnabled: true, intervals: [], timeZoneIdentifier: utc.identifier)
        XCTAssertTrue(snap.isBlocking(at: mondayMidnightUTC()))
    }

    func test_singleMondayMorningInterval_isFreeOnlyDuringWindow() {
        // Free 09:00–11:00 Monday only.
        let snap = ScheduleSnapshot(
            isEnabled: true,
            intervals: [.init(startMinuteOfWeek: 9 * 60, durationMinutes: 120)],
            timeZoneIdentifier: utc.identifier
        )
        let monday = mondayMidnightUTC()

        XCTAssertFalse(snap.isFreeTime(at: monday.addingTimeInterval(8 * 3600)))   // 08:00 Mon
        XCTAssertTrue(snap.isFreeTime(at: monday.addingTimeInterval(9 * 3600)))    // 09:00 Mon
        XCTAssertTrue(snap.isFreeTime(at: monday.addingTimeInterval(10 * 3600)))   // 10:00 Mon
        XCTAssertFalse(snap.isFreeTime(at: monday.addingTimeInterval(11 * 3600)))  // 11:00 Mon (exclusive end)
        XCTAssertFalse(snap.isFreeTime(at: monday.addingTimeInterval(24 * 3600 + 9 * 3600))) // 09:00 Tue
    }

    // MARK: - nextBoundary

    func test_nextBoundary_disabled_returnsNil() {
        let snap = ScheduleSnapshot(isEnabled: false, intervals: [], timeZoneIdentifier: utc.identifier)
        XCTAssertNil(snap.nextBoundary(after: mondayMidnightUTC()))
    }

    func test_nextBoundary_alwaysBlocking_returnsNil() {
        let snap = ScheduleSnapshot(isEnabled: true, intervals: [], timeZoneIdentifier: utc.identifier)
        XCTAssertNil(snap.nextBoundary(after: mondayMidnightUTC()))
    }

    func test_nextBoundary_alwaysFree_returnsNil() {
        let snap = ScheduleSnapshot(
            isEnabled: true,
            intervals: [.init(startMinuteOfWeek: 0, durationMinutes: ScheduleSnapshot.minutesPerWeek)],
            timeZoneIdentifier: utc.identifier
        )
        XCTAssertNil(snap.nextBoundary(after: mondayMidnightUTC()))
    }

    func test_nextBoundary_fromBlockingIntoFree_returnsStartOfWindow() {
        // Free 09:00–11:00 Monday only. From 08:00 Monday, next boundary is 09:00 Mon.
        let snap = ScheduleSnapshot(
            isEnabled: true,
            intervals: [.init(startMinuteOfWeek: 9 * 60, durationMinutes: 120)],
            timeZoneIdentifier: utc.identifier
        )
        let monday = mondayMidnightUTC()
        let from = monday.addingTimeInterval(8 * 3600)
        let expected = monday.addingTimeInterval(9 * 3600)
        XCTAssertEqual(snap.nextBoundary(after: from), expected)
    }

    func test_nextBoundary_fromFreeIntoBlocking_returnsEndOfWindow() {
        // From 10:00 Monday during a 09:00–11:00 free window, next boundary = 11:00.
        let snap = ScheduleSnapshot(
            isEnabled: true,
            intervals: [.init(startMinuteOfWeek: 9 * 60, durationMinutes: 120)],
            timeZoneIdentifier: utc.identifier
        )
        let monday = mondayMidnightUTC()
        let from = monday.addingTimeInterval(10 * 3600)
        let expected = monday.addingTimeInterval(11 * 3600)
        XCTAssertEqual(snap.nextBoundary(after: from), expected)
    }

    func test_nextBoundary_skipsToNextWeekIfNoIntervalThisWeek() {
        // Free only on Sunday 10:00–11:00. From Sunday 12:00, boundary is next Monday's
        // schedule — actually the window itself the following Sunday.
        let sundayMOW = 6 * ScheduleSnapshot.minutesPerDay + 10 * 60
        let snap = ScheduleSnapshot(
            isEnabled: true,
            intervals: [.init(startMinuteOfWeek: sundayMOW, durationMinutes: 60)],
            timeZoneIdentifier: utc.identifier
        )
        let monday = mondayMidnightUTC()
        let sundayNoon = monday.addingTimeInterval(6 * 24 * 3600 + 12 * 3600)
        let nextSunday10 = monday.addingTimeInterval(13 * 24 * 3600 + 10 * 3600)
        XCTAssertEqual(snap.nextBoundary(after: sundayNoon), nextSunday10)
    }
}
