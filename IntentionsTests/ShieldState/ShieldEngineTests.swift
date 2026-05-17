import XCTest
@preconcurrency import FamilyControls
@testable import Intentions

final class ShieldEngineTests: XCTestCase {

    private var store: InMemoryIntentLogStore!
    private var applier: FakeShieldApplier!
    private var engine: ShieldEngine!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        store = InMemoryIntentLogStore()
        applier = FakeShieldApplier()
        engine = ShieldEngine(store: store, applier: applier, scheduler: nil)
    }

    private func makeFreeAllWeekSnapshot() -> ScheduleSnapshot {
        // One routine on every weekday, full day → always free.
        ScheduleSnapshot(
            isEnabled: true,
            routines: [
                .init(
                    startMinute: 0,
                    durationMinutes: ScheduleSnapshot.minutesPerDay,
                    days: Set(Weekday.allCases)
                )
            ],
            timeZoneIdentifier: TimeZone(identifier: "UTC")!.identifier
        )
    }

    private func makeBlockedAllWeekSnapshot() -> ScheduleSnapshot {
        // Enabled but with no routines → never free.
        ScheduleSnapshot(isEnabled: true, routines: [], timeZoneIdentifier: TimeZone(identifier: "UTC")!.identifier)
    }

    private func makeDisabledSnapshot() -> ScheduleSnapshot {
        ScheduleSnapshot(isEnabled: false, routines: [], timeZoneIdentifier: "UTC")
    }

    // MARK: - Start session

    func test_startSession_fromNoActive_writesLogAndAppliesAllExcept() {
        let picks = FamilyActivitySelection()
        engine.startSession(apps: picks, endsAt: t0.addingTimeInterval(300), now: t0)

        XCTAssertNotNil(store.load().activeSession)
        XCTAssertEqual(store.load().activeSession?.endsAt, t0.addingTimeInterval(300))

        XCTAssertEqual(applier.calls.count, 1)
        guard case .allExcept = applier.calls.first else {
            return XCTFail("expected .allExcept")
        }
    }

    func test_startSession_replacesExistingActiveSession() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        let firstId = store.load().activeSession?.id

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(600), now: t0)
        let secondId = store.load().activeSession?.id

        XCTAssertNotNil(firstId)
        XCTAssertNotNil(secondId)
        XCTAssertNotEqual(firstId, secondId)
        XCTAssertEqual(store.load().activeSession?.endsAt, t0.addingTimeInterval(600))
    }

    // MARK: - End session

    func test_endSession_noSnapshot_appliesAll() {
        // Pre-snapshot install fallback ⇒ .all.
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.endSession(now: t0.addingTimeInterval(60))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.all])
    }

    func test_endSession_scheduleDisabled_appliesNone() {
        // Schedule disabled ⇒ free everywhere ⇒ .none after session ends.
        var log = store.load()
        log.weeklySchedule = makeDisabledSnapshot()
        store.save(log)

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.endSession(now: t0.addingTimeInterval(60))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.none])
    }

    // MARK: - Handle expiry (DAM path)

    func test_handleExpiry_sessionPastEndsAt_noSnapshot_appliesAll() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.handleExpiry(now: t0.addingTimeInterval(301))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.all])
    }

    func test_handleExpiry_sessionStillActive_noOp() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.handleExpiry(now: t0.addingTimeInterval(100))

        XCTAssertNotNil(store.load().activeSession, "session should not be cleared early")
        XCTAssertEqual(applier.calls.count, 0, "no shield write for non-expiry")
    }

    func test_handleExpiry_noActiveSession_noOp() {
        engine.handleExpiry(now: t0)
        XCTAssertEqual(applier.calls.count, 0)
    }

    // MARK: - Foreground catch-up

    // catchUpOnForeground is idempotent — always reapplies via compute() so the
    // springboard re-renders. Same shield write whether session expired, active,
    // or absent; compute() determines the correct config.

    func test_catchUpOnForeground_staleExpiredSession_clearsAndApplies() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.catchUpOnForeground(now: t0.addingTimeInterval(500))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.all])
    }

    func test_catchUpOnForeground_activeSession_reappliesAllExcept() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.catchUpOnForeground(now: t0.addingTimeInterval(60))

        XCTAssertNotNil(store.load().activeSession)
        XCTAssertEqual(applier.calls.count, 1)
        guard case .allExcept = applier.calls.first else {
            return XCTFail("expected .allExcept")
        }
    }

    func test_catchUpOnForeground_noSession_noSnapshot_appliesAll() {
        engine.catchUpOnForeground(now: t0)
        // Empty log + no schedule → .all (legacy fallback).
        XCTAssertEqual(applier.calls, [.all])
    }

    // MARK: - Schedule-aware compute

    func test_compute_scheduleFreeTime_noSession_returnsNone() {
        var log = store.load()
        log.weeklySchedule = makeFreeAllWeekSnapshot()
        store.save(log)

        engine.catchUpOnForeground(now: t0)
        XCTAssertEqual(applier.calls, [.none])
    }

    func test_compute_scheduleBlockedTime_noSession_returnsAll() {
        var log = store.load()
        log.weeklySchedule = makeBlockedAllWeekSnapshot()
        store.save(log)

        engine.catchUpOnForeground(now: t0)
        XCTAssertEqual(applier.calls, [.all])
    }

    func test_compute_freeTimeWinsOverSession() {
        // R3 (#27): free-time has precedence over an active session. A session
        // armed during a free-time window MUST yield .none — free-time means
        // all apps free. Mutex is enforced by ShieldEngine clearing the session
        // on free-time entry; compute() is the pure-function half of that rule.
        var log = store.load()
        log.weeklySchedule = makeFreeAllWeekSnapshot()
        store.save(log)

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        XCTAssertEqual(applier.calls.last, .none, "free-time wins over session — expected .none")
    }

    func test_compute_scheduleDisabled_returnsNone() {
        // Schedule disabled ⇒ "Blocking off" in UI ⇒ nothing blocked.
        var log = store.load()
        log.weeklySchedule = makeDisabledSnapshot()
        store.save(log)

        engine.catchUpOnForeground(now: t0)
        XCTAssertEqual(applier.calls, [.none])
    }

    // MARK: - Schedule transition (DAM path)

    func test_handleScheduleTransition_appliesCurrentConfig() {
        var log = store.load()
        log.weeklySchedule = makeFreeAllWeekSnapshot()
        store.save(log)

        engine.handleScheduleTransition(now: t0)
        XCTAssertEqual(applier.calls, [.none])
    }

    func test_handleScheduleTransition_sessionActive_keepsSessionShield() {
        var log = store.load()
        log.weeklySchedule = makeBlockedAllWeekSnapshot()
        store.save(log)

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(600), now: t0)
        applier.reset()

        engine.handleScheduleTransition(now: t0.addingTimeInterval(60))
        XCTAssertEqual(applier.calls.count, 1)
        guard case .allExcept = applier.calls.first else {
            return XCTFail("expected session to remain — .allExcept")
        }
    }

    // MARK: - Refresh schedule monitoring

    func test_refreshScheduleMonitoring_persistsSnapshotAndApplies() {
        let snap = makeFreeAllWeekSnapshot()
        let result = engine.refreshScheduleMonitoring(snap, now: t0)

        XCTAssertEqual(result, .noSessionChange)
        XCTAssertEqual(store.load().weeklySchedule, snap)
        XCTAssertEqual(applier.calls, [.none])
    }

    func test_refreshScheduleMonitoring_idempotent() {
        let snap = makeBlockedAllWeekSnapshot()
        _ = engine.refreshScheduleMonitoring(snap, now: t0)
        _ = engine.refreshScheduleMonitoring(snap, now: t0)
        XCTAssertEqual(applier.calls, [.all, .all])
        XCTAssertEqual(store.load().weeklySchedule, snap)
    }

    // MARK: - Free-time / session mutex (R3, #27)

    /// Helper: inject an active session directly into the in-memory log. Used
    /// to set up the "session somehow exists" precondition without going
    /// through startSession (which now itself fires compute() under R3).
    private func injectActiveSession(endsAt: Date) {
        var log = store.load()
        log.activeSession = Session(apps: .init(), startedAt: t0, endsAt: endsAt)
        store.save(log)
    }

    /// Build a snapshot whose free-time window covers an exact wall-clock
    /// interval relative to t0. Used so the engine's lookback probe sees a
    /// real free↔blocking boundary at `now`.
    private func snapshotFree(fromOffset: TimeInterval, durationSec: TimeInterval) -> ScheduleSnapshot {
        // Routines are single-day, so derive (weekday, minute-of-day) at
        // t0 + fromOffset and clamp the duration so it doesn't cross midnight.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = t0.addingTimeInterval(fromOffset)
        let calendarWeekday = cal.component(.weekday, from: date)
        let weekday = Weekday.from(calendarWeekday: calendarWeekday)
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let startMinute = h * 60 + m
        let maxDuration = ScheduleSnapshot.minutesPerDay - startMinute
        let duration = min(Int(durationSec / 60), maxDuration)
        return ScheduleSnapshot(
            isEnabled: true,
            routines: [.init(startMinute: startMinute, durationMinutes: duration, days: [weekday])],
            timeZoneIdentifier: "UTC"
        )
    }

    func test_handleScheduleTransition_entersFreeTimeWithActiveSession_clearsSessionReturnsTerminated() {
        // DAM fires `handleScheduleTransition` at the moment we enter a
        // free-time window. Snapshot at `now` is in free-time; session is in
        // log. R3: terminate it.
        var log = store.load()
        log.weeklySchedule = makeFreeAllWeekSnapshot()
        store.save(log)
        injectActiveSession(endsAt: t0.addingTimeInterval(600))
        applier.reset()

        let result = engine.handleScheduleTransition(now: t0.addingTimeInterval(60))

        XCTAssertEqual(result, .sessionTerminatedByFreeTime)
        XCTAssertNil(store.load().activeSession, "session must be cleared in log on free-time entry")
        XCTAssertEqual(applier.calls, [.none])
    }

    func test_handleScheduleTransition_exitsFreeTimeWithActiveSession_clearsSessionReturnsTerminated() {
        // Mutex is symmetric: exiting free-time also terminates an in-log
        // session. Engine detects "just left free-time" by probing the snapshot
        // a minute before `now`.
        //
        // For this test we use an exact free-window so isFreeTime(now - 60s)
        // is true while isFreeTime(now) is false.
        let freeSnapshot = snapshotFree(fromOffset: 0, durationSec: 120)
        var log = store.load()
        log.weeklySchedule = freeSnapshot
        store.save(log)
        injectActiveSession(endsAt: t0.addingTimeInterval(600))
        applier.reset()

        // Fire 30s after the window ends. now - 60s = 30s before window end
        // (still in free-time) → lookback catches it.
        let now = t0.addingTimeInterval(120 + 30)
        let result = engine.handleScheduleTransition(now: now)

        XCTAssertEqual(result, .sessionTerminatedByFreeTime)
        XCTAssertNil(store.load().activeSession, "session must be cleared in log on free-time exit")
        XCTAssertEqual(applier.calls, [.all])
    }

    func test_handleScheduleTransition_noSession_returnsNoChange() {
        var log = store.load()
        log.weeklySchedule = makeFreeAllWeekSnapshot()
        store.save(log)

        let result = engine.handleScheduleTransition(now: t0)

        XCTAssertEqual(result, .noSessionChange)
    }

    func test_handleScheduleTransition_sessionInBlockingWindow_returnsNoChange() {
        // Schedule never enters free-time (always-blocking) — even though a
        // session is active, no mutex violation can occur.
        var log = store.load()
        log.weeklySchedule = makeBlockedAllWeekSnapshot()
        store.save(log)

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(600), now: t0)
        applier.reset()

        let result = engine.handleScheduleTransition(now: t0.addingTimeInterval(60))

        XCTAssertEqual(result, .noSessionChange)
        XCTAssertNotNil(store.load().activeSession)
    }

    func test_refreshScheduleMonitoring_userEditCreatesRetroactiveFreeTime_terminatesSession() {
        // Symmetric path: user edits the schedule to add a free-time window
        // that covers the present moment — should terminate the active session
        // exactly like DAM-driven entry. (Q3 in design.)
        var log = store.load()
        log.weeklySchedule = makeBlockedAllWeekSnapshot()
        store.save(log)

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(600), now: t0)
        applier.reset()

        // User saves a new schedule: now in free-time at the edit moment.
        let newSnapshot = makeFreeAllWeekSnapshot()
        let result = engine.refreshScheduleMonitoring(newSnapshot, now: t0.addingTimeInterval(60))

        XCTAssertEqual(result, .sessionTerminatedByFreeTime)
        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.none])
    }

    // MARK: - Disabled-schedule precedence over R3 mutex (#27 collision with #28)
    //
    // `WeeklySchedule.isFreeTime(at:)` and `ScheduleSnapshot.isFreeTime(at:)`
    // both return `true` when `!isEnabled` ("Blocking off ⇒ nothing blocked").
    // That is correct for compute() but WRONG as an R3-mutex trigger:
    // disabling blocking is semantically distinct from "entering a free-time
    // window" and has its own UX — the user-facing reason is "you turned
    // blocking off", not "free time started".
    //
    // The engine MUST NOT signal `.sessionTerminatedByFreeTime` when the
    // snapshot has `isEnabled == false`. That signal exists exclusively for
    // the R3 banner ("Free time started — your session ended."). The silent
    // cancel for a disabled-blocking edit is owned by ContentViewModel's
    // existing `cancelActiveSessionForDisable` path (#28).

    func test_refreshScheduleMonitoring_disabledScheduleWithActiveSession_returnsNoChange() {
        // Pre-existing session in log + user disables blocking → engine still
        // clears the session (compute() puts us in `.none`, so the session is
        // a stale state) but the RESULT must be `.noSessionChange` so the
        // caller routes through the silent disable-cancel path, not the R3
        // banner path.
        var log = store.load()
        log.weeklySchedule = makeBlockedAllWeekSnapshot()
        store.save(log)

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(600), now: t0)
        applier.reset()

        // User saves a disabled schedule.
        let result = engine.refreshScheduleMonitoring(makeDisabledSnapshot(), now: t0.addingTimeInterval(60))

        XCTAssertEqual(result, .noSessionChange,
                       "disabling blocking is not an R3 free-time event — caller must route to silent cancel")
        XCTAssertEqual(applier.calls, [.none], "disabled schedule yields .none from compute()")
    }

    func test_handleScheduleTransition_disabledScheduleWithActiveSession_returnsNoChange() {
        // DAM-path symmetry: if the persisted snapshot is disabled and somehow
        // a session lingered, the boundary fire must NOT report
        // `.sessionTerminatedByFreeTime`. Disabled snapshots can't even
        // schedule a boundary in production (nextBoundary returns nil), but the
        // engine is the layer that owns the rule — we lock it down here so a
        // future caller that synthesises this state can't leak the banner.
        var log = store.load()
        log.weeklySchedule = makeDisabledSnapshot()
        store.save(log)
        injectActiveSession(endsAt: t0.addingTimeInterval(600))
        applier.reset()

        let result = engine.handleScheduleTransition(now: t0.addingTimeInterval(60))

        XCTAssertEqual(result, .noSessionChange,
                       "disabled schedule must never trip the R3 mutex signal")
    }
}
