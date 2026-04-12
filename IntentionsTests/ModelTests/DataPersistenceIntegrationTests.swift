import XCTest
import SwiftData
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

// MARK: - Integration Tests for Data Persistence Service
@MainActor
final class DataPersistenceIntegrationTests: XCTestCase {
    
    var service: (any DataPersisting)!
    var mockService: MockDataPersistenceService!
    
    override func setUp() async throws {
        try await super.setUp()
        // Use mock service for integration tests to avoid SwiftData setup complexity
        mockService = MockDataPersistenceService()
        service = mockService
    }
    
    override func tearDown() async throws {
        // Capture the service locally to avoid data race warnings with 'self'
        let currentMockService = mockService
        await currentMockService?.reset()
        
        service = nil
        mockService = nil
        try await super.tearDown()
    }
    
    // MARK: - Complete User Workflow Tests
    
    func testCompleteUserOnboardingWorkflow() async throws {
        // Test a complete user onboarding workflow

        // 1. User configures schedule settings
        let scheduleSettings = ScheduleSettings()
        scheduleSettings.isEnabled = true
        scheduleSettings.activeHours = 9...18
        scheduleSettings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        scheduleSettings.timeZone = TimeZone.current

        try await service.saveScheduleSettings(scheduleSettings)

        // 2. User creates their first intention session
        let firstSession = try IntentionSession(
            applications: Set<ApplicationToken>(),
            duration: 15 * 60 // 15 minutes
        )

        try await service.saveIntentionSession(firstSession)

        // 3. Verify all data was saved correctly
        let savedSettings = try await service.loadScheduleSettings()
        let savedSessions = try await service.loadIntentionSessions()

        XCTAssertNotNil(savedSettings)
        XCTAssertEqual(savedSessions.count, 1)

        XCTAssertEqual(savedSettings!.activeDays.count, 5)
        XCTAssertEqual(savedSessions.first!.duration, 15 * 60)
    }
    
    func testSessionLifecycleManagement() async throws {
        // Test complete session lifecycle from creation to completion

        // 1. Create active session
        let session = try IntentionSession(
            applications: Set<ApplicationToken>(),
            duration: 30 * 60 // 30 minutes
        )
        session.requestedAppGroups = []
        session.state = .active(startedAt: Date())
        
        try await service.saveIntentionSession(session)
        
        // 2. Simulate session updates during usage
        // Session is being used, but still active
        try await service.saveIntentionSession(session)
        
        // 3. Complete session
        session.complete() // This should set isActive = false, wasCompleted = true
        try await service.saveIntentionSession(session)
        
        // 5. Verify final state
        let sessions = try await service.loadIntentionSessions()
        let completedSession = sessions.first!
        
        XCTAssertFalse(completedSession.isActive)
        XCTAssertTrue(completedSession.wasCompleted)
        XCTAssertNotNil(completedSession.endTime)
    }
    
    func testErrorRecoveryScenarios() async throws {
        // Test how the service handles various error scenarios

        // 1. Attempt to delete non-existent session
        let nonExistentId = UUID()

        do {
            try await service.deleteIntentionSession(nonExistentId)
            XCTFail("Expected error for non-existent session")
        } catch AppError.dataNotFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    
    func testScheduleSettingsWorkflow() async throws {
        // Test complete schedule settings workflow
        
        // 1. Create initial settings
        let settings = ScheduleSettings()
        settings.isEnabled = true
        settings.activeHours = 8...20
        settings.activeDays = Set(Weekday.allCases) // All days
        settings.timeZone = TimeZone.current
        
        try await service.saveScheduleSettings(settings)
        
        // 2. Verify settings were saved
        let loadedSettings = try await service.loadScheduleSettings()
        XCTAssertNotNil(loadedSettings)
        XCTAssertEqual(loadedSettings!.activeHours, 8...20)
        XCTAssertEqual(loadedSettings!.activeDays.count, 7)
        
        // 3. Update settings to work days only
        settings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        settings.activeHours = 9...17
        try await service.saveScheduleSettings(settings)
        
        // 4. Verify update
        let updatedSettings = try await service.loadScheduleSettings()
        XCTAssertNotNil(updatedSettings)
        XCTAssertEqual(updatedSettings!.activeHours, 9...17)
        XCTAssertEqual(updatedSettings!.activeDays.count, 5)
    }
    
    
    func testComplexSessionScenarios() async throws {
        // Test complex session scenarios with multiple app groups

        // 1. Create session with multiple groups
        let groupId1 = UUID()
        let groupId2 = UUID()
        let session = try IntentionSession(
            applications: Set<ApplicationToken>(),
            duration: 60 * 60 // 1 hour
        )
        session.requestedAppGroups = [groupId1, groupId2]

        try await service.saveIntentionSession(session)

        // 2. Verify session with multiple groups
        let sessions = try await service.loadIntentionSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first!.requestedAppGroups.count, 2)
        XCTAssertTrue(sessions.first!.requestedAppGroups.contains(groupId1))
        XCTAssertTrue(sessions.first!.requestedAppGroups.contains(groupId2))
    }
    
    // MARK: - Performance Tests
    
    
    func testLargeDataSetPerformance() async throws {
        // Test performance with larger datasets
        let startTime = Date()

        // Create 100 sessions
        for i in 1...100 {
            let session = try IntentionSession(
                applications: Set<ApplicationToken>(),
                duration: TimeInterval(1 * 5 * 60)
            )
            session.requestedAppGroups = [] // Empty for performance test

            // All sessions are completed for performance test
            let sessionStartTime = Date().addingTimeInterval(TimeInterval(-i * 60))
            let duration = TimeInterval(i * 60)
            session.state = .completed(totalElapsed: duration, completedAt: sessionStartTime.addingTimeInterval(duration))

            try await service.saveIntentionSession(session)
        }

        let saveTime = Date().timeIntervalSince(startTime)

        // Load all data
        let loadStartTime = Date()
        let sessions = try await service.loadIntentionSessions()
        let loadTime = Date().timeIntervalSince(loadStartTime)

        XCTAssertEqual(sessions.count, 100)

        // Performance assertions (adjust thresholds as needed for mock service)
        XCTAssertLessThan(saveTime, 10.0, "Save operations took too long")
        XCTAssertLessThan(loadTime, 2.0, "Load operations took too long")

        print("Save time: \(saveTime)s, Load time: \(loadTime)s")
    }
    
    func testExpiredSessionCleanup() async throws {
        // Test the expired session cleanup functionality
        
        // Create sessions with different ages
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-24 * 60 * 60)
        let oneWeekAgo = now.addingTimeInterval(-6 * 24 * 60 * 60)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 24 * 60 * 60)
        
        let recentSession = try IntentionSession(applications: Set(), duration: 30 * 60)
        recentSession.state = .completed(totalElapsed: 30 * 60, completedAt: oneDayAgo.addingTimeInterval(30 * 60))
        
        let weekOldSession = try IntentionSession(applications: Set(), duration: 30 * 60)
        weekOldSession.state = .completed(totalElapsed: 30 * 60, completedAt: oneWeekAgo.addingTimeInterval(30 * 60))
        
        let oldSession = try IntentionSession(applications: Set(), duration: 30 * 60)
        oldSession.state = .completed(totalElapsed: 30 * 60, completedAt: twoWeeksAgo.addingTimeInterval(30 * 60))
        
        try await service.saveIntentionSession(recentSession)
        try await service.saveIntentionSession(weekOldSession)
        try await service.saveIntentionSession(oldSession)
        
        // Verify all sessions were saved
        let allSessions = try await service.loadIntentionSessions()
        XCTAssertEqual(allSessions.count, 3)
        
        // Clear expired sessions (older than 7 days)
        try await service.clearExpiredSessions()
        
        // Verify only recent sessions remain
        let remainingSessions = try await service.loadIntentionSessions()
        XCTAssertEqual(remainingSessions.count, 2) // Recent and week-old should remain
        
        let remainingIds = Set(remainingSessions.map(\.id))
        XCTAssertTrue(remainingIds.contains(recentSession.id))
        XCTAssertTrue(remainingIds.contains(weekOldSession.id))
        XCTAssertFalse(remainingIds.contains(oldSession.id))
    }
}
