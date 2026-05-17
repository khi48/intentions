import XCTest
@preconcurrency import FamilyControls
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

    func test_loadFromEmpty_returnsDefaultEmpty() {
        let store = IntentLogStore(suiteName: testSuiteName)
        let log = store.load()
        XCTAssertEqual(log, .empty)
    }

    func test_saveThenLoad_roundTripsScheduleSnapshot() {
        let store = IntentLogStore(suiteName: testSuiteName)
        var log = IntentLog.empty
        log.weeklySchedule = ScheduleSnapshot(
            isEnabled: true,
            routines: [
                .init(startMinute: 9 * 60, durationMinutes: 60, days: [.monday]),
                .init(startMinute: 14 * 60, durationMinutes: 90, days: [.tuesday, .thursday])
            ],
            timeZoneIdentifier: "UTC"
        )
        store.save(log)

        let reloaded = store.load()
        XCTAssertEqual(reloaded.weeklySchedule?.isEnabled, true)
        XCTAssertEqual(reloaded.weeklySchedule?.routines.count, 2)
        XCTAssertEqual(reloaded.weeklySchedule?.routines.first?.startMinute, 9 * 60)
        XCTAssertEqual(reloaded.weeklySchedule?.routines.first?.durationMinutes, 60)
        XCTAssertEqual(reloaded.weeklySchedule?.routines.first?.days, [.monday])
        XCTAssertEqual(reloaded.weeklySchedule?.routines.last?.days, [.tuesday, .thursday])
        XCTAssertNil(reloaded.activeSession)
    }

    func test_freshInstancePerRead_avoidsStaleCache() {
        let writer = IntentLogStore(suiteName: testSuiteName)
        var log = IntentLog.empty
        log.weeklySchedule = ScheduleSnapshot(isEnabled: true, routines: [], timeZoneIdentifier: "UTC")
        writer.save(log)

        let reader = IntentLogStore(suiteName: testSuiteName)
        XCTAssertEqual(reader.load().weeklySchedule?.isEnabled, true)
    }

    func test_corruptedData_fallsBackToEmpty() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.set(Data([0xFF, 0xFE, 0xFD]), forKey: IntentLogStore.storageKey)

        let store = IntentLogStore(suiteName: testSuiteName)
        XCTAssertEqual(store.load(), .empty)
    }

    /// Backwards-compat: blobs persisted before issue #7 stripped `defaultState`
    /// must still decode cleanly. Codable ignores unknown keys by default;
    /// IntentLog's CodingKeys deliberately omit `defaultState` so the decoder
    /// silently drops it.
    func test_legacyBlob_withDefaultState_decodesCleanly() throws {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        let legacyJSON = """
        {
            "defaultState": "blocked",
            "knownApplicationTokens": [],
            "knownWebDomainTokens": []
        }
        """.data(using: .utf8)!
        defaults.set(legacyJSON, forKey: IntentLogStore.storageKey)

        let store = IntentLogStore(suiteName: testSuiteName)
        let loaded = store.load()

        // No crash, decodes to an empty-equivalent log: no session, no schedule.
        XCTAssertNil(loaded.activeSession)
        XCTAssertNil(loaded.weeklySchedule)
        XCTAssertTrue(loaded.knownApplicationTokens.isEmpty)
        XCTAssertTrue(loaded.knownWebDomainTokens.isEmpty)
    }
}
