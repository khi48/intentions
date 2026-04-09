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
        XCTAssertTrue(isAuthorized)
    }

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
    
}
