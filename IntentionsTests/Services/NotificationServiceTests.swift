//
//  NotificationServiceTests.swift
//  IntentionsTests
//
//  Tests for the pure spec-builder fn that produces free-time end notifications
//  from a (schedule, settings) input. Per #24: no UNUserNotificationCenter
//  contact — the builder is static + side-effect free so it can be unit-tested
//  without permissions or a notification-center fake.
//
//  After the FreeTimeRoutine migration: routines are single-day and recur on
//  the configured weekday set. The spec-builder emits one (warning + completion)
//  per routine × per weekday in `routine.days`.
//

import XCTest
@preconcurrency import UserNotifications
@testable import Intentions

@MainActor
final class NotificationServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Routine starting at 09:00 with the given duration on the supplied weekdays
    /// (default: Monday only). Produces a stable id when caller supplies one.
    private func morningRoutine(
        durationMinutes: Int,
        days: Set<Weekday> = [.monday],
        id: UUID = UUID()
    ) -> FreeTimeRoutine {
        FreeTimeRoutine(
            id: id,
            name: nil,
            startMinute: 9 * 60,
            durationMinutes: durationMinutes,
            days: days,
            sortIndex: 0
        )
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
            routines: [morningRoutine(durationMinutes: 120)],
            timeZone: utc,
            settings: settings(master: false)
        )
        XCTAssertEqual(requests, [])
    }

    func testReturnsEmptyWhenScheduleDisabled() {
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: false,
            routines: [morningRoutine(durationMinutes: 120)],
            timeZone: utc,
            settings: settings()
        )
        XCTAssertEqual(requests, [])
    }

    func testReturnsEmptyWhenBothSubTogglesOff() {
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [morningRoutine(durationMinutes: 120)],
            timeZone: utc,
            settings: settings(warnings: false, completion: false)
        )
        XCTAssertEqual(requests, [])
    }

    func testReturnsEmptyWhenNoRoutines() {
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [],
            timeZone: utc,
            settings: settings()
        )
        XCTAssertEqual(requests, [])
    }

    // MARK: - Identifier shape + per-day expansion

    func testProducesOneWarningAndOneCompletionPerRoutineDay() {
        let id = UUID()
        let routine = morningRoutine(durationMinutes: 120, days: [.monday], id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(warningIntervals: [1])
        )

        XCTAssertEqual(requests.count, 2)
        let ids = Set(requests.map(\.identifier))
        XCTAssertTrue(ids.contains("freetime_warning_\(id.uuidString)_\(Weekday.monday.rawValue)_1min"))
        XCTAssertTrue(ids.contains("freetime_completion_\(id.uuidString)_\(Weekday.monday.rawValue)"))
    }

    func testMultiDayRoutineExpandsPerDay() {
        // Mon+Wed+Fri × (1 warning + 1 completion) = 6 requests.
        let id = UUID()
        let routine = morningRoutine(durationMinutes: 120, days: [.monday, .wednesday, .friday], id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(warningIntervals: [1])
        )

        XCTAssertEqual(requests.count, 6)

        // Each weekday should produce its own warning + completion identifier.
        for day in [Weekday.monday, .wednesday, .friday] {
            let warningId = "freetime_warning_\(id.uuidString)_\(day.rawValue)_1min"
            let completionId = "freetime_completion_\(id.uuidString)_\(day.rawValue)"
            XCTAssertTrue(
                requests.contains(where: { $0.identifier == warningId }),
                "missing warning for \(day): \(warningId)"
            )
            XCTAssertTrue(
                requests.contains(where: { $0.identifier == completionId }),
                "missing completion for \(day): \(completionId)"
            )
        }
    }

    func testWarningOnlyWhenCompletionOff() {
        let id = UUID()
        let routine = morningRoutine(durationMinutes: 120, days: [.monday], id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(completion: false, warningIntervals: [1])
        )

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests.first?.identifier,
            "freetime_warning_\(id.uuidString)_\(Weekday.monday.rawValue)_1min"
        )
    }

    func testCompletionOnlyWhenWarningOff() {
        let id = UUID()
        let routine = morningRoutine(durationMinutes: 120, days: [.monday], id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(warnings: false, warningIntervals: [1])
        )

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests.first?.identifier,
            "freetime_completion_\(id.uuidString)_\(Weekday.monday.rawValue)"
        )
    }

    func testMultipleWarningIntervalsProduceMultipleWarnings() {
        let id = UUID()
        let routine = morningRoutine(durationMinutes: 120, days: [.monday], id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(warningIntervals: [10, 5, 1])
        )

        // 3 warnings + 1 completion
        XCTAssertEqual(requests.count, 4)
        let warningIds = requests.map(\.identifier).filter { $0.hasPrefix("freetime_warning_") }
        XCTAssertEqual(Set(warningIds), Set([
            "freetime_warning_\(id.uuidString)_\(Weekday.monday.rawValue)_10min",
            "freetime_warning_\(id.uuidString)_\(Weekday.monday.rawValue)_5min",
            "freetime_warning_\(id.uuidString)_\(Weekday.monday.rawValue)_1min",
        ]))
    }

    func testMultipleRoutinesProduceCartesianProduct() {
        let a = morningRoutine(durationMinutes: 120, days: [.monday])
        let b = FreeTimeRoutine(
            id: UUID(),
            name: nil,
            startMinute: 17 * 60,
            durationMinutes: 60,
            days: [.monday],
            sortIndex: 1
        )
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [a, b],
            timeZone: utc,
            settings: settings(warningIntervals: [1])
        )

        // 2 routines × 1 day each × (1 warning + 1 completion) = 4
        XCTAssertEqual(requests.count, 4)
    }

    // MARK: - Skip short windows for warning, keep completion

    func testSkipsWarningWhenWindowEqualsWarningOffset() {
        // 1-minute window with a 1-minute warning would fire at the window
        // start, which is meaningless — skip.
        let id = UUID()
        let routine = morningRoutine(durationMinutes: 1, days: [.monday], id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(warningIntervals: [1])
        )

        // Only the completion survives.
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests.first?.identifier,
            "freetime_completion_\(id.uuidString)_\(Weekday.monday.rawValue)"
        )
    }

    func testSkipsWarningWhenWindowShorterThanWarningOffset() {
        let id = UUID()
        let routine = morningRoutine(durationMinutes: 3, days: [.monday], id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(warningIntervals: [5])
        )

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests.first?.identifier,
            "freetime_completion_\(id.uuidString)_\(Weekday.monday.rawValue)"
        )
    }

    func testSkipsOnlyTheTooLongWarningsKeepsTheShorterOnes() {
        // 4-minute window with [10, 5, 1]: 10 and 5 skip (>=4), 1 fits.
        let id = UUID()
        let routine = morningRoutine(durationMinutes: 4, days: [.monday], id: id)
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(warningIntervals: [10, 5, 1])
        )

        // 1-min warning + completion
        XCTAssertEqual(requests.count, 2)
        let warningIds = requests.map(\.identifier).filter { $0.hasPrefix("freetime_warning_") }
        XCTAssertEqual(
            warningIds,
            ["freetime_warning_\(id.uuidString)_\(Weekday.monday.rawValue)_1min"]
        )
    }

    // MARK: - Body strings + completion copy

    func testWarningBodyDefaultMinute() {
        let routine = morningRoutine(durationMinutes: 120, days: [.monday])
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(warningIntervals: [1])
        )

        let warning = requests.first { $0.identifier.hasPrefix("freetime_warning_") }
        XCTAssertEqual(warning?.content.title, "Free Time Ending Soon")
        XCTAssertEqual(warning?.content.body, "1 minute left of free time")
    }

    func testWarningBodyPluralisesAboveOne() {
        let routine = morningRoutine(durationMinutes: 120, days: [.monday])
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(warningIntervals: [5])
        )

        let warning = requests.first { $0.identifier.hasPrefix("freetime_warning_") }
        XCTAssertEqual(warning?.content.body, "5 minutes left of free time")
    }

    func testCompletionCopy() {
        let routine = morningRoutine(durationMinutes: 120, days: [.monday])
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings()
        )

        let completion = requests.first { $0.identifier.hasPrefix("freetime_completion_") }
        XCTAssertEqual(completion?.content.title, "Free Time Ended")
        XCTAssertEqual(completion?.content.body, "Apps are now blocked again.")
    }

    // MARK: - Trigger shape (DateComponents, repeats:true, timeZone)

    func testCompletionTriggerFiresAtRoutineEndWithScheduleTimeZone() throws {
        // Monday 09:00 + 120 minutes → ends Monday 11:00 (Foundation weekday 2).
        let routine = morningRoutine(durationMinutes: 120, days: [.monday])
        let nzst = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
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
        let routine = morningRoutine(durationMinutes: 120, days: [.monday])
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
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

    func testWarningSkippedWhenWindowEqualsWarningInterval() throws {
        // Monday 00:30 + 60min → ends Mon 01:30. 60-min warning would land at
        // the routine start, so the "skip if duration <= warning" guard catches
        // it. Assert no warning, completion still present.
        let id = UUID()
        let routine = FreeTimeRoutine(
            id: id,
            name: nil,
            startMinute: 30,
            durationMinutes: 60,
            days: [.monday],
            sortIndex: 0
        )
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(warningIntervals: [60])
        )

        XCTAssertNil(requests.first { $0.identifier.hasPrefix("freetime_warning_") })
        XCTAssertNotNil(
            requests.first { $0.identifier == "freetime_completion_\(id.uuidString)_\(Weekday.monday.rawValue)" }
        )
    }

    func testCompletionAtMidnightRollsToNextWeekday() throws {
        // Routine ending exactly at midnight on Monday: end-of-day minute = 1440.
        // The trigger must roll into Tuesday 00:00 (Foundation weekday 3).
        let id = UUID()
        let routine = FreeTimeRoutine(
            id: id,
            name: nil,
            startMinute: 23 * 60,
            durationMinutes: 60,
            days: [.monday],
            sortIndex: 0
        )
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(completion: true, warnings: false, warningIntervals: [1])
        )

        let completion = try XCTUnwrap(
            requests.first { $0.identifier == "freetime_completion_\(id.uuidString)_\(Weekday.monday.rawValue)" }
        )
        let trigger = try XCTUnwrap(completion.trigger as? UNCalendarNotificationTrigger)
        let comps = trigger.dateComponents
        XCTAssertEqual(comps.weekday, 3) // Tuesday — rolled
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }

    func testCompletionForSundayLateRoutine() throws {
        // Sunday = Foundation weekday 1.
        // Sunday 22:00 + 60min → ends Sunday 23:00, weekday=1.
        let id = UUID()
        let routine = FreeTimeRoutine(
            id: id,
            name: nil,
            startMinute: 22 * 60,
            durationMinutes: 60,
            days: [.sunday],
            sortIndex: 0
        )
        let requests = NotificationService.freeTimeNotificationRequests(
            isScheduleEnabled: true,
            routines: [routine],
            timeZone: utc,
            settings: settings(completion: true, warnings: false, warningIntervals: [1])
        )

        let completion = try XCTUnwrap(
            requests.first { $0.identifier == "freetime_completion_\(id.uuidString)_\(Weekday.sunday.rawValue)" }
        )
        let trigger = try XCTUnwrap(completion.trigger as? UNCalendarNotificationTrigger)
        let comps = trigger.dateComponents
        XCTAssertEqual(comps.weekday, 1) // Sunday
        XCTAssertEqual(comps.hour, 23)
        XCTAssertEqual(comps.minute, 0)
    }

    // MARK: - dateComponents(weekday:minuteOfDay:timeZone:) — unit-test the helper

    func testDateComponentsMondayMidnight() {
        let c = NotificationService.dateComponents(weekday: .monday, minuteOfDay: 0, timeZone: utc)
        XCTAssertEqual(c.weekday, 2)   // Monday
        XCTAssertEqual(c.hour, 0)
        XCTAssertEqual(c.minute, 0)
        XCTAssertEqual(c.second, 0)
        XCTAssertEqual(c.timeZone, utc)
    }

    func testDateComponentsSaturdayLastMinute() {
        let c = NotificationService.dateComponents(weekday: .saturday, minuteOfDay: 23 * 60 + 59, timeZone: utc)
        XCTAssertEqual(c.weekday, 7) // Saturday
        XCTAssertEqual(c.hour, 23)
        XCTAssertEqual(c.minute, 59)
    }

    func testDateComponentsSundayMidday() {
        let c = NotificationService.dateComponents(weekday: .sunday, minuteOfDay: 12 * 60, timeZone: utc)
        XCTAssertEqual(c.weekday, 1) // Sunday
        XCTAssertEqual(c.hour, 12)
        XCTAssertEqual(c.minute, 0)
    }

    func testDateComponentsRollsAtMidnight() {
        // Monday end-of-day minute = 1440 → Tuesday 00:00.
        let c = NotificationService.dateComponents(weekday: .monday, minuteOfDay: 1440, timeZone: utc)
        XCTAssertEqual(c.weekday, 3) // Tuesday
        XCTAssertEqual(c.hour, 0)
        XCTAssertEqual(c.minute, 0)
    }

    func testDateComponentsRollsSaturdayMidnightToSunday() {
        // Saturday 1440 → Sunday 00:00. Saturday calendarWeekday=7, % 7 = 0,
        // + 1 = 1 → Sunday.
        let c = NotificationService.dateComponents(weekday: .saturday, minuteOfDay: 1440, timeZone: utc)
        XCTAssertEqual(c.weekday, 1) // Sunday
        XCTAssertEqual(c.hour, 0)
        XCTAssertEqual(c.minute, 0)
    }

    // MARK: - R3 mutex teardown banner (#30) — per-session pre-scheduled spec-builder

    private var fixedSessionId: UUID { UUID(uuidString: "12345678-1234-1234-1234-123456789012")! }

    func testTerminatedByFreeTimeReturnsNilWhenMasterDisabled() {
        let request = SessionEndNotification.sessionTerminatedByFreeTimeRequest(
            settings: settings(master: false),
            sessionId: fixedSessionId,
            triggerInterval: 600
        )
        XCTAssertNil(request)
    }

    func testTerminatedByFreeTimeReturnsNilWhenCompletionDisabled() {
        let request = SessionEndNotification.sessionTerminatedByFreeTimeRequest(
            settings: settings(completion: false),
            sessionId: fixedSessionId,
            triggerInterval: 600
        )
        XCTAssertNil(request)
    }

    func testTerminatedByFreeTimeIgnoresWarningToggle() {
        let request = SessionEndNotification.sessionTerminatedByFreeTimeRequest(
            settings: settings(warnings: false, completion: true),
            sessionId: fixedSessionId,
            triggerInterval: 600
        )
        XCTAssertNotNil(request)
    }

    func testTerminatedByFreeTimeReturnsNilWhenTriggerBelowOneSecond() {
        // UNTimeIntervalNotificationTrigger requires timeInterval >= 1.0; the
        // spec-builder must reject smaller values rather than crash at add-time.
        let request = SessionEndNotification.sessionTerminatedByFreeTimeRequest(
            settings: settings(),
            sessionId: fixedSessionId,
            triggerInterval: 0.5
        )
        XCTAssertNil(request)
    }

    func testTerminatedByFreeTimeIdentifierCarriesSessionId() {
        let sessionId = fixedSessionId
        let request = SessionEndNotification.sessionTerminatedByFreeTimeRequest(
            settings: settings(),
            sessionId: sessionId,
            triggerInterval: 600
        )

        XCTAssertEqual(request?.identifier, "session_terminated_by_freetime_\(sessionId.uuidString)")
        XCTAssertTrue(request?.identifier.hasPrefix(SessionEndNotification.sessionTerminatedByFreeTimeIdentifierPrefix) ?? false)
    }

    func testTerminatedByFreeTimeBuildsRequestWhenEnabled() {
        let request = SessionEndNotification.sessionTerminatedByFreeTimeRequest(
            settings: settings(),
            sessionId: fixedSessionId,
            triggerInterval: 600
        )
        XCTAssertNotNil(request)

        XCTAssertEqual(request?.content.title, "Session Ended")
        XCTAssertEqual(request?.content.body, "Free time started — your session ended.")
        XCTAssertEqual(request?.content.categoryIdentifier, NotificationType.sessionCompletion.rawValue)
        XCTAssertNotNil(request?.content.sound)
    }

    func testTerminatedByFreeTimeTriggerUsesPassedInterval() {
        let request = SessionEndNotification.sessionTerminatedByFreeTimeRequest(
            settings: settings(),
            sessionId: fixedSessionId,
            triggerInterval: 1234.5
        )
        let trigger = request?.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertNotNil(trigger)
        XCTAssertFalse(trigger?.repeats ?? true)
        XCTAssertEqual(trigger?.timeInterval, 1234.5)
    }

    func testTerminatedByFreeTimeIdentifierDiffersBySession() {
        let id1 = SessionEndNotification.sessionTerminatedByFreeTimeIdentifier(sessionId: UUID())
        let id2 = SessionEndNotification.sessionTerminatedByFreeTimeIdentifier(sessionId: UUID())
        XCTAssertNotEqual(id1, id2)
        XCTAssertTrue(id1.hasPrefix(SessionEndNotification.sessionTerminatedByFreeTimeIdentifierPrefix))
        XCTAssertTrue(id2.hasPrefix(SessionEndNotification.sessionTerminatedByFreeTimeIdentifierPrefix))
    }
}
