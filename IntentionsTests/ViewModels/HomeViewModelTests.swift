//
//  HomeViewModelTests.swift
//  IntentionsTests
//
//  Created by Claude on 13/07/2025.
//

import XCTest
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

@MainActor
final class HomeViewModelTests: XCTestCase {
    
    var viewModel: HomeViewModel!
    var mockDataService: MockDataPersistenceService!
    var mockScreenTimeService: MockScreenTimeService!
    
    override func setUp() async throws {
        mockDataService = MockDataPersistenceService()
        mockScreenTimeService = MockScreenTimeService()
        viewModel = HomeViewModel(
            dataService: mockDataService,
            screenTimeService: mockScreenTimeService
        )
    }
    
    override func tearDown() async throws {
        viewModel = nil
        mockDataService = nil
        mockScreenTimeService = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.activeSession)
        XCTAssertEqual(viewModel.authorizationStatus, .notDetermined)
        XCTAssertTrue(viewModel.quickActionGroups.isEmpty)
        XCTAssertTrue(viewModel.recentSessions.isEmpty)
    }
    
    // MARK: - Data Loading Tests
    
    func testLoadData() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        let testGroup = createTestAppGroup()
        mockDataService.mockAppGroups = [testGroup]
        
        // When
        await viewModel.loadData()
        
        // Then
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.authorizationStatus, .approved)
        XCTAssertEqual(viewModel.quickActionGroups.count, 1)
        XCTAssertEqual(viewModel.quickActionGroups.first?.name, testGroup.name)
    }
    
    func testLoadDataWithActiveSession() async {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        try! await mockDataService.saveIntentionSession(testSession)
        
        // When
        await viewModel.loadData()
        
        // Then
        XCTAssertNotNil(viewModel.activeSession)
        XCTAssertEqual(viewModel.activeSession?.id, testSession.id)
    }
    
    func testLoadDataError() async {
        // Given
        mockDataService.shouldThrowLoadError = true
        
        // When
        await viewModel.loadData()
        
        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    // MARK: - Session Management Tests
    
    func testCanStartSession() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.loadData()
        
        // Then
        XCTAssertTrue(viewModel.canStartSession)
    }
    
    func testCannotStartSessionWhenNotAuthorized() {
        // Given - default is .notDetermined
        
        // Then
        XCTAssertFalse(viewModel.canStartSession)
    }
    
    func testCannotStartSessionWhenActiveSessionExists() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        try! await mockDataService.saveIntentionSession(testSession)
        await viewModel.loadData()
        
        // Then
        XCTAssertFalse(viewModel.canStartSession)
    }
    
    func testCanEndSession() async {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        try! await mockDataService.saveIntentionSession(testSession)
        await viewModel.loadData()
        
        // Then
        XCTAssertTrue(viewModel.canEndSession)
    }
    
    func testCannotEndSessionWhenNoActiveSession() {
        // Given - no active session
        
        // Then
        XCTAssertFalse(viewModel.canEndSession)
    }
    
    func testStartQuickSession() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.loadData()
        let testGroup = createTestAppGroup()
        var sessionStartCalled = false
        var capturedSession: IntentionSession?
        
        viewModel.onSessionStart = { session in
            sessionStartCalled = true
            capturedSession = session
        }
        
        // When
        await viewModel.startQuickSession(with: testGroup, duration: 1800)
        
        
        // Then
        XCTAssertTrue(sessionStartCalled)
        XCTAssertNotNil(capturedSession)
        XCTAssertNotNil(viewModel.activeSession)
        XCTAssertEqual(viewModel.activeSession?.duration, 1800)
        XCTAssertTrue(viewModel.activeSession?.requestedAppGroups.contains(testGroup.id) == true)
    }
    
    func testStartQuickSessionWhenNotAuthorized() async {
        // Given
        let testGroup = createTestAppGroup()
        var sessionStartCalled = false
        
        viewModel.onSessionStart = { _ in
            sessionStartCalled = true
        }
        
        // When
        await viewModel.startQuickSession(with: testGroup)
        
        // Then
        XCTAssertFalse(sessionStartCalled)
        XCTAssertNil(viewModel.activeSession)
    }
    
    func testEndCurrentSession() async {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        try! await mockDataService.saveIntentionSession(testSession)
        await viewModel.loadData()
        var sessionEndCalled = false
        
        viewModel.onSessionEnd = {
            sessionEndCalled = true
        }
        
        // When
        await viewModel.endCurrentSession()
        
        // Then
        XCTAssertTrue(sessionEndCalled)
        XCTAssertNil(viewModel.activeSession)
    }
    
    func testEndCurrentSessionWhenNoActiveSession() async {
        // Given
        var sessionEndCalled = false
        viewModel.onSessionEnd = {
            sessionEndCalled = true
        }
        
        // When
        await viewModel.endCurrentSession()
        
        // Then
        XCTAssertFalse(sessionEndCalled)
    }
    
    // MARK: - Session Statistics Tests
    
    func testRemainingTime() async {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800) // 30 minutes
        try! await mockDataService.saveIntentionSession(testSession)
        await viewModel.loadData()
        
        // Then
        XCTAssertGreaterThan(viewModel.remainingTime, 0)
        XCTAssertLessThanOrEqual(viewModel.remainingTime, 1800)
    }
    
    func testSessionProgress() async {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        try! await mockDataService.saveIntentionSession(testSession)
        await viewModel.loadData()
        
        // Then
        XCTAssertGreaterThanOrEqual(viewModel.sessionProgress, 0.0)
        XCTAssertLessThanOrEqual(viewModel.sessionProgress, 1.0)
    }
    
    func testFormattedRemainingTime() async {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 7200) // 2 hours to have plenty of buffer
        try! await mockDataService.saveIntentionSession(testSession)
        await viewModel.loadData()
        
        // Then - The test expects that we have an active session with hours remaining
        XCTAssertNotNil(viewModel.activeSession)
        XCTAssertTrue(viewModel.activeSession?.isActive == true)
        XCTAssertGreaterThan(viewModel.remainingTime, 3600) // Should have well over 1 hour left
        XCTAssertTrue(viewModel.formattedRemainingTime.contains("h"))
    }
    
    func testFormattedRemainingTimeMinutes() async {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800) // 30 minutes
        try! await mockDataService.saveIntentionSession(testSession)
        await viewModel.loadData()
        
        // Then
        XCTAssertTrue(viewModel.formattedRemainingTime.contains("m"))
        XCTAssertFalse(viewModel.formattedRemainingTime.contains("h"))
    }
    
    // MARK: - Authorization Tests
    
    func testRequestAuthorization() async {
        // Given
        await mockScreenTimeService.setShouldSucceedAuthorization(true)
        
        // When
        await viewModel.requestAuthorization()
        
        // Then
        XCTAssertEqual(viewModel.authorizationStatus, .approved)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testRequestAuthorizationDenied() async {
        // Given
        await mockScreenTimeService.setShouldSucceedAuthorization(false)
        
        // When
        await viewModel.requestAuthorization()
        
        // Then
        XCTAssertEqual(viewModel.authorizationStatus, .denied)
        XCTAssertNotNil(viewModel.errorMessage)
    }
    
    func testShowIntentionPromptWhenAuthorized() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.loadData()
        var promptShown = false
        
        viewModel.onShowIntentionPrompt = {
            promptShown = true
        }
        
        // When
        viewModel.showIntentionPrompt()
        
        // Then
        XCTAssertTrue(promptShown)
    }
    
    func testShowIntentionPromptWhenNotAuthorized() async {
        // Given - default is .notDetermined
        var promptShown = false
        
        viewModel.onShowIntentionPrompt = {
            promptShown = true
        }
        
        // When
        viewModel.showIntentionPrompt()
        
        // Wait for the async error handling to complete
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Then
        XCTAssertFalse(promptShown)
        // Should show error instead
        XCTAssertNotNil(viewModel.errorMessage)
    }
    
    // MARK: - Status Display Tests
    
    func testStatusMessageNotDetermined() {
        // Given - default state
        
        // Then
        XCTAssertEqual(viewModel.statusMessage, "Screen Time access required")
        XCTAssertEqual(viewModel.statusColor, .orange)
    }
    
    func testStatusMessageDenied() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.denied)
        await viewModel.loadData()
        
        // Then
        XCTAssertEqual(viewModel.statusMessage, "Screen Time access denied")
        XCTAssertEqual(viewModel.statusColor, .red)
    }
    
    func testStatusMessageApprovedNoSession() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.loadData()
        
        // Then
        XCTAssertEqual(viewModel.statusMessage, "Ready to set intention")
        XCTAssertEqual(viewModel.statusColor, .blue)
    }
    
    func testStatusMessageApprovedWithSession() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        try! await mockDataService.saveIntentionSession(testSession)
        await viewModel.loadData()
        
        // Then
        XCTAssertTrue(viewModel.statusMessage.contains("Session active"))
        XCTAssertTrue(viewModel.statusMessage.contains("remaining"))
        XCTAssertEqual(viewModel.statusColor, .green)
    }
    
    // MARK: - Statistics Tests
    
    func testTodayStatsCalculation() async {
        // Given
        let session1 = try! IntentionSession(duration: 1800)
        let session2 = try! IntentionSession(duration: 3600)
        // Simulate different creation times for today's stats
        session2.createdAt = Date().addingTimeInterval(-3600)
        try! await mockDataService.saveIntentionSession(session1)
        try! await mockDataService.saveIntentionSession(session2)
        
        // When
        await viewModel.loadData()
        
        // Then
        XCTAssertEqual(viewModel.todayStats.totalSessions, 2)
        XCTAssertEqual(viewModel.todayStats.totalTime, 5400) // 1800 + 3600
        XCTAssertEqual(viewModel.todayStats.averageSessionLength, 2700) // 5400 / 2
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() async {
        // Given
        let testError = AppError.sessionNotFound
        
        // When
        await viewModel.handleError(testError)
        
        // Then
        XCTAssertEqual(viewModel.errorMessage, testError.localizedDescription)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testClearError() async {
        // Given
        await viewModel.handleError(AppError.sessionNotFound)
        XCTAssertNotNil(viewModel.errorMessage)
        
        // When
        viewModel.clearError()
        
        // Then
        XCTAssertNil(viewModel.errorMessage)
    }
    
    // MARK: - Helper Methods
    
    private func createTestAppGroup(name: String = "Test Group") -> AppGroup {
        let tokens = Set([try! createMockApplicationToken(uniqueId: name)])
        
        return try! AppGroup(
            id: UUID(),
            name: name,
            applications: tokens,
            createdAt: Date(),
            lastModified: Date()
        )
    }
    
    private func createMockApplicationToken(uniqueId: String = "testData") throws -> ApplicationToken {
        let tokenData = """
        {
            "data": "\(uniqueId.data(using: .utf8)?.base64EncodedString() ?? "dGVzdERhdGE=")"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        return try decoder.decode(ApplicationToken.self, from: tokenData)
    }
}