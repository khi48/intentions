// ScreenTimeServiceTests.swift
// Tests for ScreenTimeService using Application objects

import XCTest
@preconcurrency import FamilyControls
import ManagedSettings
@testable import Intentions

// MARK: - Sendable Conformance for FamilyControls Types
//extension Application: @unchecked @retroactive Sendable {}
//extension Set where Element == Application: @unchecked Sendable {}

final class MockScreenTimeServiceTests: XCTestCase {
    
    private var mockService: MockScreenTimeService!
    
    override func setUp() {
        super.setUp()
        mockService = MockScreenTimeService()
    }
    
    override func tearDown() {
        mockService = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() async throws {
        // Given - Fresh service
        let initialStatus = await mockService.getStatusInfo()
        XCTAssertFalse(initialStatus.isInitialized)
        
        // When - Initialize service
        try await mockService.initialize()
        
        // Then - Should be initialized
        let updatedStatus = await mockService.getStatusInfo()
        XCTAssertTrue(updatedStatus.isInitialized)
    }
    
    func testDoubleInitialization() async throws {
        // Given - Already initialized service
        try await mockService.initialize()
        
        // When - Initialize again
        try await mockService.initialize()
        
        // Then - Should not throw error
        let status = await mockService.getStatusInfo()
        XCTAssertTrue(status.isInitialized)
    }
    
    // MARK: - Authorization Tests
    
    func testRequestAuthorizationSuccess() async throws {
        // Given - Initialized service with approved authorization
        try await mockService.initialize()
        await mockService.setMockAuthorizationStatus(.approved)
        
        // When - Request authorization
        let isAuthorized = await mockService.requestAuthorization()
        
        // Then - Should be authorized
//        await mockService.isAuthorized()
        XCTAssertTrue(isAuthorized)
    }
    
//    func testRequestAuthorizationFailure() async throws {
//        // Given - Initialized service with denied authorization
//        try await mockService.initialize()
//        await mockService.setMockAuthorizationStatus(.denied)
//        
//        // When/Then - Request authorization should throw
////        do {
//        let _ = await mockService.requestAuthorization()
//        XCTFail("Expected authorization to fail")
////        } catch AppError.screenTimeAuthorizationFailed {
////            // Expected error
////        } catch {
////            XCTFail("Unexpected error: \(error)")
////        }
//    }
//    
////    func testRequestAuthorizationWithoutInitialization() async throws {
////        // Given - Uninitialized service
////        
////        // When/Then - Should throw initialization error
//////        do {
////        try await mockService.requestAuthorization()
////        XCTFail("Expected AppError.invalidConfiguration")
//////        } catch AppError.invalidConfiguration {
//////            // Expected error
//////        } catch {
//////            XCTFail("Unexpected error: \(error)")
//////        }
////    }
    
    // MARK: - App Management Tests
    
//    func testAllowApps() async throws {
//        // Given - Initialized and authorized service
//        try await mockService.initialize()
//        await mockService.setMockAuthorizationStatus(.approved)
//        try await mockService.requestAuthorization()
//        
//        // When - Allow apps using helper method
//        try await mockService.allowTestApps(count: 3, duration: 1800)
//        
//        // Then - Status should reflect allowed apps
//        let status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.hasActiveSession)
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 3)
//        XCTAssertNotNil(status.sessionEndTime)
//    }
//    
//    func testAllowAppsDirectly() async throws {
//        // Given - Ready service
//        try await mockService.initialize()
//        await mockService.setMockAuthorizationStatus(.approved)
//        try await mockService.requestAuthorization()
//        
//        // Create applications directly in actor
//        let applications = try await mockService.createTestApplications(count: 2)
//        
//        // When - Allow specific applications
//        try await mockService.allowApps(applications, duration: 3600)
//        
//        // Then - Should have active session
//        let status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.hasActiveSession)
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 2)
//    }
//    
//    func testBlockAllApps() async throws {
//        // Given - Service with active session
//        try await mockService.setupTestSession(appCount: 3, duration: 1800)
//        
//        // Verify session is active
//        var status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.hasActiveSession)
//        
//        // When - Block all apps
//        try await mockService.blockAllApps()
//        
//        // Then - Should have no active session
//        status = await mockService.getStatusInfo()
//        XCTAssertFalse(status.hasActiveSession)
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 0)
//        XCTAssertNil(status.sessionEndTime)
//    }
//    
//    func testStopRestrictions() async throws {
//        // Given - Service with active session
//        try await mockService.setupTestSession(appCount: 5, duration: 3600)
//        
//        // Verify session exists
//        var status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.hasActiveSession)
//        
//        // When - Stop restrictions
//        try await mockService.stopRestrictions()
//        
//        // Then - Should clear all restrictions
//        status = await mockService.getStatusInfo()
//        XCTAssertFalse(status.hasActiveSession)
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 0)
//    }
//    
//    // MARK: - Error Handling Tests
//    
//    func testAllowAppsWithoutInitialization() async throws {
//        // Given - Uninitialized service
//        
//        // When/Then - Should throw initialization error
//        do {
//            try await mockService.allowTestApps(count: 3, duration: 1800)
//            XCTFail("Expected AppError.invalidConfiguration")
//        } catch AppError.invalidConfiguration {
//            // Expected error
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
//    
//    func testAllowAppsWithoutAuthorization() async throws {
//        // Given - Service initialized but not authorized
//        try await mockService.initialize()
//        await mockService.setMockAuthorizationStatus(.denied)
//        
//        // When/Then - Should throw authorization error
//        do {
//            try await mockService.allowTestApps(count: 3, duration: 1800)
//            XCTFail("Expected AppError.screenTimeAuthorizationFailed")
//        } catch AppError.screenTimeAuthorizationFailed {
//            // Expected error
//        } catch {
//            XCTFail("Unexpected error: \(error)")
//        }
//    }
    
    func testBlockAllAppsWithoutInitialization() async throws {
        // Given - Uninitialized service
        
        // When/Then - Should throw initialization error
        do {
            try await mockService.blockAllApps()
            XCTFail("Expected AppError.screenTimeAuthorizationFailed")
        } catch AppError.screenTimeAuthorizationFailed {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Session Management Tests
    
//    func testSessionTimeout() async throws {
//        // Given - Service with very short session
//        try await mockService.setupTestSession(appCount: 2, duration: 0.1) // 0.1 seconds
//        
//        // Verify session is initially active
//        var status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.hasActiveSession)
//        
//        // When - Wait for session to expire
//        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
//        
//        // Then - Session should be expired
//        status = await mockService.getStatusInfo()
//        XCTAssertFalse(status.hasActiveSession)
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 0)
//    }
//    
//    func testMultipleAllowCallsOverwritePrevious() async throws {
//        // Given - Service with initial session
//        try await mockService.setupTestSession(appCount: 2, duration: 1800)
//        
//        // Verify initial session
//        var status = await mockService.getStatusInfo()
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 2)
//        
//        // When - Allow different set of apps
//        try await mockService.allowTestApps(count: 5, duration: 3600)
//        
//        // Then - Should have new session
//        status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.hasActiveSession)
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 5)
//    }
//    
//    func testGetRemainingSessionTime() async throws {
//        // Given - Service with active session
//        try await mockService.setupTestSession(appCount: 3, duration: 1800) // 30 minutes
//        
//        // When - Get remaining time
//        let remainingTime = await mockService.getRemainingSessionTime()
//        
//        // Then - Should have remaining time close to 30 minutes
//        XCTAssertNotNil(remainingTime)
//        XCTAssertGreaterThan(remainingTime!, 1795) // Allow small margin for execution time
//        XCTAssertLessThan(remainingTime!, 1800)
//    }
//    
//    // MARK: - Status Information Tests
//    
//    func testStatusInfoProgression() async throws {
//        // Given - Fresh service
//        var status = await mockService.getStatusInfo()
//        XCTAssertFalse(status.isInitialized)
//        XCTAssertFalse(status.isAuthorized)
//        XCTAssertFalse(status.hasActiveSession)
//        
//        // When - Initialize
//        try await mockService.initialize()
//        status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.isInitialized)
//        XCTAssertFalse(status.isAuthorized)
//        
//        // When - Authorize
//        await mockService.setMockAuthorizationStatus(.approved)
//        try await mockService.requestAuthorization()
//        status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.isAuthorized)
//        
//        // When - Allow apps
//        try await mockService.allowTestApps(count: 4, duration: 3600)
//        status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.hasActiveSession)
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 4)
//    }
//    
//    func testHasActiveSession() async throws {
//        // Given - Service without session
//        try await mockService.initialize()
//        XCTAssertFalse(await mockService.hasActiveSession())
//        
//        // When - Create session
//        try await mockService.setupTestSession(appCount: 2, duration: 1800)
//        
//        // Then - Should have active session
//        XCTAssertTrue(await mockService.hasActiveSession())
//        
//        // When - Stop restrictions
//        try await mockService.stopRestrictions()
//        
//        // Then - Should not have active session
//        XCTAssertFalse(await mockService.hasActiveSession())
//    }
//    
//    func testGetAllowedAppsCount() async throws {
//        // Given - Service without apps
//        try await mockService.initialize()
//        XCTAssertEqual(await mockService.getAllowedAppsCount(), 0)
//        
//        // When - Allow apps
//        try await mockService.setupTestSession(appCount: 7, duration: 1800)
//        
//        // Then - Should return correct count
//        XCTAssertEqual(await mockService.getAllowedAppsCount(), 7)
//    }
//    
//    // MARK: - Mock State Management Tests
//    
//    func testMockStateReset() async throws {
//        // Given - Service with active session
//        try await mockService.setupTestSession(appCount: 3, duration: 1800)
//        XCTAssertTrue(await mockService.hasActiveSession())
//        
//        // When - Reset mock state
//        await mockService.resetMockState()
//        
//        // Then - Should be back to initial state
//        let status = await mockService.getStatusInfo()
//        XCTAssertFalse(status.isInitialized)
//        XCTAssertFalse(status.isAuthorized)
//        XCTAssertFalse(status.hasActiveSession)
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 0)
//    }
//    
//    func testMockAuthorizationStatusControl() async throws {
//        // Given - Initialized service
//        try await mockService.initialize()
//        
//        // Test approved status
//        await mockService.setMockAuthorizationStatus(.approved)
//        XCTAssertTrue(await mockService.isAuthorized())
//        XCTAssertEqual(await mockService.getMockAuthorizationStatus(), .approved)
//        
//        // Test denied status
//        await mockService.setMockAuthorizationStatus(.denied)
//        XCTAssertFalse(await mockService.isAuthorized())
//        XCTAssertEqual(await mockService.getMockAuthorizationStatus(), .denied)
//        
//        // Test not determined status
//        await mockService.setMockAuthorizationStatus(.notDetermined)
//        XCTAssertFalse(await mockService.isAuthorized())
//        XCTAssertEqual(await mockService.getMockAuthorizationStatus(), .notDetermined)
//    }
//    
//    // MARK: - Integration Tests
//    
//    func testCompleteWorkflow() async throws {
//        // Test a complete workflow from start to finish
//        
//        // Initialize
//        try await mockService.initialize()
//        var status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.isInitialized)
//        
//        // Authorize
//        await mockService.setMockAuthorizationStatus(.approved)
//        try await mockService.requestAuthorization()
//        XCTAssertTrue(await mockService.isAuthorized())
//        
//        // Allow apps
//        try await mockService.allowTestApps(count: 3, duration: 1800)
//        status = await mockService.getStatusInfo()
//        XCTAssertTrue(status.hasActiveSession)
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 3)
//        
//        // Block all apps
//        try await mockService.blockAllApps()
//        status = await mockService.getStatusInfo()
//        XCTAssertFalse(status.hasActiveSession)
//        XCTAssertEqual(status.currentlyAllowedAppsCount, 0)
//    }
}
