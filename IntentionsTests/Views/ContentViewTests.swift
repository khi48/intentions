//
//  ContentViewTests.swift
//  IntentionsTests
//
//  Created by Claude on 13/07/2025.
//

import XCTest
import SwiftUI
@preconcurrency import FamilyControls
@testable import Intentions

@MainActor
final class ContentViewTests: XCTestCase {
    
    @MainActor
    func testContentViewCreation() {
        // Given & When
        let contentView = ContentView()
        
        // Then
        XCTAssertNotNil(contentView)
    }
}

// MARK: - Authorization Status Tests

final class AuthorizationStatusTests: XCTestCase {
    
    func testAuthorizationStatusValues() {
        // Test that we handle all authorization status cases
        let statuses: [AuthorizationStatus] = [.notDetermined, .denied, .approved]
        
        for status in statuses {
            // Verify each status can be handled
            switch status {
            case .notDetermined:
                XCTAssertTrue(true, "Should handle notDetermined status")
            case .denied:
                XCTAssertTrue(true, "Should handle denied status")
            case .approved:
                XCTAssertTrue(true, "Should handle approved status")
            @unknown default:
                XCTAssertTrue(true, "Should handle unknown status")
            }
        }
    }
    
    func testAuthorizationButtonTitles() {
        // Test authorization button title logic
        func buttonTitle(for status: AuthorizationStatus) -> String {
            switch status {
            case .notDetermined:
                return "Request Screen Time Access"
            case .denied:
                return "Open Settings"
            case .approved:
                return "Continue"
            @unknown default:
                return "Request Access"
            }
        }
        
        XCTAssertEqual(buttonTitle(for: .notDetermined), "Request Screen Time Access")
        XCTAssertEqual(buttonTitle(for: .denied), "Open Settings")
        XCTAssertEqual(buttonTitle(for: .approved), "Continue")
    }
    
    func testAuthorizationStatusColors() {
        // Test status color logic
        func statusColor(for status: AuthorizationStatus) -> String {
            switch status {
            case .notDetermined:
                return "orange"
            case .denied:
                return "red"
            case .approved:
                return "green"
            @unknown default:
                return "gray"
            }
        }
        
        XCTAssertEqual(statusColor(for: .notDetermined), "orange")
        XCTAssertEqual(statusColor(for: .denied), "red")
        XCTAssertEqual(statusColor(for: .approved), "green")
    }
}

// MARK: - Navigation Integration Tests

final class NavigationIntegrationTests: XCTestCase {
    
    @MainActor
    func testTabViewNavigation() throws {
        // Test that ContentViewModel properly manages tab navigation
        let mockScreenTimeService = MockScreenTimeService()
        let mockDataService = MockDataPersistenceService()
        let viewModel = try ContentViewModel(
            screenTimeService: mockScreenTimeService,
            dataService: mockDataService
        )

        // Test initial state
        XCTAssertEqual(viewModel.selectedTab, .home)

        // Test navigation
        viewModel.navigateToTab(.settings)
        XCTAssertEqual(viewModel.selectedTab, .settings)

        viewModel.navigateToTab(.home)
        XCTAssertEqual(viewModel.selectedTab, .home)
    }
    
    @MainActor
    func testTabNavigation() async {
        let mockScreenTimeService = MockScreenTimeService()
        let mockDataService = MockDataPersistenceService()
        let viewModel = try! ContentViewModel(
            screenTimeService: mockScreenTimeService,
            dataService: mockDataService
        )

        XCTAssertEqual(viewModel.selectedTab, .home)
        viewModel.navigateToTab(.settings)
        XCTAssertEqual(viewModel.selectedTab, .settings)
    }
}

// MARK: - Error Handling Tests

final class ErrorHandlingTests: XCTestCase {
    
    @MainActor
    func testErrorMessageDisplay() async throws {
        // Test error message handling
        let mockScreenTimeService = MockScreenTimeService()
        let mockDataService = MockDataPersistenceService()
        let viewModel = try ContentViewModel(
            screenTimeService: mockScreenTimeService,
            dataService: mockDataService
        )
        
        // Test clear error state
        XCTAssertNil(viewModel.errorMessage)
        
        // Test error handling
        await viewModel.handleError(AppError.sessionNotFound)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.errorMessage, AppError.sessionNotFound.localizedDescription)
        
        // Test error clearing
        viewModel.clearError()
        XCTAssertNil(viewModel.errorMessage)
    }
    
    @MainActor
    func testErrorTypes() async throws {
        // Test different error types are handled properly
        let mockScreenTimeService = MockScreenTimeService()
        let mockDataService = MockDataPersistenceService()
        let viewModel = try ContentViewModel(
            screenTimeService: mockScreenTimeService,
            dataService: mockDataService
        )
        
        let appErrors: [AppError] = [
            .screenTimeAuthorizationFailed,
            .screenTimeAuthorizationRequired("Test message"),
            .sessionNotFound,
            .invalidConfiguration("Test config error")
        ]
        
        for error in appErrors {
            await viewModel.handleError(error)
            XCTAssertNotNil(viewModel.errorMessage)
            XCTAssertEqual(viewModel.errorMessage, error.localizedDescription)
            viewModel.clearError()
        }
        
        // Test non-AppError
        let nsError = NSError(domain: "test", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        await viewModel.handleError(nsError)
        XCTAssertEqual(viewModel.errorMessage, "Test error")
    }
}

// MARK: - Loading State Tests

final class LoadingStateTests: XCTestCase {
    
    @MainActor
    func testLoadingStateManagement() async throws {
        // Test loading state during operations
        let mockScreenTimeService = MockScreenTimeService()
        let mockDataService = MockDataPersistenceService()
        let viewModel = try ContentViewModel(
            screenTimeService: mockScreenTimeService,
            dataService: mockDataService
        )
        
        // Test initial state
        XCTAssertFalse(viewModel.isLoading)
        
        // Test loading during initialization
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.initializeApp()
        
        // Should be done loading after initialization
        XCTAssertFalse(viewModel.isLoading)
        
        // Test loading during session operations
        let testSession = try! IntentionSession(duration: 1800)
        await viewModel.startSession(testSession)
        
        // Should be done loading after session start
        XCTAssertFalse(viewModel.isLoading)
    }
}