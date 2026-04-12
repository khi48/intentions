//
//  ScreenTimeStatusInfoTests.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 16/06/2025.
//


// IntentionsTests/Models/ScreenTimeStatusInfoTests.swift
// Unit tests for ScreenTimeStatusInfo model

import XCTest
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

@MainActor
final class ScreenTimeStatusInfoTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testScreenTimeStatusInfoInitialization() {
        // Given - Status info parameters
        let authStatus = AuthorizationStatus.approved
        let allowedCount = 5
        let systemCount = 3
        let hasSession = true
        let isInitialized = true
        
        // When - Create status info
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: authStatus,
            currentlyAllowedAppsCount: allowedCount,
            essentialSystemAppsCount: systemCount,
            hasActiveSession: hasSession,
            isInitialized: isInitialized
        )
        
        // Then - Properties should be set correctly
        XCTAssertEqual(statusInfo.authorizationStatus, authStatus)
        XCTAssertEqual(statusInfo.currentlyAllowedAppsCount, allowedCount)
        XCTAssertEqual(statusInfo.essentialSystemAppsCount, systemCount)
        XCTAssertEqual(statusInfo.hasActiveSession, hasSession)
        XCTAssertEqual(statusInfo.isInitialized, isInitialized)
    }
    
    // MARK: - Computed Properties Tests
    
    func testIsFullyOperationalWhenApprovedAndInitialized() {
        // Given - Approved and initialized status
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: 0,
            essentialSystemAppsCount: 0,
            hasActiveSession: false,
            isInitialized: true
        )
        
        // When - Check if fully operational
        let isOperational = statusInfo.isFullyOperational
        
        // Then - Should be fully operational
        XCTAssertTrue(isOperational)
    }
    
    func testIsNotFullyOperationalWhenNotApproved() {
        // Given - Not approved status
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .denied,
            currentlyAllowedAppsCount: 0,
            essentialSystemAppsCount: 0,
            hasActiveSession: false,
            isInitialized: true
        )
        
        // When - Check if fully operational
        let isOperational = statusInfo.isFullyOperational
        
        // Then - Should not be fully operational
        XCTAssertFalse(isOperational)
    }
    
    func testIsNotFullyOperationalWhenNotInitialized() {
        // Given - Approved but not initialized status
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: 0,
            essentialSystemAppsCount: 0,
            hasActiveSession: false,
            isInitialized: false
        )
        
        // When - Check if fully operational
        let isOperational = statusInfo.isFullyOperational
        
        // Then - Should not be fully operational
        XCTAssertFalse(isOperational)
    }
    
    func testIsNotFullyOperationalWhenNeitherApprovedNorInitialized() {
        // Given - Not approved and not initialized
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .notDetermined,
            currentlyAllowedAppsCount: 0,
            essentialSystemAppsCount: 0,
            hasActiveSession: false,
            isInitialized: false
        )
        
        // When - Check if fully operational
        let isOperational = statusInfo.isFullyOperational
        
        // Then - Should not be fully operational
        XCTAssertFalse(isOperational)
    }
    
    // MARK: - Status Description Tests
    
    func testStatusDescriptionForNotDetermined() {
        // Given - Not determined authorization
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .notDetermined,
            currentlyAllowedAppsCount: 0,
            essentialSystemAppsCount: 0,
            hasActiveSession: false,
            isInitialized: false
        )
        
        // When - Get status description
        let description = statusInfo.statusDescription
        
        // Then - Should indicate authorization not requested
        XCTAssertEqual(description, "Authorization not requested")
    }
    
    func testStatusDescriptionForDenied() {
        // Given - Denied authorization
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .denied,
            currentlyAllowedAppsCount: 0,
            essentialSystemAppsCount: 0,
            hasActiveSession: false,
            isInitialized: false
        )
        
        // When - Get status description
        let description = statusInfo.statusDescription
        
        // Then - Should indicate authorization denied
        XCTAssertEqual(description, "Authorization denied by user")
    }
    
    func testStatusDescriptionForApprovedButNotInitialized() {
        // Given - Approved but not initialized
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: 0,
            essentialSystemAppsCount: 0,
            hasActiveSession: false,
            isInitialized: false
        )
        
        // When - Get status description
        let description = statusInfo.statusDescription
        
        // Then - Should indicate authorized but not initialized
        XCTAssertEqual(description, "Authorized but not initialized")
    }
    
    func testStatusDescriptionForFullyOperational() {
        // Given - Fully operational status with apps allowed
        let allowedCount = 7
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: allowedCount,
            essentialSystemAppsCount: 2,
            hasActiveSession: true,
            isInitialized: true
        )
        
        // When - Get status description
        let description = statusInfo.statusDescription
        
        // Then - Should indicate fully operational with app count
        let expectedDescription = "Fully operational - \(allowedCount) apps allowed"
        XCTAssertEqual(description, expectedDescription)
    }
    
    func testStatusDescriptionForFullyOperationalWithZeroApps() {
        // Given - Fully operational status with no apps allowed
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: 0,
            essentialSystemAppsCount: 3,
            hasActiveSession: false,
            isInitialized: true
        )
        
        // When - Get status description
        let description = statusInfo.statusDescription
        
        // Then - Should indicate fully operational with zero apps
        XCTAssertEqual(description, "Fully operational - 0 apps allowed")
    }
    
    func testStatusDescriptionForUnknownAuthorizationStatus() {
        // This test is tricky because @unknown default handles future cases
        // We can't directly create an unknown status, but we can test the logic
        
        // Given - We'll test by creating a status and verifying the current cases work
        let knownStatuses: [AuthorizationStatus] = [.notDetermined, .denied, .approved]
        
        for status in knownStatuses {
            let statusInfo = ScreenTimeStatusInfo(
                authorizationStatus: status,
                currentlyAllowedAppsCount: 0,
                essentialSystemAppsCount: 0,
                hasActiveSession: false,
                isInitialized: status == .approved
            )
            
            // When - Get description
            let description = statusInfo.statusDescription
            
            // Then - Should not return unknown status description
            XCTAssertFalse(description.contains("Unknown authorization status"))
        }
    }
    
    // MARK: - Sendable Conformance Tests
    
    func testSendableConformance() async {
        // Given - Status info that should be Sendable
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: 5,
            essentialSystemAppsCount: 2,
            hasActiveSession: true,
            isInitialized: true
        )
        
        // When - Pass across actor boundary (should compile without issues)
        let description = await withCheckedContinuation { continuation in
            // Capture statusInfo directly, not self
            let capturedStatusInfo = statusInfo
            Task {
                // This closure captures statusInfo and runs on different actor
                let description = capturedStatusInfo.statusDescription
                continuation.resume(returning: description)
            }
        }
        
        // Then - Should work without data race issues
        XCTAssertTrue(description.contains("Fully operational"))
    }
    
    // MARK: - Equality and Comparison Tests
    
    func testStatusInfoEquality() {
        // Given - Two identical status info objects
        let statusInfo1 = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: 3,
            essentialSystemAppsCount: 1,
            hasActiveSession: true,
            isInitialized: true
        )
        
        let statusInfo2 = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: 3,
            essentialSystemAppsCount: 1,
            hasActiveSession: true,
            isInitialized: true
        )
        
        // When - Compare properties (since struct doesn't auto-generate Equatable)
        let areEqual = statusInfo1.authorizationStatus == statusInfo2.authorizationStatus &&
                      statusInfo1.currentlyAllowedAppsCount == statusInfo2.currentlyAllowedAppsCount &&
                      statusInfo1.essentialSystemAppsCount == statusInfo2.essentialSystemAppsCount &&
                      statusInfo1.hasActiveSession == statusInfo2.hasActiveSession &&
                      statusInfo1.isInitialized == statusInfo2.isInitialized
        
        // Then - Should be equal
        XCTAssertTrue(areEqual)
    }
    
    func testStatusInfoInequality() {
        // Given - Two different status info objects
        let statusInfo1 = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: 3,
            essentialSystemAppsCount: 1,
            hasActiveSession: true,
            isInitialized: true
        )
        
        let statusInfo2 = ScreenTimeStatusInfo(
            authorizationStatus: .denied,
            currentlyAllowedAppsCount: 0,
            essentialSystemAppsCount: 1,
            hasActiveSession: false,
            isInitialized: false
        )
        
        // When - Compare key properties
        let authStatusEqual = statusInfo1.authorizationStatus == statusInfo2.authorizationStatus
        let allowedCountEqual = statusInfo1.currentlyAllowedAppsCount == statusInfo2.currentlyAllowedAppsCount
        let sessionEqual = statusInfo1.hasActiveSession == statusInfo2.hasActiveSession
        let initializedEqual = statusInfo1.isInitialized == statusInfo2.isInitialized
        
        // Then - Should be different
        XCTAssertFalse(authStatusEqual)
        XCTAssertFalse(allowedCountEqual)
        XCTAssertFalse(sessionEqual)
        XCTAssertFalse(initializedEqual)
    }
    
    // MARK: - Edge Cases Tests
    
    func testStatusInfoWithNegativeCounts() {
        // Given - Status info with edge case values
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: -1, // Edge case: negative count
            essentialSystemAppsCount: -5,  // Edge case: negative count
            hasActiveSession: false,
            isInitialized: true
        )
        
        // When - Get computed properties
        let isOperational = statusInfo.isFullyOperational
        let description = statusInfo.statusDescription
        
        // Then - Should handle gracefully (though negative counts are invalid in real usage)
        XCTAssertTrue(isOperational) // Based on authorization and initialization only
        XCTAssertTrue(description.contains("-1 apps allowed")) // Should include the actual count
    }
    
    func testStatusInfoWithLargeCounts() {
        // Given - Status info with large counts
        let largeCount = Int.max
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: largeCount,
            essentialSystemAppsCount: largeCount,
            hasActiveSession: true,
            isInitialized: true
        )
        
        // When - Get description
        let description = statusInfo.statusDescription
        
        // Then - Should handle large numbers
        XCTAssertTrue(description.contains("\(largeCount) apps allowed"))
        XCTAssertTrue(statusInfo.isFullyOperational)
    }
    
    // MARK: - Performance Tests
    
    func testStatusDescriptionPerformance() {
        // Given - Status info
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: 100,
            essentialSystemAppsCount: 10,
            hasActiveSession: true,
            isInitialized: true
        )
        
        // When - Measure performance of description generation
        measure {
            for _ in 0..<10000 {
                _ = statusInfo.statusDescription
            }
        }
        
        // Then - Should complete within reasonable time (measured by XCTest)
    }
    
    func testIsFullyOperationalPerformance() {
        // Given - Status info
        let statusInfo = ScreenTimeStatusInfo(
            authorizationStatus: .approved,
            currentlyAllowedAppsCount: 50,
            essentialSystemAppsCount: 5,
            hasActiveSession: false,
            isInitialized: true
        )
        
        // When - Measure performance of operational check
        measure {
            for _ in 0..<100000 {
                _ = statusInfo.isFullyOperational
            }
        }
        
        // Then - Should complete within reasonable time (measured by XCTest)
    }
}
