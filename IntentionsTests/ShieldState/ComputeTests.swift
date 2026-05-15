import XCTest
@preconcurrency import FamilyControls
@testable import Intentions

final class ComputeTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(endOffset: TimeInterval, apps: FamilyActivitySelection = .init()) -> Session {
        Session(apps: apps, startedAt: t0, endsAt: t0.addingTimeInterval(endOffset))
    }

    private func snapshot(enabled: Bool, freeAllWeek: Bool) -> ScheduleSnapshot {
        let intervals: [ScheduleSnapshot.Interval] = freeAllWeek
            ? [.init(startMinuteOfWeek: 0, durationMinutes: ScheduleSnapshot.minutesPerWeek)]
            : []
        return ScheduleSnapshot(isEnabled: enabled, intervals: intervals, timeZoneIdentifier: "UTC")
    }

    // MARK: - No session, no schedule snapshot

    func test_noSession_noSnapshot_returnsAll() {
        // Legacy fallback: pre-snapshot install that hasn't yet persisted a
        // schedule. The app's intent is "all apps blocked by default", so
        // unknown state ⇒ block.
        let log = IntentLog(activeSession: nil)
        XCTAssertEqual(compute(log, at: t0), .all)
    }

    // MARK: - Active session

    func test_sessionActive_returnsAllExceptApps() {
        let picks = FamilyActivitySelection()
        let log = IntentLog(activeSession: session(endOffset: 300, apps: picks))
        guard case .allExcept(let returned) = compute(log, at: t0.addingTimeInterval(100)) else {
            return XCTFail("expected .allExcept")
        }
        XCTAssertEqual(returned, picks)
    }

    func test_sessionActive_independentOfSchedule() {
        let picks = FamilyActivitySelection()
        var freeLog = IntentLog(activeSession: session(endOffset: 300, apps: picks))
        freeLog.weeklySchedule = snapshot(enabled: true, freeAllWeek: true)

        var blockedLog = IntentLog(activeSession: session(endOffset: 300, apps: picks))
        blockedLog.weeklySchedule = snapshot(enabled: true, freeAllWeek: false)

        XCTAssertEqual(compute(freeLog,    at: t0.addingTimeInterval(100)),
                       compute(blockedLog, at: t0.addingTimeInterval(100)))
    }

    // MARK: - Expiry boundary

    func test_sessionExactlyAtEndsAt_treatedAsExpired_noSnapshot_returnsAll() {
        let log = IntentLog(activeSession: session(endOffset: 300))
        XCTAssertEqual(compute(log, at: t0.addingTimeInterval(300)), .all)
    }

    func test_sessionPastEndsAt_scheduleEnabledOutsideFree_returnsAll() {
        var log = IntentLog(activeSession: session(endOffset: 300))
        log.weeklySchedule = snapshot(enabled: true, freeAllWeek: false)
        XCTAssertEqual(compute(log, at: t0.addingTimeInterval(301)), .all)
    }

    func test_sessionPastEndsAt_scheduleDisabled_returnsNone() {
        var log = IntentLog(activeSession: session(endOffset: 300))
        log.weeklySchedule = snapshot(enabled: false, freeAllWeek: false)
        XCTAssertEqual(compute(log, at: t0.addingTimeInterval(301)), .none)
    }

    // MARK: - Schedule (no session)

    func test_scheduleEnabled_outsideFree_returnsAll() {
        var log = IntentLog(activeSession: nil)
        log.weeklySchedule = snapshot(enabled: true, freeAllWeek: false)
        XCTAssertEqual(compute(log, at: t0), .all)
    }

    func test_scheduleEnabled_inFree_returnsNone() {
        var log = IntentLog(activeSession: nil)
        log.weeklySchedule = snapshot(enabled: true, freeAllWeek: true)
        XCTAssertEqual(compute(log, at: t0), .none)
    }

    func test_scheduleDisabled_returnsNone() {
        // Disabled schedule ⇒ "Blocking off" in UI ⇒ nothing blocked.
        var log = IntentLog(activeSession: nil)
        log.weeklySchedule = snapshot(enabled: false, freeAllWeek: false)
        XCTAssertEqual(compute(log, at: t0), .none)
    }
}
