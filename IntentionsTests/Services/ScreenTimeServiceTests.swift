// IntentionsTests/Services/ScreenTimeServiceTests.swift
// Unit tests for ScreenTime Service business logic

import XCTest
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

extension ApplicationToken: @unchecked Sendable {}

final class ScreenTimeServiceTests: XCTestCase, @unchecked Sendable {
    
    private var mockService: MockScreenTimeService!
    
    override func setUp() {
        super.setUp()
        mockService = MockScreenTimeService()
    }
    
    override func tearDown() {
        mockService = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestToken() throws -> ApplicationToken {
        let tokenData = """
        {
            "data": "dGVzdERhdGE="
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        return try decoder.decode(ApplicationToken.self, from: tokenData)
    }
    
    private func createTestTokens(count: Int = 2) throws -> Set<ApplicationToken> {
        var tokens: Set<ApplicationToken> = []
        for i in 0..<count {
            let base64String = Data("testData\(i)".utf8).base64EncodedString()
            
            let tokenData = """
            {
                "data": "\(base64String)"
            }
            """.data(using: .utf8)!
            
            let decoder = JSONDecoder()
            let token = try decoder.decode(ApplicationToken.self, from: tokenData)
            tokens.insert(token)
        }
        return tokens
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationFlow() async throws {
        // Given - Fresh service
        let statusBefore = await mockService.getStatusInfo()
        XCTAssertFalse(statusBefore.isInitialized)
        XCTAssertFalse(statusBefore.isFullyOperational)
        
        // When - Initialize
        try await mockService.initialize()
        
        // Then - Should be initialized and operational
        let statusAfter = await mockService.getStatusInfo()
        XCTAssertTrue(statusAfter.isInitialized)
        XCTAssertTrue(statusAfter.isFullyOperational)
        XCTAssertEqual(statusAfter.authorizationStatus, .approved)
    }
    
    func testDoubleInitializationIsIdempotent() async throws {
        // Given - Already initialized service
        try await mockService.initialize()
        let statusAfterFirst = await mockService.getStatusInfo()
        
        // When - Initialize again
        try await mockService.initialize()
        
        // Then - Should remain in same state
        let statusAfterSecond = await mockService.getStatusInfo()
        XCTAssertEqual(statusAfterFirst.isInitialized, statusAfterSecond.isInitialized)
        XCTAssertEqual(statusAfterFirst.authorizationStatus, statusAfterSecond.authorizationStatus)
    }
    
    func testInitializationFailsWithoutAuthorization() async {
        // Given - Service with denied authorization
        await mockService.setMockAuthorizationStatus(.denied)
        
        // When/Then - Initialize should fail
        do {
            try await mockService.initialize()
            XCTFail("Initialize should fail without authorization")
        } catch AppError.screenTimeAuthorizationFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Authorization Tests
    
    func testRequestAuthorizationSuccess() async {
        // When - Request authorization
        let success = await mockService.requestAuthorization()
        
        // Then - Should succeed and update status
        XCTAssertTrue(success)
        
        let status = await mockService.authorizationStatus()
        XCTAssertEqual(status, .approved)
    }
    
    func testAuthorizationStatusReturnsCorrectValue() async {
        // Given - Set specific status
        await mockService.setMockAuthorizationStatus(.denied)
        
        // When - Check status
        let status = await mockService.authorizationStatus()
        
        // Then - Should return set status
        XCTAssertEqual(status, .denied)
    }
    
    // MARK: - App Blocking Tests
    
    func testBlockAllAppsRequiresAuthorization() async {
        // Given - Service without authorization
        await mockService.setMockAuthorizationStatus(.denied)
        
        // When/Then - Block should fail
        do {
            try await mockService.blockAllApps()
            XCTFail("Block should fail without authorization")
        } catch AppError.screenTimeAuthorizationFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testBlockAllAppsClearsAllowedApps() async throws {
        // Given - Service with some allowed apps
        try await mockService.initialize()
        let tokens = try createTestTokens()
        try await mockService.allowApps(tokens, duration: 3600, sessionId: UUID())
        
        let allowedBefore = await mockService.getCurrentlyAllowedApps()
        XCTAssertFalse(allowedBefore.isEmpty)
        
        // When - Block all apps
        try await mockService.blockAllApps()
        
        // Then - Should clear allowed apps
        let allowedAfter = await mockService.getCurrentlyAllowedApps()
        XCTAssertTrue(allowedAfter.isEmpty)
    }
    
    func testBlockAllAppsCancelsActiveSessions() async throws {
        // Given - Service with active session
        try await mockService.initialize()
        let tokens = try createTestTokens()
        try await mockService.allowApps(tokens, duration: 3600, sessionId: UUID())
        
        let statusBefore = await mockService.getStatusInfo()
        XCTAssertTrue(statusBefore.hasActiveSession)
        
        // When - Block all apps
        try await mockService.blockAllApps()
        
        // Then - Should cancel session
        let statusAfter = await mockService.getStatusInfo()
        XCTAssertFalse(statusAfter.hasActiveSession)
    }
    
    // MARK: - App Allowing Tests
    
    func testAllowAppsRequiresAuthorization() async {
        // Given - Service without authorization
        await mockService.setMockAuthorizationStatus(.denied)
        
        // When/Then - Allow should fail
        do {
            let tokens = try createTestTokens()
            try await mockService.allowApps(tokens, duration: 1800, sessionId: UUID())
            XCTFail("Allow should fail without authorization")
        } catch AppError.screenTimeAuthorizationFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testAllowAppsWithValidDuration() async throws {
        // Given - Initialized service
        try await mockService.initialize()
        let tokens = try createTestTokens(count: 3)
        
        // When - Allow apps
        try await mockService.allowApps(tokens, duration: 1800, sessionId: UUID())
        
        // Then - Apps should be allowed
        let allowedApps = await mockService.getCurrentlyAllowedApps()
        XCTAssertEqual(allowedApps.count, 3)
        XCTAssertEqual(allowedApps, tokens)
        
        // Should have active session
        let status = await mockService.getStatusInfo()
        XCTAssertTrue(status.hasActiveSession)
    }
    
    func testAllowAppsRejectsInvalidDuration() async throws {
        // Given - Initialized service
        try await mockService.initialize()
        let tokens = try createTestTokens()
        
        // When/Then - Should reject negative duration
        do {
            try await mockService.allowApps(tokens, duration: -1, sessionId: UUID())
            XCTFail("Should reject negative duration")
        } catch AppError.invalidConfiguration(let message) {
            XCTAssertTrue(message.contains("greater than 0"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
        
        // When/Then - Should reject zero duration
        do {
            try await mockService.allowApps(tokens, duration: 0, sessionId: UUID())
            XCTFail("Should reject zero duration")
        } catch AppError.invalidConfiguration {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testAllowAppsReplacesExistingSession() async throws {
        // Given - Service with existing session
        try await mockService.initialize()
        let firstTokens = try createTestTokens(count: 1)
        try await mockService.allowApps(firstTokens, duration: 3600, sessionId: UUID())
        
        let allowedFirst = await mockService.getCurrentlyAllowedApps()
        XCTAssertEqual(allowedFirst.count, 1)
        
        // When - Allow different apps
        let secondTokens = try createTestTokens(count: 2)
        try await mockService.allowApps(secondTokens, duration: 1800, sessionId: UUID())
        
        // Then - Should replace previous session
        let allowedSecond = await mockService.getCurrentlyAllowedApps()
        XCTAssertEqual(allowedSecond.count, 2)
        XCTAssertEqual(allowedSecond, secondTokens)
        XCTAssertNotEqual(allowedSecond, firstTokens)
    }
    
    // MARK: - Session Expiration Tests
    
    func testSessionExpiresAutomatically() async throws {
        // Given - Service with short session
        try await mockService.initialize()
        let tokens = try createTestTokens()
        
        // When - Allow apps for very short duration
        try await mockService.allowApps(tokens, duration: 0.1, sessionId: UUID()) // 100ms
        
        // Verify apps are initially allowed
        let allowedBefore = await mockService.getCurrentlyAllowedApps()
        XCTAssertEqual(allowedBefore, tokens)
        
        // Wait for expiration
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Then - Apps should be blocked again
        let allowedAfter = await mockService.getCurrentlyAllowedApps()
        XCTAssertTrue(allowedAfter.isEmpty, "Apps should be blocked after expiration")
    }
    
    func testSessionExpirationCancellation() async throws {
        // Given - Service with long session
        try await mockService.initialize()
        let tokens = try createTestTokens()
        try await mockService.allowApps(tokens, duration: 10, sessionId: UUID()) // 10 seconds
        
        let statusBefore = await mockService.getStatusInfo()
        XCTAssertTrue(statusBefore.hasActiveSession)
        
        // When - Manually revoke access
        try await mockService.allowAllAccess()
        
        // Then - Session should be cancelled
        let statusAfter = await mockService.getStatusInfo()
        XCTAssertFalse(statusAfter.hasActiveSession)
        
        let allowedApps = await mockService.getCurrentlyAllowedApps()
        XCTAssertTrue(allowedApps.isEmpty)
    }
    
    // MARK: - App Permission Tests
    
    func testIsAppAllowedForAllowedApp() async throws {
        // Given - Service with allowed apps
        try await mockService.initialize()
        let tokens = try createTestTokens()
        try await mockService.allowApps(tokens, duration: 3600, sessionId: UUID())
        
        // When - Check if app is allowed
        let testToken = tokens.first!
        let isAllowed = await mockService.isAppAllowed(testToken)
        
        // Then - Should return true
        XCTAssertTrue(isAllowed)
    }
    
    func testIsAppAllowedForBlockedApp() async throws {
        // Given - Service with no allowed apps
        try await mockService.initialize()
        let testToken = try createTestToken()
        
        // When - Check if app is allowed
        let isAllowed = await mockService.isAppAllowed(testToken)
        
        // Then - Should return false
        XCTAssertFalse(isAllowed)
    }
    
    func testIsAppAllowedForSystemApp() async throws {
        // Given - Service with system app
        try await mockService.initialize()
        let systemToken = try createTestToken()
        await mockService.addMockSystemApp(systemToken)
        
        // When - Check if system app is allowed
        let isAllowed = await mockService.isAppAllowed(systemToken)
        
        // Then - System apps should always be allowed
        XCTAssertTrue(isAllowed)
    }
    
    // MARK: - System Apps Tests
    
    func testAddEssentialSystemApp() async throws {
        // Given - Service
        let systemToken = try createTestToken()
        
        // When - Add system app
        await mockService.addMockSystemApp(systemToken)
        
        // Then - Should be in system apps list
        let systemApps = await mockService.getEssentialSystemApps()
        XCTAssertTrue(systemApps.contains(systemToken))
    }
    
    func testSystemAppsCountInStatus() async throws {
        // Given - Service with system apps
        let systemTokens = try createTestTokens(count: 3)
        for token in systemTokens {
            await mockService.addMockSystemApp(token)
        }
        
        // When - Get status
        let status = await mockService.getStatusInfo()
        
        // Then - Should report correct count
        XCTAssertEqual(status.essentialSystemAppsCount, 3)
    }
    
    // MARK: - Revoke Access Tests
    
    func testRevokeAllAccessRequiresAuthorization() async {
        // Given - Service without authorization
        await mockService.setMockAuthorizationStatus(.denied)
        
        // When/Then - Revoke should fail
        do {
            try await mockService.allowAllAccess()
            XCTFail("Revoke should fail without authorization")
        } catch AppError.screenTimeAuthorizationFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testRevokeAllAccessClearsAppsAndSession() async throws {
        // Given - Service with active session
        try await mockService.initialize()
        let tokens = try createTestTokens()
        try await mockService.allowApps(tokens, duration: 3600, sessionId: UUID())
        
        let allowedBefore = await mockService.getCurrentlyAllowedApps()
        XCTAssertFalse(allowedBefore.isEmpty)
        
        let statusBefore = await mockService.getStatusInfo()
        XCTAssertTrue(statusBefore.hasActiveSession)
        
        // When - Revoke access
        try await mockService.allowAllAccess()
        
        // Then - Should clear apps and cancel session
        let allowedAfter = await mockService.getCurrentlyAllowedApps()
        XCTAssertTrue(allowedAfter.isEmpty)
        
        let statusAfter = await mockService.getStatusInfo()
        XCTAssertFalse(statusAfter.hasActiveSession)
    }
    
    // MARK: - Status Information Tests
    
    func testStatusInfoAccuracy() async throws {
        // Given - Service in various states
        try await mockService.initialize()
        
        let systemTokens = try createTestTokens(count: 2)
        for token in systemTokens {
            await mockService.addMockSystemApp(token)
        }
        
        let userTokens = try createTestTokens(count: 3)
        try await mockService.allowApps(userTokens, duration: 3600, sessionId: UUID())
        
        // When - Get status
        let status = await mockService.getStatusInfo()
        
        // Then - Should reflect actual state
        XCTAssertEqual(status.authorizationStatus, .approved)
        XCTAssertTrue(status.isInitialized)
        XCTAssertTrue(status.isFullyOperational)
        XCTAssertEqual(status.currentlyAllowedAppsCount, 3)
        XCTAssertEqual(status.essentialSystemAppsCount, 2)
        XCTAssertTrue(status.hasActiveSession)
        
        XCTAssertTrue(status.statusDescription.contains("Fully operational"))
        XCTAssertTrue(status.statusDescription.contains("3 apps allowed"))
    }
    
    func testStatusDescriptionForDifferentStates() async throws {
        // Test not determined status
        await mockService.setMockAuthorizationStatus(.notDetermined)
        var status = await mockService.getStatusInfo()
        XCTAssertTrue(status.statusDescription.contains("not requested"))
        
        // Test denied status
        await mockService.setMockAuthorizationStatus(.denied)
        status = await mockService.getStatusInfo()
        XCTAssertTrue(status.statusDescription.contains("denied"))
        
        // Test approved but not initialized
        await mockService.setMockAuthorizationStatus(.approved)
        status = await mockService.getStatusInfo()
        XCTAssertTrue(status.statusDescription.contains("not initialized"))
        
        // Test fully operational
        try await mockService.initialize()
        status = await mockService.getStatusInfo()
        XCTAssertTrue(status.statusDescription.contains("Fully operational"))
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentAllowRequests() async throws {
        // Given - Initialized service
        try await mockService.initialize()
        
        let tokens1 = try createTestTokens(count: 1)
        let tokens2 = try createTestTokens(count: 2)
        
        // When - Make concurrent allow requests
        async let result1: Void = mockService.allowApps(tokens1, duration: 1800, sessionId: UUID())
        async let result2: Void = mockService.allowApps(tokens2, duration: 3600, sessionId: UUID())
        
        // Then - Both should complete without errors
        try await result1
        try await result2
        
        // Last one should win
        let finalAllowed = await mockService.getCurrentlyAllowedApps()
        XCTAssertTrue(finalAllowed.count > 0, "Should have some apps allowed")
    }
    
    func testConcurrentBlockAndAllow() async throws {
        // Given - Initialized service
        try await mockService.initialize()
        let tokens = try createTestTokens()
        
        // When - Make concurrent block and allow requests
        async let blockResult: Void = mockService.blockAllApps()
        async let allowResult: Void = mockService.allowApps(tokens, duration: 1800, sessionId: UUID())
        
        // Then - Both should complete without errors
        try await blockResult
        try await allowResult
        
        // Final state should be consistent
        let status = await mockService.getStatusInfo()
        XCTAssertTrue(status.isFullyOperational)
    }
}
