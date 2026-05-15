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
        // One interval covering the whole week.
        ScheduleSnapshot(
            isEnabled: true,
            intervals: [.init(startMinuteOfWeek: 0, durationMinutes: ScheduleSnapshot.minutesPerWeek)],
            timeZoneIdentifier: TimeZone(identifier: "UTC")!.identifier
        )
    }

    private func makeBlockedAllWeekSnapshot() -> ScheduleSnapshot {
        // Enabled but with no intervals → never free.
        ScheduleSnapshot(isEnabled: true, intervals: [], timeZoneIdentifier: TimeZone(identifier: "UTC")!.identifier)
    }

    private func makeDisabledSnapshot() -> ScheduleSnapshot {
        ScheduleSnapshot(isEnabled: false, intervals: [], timeZoneIdentifier: "UTC")
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

    func test_compute_sessionWinsOverSchedule_freeTime() {
        // Session active during free time — session apps unlocked, others shielded.
        var log = store.load()
        log.weeklySchedule = makeFreeAllWeekSnapshot()
        store.save(log)

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        // Last apply call is from startSession.
        guard case .allExcept = applier.calls.last else {
            return XCTFail("expected session to take priority over free time → .allExcept")
        }
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
        engine.refreshScheduleMonitoring(snap, now: t0)

        XCTAssertEqual(store.load().weeklySchedule, snap)
        XCTAssertEqual(applier.calls, [.none])
    }

    func test_refreshScheduleMonitoring_idempotent() {
        let snap = makeBlockedAllWeekSnapshot()
        engine.refreshScheduleMonitoring(snap, now: t0)
        engine.refreshScheduleMonitoring(snap, now: t0)
        XCTAssertEqual(applier.calls, [.all, .all])
        XCTAssertEqual(store.load().weeklySchedule, snap)
    }
}
