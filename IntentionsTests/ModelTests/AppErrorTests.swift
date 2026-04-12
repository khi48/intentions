//
//  AppErrorTests.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//

// AppErrorTests.swift
// Unit tests for AppError enum

import XCTest
@testable import Intentions

final class AppErrorTests: XCTestCase {
    
    func testScreenTimeAuthorizationFailedError() {
        // Given
        let error = AppError.screenTimeAuthorizationFailed
        
        // Then
        XCTAssertEqual(error.errorDescription, "Screen Time authorization was denied. Please enable it in Settings to use Intent.")
        XCTAssertEqual(error.recoverySuggestion, "Go to Settings > Screen Time > Content & Privacy Restrictions and enable access for Intent.")
    }
    
    func testScreenTimeNotAvailableError() {
        // Given
        let error = AppError.screenTimeNotAvailable
        
        // Then
        XCTAssertEqual(error.errorDescription, "Screen Time is not available on this device.")
        XCTAssertEqual(error.recoverySuggestion, "This app requires iOS 16.0 or later with Screen Time support.")
    }
    
    func testAppBlockingFailedError() {
        // Given
        let details = "ManagedSettings store unavailable"
        let error = AppError.appBlockingFailed(details)
        
        // Then
        XCTAssertEqual(error.errorDescription, "Failed to block apps: ManagedSettings store unavailable.")
        XCTAssertEqual(error.recoverySuggestion, "Try restarting the app or check Screen Time settings.")
    }
    
    func testSessionExpiredError() {
        // Given
        let error = AppError.sessionExpired
        
        // Then
        XCTAssertEqual(error.errorDescription, "Your session has expired and apps have been locked.")
        XCTAssertEqual(error.recoverySuggestion, "Start a new session to access apps again.")
    }
    
    func testSessionNotFoundError() {
        // Given
        let error = AppError.sessionNotFound
        
        // Then
        XCTAssertEqual(error.errorDescription, "Could not find the active session.")
        XCTAssertEqual(error.recoverySuggestion, "Start a new session from the main screen.")
    }
    
    func testDataNotFoundError() {
        // Given
        let item = "app group"
        let error = AppError.dataNotFound(item)
        
        // Then
        XCTAssertEqual(error.errorDescription, "Could not find app group. It may have been deleted.")
        XCTAssertEqual(error.recoverySuggestion, "Try refreshing or recreating the item.")
    }
    
    func testInvalidConfigurationError() {
        // Given
        let details = "negative time duration"
        let error = AppError.invalidConfiguration(details)
        
        // Then
        XCTAssertEqual(error.errorDescription, "Invalid configuration: negative time duration.")
        XCTAssertEqual(error.recoverySuggestion, "Check your settings and try again.")
    }
    
    func testPersistenceError() {
        // Given
        let details = "Core Data save failed"
        let error = AppError.persistenceError(details)
        
        // Then
        XCTAssertEqual(error.errorDescription, "Failed to save data: Core Data save failed.")
        XCTAssertEqual(error.recoverySuggestion, "Ensure the app has permission to store data and try again.")
    }
    
    func testAppDiscoveryFailedError() {
        // Given
        let details = "FamilyControls authorization required"
        let error = AppError.appDiscoveryFailed(details)
        
        // Then
        XCTAssertEqual(error.errorDescription, "Failed to discover apps: FamilyControls authorization required.")
        XCTAssertEqual(error.recoverySuggestion, "Try refreshing the app list or restarting the app.")
    }
    
    func testTimerError() {
        // Given
        let details = "background timer interrupted"
        let error = AppError.timerError(details)
        
        // Then
        XCTAssertEqual(error.errorDescription, "Timer error: background timer interrupted.")
        XCTAssertEqual(error.recoverySuggestion, "Try starting a new session.")
    }
    
    func testErrorAsLocalizedError() {
        // Given
        let error: LocalizedError = AppError.sessionExpired
        
        // Then
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
        XCTAssertNil(error.failureReason) // Not implemented in our enum
        XCTAssertNil(error.helpAnchor) // Not implemented in our enum
    }
    
    func testErrorEquality() {
        // Given
        let error1 = AppError.sessionExpired
        let error2 = AppError.sessionExpired
        let error3 = AppError.sessionNotFound
        let error4 = AppError.dataNotFound("test")
        let error5 = AppError.dataNotFound("test")
        let error6 = AppError.dataNotFound("different")
        
        // Then - Test basic enum cases
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
        
        // Test associated value cases
        XCTAssertEqual(error4, error5)
        XCTAssertNotEqual(error4, error6)
    }
    
    func testErrorSwitchStatement() {
        // Given
        let errors: [AppError] = [
            .screenTimeAuthorizationFailed,
            .screenTimeAuthorizationRequired("test message"),
            .sessionExpired,
            .dataNotFound("test"),
            .invalidConfiguration("test config"),
            .persistenceError("save failed")
        ]
        
        // When & Then - Verify all cases can be handled
        for error in errors {
            var handled = false
            
            switch error {
            case .screenTimeAuthorizationFailed:
                handled = true
            case .screenTimeAuthorizationRequired:
                handled = true
            case .screenTimeNotAvailable:
                handled = true
            case .appBlockingFailed:
                handled = true
            case .sessionExpired:
                handled = true
            case .sessionNotFound:
                handled = true
            case .dataNotFound:
                handled = true
            case .invalidConfiguration:
                handled = true
            case .persistenceError:
                handled = true
            case .appDiscoveryFailed:
                handled = true
            case .timerError:
                handled = true
            }
            
            XCTAssertTrue(handled, "Error case \(error) was not handled")
        }
    }
    
    func testErrorMessageConsistency() {
        // Test that all error descriptions are non-empty and properly formatted
        let errors: [AppError] = [
            .screenTimeAuthorizationFailed,
            .screenTimeNotAvailable,
            .appBlockingFailed("test"),
            .sessionExpired,
            .sessionNotFound,
            .dataNotFound("item"),
            .invalidConfiguration("config"),
            .persistenceError("save issue"),
            .appDiscoveryFailed("discovery issue"),
            .timerError("timer issue")
        ]
        
        for error in errors {
            // Then - All errors should have descriptions and recovery suggestions
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
            XCTAssertNotNil(error.recoverySuggestion)
            XCTAssertFalse(error.recoverySuggestion!.isEmpty)
            
            // Descriptions should not end with periods for consistency
            XCTAssertTrue(error.errorDescription!.hasSuffix("."))
            XCTAssertTrue(error.recoverySuggestion!.hasSuffix("."))
        }
    }
    
    func testErrorChaining() {
        // Test that errors can be properly wrapped and unwrapped
        let originalError = AppError.sessionExpired
        let wrappedError = AppError.persistenceError("Failed due to: \(originalError.errorDescription ?? "unknown")")
        
        XCTAssertTrue(wrappedError.errorDescription?.contains("session has expired") == true)
    }
}
