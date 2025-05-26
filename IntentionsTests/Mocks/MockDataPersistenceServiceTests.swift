//
//  MockDataPersistenceServiceTests.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 02/07/2025.
//

import XCTest
@preconcurrency import FamilyControls
import ManagedSettings
@testable import Intentions

// MARK: - Mock Service Tests
final class MockDataPersistenceServiceTests: XCTestCase {
    
    var mockService: MockDataPersistenceService!
    
    override func setUp() async throws {
        try await super.setUp()
        mockService = MockDataPersistenceService()
    }
    
    override func tearDown() async throws {
        await mockService.reset()
        mockService = nil
        try await super.tearDown()
    }
    
    @MainActor
    func testMockServiceBasicFunctionality() async throws {
        // Given
        let testString = "test_value"
        let key = "test_key"
        
        // When
        try await mockService.save(testString, forKey: key)
        let result = try await mockService.load(String.self, forKey: key)
        
        // Then
        XCTAssertEqual(result, testString)
    }
    
    @MainActor
    func testMockServiceErrorSimulation() async throws {
        // Given
        mockService.shouldThrowSaveError = true
        
        // When & Then
        do {
            try await mockService.save("test", forKey: "test")
            XCTFail("Expected save error")
        } catch AppError.persistenceError {
            // Expected error
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    @MainActor
    func testMockServiceReset() async throws {
        // Given
        try await mockService.save("test", forKey: "test")
        
        let appGroup = try AppGroup(name: "Test")
        try await mockService.saveAppGroup(appGroup)
        
        // When
        await mockService.reset()
        
        // Then
        let loadedString = try await mockService.load(String.self, forKey: "test")
        let appGroupCount = await mockService.getStoredAppGroupCount()
        
        XCTAssertNil(loadedString)
        XCTAssertEqual(appGroupCount, 0)
    }
    
    @MainActor
    func testMockServiceAppGroupOperations() async throws {
        // Given
        let appGroup = try AppGroup(name: "Test Group")
        appGroup.applications = Set<ApplicationToken>()
        appGroup.categories = Set<ActivityCategoryToken>()
        
        // When
        try await mockService.saveAppGroup(appGroup)
        let groups = try await mockService.loadAppGroups()
        let retrievedGroup = await mockService.getAppGroup(id: appGroup.id)
        
        // Then
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, "Test Group")
        XCTAssertNotNil(retrievedGroup)
        XCTAssertEqual(retrievedGroup?.id, appGroup.id)
    }
    
    @MainActor
    func testMockServiceSessionOperations() async throws {
        // Given
        let session = try IntentionSession(
            applications: Set<ApplicationToken>(),
            duration: 30 * 60
        )
        session.requestedAppGroups = [UUID()]
        
        // When
        try await mockService.saveIntentionSession(session)
        let sessions = try await mockService.loadIntentionSessions()
        let retrievedSession = await mockService.getSession(id: session.id)
        
        // Then
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, session.id)
        XCTAssertNotNil(retrievedSession)
        XCTAssertEqual(retrievedSession?.duration, 30 * 60)
    }
    
    @MainActor
    func testMockServiceScheduleSettingsOperations() async throws {
        // Given
        let settings = ScheduleSettings()
        settings.isEnabled = true
        settings.activeHours = 9...17
        settings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        
        // When
        try await mockService.saveScheduleSettings(settings)
        let loadedSettings = try await mockService.loadScheduleSettings()
        let hasSettings = await mockService.hasScheduleSettings()
        
        // Then
        XCTAssertNotNil(loadedSettings)
        XCTAssertEqual(loadedSettings?.isEnabled, true)
        XCTAssertEqual(loadedSettings?.activeHours, 9...17)
        XCTAssertTrue(hasSettings)
    }
}
