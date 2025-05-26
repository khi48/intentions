//
//  IntentionSessionTests.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//
// IntentionSessionTests.swift
// Unit tests for IntentionSession model

import XCTest
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

final class IntentionSessionTests: XCTestCase {
    
    // Helper method to create test session without throwing
    private func createTestSession(appGroups: [UUID] = [], applications: Set<ApplicationToken> = [], duration: TimeInterval = 1800) -> IntentionSession {
        do {
            return try IntentionSession(appGroups: appGroups, applications: applications, duration: duration)
        } catch {
            XCTFail("Failed to create test session: \(error)")
            // Return a dummy session that won't be used due to XCTFail
            // Use the passed duration parameter instead of hardcoded 1800
            return try! IntentionSession(duration: duration)
        }
    }
    
    // Helper method to safely create ApplicationToken for testing
    private func createSafeToken() throws -> ApplicationToken {
        let tokenData = """
            {
                "data": "dGVzdA=="
            }
            """.data(using: .utf8)!
        let decoder = JSONDecoder()
        return try decoder.decode(ApplicationToken.self, from: tokenData)
    }
    
    // Helper to create a set of test tokens
    private func createTestTokens(count: Int = 2) -> Set<ApplicationToken> {
        var tokens: Set<ApplicationToken> = []
        for _ in 0..<count {
            do {
                let token = try createSafeToken()
                tokens.insert(token)
            } catch {
                XCTFail("Cannot create ApplicationToken for testing: \(error)")
                break
            }
        }
        return tokens
    }
    
    func testIntentionSessionInitialization() {
        // Given
        let duration: TimeInterval = 1800 // 30 minutes
        let appGroups = [UUID(), UUID()]
        
        // When
        let session = createTestSession(appGroups: appGroups, duration: duration)
        
        // Then
        XCTAssertEqual(session.requestedAppGroups, appGroups)
        XCTAssertEqual(session.duration, duration)
        XCTAssertTrue(session.isActive)
        XCTAssertFalse(session.wasCompleted)
        XCTAssertTrue(session.requestedApplications.isEmpty)
        
        // Check time calculations
        XCTAssertEqual(session.endTime.timeIntervalSince(session.startTime), duration, accuracy: 0.1)
        XCTAssertFalse(session.isExpired) // Should not be expired immediately
    }
    
    func testRemainingTimeCalculation() {
        // Given
        let duration: TimeInterval = 300 // 5 minute
        let session = createTestSession(duration: duration)
        
        // When - Immediately after creation
        let remainingTime = session.remainingTime
        
        // Then
        XCTAssertGreaterThan(remainingTime, 290) // Should be close to 60 seconds
        XCTAssertLessThanOrEqual(remainingTime, duration)
    }
    
    func testExpiredSession() {
        // Given - Create session with completed state (simulating expired session)
        let session = createTestSession(duration: 300)
        let endTime = Date().addingTimeInterval(-300) // 1 minute ago
        session.state = .completed(totalElapsed: 300, completedAt: endTime)
        
        // When & Then
        XCTAssertTrue(session.isExpired)
        XCTAssertEqual(session.remainingTime, 0)
    }
    
    func testProgressPercentage() {
        // Given
        let duration: TimeInterval = 300
        let session = createTestSession(duration: duration)
        
        // When - Simulate 25% progress with active state
        let startTime = Date().addingTimeInterval(-75)
        session.state = .active(startedAt: startTime)
        
        // Then
        let progress = session.progressPercentage
        XCTAssertGreaterThanOrEqual(progress, 0.2)
        XCTAssertLessThanOrEqual(progress, 0.3)
    }
    
    func testSessionCompletion() {
        // Given
        let session = createTestSession(duration: 300)
        XCTAssertTrue(session.isActive)
        XCTAssertFalse(session.wasCompleted)
        
        // When
        session.complete()
        
        // Then
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.wasCompleted)
    }
    
    func testSessionCancellation() {
        // Given
        let session = createTestSession(duration: 300)
        XCTAssertTrue(session.isActive)
        XCTAssertFalse(session.wasCompleted)
        
        // When
        session.cancel()
        
        // Then
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.wasCompleted)
    }
    
    func testIntentionSessionCodable() throws {
        // Given
        let appGroups = [UUID(), UUID()]
        let duration: TimeInterval = 3600
        let session = createTestSession(appGroups: appGroups, duration: duration)
        session.complete()
        
        // When - Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        
        // Then - Decode
        let decoder = JSONDecoder()
        let decodedSession = try decoder.decode(IntentionSession.self, from: data)
        
        XCTAssertEqual(decodedSession.id, session.id)
        XCTAssertEqual(decodedSession.requestedAppGroups, session.requestedAppGroups)
        XCTAssertEqual(decodedSession.duration, session.duration)
        XCTAssertEqual(decodedSession.isActive, session.isActive)
        XCTAssertEqual(decodedSession.wasCompleted, session.wasCompleted)
        XCTAssertEqual(decodedSession.startTime.timeIntervalSince1970,
                      session.startTime.timeIntervalSince1970, accuracy: 0.001)
    }
    
//    func testZeroDurationSession() {
//        // Given
//        XCTAssertThrowsError(
//            try session = createTestSession(duration: 0)
//        ) {
////            XCTAssertTrue()
//        }
//        
//        // Then
////        XCTAssertEqual(session.duration, 0)
////        XCTAssertEqual(session.progressPercentage, 0)
////        XCTAssertEqual(session.remainingTime, 0)
////        XCTAssertTrue(session.isExpired) // Zero duration should be immediately expired
//    }
    
    func testSessionWithApplicationTokens() {
        // Given
        let tokens = createTestTokens(count: 2)
        
        // Skip test if we can't create tokens
        guard !tokens.isEmpty else {
            let _ = XCTSkip("Cannot create ApplicationTokens for testing")
            return
        }
        
        let session = createTestSession(applications: tokens, duration: 1800)
        
        // Then
        XCTAssertEqual(session.requestedApplications.count, tokens.count)
        XCTAssertTrue(session.requestedAppGroups.isEmpty)
    }
    
    func testMixedSessionContent() {
        // Given
        let appGroups = [UUID()]
        let tokens = createTestTokens(count: 1)
        
        // Skip test if we can't create tokens
        guard !tokens.isEmpty else {
            let _ = XCTSkip("Cannot create ApplicationTokens for testing")
            return
        }
        
        let session = createTestSession(appGroups: appGroups, applications: tokens, duration: 3600)
        
        // Then
        XCTAssertEqual(session.requestedAppGroups.count, 1)
        XCTAssertEqual(session.requestedApplications.count, 1)
    }
    
    func testSessionCodableWithApplicationTokens() throws {
        // Given
        let tokens = createTestTokens(count: 1)
        
        // Skip test if we can't create tokens
        guard !tokens.isEmpty else {
            throw XCTSkip("Cannot create ApplicationTokens for testing")
        }
        
        let session = createTestSession(applications: tokens, duration: 1800)
        
        // When - Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        
        // Then - Decode (note: ApplicationTokens may not decode properly)
        let decoder = JSONDecoder()
        let decodedSession = try decoder.decode(IntentionSession.self, from: data)
        
        XCTAssertEqual(decodedSession.id, session.id)
        XCTAssertEqual(decodedSession.duration, session.duration)
        // Note: requestedApplications may be empty after decoding due to ApplicationToken limitations
    }
    
    // Test session logic without relying on ApplicationTokens
    func testSessionLogicWithoutTokens() {
        // Given - Test core session functionality without ApplicationTokens
        let session = createTestSession(duration: 3600)
        
        // Test initial state
        XCTAssertTrue(session.isActive)
        XCTAssertFalse(session.wasCompleted)
        XCTAssertFalse(session.isExpired)
        
        // Test time calculations
        XCTAssertGreaterThan(session.remainingTime, 3500) // Should be close to 3600
        XCTAssertLessThanOrEqual(session.progressPercentage, 0.1) // Should be very small initially
        
        // Test state changes
        session.complete()
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.wasCompleted)
        
        // Create another session for cancel test
        let cancelSession = createTestSession(duration: 1800)
        cancelSession.cancel()
        XCTAssertFalse(cancelSession.isActive)
        XCTAssertFalse(cancelSession.wasCompleted)
    }
    
    func testSessionWithOnlyAppGroups() {
        // Given - Test session with only app groups (no ApplicationTokens)
        let appGroups = [UUID(), UUID(), UUID()]
        let session = createTestSession(appGroups: appGroups, duration: 2700) // 45 minutes
        
        // Then
        XCTAssertEqual(session.requestedAppGroups.count, 3)
        XCTAssertTrue(session.requestedApplications.isEmpty)
        XCTAssertEqual(session.duration, 2700)
        XCTAssertTrue(session.isActive)
    }
    
    // MARK: - Validation Tests
    
    func testSessionDurationTooShort() throws {
        // Given - duration less than minimum
        let shortDuration = AppConstants.Session.minimumDuration - 1
        
        // When & Then
        XCTAssertThrowsError(try IntentionSession(duration: shortDuration)) { error in
            if case AppError.invalidConfiguration(let message) = error {
                XCTAssertTrue(message.contains("Session duration must be at least"))
            } else {
                XCTFail("Expected AppError.invalidConfiguration but got \(error)")
            }
        }
    }
    
    func testSessionDurationTooLong() throws {
        // Given - duration greater than maximum
        let longDuration = AppConstants.Session.maximumDuration + 1
        
        // When & Then
        XCTAssertThrowsError(try IntentionSession(duration: longDuration)) { error in
            if case AppError.invalidConfiguration(let message) = error {
                XCTAssertTrue(message.contains("Session duration cannot exceed"))
            } else {
                XCTFail("Expected AppError.invalidConfiguration but got \(error)")
            }
        }
    }
    
    func testSessionValidBoundaryDurations() throws {
        // Given - durations exactly at boundaries
        let minDuration = AppConstants.Session.minimumDuration
        let maxDuration = AppConstants.Session.maximumDuration
        
        // When & Then - should not throw
        let minSession = try IntentionSession(duration: minDuration)
        let maxSession = try IntentionSession(duration: maxDuration)
        
        XCTAssertEqual(minSession.duration, minDuration)
        XCTAssertEqual(maxSession.duration, maxDuration)
    }
    
    func testSessionZeroDurationValidation() throws {
        // Given - zero duration
        let zeroDuration: TimeInterval = 0
        
        // When & Then
        XCTAssertThrowsError(try IntentionSession(duration: zeroDuration)) { error in
            if case AppError.invalidConfiguration(let message) = error {
                XCTAssertTrue(message.contains("Session duration must be at least"))
            } else {
                XCTFail("Expected AppError.invalidConfiguration but got \(error)")
            }
        }
    }
    
    func testSessionNegativeDurationValidation() throws {
        // Given - negative duration
        let negativeDuration: TimeInterval = -60
        
        // When & Then
        XCTAssertThrowsError(try IntentionSession(duration: negativeDuration)) { error in
            if case AppError.invalidConfiguration(let message) = error {
                XCTAssertTrue(message.contains("Session duration must be at least"))
            } else {
                XCTFail("Expected AppError.invalidConfiguration but got \(error)")
            }
        }
    }
}
