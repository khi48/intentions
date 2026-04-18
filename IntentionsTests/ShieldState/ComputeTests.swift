import XCTest
@preconcurrency import FamilyControls
@testable import Intentions

final class ComputeTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(endOffset: TimeInterval, apps: FamilyActivitySelection = .init()) -> Session {
        Session(apps: apps, startedAt: t0, endsAt: t0.addingTimeInterval(endOffset))
    }

    // MARK: - No session

    func test_noSession_defaultBlocked_returnsAll() {
        let log = IntentLog(defaultState: .blocked, activeSession: nil)
        XCTAssertEqual(compute(log, at: t0), .all)
    }

    func test_noSession_defaultOpen_returnsNone() {
        let log = IntentLog(defaultState: .open, activeSession: nil)
        XCTAssertEqual(compute(log, at: t0), .none)
    }

    // MARK: - Active session

    func test_sessionActive_returnsAllExceptApps() {
        let picks = FamilyActivitySelection()
        let log = IntentLog(
            defaultState: .blocked,
            activeSession: session(endOffset: 300, apps: picks)
        )
        guard case .allExcept(let returned) = compute(log, at: t0.addingTimeInterval(100)) else {
            return XCTFail("expected .allExcept")
        }
        XCTAssertEqual(returned, picks)
    }

    func test_sessionActive_independentOfDefault() {
        let picks = FamilyActivitySelection()
        let blockedLog = IntentLog(defaultState: .blocked, activeSession: session(endOffset: 300, apps: picks))
        let openLog    = IntentLog(defaultState: .open,    activeSession: session(endOffset: 300, apps: picks))
        XCTAssertEqual(compute(blockedLog, at: t0.addingTimeInterval(100)),
                       compute(openLog,    at: t0.addingTimeInterval(100)))
    }

    // MARK: - Expiry boundary

    func test_sessionExactlyAtEndsAt_treatedAsExpired() {
        let log = IntentLog(defaultState: .blocked, activeSession: session(endOffset: 300))
        XCTAssertEqual(compute(log, at: t0.addingTimeInterval(300)), .all)
    }

    func test_sessionPastEndsAt_defaultBlocked_returnsAll() {
        let log = IntentLog(defaultState: .blocked, activeSession: session(endOffset: 300))
        XCTAssertEqual(compute(log, at: t0.addingTimeInterval(301)), .all)
    }

    func test_sessionPastEndsAt_defaultOpen_returnsNone() {
        let log = IntentLog(defaultState: .open, activeSession: session(endOffset: 300))
        XCTAssertEqual(compute(log, at: t0.addingTimeInterval(301)), .none)
    }
}
