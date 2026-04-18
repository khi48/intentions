import XCTest
@testable import Intentions

final class IntentLogStoreTests: XCTestCase {

    private let testSuiteName = "test.intentions.shieldstate"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: testSuiteName)?.removePersistentDomain(forName: testSuiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: testSuiteName)?.removePersistentDomain(forName: testSuiteName)
        super.tearDown()
    }

    func test_loadFromEmpty_returnsDefaultBlockedNoSession() {
        let store = IntentLogStore(suiteName: testSuiteName)
        let log = store.load()
        XCTAssertEqual(log, .empty)
    }

    func test_saveThenLoad_roundTrips() {
        let store = IntentLogStore(suiteName: testSuiteName)
        var log = IntentLog.empty
        log.defaultState = .open
        store.save(log)

        let reloaded = store.load()
        XCTAssertEqual(reloaded.defaultState, .open)
        XCTAssertNil(reloaded.activeSession)
    }

    func test_freshInstancePerRead_avoidsStaleCache() {
        let writer = IntentLogStore(suiteName: testSuiteName)
        writer.save(IntentLog(defaultState: .open, activeSession: nil))

        let reader = IntentLogStore(suiteName: testSuiteName)
        XCTAssertEqual(reader.load().defaultState, .open)
    }

    func test_corruptedData_fallsBackToEmpty() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.set(Data([0xFF, 0xFE, 0xFD]), forKey: IntentLogStore.storageKey)

        let store = IntentLogStore(suiteName: testSuiteName)
        XCTAssertEqual(store.load(), .empty)
    }
}
