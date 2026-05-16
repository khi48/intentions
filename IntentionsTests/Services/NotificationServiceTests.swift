//
//  NotificationServiceTests.swift
//  IntentionsTests
//
//  Tests for the pure spec-builder fn that produces free-time end notifications
//  from a (schedule, settings) input. Per #24: no UNUserNotificationCenter
//  contact — the builder is static + side-effect free so it can be unit-tested
//  without permissions or a notification-center fake.
//

import XCTest
@preconcurrency import UserNotifications
@testable import Intentions

@MainActor
final class NotificationServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Interval starting Monday 09:00 with the given duration.
    /// Monday-zero day index 0; 9*60 = 540 minutes into the week.
    private func mondayInterval(durationMinutes: Int, id: UUID = UUID()) -> FreeTimeInterval {
        FreeTimeInterval(id: id, startMinuteOfWeek: 9 * 60, durationMinutes: durationMinutes)
    }

    /// A NotificationSettings with explicit warning intervals.
    private func settings(
        master: Bool = true,
        warnings: Bool = true,
        completion: Bool = true,
        warningIntervals: [Int] = [1]
    ) -> NotificationSettings {
        var s = NotificationSettings()
        s.isEnabled = master
        s.sessionWarningsEnabled = warnings
        s.sessionCompletionEnabled = completion
        s.warningIntervals = warningIntervals
        return s
    }

    private var utc: TimeZone { TimeZone(identifier: "UTC")! }

    // MARK: - Gating: master / sub-toggles / schedule.isEnabled

    func testReturnsEmptyWhenMasterDisabled() {
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [mondayInterval(durationMinutes: 120)],
            timeZone: utc,
            settings: settings(master: false)
        )
        XCTAssertEqual(requests, [])
    }

    func testReturnsEmptyWhenScheduleDisabled() {
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: false,
            intervals: [mondayInterval(durationMinutes: 120)],
            timeZone: utc,
            settings: settings()
        )
        XCTAssertEqual(requests, [])
    }

    func testReturnsEmptyWhenBothSubTogglesOff() {
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [mondayInterval(durationMinutes: 120)],
            timeZone: utc,
            settings: settings(warnings: false, completion: false)
        )
        XCTAssertEqual(requests, [])
    }

    func testReturnsEmptyWhenNoIntervals() {
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [],
            timeZone: utc,
            settings: settings()
        )
        XCTAssertEqual(requests, [])
    }

    // MARK: - Identifier shape + count

    func testProducesOneWarningAndOneCompletionPerInterval() {
        let id = UUID()
        let interval = mondayInterval(durationMinutes: 120, id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(warningIntervals: [1])
        )

        XCTAssertEqual(requests.count, 2)
        let ids = Set(requests.map(\.identifier))
        XCTAssertTrue(ids.contains("freetime_warning_\(id.uuidString)_1min"))
        XCTAssertTrue(ids.contains("freetime_completion_\(id.uuidString)"))
    }

    func testWarningOnlyWhenCompletionOff() {
        let id = UUID()
        let interval = mondayInterval(durationMinutes: 120, id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(completion: false, warningIntervals: [1])
        )

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.identifier, "freetime_warning_\(id.uuidString)_1min")
    }

    func testCompletionOnlyWhenWarningOff() {
        let id = UUID()
        let interval = mondayInterval(durationMinutes: 120, id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(warnings: false, warningIntervals: [1])
        )

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.identifier, "freetime_completion_\(id.uuidString)")
    }

    func testMultipleWarningIntervalsProduceMultipleWarnings() {
        let id = UUID()
        let interval = mondayInterval(durationMinutes: 120, id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(warningIntervals: [10, 5, 1])
        )

        // 3 warnings + 1 completion
        XCTAssertEqual(requests.count, 4)
        let warningIds = requests.map(\.identifier).filter { $0.hasPrefix("freetime_warning_") }
        XCTAssertEqual(Set(warningIds), Set([
            "freetime_warning_\(id.uuidString)_10min",
            "freetime_warning_\(id.uuidString)_5min",
            "freetime_warning_\(id.uuidString)_1min",
        ]))
    }

    func testMultipleIntervalsProduceCartesianProduct() {
        let a = mondayInterval(durationMinutes: 120)
        let b = FreeTimeInterval(id: UUID(), startMinuteOfWeek: 17 * 60, durationMinutes: 60)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [a, b],
            timeZone: utc,
            settings: settings(warningIntervals: [1])
        )

        // 2 intervals × (1 warning + 1 completion) = 4
        XCTAssertEqual(requests.count, 4)
    }

    // MARK: - Skip short windows for warning, keep completion

    func testSkipsWarningWhenWindowEqualsWarningOffset() {
        // 1-minute window with a 1-minute warning would fire at the window
        // start, which is meaningless — skip.
        let id = UUID()
        let interval = mondayInterval(durationMinutes: 1, id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(warningIntervals: [1])
        )

        // Only the completion survives.
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.identifier, "freetime_completion_\(id.uuidString)")
    }

    func testSkipsWarningWhenWindowShorterThanWarningOffset() {
        let id = UUID()
        let interval = mondayInterval(durationMinutes: 3, id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(warningIntervals: [5])
        )

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.identifier, "freetime_completion_\(id.uuidString)")
    }

    func testSkipsOnlyTheTooLongWarningsKeepsTheShorterOnes() {
        // 4-minute window with [10, 5, 1]: 10 and 5 skip (>=4), 1 fits.
        let id = UUID()
        let interval = mondayInterval(durationMinutes: 4, id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(warningIntervals: [10, 5, 1])
        )

        // 1-min warning + completion
        XCTAssertEqual(requests.count, 2)
        let warningIds = requests.map(\.identifier).filter { $0.hasPrefix("freetime_warning_") }
        XCTAssertEqual(warningIds, ["freetime_warning_\(id.uuidString)_1min"])
    }

    // MARK: - Body strings + completion copy

    func testWarningBodyDefaultMinute() {
        let interval = mondayInterval(durationMinutes: 120)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(warningIntervals: [1])
        )

        let warning = requests.first { $0.identifier.hasPrefix("freetime_warning_") }
        XCTAssertEqual(warning?.content.title, "Free Time Ending Soon")
        XCTAssertEqual(warning?.content.body, "1 minute left of free time")
    }

    func testWarningBodyPluralisesAboveOne() {
        let interval = mondayInterval(durationMinutes: 120)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(warningIntervals: [5])
        )

        let warning = requests.first { $0.identifier.hasPrefix("freetime_warning_") }
        XCTAssertEqual(warning?.content.body, "5 minutes left of free time")
    }

    func testCompletionCopy() {
        let interval = mondayInterval(durationMinutes: 120)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings()
        )

        let completion = requests.first { $0.identifier.hasPrefix("freetime_completion_") }
        XCTAssertEqual(completion?.content.title, "Free Time Ended")
        XCTAssertEqual(completion?.content.body, "Apps are now blocked again.")
    }

    // MARK: - Trigger shape (DateComponents, repeats:true, timeZone)

    func testCompletionTriggerFiresAtIntervalEndWithScheduleTimeZone() throws {
        // Monday 09:00 + 120 minutes → ends Monday 11:00 (Foundation weekday 2).
        let interval = mondayInterval(durationMinutes: 120)
        let nzst = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: nzst,
            settings: settings(completion: true, warnings: false, warningIntervals: [1])
        )

        let completion = try XCTUnwrap(requests.first { $0.identifier.hasPrefix("freetime_completion_") })
        let trigger = try XCTUnwrap(completion.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)

        let components = trigger.dateComponents
        XCTAssertEqual(components.weekday, 2) // Monday
        XCTAssertEqual(components.hour, 11)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
        XCTAssertEqual(components.timeZone, nzst)
    }

    func testWarningTriggerFiresWarningMinutesBeforeEnd() throws {
        // Monday 09:00 + 120min → ends Mon 11:00. 1-min warning at Mon 10:59.
        let interval = mondayInterval(durationMinutes: 120)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(warningIntervals: [1])
        )

        let warning = try XCTUnwrap(requests.first { $0.identifier.hasPrefix("freetime_warning_") })
        let trigger = try XCTUnwrap(warning.trigger as? UNCalendarNotificationTrigger)
        let comps = trigger.dateComponents
        XCTAssertEqual(comps.weekday, 2)
        XCTAssertEqual(comps.hour, 10)
        XCTAssertEqual(comps.minute, 59)
    }

    func testWarningTriggerWrapsBackwardsAcrossDayBoundary() throws {
        // Monday 00:30 + 60min → ends Mon 01:30. 60-min warning at Mon 00:30.
        // That's also the interval START, which the "skip if duration <= warning"
        // guard catches — assert no warning was produced for this case.
        let id = UUID()
        let interval = FreeTimeInterval(id: id, startMinuteOfWeek: 30, durationMinutes: 60)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(warningIntervals: [60])
        )

        XCTAssertNil(requests.first { $0.identifier.hasPrefix("freetime_warning_") })
        XCTAssertNotNil(requests.first { $0.identifier == "freetime_completion_\(id.uuidString)" })
    }

    func testCompletionAtMidnightProducesCorrectComponents() throws {
        // Interval ending exactly at Tuesday 00:00 — minute-of-week = 1*1440 = 1440.
        // End minute-of-week wraps to 1440 (Tuesday 00:00, weekday=3).
        let id = UUID()
        let interval = FreeTimeInterval(id: id, startMinuteOfWeek: 23 * 60, durationMinutes: 60)
        // ends at minute-of-week 24*60 = 1440 → Tuesday 00:00 (weekday 3).
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(completion: true, warnings: false, warningIntervals: [1])
        )

        let completion = try XCTUnwrap(requests.first { $0.identifier == "freetime_completion_\(id.uuidString)" })
        let trigger = try XCTUnwrap(completion.trigger as? UNCalendarNotificationTrigger)
        let comps = trigger.dateComponents
        XCTAssertEqual(comps.weekday, 3) // Tuesday
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }

    func testCompletionForSundayLateInterval() throws {
        // Sunday is Monday-zero=6 → Foundation weekday=1.
        // Sunday 22:00 + 60min → ends Sunday 23:00, weekday=1.
        let id = UUID()
        let sundayStart = 6 * FreeTimeInterval.minutesPerDay + 22 * 60
        let interval = FreeTimeInterval(id: id, startMinuteOfWeek: sundayStart, durationMinutes: 60)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            intervals: [interval],
            timeZone: utc,
            settings: settings(completion: true, warnings: false, warningIntervals: [1])
        )

        let completion = try XCTUnwrap(requests.first { $0.identifier == "freetime_completion_\(id.uuidString)" })
        let trigger = try XCTUnwrap(completion.trigger as? UNCalendarNotificationTrigger)
        let comps = trigger.dateComponents
        XCTAssertEqual(comps.weekday, 1) // Sunday
        XCTAssertEqual(comps.hour, 23)
        XCTAssertEqual(comps.minute, 0)
    }

    // MARK: - dateComponents(forMinuteOfWeek:timeZone:) — unit test the inverse

    func testDateComponentsMondayMidnight() {
        let c = NotificationService.dateComponents(forMinuteOfWeek: 0, timeZone: utc)
        XCTAssertEqual(c.weekday, 2)   // Monday
        XCTAssertEqual(c.hour, 0)
        XCTAssertEqual(c.minute, 0)
        XCTAssertEqual(c.second, 0)
        XCTAssertEqual(c.timeZone, utc)
    }

    func testDateComponentsSaturdayLastMinute() {
        // Sat = Monday-zero 5. 5*1440 + 23*60 + 59 = 8639. Foundation weekday=7.
        let c = NotificationService.dateComponents(forMinuteOfWeek: 5 * 1440 + 23 * 60 + 59, timeZone: utc)
        XCTAssertEqual(c.weekday, 7)
        XCTAssertEqual(c.hour, 23)
        XCTAssertEqual(c.minute, 59)
    }

    func testDateComponentsSundayMidday() {
        // Sun = Monday-zero 6 → Foundation weekday 1.
        let c = NotificationService.dateComponents(forMinuteOfWeek: 6 * 1440 + 12 * 60, timeZone: utc)
        XCTAssertEqual(c.weekday, 1)
        XCTAssertEqual(c.hour, 12)
        XCTAssertEqual(c.minute, 0)
    }

    func testDateComponentsNormalisesNegative() {
        // (0 - 1 + 10080) % 10080 = 10079 → Sunday 23:59.
        let c = NotificationService.dateComponents(forMinuteOfWeek: 10079, timeZone: utc)
        XCTAssertEqual(c.weekday, 1) // Sunday
        XCTAssertEqual(c.hour, 23)
        XCTAssertEqual(c.minute, 59)
    }

    // MARK: - R3 mutex teardown banner (#27) — pure spec-builder

    func testTerminatedByFreeTimeReturnsNilWhenMasterDisabled() {
        let request = NotificationService.sessionTerminatedByFreeTimeRequest(
            settings: settings(master: false)
        )
        XCTAssertNil(request)
    }

    func testTerminatedByFreeTimeReturnsNilWhenCompletionDisabled() {
        let request = NotificationService.sessionTerminatedByFreeTimeRequest(
            settings: settings(completion: false)
        )
        XCTAssertNil(request)
    }

    func testTerminatedByFreeTimeIgnoresWarningToggle() {
        // Warning toggle off should NOT silence the teardown — it's a completion-class event.
        let request = NotificationService.sessionTerminatedByFreeTimeRequest(
            settings: settings(warnings: false, completion: true)
        )
        XCTAssertNotNil(request)
    }

    func testTerminatedByFreeTimeBuildsRequestWhenEnabled() {
        let request = NotificationService.sessionTerminatedByFreeTimeRequest(settings: settings())
        XCTAssertNotNil(request)

        XCTAssertEqual(request?.identifier, "session_terminated_by_freetime")
        XCTAssertEqual(request?.identifier, NotificationService.sessionTerminatedByFreeTimeIdentifier)
        XCTAssertEqual(request?.content.title, "Session Ended")
        XCTAssertEqual(request?.content.body, "Free time started — your session ended.")
        XCTAssertEqual(request?.content.categoryIdentifier, NotificationType.sessionCompletion.rawValue)
        XCTAssertNotNil(request?.content.sound)
    }

    func testTerminatedByFreeTimeTriggerIsImmediateNonRepeating() {
        let request = NotificationService.sessionTerminatedByFreeTimeRequest(settings: settings())
        let trigger = request?.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertNotNil(trigger)
        XCTAssertFalse(trigger?.repeats ?? true)
        XCTAssertEqual(trigger?.timeInterval, 1.0)
    }
}
