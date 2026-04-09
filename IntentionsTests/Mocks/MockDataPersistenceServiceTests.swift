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

        // When
        await mockService.reset()

        // Then
        let loadedString = try await mockService.load(String.self, forKey: "test")

        XCTAssertNil(loadedString)
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
