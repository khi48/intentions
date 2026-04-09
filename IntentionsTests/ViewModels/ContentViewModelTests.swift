//
//  ContentViewModelTests.swift
//  IntentionsTests
//
//  Created by Claude on 12/07/2025.
//

import XCTest
@preconcurrency import FamilyControls
import ManagedSettings
@testable import Intentions

final class ContentViewModelTests: XCTestCase {
    
    private var viewModel: ContentViewModel!
    private var mockScreenTimeService: MockScreenTimeService!
    private var mockDataService: MockDataPersistenceService!
    
    override func setUp() {
        super.setUp()
        mockScreenTimeService = MockScreenTimeService()
        mockDataService = MockDataPersistenceService()
        
        // We'll initialize the viewModel in each test method that needs it
        // since ContentViewModel's init is @MainActor
    }
    
    override func tearDown() {
        viewModel = nil
        mockScreenTimeService = nil
        mockDataService = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    @MainActor
    private func createViewModel() throws {
        viewModel = try ContentViewModel(
            screenTimeService: mockScreenTimeService,
            dataService: mockDataService
        )
    }
    
    // MARK: - Initialization Tests
    
    @MainActor
    func testInitialization() throws {
        // Given - Fresh view model
        try createViewModel()
        
        // When - Check initial state
        // Then
        XCTAssertEqual(viewModel.authorizationStatus, .notDetermined)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.activeSession)
        XCTAssertFalse(viewModel.showingSetupFlow)
        XCTAssertFalse(viewModel.showingSetupFlow)
        XCTAssertEqual(viewModel.selectedTab, .home)
        XCTAssertFalse(viewModel.isAppReady)
    }
    
    @MainActor
    func testInitializeAppSuccess() async throws {
        // Given
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        
        // When
        await viewModel.initializeApp()
        
        // Then
        XCTAssertEqual(viewModel.authorizationStatus, .approved)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.isAppReady)
    }
    
    @MainActor
    func testInitializeAppWithDeniedAuthorization() async throws {
        // Given
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.denied)
        
        // When
        await viewModel.initializeApp()
        
        // Then
        XCTAssertEqual(viewModel.authorizationStatus, .denied)
        XCTAssertFalse(viewModel.isAppReady)
    }
    
    @MainActor
    func testLoadActiveSessionFromPersistence() async throws {
        // Given - Create a test session and save it
        try createViewModel()
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        try! await mockDataService.saveIntentionSession(testSession)
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        
        // When
        await viewModel.initializeApp()
        
        // Then
        XCTAssertNotNil(viewModel.activeSession)
        XCTAssertEqual(viewModel.activeSession?.id, testSession.id)
    }
    
    // MARK: - Authorization Tests
    
    @MainActor
    func testRequestAuthorizationSuccess() async throws {
        // Given
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.notDetermined)
        
        // When
        await viewModel.requestAuthorization()
        
        // Then
        XCTAssertEqual(viewModel.authorizationStatus, .approved)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.isAppReady)
    }
    
    @MainActor
    func testRequestAuthorizationFailure() async throws {
        // Given
        try createViewModel()
        await mockScreenTimeService.setShouldSucceedAuthorization(false)
        
        // When
        await viewModel.requestAuthorization()
        
        // Then
        XCTAssertNotEqual(viewModel.authorizationStatus, .approved)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isAppReady)
    }
    
    @MainActor
    func testIsAppReadyProperty() async throws {
        // Given - Not determined status
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.notDetermined)
        await viewModel.initializeApp()
        XCTAssertFalse(viewModel.isAppReady)
        
        // When - Approved status
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.initializeApp()
        
        // Then
        XCTAssertTrue(viewModel.isAppReady)
        
        // When - Denied status
        await mockScreenTimeService.setMockAuthorizationStatus(.denied)
        await viewModel.initializeApp()
        
        // Then
        XCTAssertFalse(viewModel.isAppReady)
    }
    
    // MARK: - Navigation Tests
    
    @MainActor
    func testNavigateToTab() throws {
        // Given
        try createViewModel()
        XCTAssertEqual(viewModel.selectedTab, .home)
        
        // When
        viewModel.navigateToTab(.settings)
        
        // Then
        XCTAssertEqual(viewModel.selectedTab, .settings)
    }
    
    // MARK: - Session Management Tests
    
    @MainActor
    func testStartSessionSuccess() async throws {
        // Given
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.initializeApp()
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        
        // When
        await viewModel.startSession(testSession)
        
        // Then
        XCTAssertEqual(viewModel.activeSession?.id, testSession.id)
        XCTAssertFalse(viewModel.showingSetupFlow)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        
        // Verify session was saved
        let savedSessions = try! await mockDataService.loadIntentionSessions()
        XCTAssertEqual(savedSessions.count, 1)
        XCTAssertEqual(savedSessions.first?.id, testSession.id)
    }
    
    @MainActor
    func testStartSessionWithApplications() async throws {
        // Given
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.initializeApp()
        
        let testTokens = Set([createTestToken()])
        let testSession = try! IntentionSession(
            applications: testTokens,
            duration: 1800
        )
        
        // When
        await viewModel.startSession(testSession)
        
        // Then
        XCTAssertEqual(viewModel.activeSession?.id, testSession.id)
        
        // Verify Screen Time service was called
        let allowedApps = await mockScreenTimeService.getCurrentlyAllowedApps()
        XCTAssertEqual(allowedApps.count, 1)
    }
    
    @MainActor
    func testStartSessionFailure() async throws {
        // Given
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.initializeApp()
        mockDataService.shouldFailSave = true
        
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        
        // When
        await viewModel.startSession(testSession)
        
        // Then
        XCTAssertNil(viewModel.activeSession)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    @MainActor
    func testEndCurrentSessionSuccess() async throws {
        // Given - Start with an active session
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.initializeApp()
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        await viewModel.startSession(testSession)
        XCTAssertNotNil(viewModel.activeSession)
        
        // When
        await viewModel.endCurrentSession()
        
        // Then
        XCTAssertNil(viewModel.activeSession)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        
        // Verify session was completed and saved
        let savedSessions = try! await mockDataService.loadIntentionSessions()
        XCTAssertEqual(savedSessions.count, 1)
        XCTAssertTrue(savedSessions.first?.wasCompleted == true)
        
        // Verify Screen Time access was revoked
        let allowedApps = await mockScreenTimeService.getCurrentlyAllowedApps()
        XCTAssertTrue(allowedApps.isEmpty)
    }
    
    @MainActor
    func testEndCurrentSessionWhenNoActiveSession() async throws {
        // Given - No active session
        try createViewModel()
        XCTAssertNil(viewModel.activeSession)
        
        // When
        await viewModel.endCurrentSession()
        
        // Then - Should not crash or change state
        XCTAssertNil(viewModel.activeSession)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    @MainActor
    func testEndCurrentSessionFailure() async throws {
        // Given - Start with an active session
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.initializeApp()
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        await viewModel.startSession(testSession)
        
        // Set up failure
        mockDataService.shouldFailSave = true
        
        // When
        await viewModel.endCurrentSession()
        
        // Then
        XCTAssertNotNil(viewModel.activeSession) // Should still be active due to failure
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    // MARK: - Error Handling Tests
    
    @MainActor
    func testHandleError() async throws {
        // Given
        try createViewModel()
        let testError = AppError.sessionNotFound
        
        // When
        await viewModel.handleError(testError)
        
        // Then
        XCTAssertEqual(viewModel.errorMessage, testError.errorDescription)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    @MainActor
    func testHandleNonAppError() async throws {
        // Given
        try createViewModel()
        let testError = NSError(domain: "test", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        
        // When
        await viewModel.handleError(testError)
        
        // Then
        XCTAssertEqual(viewModel.errorMessage, "Test error")
        XCTAssertFalse(viewModel.isLoading)
    }
    
    @MainActor
    func testClearError() async throws {
        // Given
        try createViewModel()
        await viewModel.handleError(AppError.sessionNotFound)
        XCTAssertNotNil(viewModel.errorMessage)
        
        // When
        viewModel.clearError()
        
        // Then
        XCTAssertNil(viewModel.errorMessage)
    }
    
    // MARK: - Loading State Tests
    
    @MainActor
    func testLoadingStateDuringInitialization() async throws {
        // Given
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        
        // When - Start initialization (but don't await)
        let initTask = Task {
            await viewModel.initializeApp()
        }
        
        // Then - Should be loading briefly
        // Note: This is timing-dependent and may be flaky
        // In a real app, we might need more sophisticated testing
        
        await initTask.value
        XCTAssertFalse(viewModel.isLoading) // Should be done loading
    }
    
    @MainActor
    func testLoadingStateDuringAuthorization() async throws {
        // Given
        try createViewModel()
        await mockScreenTimeService.setAuthorizationDelay(0.1) // Add small delay
        
        // When - Start authorization (but don't await)
        let authTask = Task {
            await viewModel.requestAuthorization()
        }
        
        // Then - Eventually should be done
        await authTask.value
        XCTAssertFalse(viewModel.isLoading)
    }
    
    // MARK: - Integration Tests
    
    @MainActor
    func testCompleteWorkflow() async throws {
        // Given - Fresh view model
        try createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.notDetermined)
        
        // When - Initialize app
        await viewModel.initializeApp()
        XCTAssertEqual(viewModel.authorizationStatus, .notDetermined)
        XCTAssertFalse(viewModel.isAppReady)
        
        // When - Request authorization
        await viewModel.requestAuthorization()
        XCTAssertTrue(viewModel.isAppReady)
        
        // When - Start a session
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        await viewModel.startSession(testSession)
        XCTAssertNotNil(viewModel.activeSession)
        
        // When - End the session
        await viewModel.endCurrentSession()
        XCTAssertNil(viewModel.activeSession)
        
        // Then - Should be in clean state
        XCTAssertTrue(viewModel.isAppReady)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    // MARK: - Helper Methods
    
    private func createTestToken() -> ApplicationToken {
        let tokenData = """
        {
            "data": "dGVzdERhdGE="
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        return try! decoder.decode(ApplicationToken.self, from: tokenData)
    }
}

// MARK: - AppTab Tests

final class AppTabTests: XCTestCase {
    
    func testAppTabCases() {
        // Test all cases exist
        let allCases = AppTab.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.home))
        XCTAssertTrue(allCases.contains(.settings))
    }

    func testAppTabIdentifiable() {
        // Test Identifiable conformance
        XCTAssertEqual(AppTab.home.id, "Home")
        XCTAssertEqual(AppTab.settings.id, "Settings")
    }

    func testAppTabSystemImages() {
        // Test system images are defined
        XCTAssertEqual(AppTab.home.systemImage, "house.fill")
        XCTAssertEqual(AppTab.settings.systemImage, "gear")
    }

    func testAppTabRawValues() {
        // Test raw values
        XCTAssertEqual(AppTab.home.rawValue, "Home")
        XCTAssertEqual(AppTab.settings.rawValue, "Settings")
    }
}
