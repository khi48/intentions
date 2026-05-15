import XCTest
import SwiftData
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

@MainActor
final class DataPersistenceServiceTests: XCTestCase {

    var service: DataPersistenceService!
    var testContainer: ModelContainer!

    /// Scratch App Group suite — keeps tests off the real on-device suite so
    /// running them locally doesn't clobber a developer's persisted schedule.
    private let testAppGroupSuiteName = "test.intentions.persistence.appgroup"

    override func setUp() async throws {
        try await super.setUp()

        // Wipe scratch suite so any leftover state from a previous run can't
        // bleed in (XCTest runs share process state across cases).
        UserDefaults(suiteName: testAppGroupSuiteName)?
            .removePersistentDomain(forName: testAppGroupSuiteName)
        // Also clear the legacy standard-suite key so migration tests start
        // from a known state.
        UserDefaults.standard.removeObject(
            forKey: DataPersistenceService.legacyStandardSuiteWeeklyScheduleKey
        )

        // Create in-memory test container
        let schema = Schema([
            PersistentIntentionSession.self,
            PersistentScheduleSettings.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        testContainer = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )

        service = try DataPersistenceService(
            container: testContainer,
            appGroupSuiteName: testAppGroupSuiteName
        )
    }

    override func tearDown() async throws {
        service = nil
        testContainer = nil
        UserDefaults(suiteName: testAppGroupSuiteName)?
            .removePersistentDomain(forName: testAppGroupSuiteName)
        UserDefaults.standard.removeObject(
            forKey: DataPersistenceService.legacyStandardSuiteWeeklyScheduleKey
        )
        try await super.tearDown()
    }
    
    // MARK: - Generic Storage Tests
    
    func testSaveAndLoadGenericObject() async throws {
        // Given
        struct TestData: Codable, Equatable {
            let name: String
            let value: Int
        }
        
        let testObject = TestData(name: "test", value: 42)
        let key = "test_key"
        
        // When
        try await service.save(testObject, forKey: key)
        let loadedObject = try await service.load(TestData.self, forKey: key)
        
        // Then
        XCTAssertEqual(loadedObject, testObject)
    }
    
    func testLoadNonExistentKey() async throws {
        // When
        let result = try await service.load(String.self, forKey: "non_existent_key")
        
        // Then
        XCTAssertNil(result)
    }
    
    func testDeleteGenericObject() async throws {
        // Given
        let testString = "test_value"
        let key = "test_key"
        try await service.save(testString, forKey: key)
        
        // When
        try await service.delete(forKey: key)
        let result = try await service.load(String.self, forKey: key)
        
        // Then
        XCTAssertNil(result)
    }
    
    // MARK: - Schedule Settings Tests
    
    func testSaveAndLoadScheduleSettings() async throws {
        // Given
        let scheduleSettings = createTestScheduleSettings()
        
        // When
        try await service.saveScheduleSettings(scheduleSettings)
        let loadedSettings = try await service.loadScheduleSettings()
        
        // Then
        XCTAssertNotNil(loadedSettings)
        XCTAssertEqual(loadedSettings!.isEnabled, scheduleSettings.isEnabled)
        XCTAssertEqual(loadedSettings!.activeHours, scheduleSettings.activeHours)
        XCTAssertEqual(loadedSettings!.activeDays, scheduleSettings.activeDays)
        XCTAssertEqual(loadedSettings!.timeZone.identifier, scheduleSettings.timeZone.identifier)
    }
    
    func testUpdateScheduleSettings() async throws {
        // Given
        let scheduleSettings = createTestScheduleSettings()
        try await service.saveScheduleSettings(scheduleSettings)
        
        // When - Update settings
        scheduleSettings.isEnabled = false
        scheduleSettings.activeHours = 10...20
        scheduleSettings.activeDays = [.saturday, .sunday]
        try await service.saveScheduleSettings(scheduleSettings)
        
        let loadedSettings = try await service.loadScheduleSettings()
        
        // Then
        XCTAssertNotNil(loadedSettings)
        XCTAssertFalse(loadedSettings!.isEnabled)
        XCTAssertEqual(loadedSettings!.activeHours, 10...20)
        XCTAssertEqual(loadedSettings!.activeDays, [.saturday, .sunday])
    }
    
    func testLoadNonExistentScheduleSettings() async throws {
        // When
        let result = try await service.loadScheduleSettings()
        
        // Then
        XCTAssertNil(result)
    }
    
    // MARK: - Intention Session Tests
    
    func testSaveAndLoadIntentionSession() async throws {
        // Given
        let session = try createTestIntentionSession()
        
        // When
        try await service.saveIntentionSession(session)
        let loadedSessions = try await service.loadIntentionSessions()
        
        // Then
        XCTAssertEqual(loadedSessions.count, 1)
        let loadedSession = loadedSessions.first!
        XCTAssertEqual(loadedSession.id, session.id)
        XCTAssertEqual(loadedSession.duration, session.duration)
        XCTAssertEqual(loadedSession.isActive, session.isActive)
        XCTAssertEqual(loadedSession.wasCompleted, session.wasCompleted)
        XCTAssertEqual(loadedSession.requestedAppGroups, session.requestedAppGroups)
        XCTAssertEqual(loadedSession.requestedApplications.count, session.requestedApplications.count)
    }
    
    func testUpdateExistingIntentionSession() async throws {
        // Given
        let session = try createTestIntentionSession()
        try await service.saveIntentionSession(session)
        
        // When - Update session to completed state
        let endTime = Date()
        session.state = .completed(totalElapsed: session.duration, completedAt: endTime)
        try await service.saveIntentionSession(session)
        
        let loadedSessions = try await service.loadIntentionSessions()
        
        // Then
        XCTAssertEqual(loadedSessions.count, 1)
        let loadedSession = loadedSessions.first!
        XCTAssertFalse(loadedSession.isActive)
        XCTAssertTrue(loadedSession.wasCompleted)
        XCTAssertEqual(loadedSession.endTime.timeIntervalSince1970,
                      session.endTime.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testDeleteIntentionSession() async throws {
        // Given
        let session = try createTestIntentionSession()
        try await service.saveIntentionSession(session)
        
        // When
        try await service.deleteIntentionSession(session.id)
        let loadedSessions = try await service.loadIntentionSessions()
        
        // Then
        XCTAssertTrue(loadedSessions.isEmpty)
    }
    
    func testClearExpiredSessions() async throws {
        // Given
        let oldDate = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        let recentDate = Date().addingTimeInterval(-1 * 24 * 60 * 60) // 1 day ago
        
        let oldSession = try createTestIntentionSession(startTime: oldDate)
        let recentSession = try createTestIntentionSession(startTime: recentDate)
        
        try await service.saveIntentionSession(oldSession)
        try await service.saveIntentionSession(recentSession)
        
        // When
        try await service.clearExpiredSessions()
        let remainingSessions = try await service.loadIntentionSessions()
        
        // Then
        XCTAssertEqual(remainingSessions.count, 1)
        XCTAssertEqual(remainingSessions.first!.id, recentSession.id)
    }
    
    func testLoadIntentionSessionsSortedByDate() async throws {
        // Given
        let earlierDate = Date().addingTimeInterval(-60 * 60) // 1 hour ago
        let laterDate = Date()
        
        let earlierSession = try createTestIntentionSession(startTime: earlierDate)
        let laterSession = try createTestIntentionSession(startTime: laterDate)
        
        try await service.saveIntentionSession(earlierSession)
        try await service.saveIntentionSession(laterSession)
        
        // When
        let loadedSessions = try await service.loadIntentionSessions()
        
        // Then
        XCTAssertEqual(loadedSessions.count, 2)
        // Should be sorted by start time in descending order (most recent first)
        XCTAssertEqual(loadedSessions.first!.id, laterSession.id)
        XCTAssertEqual(loadedSessions.last!.id, earlierSession.id)
    }
    
    // MARK: - Error Handling Tests
    
    func testSaveWithPersistenceFailure() async throws {
        // Test realistic persistence failure scenarios
        
        // When & Then
        // Test with a realistic persistence failure scenario
        let mockService = MockDataPersistenceService()
        mockService.shouldThrowSaveError = true
        
        do {
            try await mockService.save("test", forKey: "test")
            XCTFail("Expected persistence error")
        } catch AppError.persistenceError {
            // Expected error
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - Weekly Schedule App Group Migration Tests (issue #8)

    /// Legacy `intentions.weeklySchedule` blob present in `UserDefaults.standard`
    /// only ⇒ first `loadWeeklySchedule` hoists it into the App Group, deletes
    /// the legacy entry, and returns the decoded schedule.
    func testWeeklyScheduleMigration_legacyBlobMovedToAppGroup() async throws {
        // Given: a legacy blob written to the standard suite, App Group empty.
        let legacy = WeeklySchedule()
        legacy.isEnabled = false
        legacy.intentionQuote = "be intentional"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyData = try encoder.encode(legacy)
        UserDefaults.standard.set(
            legacyData,
            forKey: DataPersistenceService.legacyStandardSuiteWeeklyScheduleKey
        )

        let appGroup = UserDefaults(suiteName: testAppGroupSuiteName)!
        XCTAssertNil(appGroup.data(forKey: DataPersistenceService.weeklyScheduleKey))

        // When
        let loaded = try await service.loadWeeklySchedule()

        // Then: returned schedule matches legacy bytes,
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.isEnabled, false)
        XCTAssertEqual(loaded?.intentionQuote, "be intentional")

        // App Group blob is now populated,
        let appGroupBytes = appGroup.data(forKey: DataPersistenceService.weeklyScheduleKey)
        XCTAssertNotNil(appGroupBytes)
        XCTAssertEqual(appGroupBytes, legacyData)

        // and the legacy standard-suite key is gone.
        XCTAssertNil(UserDefaults.standard.data(
            forKey: DataPersistenceService.legacyStandardSuiteWeeklyScheduleKey
        ))
    }

    /// No legacy blob and no App Group blob ⇒ migration is a no-op and
    /// `loadWeeklySchedule` returns nil (the SwiftData fallback also has
    /// nothing to migrate from in this test setup).
    func testWeeklyScheduleMigration_noLegacy_isNoOp() async throws {
        // Given: both stores empty.
        XCTAssertNil(UserDefaults.standard.data(
            forKey: DataPersistenceService.legacyStandardSuiteWeeklyScheduleKey
        ))
        let appGroup = UserDefaults(suiteName: testAppGroupSuiteName)!
        XCTAssertNil(appGroup.data(forKey: DataPersistenceService.weeklyScheduleKey))

        // When
        let loaded = try await service.loadWeeklySchedule()

        // Then: nothing produced, nothing written.
        XCTAssertNil(loaded)
        XCTAssertNil(appGroup.data(forKey: DataPersistenceService.weeklyScheduleKey))
        XCTAssertNil(UserDefaults.standard.data(
            forKey: DataPersistenceService.legacyStandardSuiteWeeklyScheduleKey
        ))
    }

    /// Migration runs at most once per legacy blob: a second `loadWeeklySchedule`
    /// after migration must read straight from the App Group key (the legacy
    /// entry was deleted in the first call) and must not corrupt the App Group
    /// blob.
    func testWeeklyScheduleMigration_idempotentAcrossLoads() async throws {
        // Given: legacy blob present.
        let legacy = WeeklySchedule()
        legacy.isEnabled = true
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyData = try encoder.encode(legacy)
        UserDefaults.standard.set(
            legacyData,
            forKey: DataPersistenceService.legacyStandardSuiteWeeklyScheduleKey
        )

        // First load: migrates.
        let first = try await service.loadWeeklySchedule()
        XCTAssertNotNil(first)
        let appGroup = UserDefaults(suiteName: testAppGroupSuiteName)!
        let appGroupBytesAfterFirst = appGroup.data(forKey: DataPersistenceService.weeklyScheduleKey)
        XCTAssertNotNil(appGroupBytesAfterFirst)
        XCTAssertNil(UserDefaults.standard.data(
            forKey: DataPersistenceService.legacyStandardSuiteWeeklyScheduleKey
        ))

        // Second load: reads from App Group, does not touch the standard suite,
        // and the App Group bytes are byte-identical to what was written.
        let second = try await service.loadWeeklySchedule()
        XCTAssertNotNil(second)
        XCTAssertEqual(second?.isEnabled, legacy.isEnabled)
        XCTAssertEqual(
            appGroup.data(forKey: DataPersistenceService.weeklyScheduleKey),
            appGroupBytesAfterFirst
        )
        XCTAssertNil(UserDefaults.standard.data(
            forKey: DataPersistenceService.legacyStandardSuiteWeeklyScheduleKey
        ))
    }

    /// Save → load round-trip uses the App Group store and never touches
    /// the legacy standard-suite key. Regression guard for the unification.
    func testSaveWeeklySchedule_writesToAppGroup_notStandard() async throws {
        let schedule = WeeklySchedule()
        schedule.isEnabled = false
        schedule.intentionQuote = "rt"

        try await service.saveWeeklySchedule(schedule)

        let appGroup = UserDefaults(suiteName: testAppGroupSuiteName)!
        XCTAssertNotNil(appGroup.data(forKey: DataPersistenceService.weeklyScheduleKey))
        XCTAssertNil(UserDefaults.standard.data(
            forKey: DataPersistenceService.legacyStandardSuiteWeeklyScheduleKey
        ))

        let loaded = try await service.loadWeeklySchedule()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.isEnabled, false)
        XCTAssertEqual(loaded?.intentionQuote, "rt")
    }

    // MARK: - Helper Methods

    private func createTestScheduleSettings() -> ScheduleSettings {
        let settings = ScheduleSettings()
        settings.isEnabled = true
        settings.activeHours = 9...17
        settings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        settings.timeZone = TimeZone.current
        return settings
    }
    
    private func createTestIntentionSession(startTime: Date = Date()) throws -> IntentionSession {
        let session = try IntentionSession(
            applications: Set<ApplicationToken>(),
            duration: 30 * 60 // 30 minutes
        )
        session.requestedAppGroups = [UUID()]
        session.state = .active(startedAt: startTime)
        return session
    }
}
