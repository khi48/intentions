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

    func test_endSession_defaultBlocked_appliesAll() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.endSession(now: t0.addingTimeInterval(60))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.all])
    }

    func test_endSession_defaultOpen_appliesNone() {
        var log = store.load()
        log.defaultState = .open
        store.save(log)

        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.endSession(now: t0.addingTimeInterval(60))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.none])
    }

    // MARK: - Flip default

    func test_flipDefault_blockedToOpen_cancelsActiveSession_andAppliesNone() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.flipDefault(to: .open, now: t0.addingTimeInterval(60))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(store.load().defaultState, .open)
        XCTAssertEqual(applier.calls, [.none])
    }

    func test_flipDefault_openToBlocked_noActiveSession_appliesAll() {
        var log = store.load()
        log.defaultState = .open
        store.save(log)

        engine.flipDefault(to: .blocked, now: t0)

        XCTAssertEqual(store.load().defaultState, .blocked)
        XCTAssertEqual(applier.calls, [.all])
    }

    // MARK: - Handle expiry (DAM path)

    func test_handleExpiry_sessionPastEndsAt_defaultBlocked_appliesAll() {
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

    func test_catchUpOnForeground_staleExpiredSession_clearsAndApplies() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.catchUpOnForeground(now: t0.addingTimeInterval(500))

        XCTAssertNil(store.load().activeSession)
        XCTAssertEqual(applier.calls, [.all])
    }

    func test_catchUpOnForeground_activeSession_noOp() {
        engine.startSession(apps: .init(), endsAt: t0.addingTimeInterval(300), now: t0)
        applier.reset()

        engine.catchUpOnForeground(now: t0.addingTimeInterval(60))

        XCTAssertNotNil(store.load().activeSession)
        XCTAssertEqual(applier.calls.count, 0)
    }

    func test_catchUpOnForeground_noSession_noOp() {
        engine.catchUpOnForeground(now: t0)
        XCTAssertEqual(applier.calls.count, 0)
    }
}
