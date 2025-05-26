import XCTest
import SwiftData
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

// MARK: - Data Persistence Integration Tests

//@MainActor
//final class DataPersistenceIntegrationTests: XCTestCase {
//    
//    var mockDataService: MockDataPersistenceService!
//    
//    override func setUp() async throws {
//        mockDataService = MockDataPersistenceService()
//        await mockDataService.reset()
//    }
//    
//    override func tearDown() async throws {
//        await mockDataService.reset()
//        mockDataService = nil
//    }
//    
//    func testAppGroupPersistence() async throws {
//        // 1. Create and save app group
//        let group = try AppGroup(
//            id: UUID(),
//            name: "Test Group",
//            createdAt: Date(),
//            lastModified: Date()
//        )
//        
//        try await mockDataService.saveAppGroup(group)
//        
//        // 2. Load app groups
//        let loadedGroups = try await mockDataService.loadAppGroups()
//        XCTAssertEqual(loadedGroups.count, 1)
//        XCTAssertEqual(loadedGroups.first?.name, "Test Group")
//        XCTAssertEqual(loadedGroups.first?.id, group.id)
//        
//        // 3. Delete app group
//        try await mockDataService.deleteAppGroup(group.id)
//        
//        // 4. Verify deletion
//        let emptyGroups = try await mockDataService.loadAppGroups()
//        XCTAssertTrue(emptyGroups.isEmpty)
//    }
//    
//    func testScheduleSettingsPersistence() async throws {
//        // 1. Create schedule settings
//        let settings = ScheduleSettings()
//        settings.isEnabled = false
//        settings.activeHours = 10...18
//        settings.activeDays = [.monday, .wednesday, .friday]
//        
//        // 2. Save settings
//        try await mockDataService.saveScheduleSettings(settings)
//        
//        // 3. Load settings
//        let loadedSettings = try await mockDataService.loadScheduleSettings()
//        XCTAssertNotNil(loadedSettings)
//        XCTAssertEqual(loadedSettings?.isEnabled, false)
//        XCTAssertEqual(loadedSettings?.activeHours, 10...18)
//        XCTAssertEqual(loadedSettings?.activeDays.count, 3)
//    }
//    
//    func testMethodCallTracking() async throws {
//        // 1. Verify initial state
//        XCTAssertTrue(mockDataService.methodCalls.isEmpty)
//        
//        // 2. Call various methods
//        try await mockDataService.saveAppGroup(try AppGroup(
//            id: UUID(),
//            name: "Test",
//            createdAt: Date(),
//            lastModified: Date()
//        ))
//        _ = try await mockDataService.loadAppGroups()
//        
//        // 3. Verify method calls were tracked
//        XCTAssertTrue(mockDataService.methodCalls.contains("saveAppGroup"))
//        XCTAssertTrue(mockDataService.methodCalls.contains("loadAppGroups"))
//    }
//}
//


// MARK: - Integration Tests for Data Persistence Service
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
        
        // 1. User creates initial app groups
        let socialGroup = try AppGroup(name: "Social Media")
        socialGroup.applications = Set<ApplicationToken>() // Would contain Facebook, Instagram, etc.
        socialGroup.categories = Set<ActivityCategoryToken>() // Would contain social categories
        
        let workGroup = try AppGroup(name: "Work Apps")
        workGroup.applications = Set<ApplicationToken>() // Would contain Slack, Email, etc.
        workGroup.categories = Set<ActivityCategoryToken>() // Would contain productivity categories
        
        try await service.saveAppGroup(socialGroup)
        try await service.saveAppGroup(workGroup)
        
        // 2. User configures schedule settings
        let scheduleSettings = ScheduleSettings()
        scheduleSettings.isEnabled = true
        scheduleSettings.activeHours = 9...18
        scheduleSettings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        scheduleSettings.timeZone = TimeZone.current
        
        try await service.saveScheduleSettings(scheduleSettings)
        
        // 3. User creates their first intention session
        let firstSession = try IntentionSession(
            applications: Set<ApplicationToken>(),
            duration: 15 * 60 // 15 minutes
        )
        firstSession.requestedAppGroups = [socialGroup.id]
        
        try await service.saveIntentionSession(firstSession)
        
        // 4. Verify all data was saved correctly
        let savedGroups = try await service.loadAppGroups()
        let savedSettings = try await service.loadScheduleSettings()
        let savedSessions = try await service.loadIntentionSessions()
        
        XCTAssertEqual(savedGroups.count, 2)
        XCTAssertNotNil(savedSettings)
        XCTAssertEqual(savedSessions.count, 1)
        
        XCTAssertTrue(savedGroups.contains { $0.name == "Social Media" })
        XCTAssertTrue(savedGroups.contains { $0.name == "Work Apps" })
        XCTAssertEqual(savedSettings!.activeDays.count, 5)
        XCTAssertEqual(savedSessions.first!.duration, 15 * 60)
    }
    
    func testSessionLifecycleManagement() async throws {
        // Test complete session lifecycle from creation to completion
        
        let appGroup = try AppGroup(name: "Productivity")
        appGroup.applications = Set<ApplicationToken>()
        appGroup.categories = Set<ActivityCategoryToken>()
        
        try await service.saveAppGroup(appGroup)
        
        // 1. Create active session
        let session = try IntentionSession(
            applications: Set<ApplicationToken>(),
            duration: 30 * 60 // 30 minutes
        )
        session.requestedAppGroups = [appGroup.id]
        session.state = .active(startedAt: Date())
        
        try await service.saveIntentionSession(session)
        
        // 2. Simulate session updates during usage
        // Session is being used, but still active
        try await service.saveIntentionSession(session)
        
        // 3. Pause session (if this functionality exists)
        let pausedTime = Date()
        session.state = .paused(totalElapsed: 300, pausedAt: pausedTime) // 5 minutes elapsed
        try await service.saveIntentionSession(session)
        
        // 4. Resume and complete session
        session.complete() // This should set isActive = false, wasCompleted = true
        try await service.saveIntentionSession(session)
        
        // 5. Verify final state
        let sessions = try await service.loadIntentionSessions()
        let completedSession = sessions.first!
        
        XCTAssertFalse(completedSession.isActive)
        XCTAssertTrue(completedSession.wasCompleted)
        XCTAssertNotNil(completedSession.endTime)
    }
    
    func testDataMigrationScenario() async throws {
        // Test scenario where user data needs to be updated/migrated
        
        // 1. Create initial app group
        let appGroup = try AppGroup(name: "Social")
        appGroup.applications = Set<ApplicationToken>()
        appGroup.categories = Set<ActivityCategoryToken>()
        
        try await service.saveAppGroup(appGroup)
        
        // 2. User updates the group (name, applications, etc.)
        appGroup.name = "Social Media & Communication"
        appGroup.updateModified() // This should update lastModified
        
        try await service.saveAppGroup(appGroup)
        
        // 3. Verify update was successful and no duplicates were created
        let groups = try await service.loadAppGroups()
        
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first!.name, "Social Media & Communication")
        XCTAssertEqual(groups.first!.id, appGroup.id)
    }
    
    func testBulkDataOperations() async throws {

        // Test performance and correctness with bulk operations
        
        // 1. Create multiple app groups
        var appGroups: [AppGroup] = []
        for i in 1...10 {
            let group = try AppGroup(name: "Group \(i)")
            group.applications = Set<ApplicationToken>()
            group.categories = Set<ActivityCategoryToken>()
            appGroups.append(group)
            try await service.saveAppGroup(group)
        }
        
        // 2. Create multiple sessions for different groups
        for (index, group) in appGroups.prefix(5).enumerated() {
            let session = try IntentionSession(
                applications: Set<ApplicationToken>(),
                duration: TimeInterval((index + 1) * 15 * 60) // 15, 30, 45, 60, 75 minutes
            )
            session.requestedAppGroups = [group.id]
            
            // Set appropriate state based on whether session should be active/completed
            let startTime = Date().addingTimeInterval(TimeInterval(-index * 3600)) // Spread over hours
            if index % 2 == 0 { // Active sessions
                session.state = .active(startedAt: startTime)
            } else { // Completed sessions
                let duration = TimeInterval((index + 1) * 15 * 60)
                session.state = .completed(totalElapsed: duration, completedAt: startTime.addingTimeInterval(duration))
            }
            
            try await service.saveIntentionSession(session)
        }
        
        // 3. Verify all data was saved
        let savedGroups = try await service.loadAppGroups()
        let savedSessions = try await service.loadIntentionSessions()
        
        XCTAssertEqual(savedGroups.count, 10)
        XCTAssertEqual(savedSessions.count, 5)
        
        // 4. Test bulk deletion
        let groupsToDelete = Array(appGroups.suffix(3))
        for group in groupsToDelete {
            try await service.deleteAppGroup(group.id)
        }
        
        let remainingGroups = try await service.loadAppGroups()
        XCTAssertEqual(remainingGroups.count, 7)
    }
    
    
    func testErrorRecoveryScenarios() async throws {
        // Test how the service handles various error scenarios
        
        // 1. Attempt to delete non-existent app group
        let nonExistentId = UUID()
        
        do {
            try await service.deleteAppGroup(nonExistentId)
            XCTFail("Expected error for non-existent app group")
        } catch AppError.dataNotFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        
        // 2. Attempt to delete non-existent session
        do {
            try await service.deleteIntentionSession(nonExistentId)
            XCTFail("Expected error for non-existent session")
        } catch AppError.dataNotFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        
        // 3. Test save/load with mock errors
        // Capture mock service locally to avoid data race warnings
        let currentMockService = mockService!
        currentMockService.shouldThrowSaveError = true
        
        let testGroup = try AppGroup(name: "Test")
        testGroup.applications = Set<ApplicationToken>()
        testGroup.categories = Set<ActivityCategoryToken>()
        
        do {
            try await service.saveAppGroup(testGroup)
            XCTFail("Expected save error")
        } catch AppError.persistenceError {
            // Expected error
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        
        // 4. Reset error flag and verify normal operation resumes
        currentMockService.shouldThrowSaveError = false
        
        try await service.saveAppGroup(testGroup)
        let savedGroups = try await service.loadAppGroups()
        XCTAssertEqual(savedGroups.count, 1)
    }
    
    
    func testConcurrentAccessScenarios() async throws {
        // Test concurrent access to the data service
        
        let group1 = try AppGroup(name: "Concurrent Group 1")
        group1.applications = Set<ApplicationToken>()
        group1.categories = Set<ActivityCategoryToken>()
        
        let group2 = try AppGroup(name: "Concurrent Group 2")
        group2.applications = Set<ApplicationToken>()
        group2.categories = Set<ActivityCategoryToken>()
        
        // Perform concurrent operations
        // Capture service locally to avoid data race warnings with async let
        let currentService = service!
        async let saveTask1: Void = currentService.saveAppGroup(group1)
        async let saveTask2: Void = currentService.saveAppGroup(group2)
        
        // Wait for both saves to complete
        _ = try await saveTask1
        _ = try await saveTask2
        
        // Verify both groups were saved
        let savedGroups = try await service.loadAppGroups()
        XCTAssertEqual(savedGroups.count, 2)
        
        let names = Set(savedGroups.map(\.name))
        XCTAssertTrue(names.contains("Concurrent Group 1"))
        XCTAssertTrue(names.contains("Concurrent Group 2"))
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
        
        // 1. Create multiple app groups
        let socialGroup = try AppGroup(name: "Social")
        socialGroup.applications = Set<ApplicationToken>()
        
        let workGroup = try AppGroup(name: "Work")
        workGroup.applications = Set<ApplicationToken>()
        
        let entertainmentGroup = try AppGroup(name: "Entertainment")
        entertainmentGroup.applications = Set<ApplicationToken>()
        
        try await service.saveAppGroup(socialGroup)
        try await service.saveAppGroup(workGroup)
        try await service.saveAppGroup(entertainmentGroup)
        
        // 2. Create session with multiple groups
        let session = try IntentionSession(
            applications: Set<ApplicationToken>(),
            duration: 60 * 60 // 1 hour
        )
        session.requestedAppGroups = [socialGroup.id, workGroup.id]
        
        try await service.saveIntentionSession(session)
        
        // 3. Verify session with multiple groups
        let sessions = try await service.loadIntentionSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first!.requestedAppGroups.count, 2)
        XCTAssertTrue(sessions.first!.requestedAppGroups.contains(socialGroup.id))
        XCTAssertTrue(sessions.first!.requestedAppGroups.contains(workGroup.id))
    }
    
    // MARK: - Performance Tests
    
    
    func testLargeDataSetPerformance() async throws {
        // Test performance with larger datasets
        let startTime = Date()
        
        // Create 50 app groups
        for i in 1...50 {
            let group = try AppGroup(name: "Performance Group \(i)")
            group.applications = Set<ApplicationToken>()
            group.categories = Set<ActivityCategoryToken>()
            try await service.saveAppGroup(group)
        }
        
        // Create 100 sessions
        for i in 1...100 {
            let session = try IntentionSession(
                applications: Set<ApplicationToken>(),
                duration: TimeInterval(1 * 5 * 60)
            )
            session.requestedAppGroups = [] // Empty for performance test
            
            // All sessions are completed for performance test
            let startTime = Date().addingTimeInterval(TimeInterval(-i * 60))
            let duration = TimeInterval(i * 60)
            session.state = .completed(totalElapsed: duration, completedAt: startTime.addingTimeInterval(duration))
            
            try await service.saveIntentionSession(session)
        }
        
        let saveTime = Date().timeIntervalSince(startTime)
        
        // Load all data
        let loadStartTime = Date()
        let groups = try await service.loadAppGroups()
        let sessions = try await service.loadIntentionSessions()
        let loadTime = Date().timeIntervalSince(loadStartTime)
        
        XCTAssertEqual(groups.count, 50)
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
