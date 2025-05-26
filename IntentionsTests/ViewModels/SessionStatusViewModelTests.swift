//
//  SessionStatusViewModelTests.swift
//  IntentionsTests
//
//  Created by Claude on 13/07/2025.
//

import XCTest
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

@MainActor
final class SessionStatusViewModelTests: XCTestCase {
    
    var viewModel: SessionStatusViewModel!
    var mockDataService: MockDataPersistenceService!
    var mockScreenTimeService: MockScreenTimeService!
    
    override func setUp() async throws {
        mockDataService = MockDataPersistenceService()
        mockScreenTimeService = MockScreenTimeService()
        viewModel = SessionStatusViewModel(
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
    
    func testInitializationWithoutSession() {
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.session)
        XCTAssertFalse(viewModel.isSessionActive)
        XCTAssertEqual(viewModel.remainingTime, 0)
        XCTAssertEqual(viewModel.progress, 0.0)
    }
    
    func testInitializationWithSession() {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        
        // When
        let viewModelWithSession = SessionStatusViewModel(
            session: testSession,
            dataService: mockDataService,
            screenTimeService: mockScreenTimeService
        )
        
        // Then
        XCTAssertEqual(viewModelWithSession.session?.id, testSession.id)
        XCTAssertTrue(viewModelWithSession.isSessionActive)
        XCTAssertGreaterThan(viewModelWithSession.remainingTime, 0)
    }
    
    // MARK: - Session Update Tests
    
    func testUpdateSession() {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        XCTAssertEqual(viewModel.session?.id, testSession.id)
        XCTAssertTrue(viewModel.isSessionActive)
        XCTAssertGreaterThan(viewModel.remainingTime, 0)
    }
    
    func testUpdateSessionToNil() {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        viewModel.updateSession(testSession)
        XCTAssertTrue(viewModel.isSessionActive)
        
        // When
        viewModel.updateSession(nil)
        
        // Then
        XCTAssertNil(viewModel.session)
        XCTAssertFalse(viewModel.isSessionActive)
        XCTAssertEqual(viewModel.remainingTime, 0)
    }
    
    func testUpdateSessionToInactive() {
        // Given
        let activeSession = try! IntentionSession(duration: 1800)
        viewModel.updateSession(activeSession)
        XCTAssertTrue(viewModel.isSessionActive)
        
        // Create inactive session by completing the active one
        let inactiveSession = activeSession
        inactiveSession.complete()
        
        // When
        viewModel.updateSession(inactiveSession)
        
        // Then
        XCTAssertFalse(viewModel.isSessionActive)
        XCTAssertEqual(viewModel.remainingTime, 0)
    }
    
    // MARK: - Time Calculations Tests
    
    func testRemainingTime() {
        // Given
        let duration: TimeInterval = 1800 // 30 minutes
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: duration)
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        XCTAssertGreaterThan(viewModel.remainingTime, 0)
        XCTAssertLessThanOrEqual(viewModel.remainingTime, duration)
    }
    
    func testElapsedTime() {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        XCTAssertGreaterThanOrEqual(viewModel.elapsedTime, 0)
    }
    
    func testProgress() {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        XCTAssertGreaterThanOrEqual(viewModel.progress, 0.0)
        XCTAssertLessThanOrEqual(viewModel.progress, 1.0)
    }
    
    func testProgressWithOldSession() {
        // Given - session with simulated progress
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800) // 30 minutes total
        // Simulate 10 minutes elapsed by modifying state
        testSession.state = .active(startedAt: Date().addingTimeInterval(-600))
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        XCTAssertGreaterThan(viewModel.progress, 0.0)
        XCTAssertLessThan(viewModel.progress, 1.0)
        // Should be approximately 1/3 complete (10/30 minutes)
        XCTAssertGreaterThan(viewModel.progress, 0.25)
        XCTAssertLessThan(viewModel.progress, 0.5)
    }
    
    // MARK: - Formatting Tests
    
    func testFormattedRemainingTime() {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 3661) // 1h 1m 1s
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        let formatted = viewModel.formattedRemainingTime
        XCTAssertTrue(formatted.contains(":"))
    }
    
    func testFormattedElapsedTime() {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        let formatted = viewModel.formattedElapsedTime
        XCTAssertTrue(formatted.contains(":"))
    }
    
    func testFormattedTotalDuration() {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 3600) // 1 hour
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        let formatted = viewModel.formattedTotalDuration
        XCTAssertTrue(formatted.contains("1:00:00"))
    }
    
    // MARK: - Session Phase Tests
    
    func testSessionPhaseInactive() {
        // Given - no session
        
        // Then
        XCTAssertEqual(viewModel.sessionPhase, .inactive)
    }
    
    func testSessionPhaseEarly() {
        // Given - new session
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        XCTAssertEqual(viewModel.sessionPhase, .early)
    }
    
    func testSessionPhaseWarning() {
        // Given - session with < 5 minutes remaining
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800) // 30 minutes total
        // Simulate 25 minutes elapsed (5 minutes remaining)
        testSession.state = .active(startedAt: Date().addingTimeInterval(-1500))
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        XCTAssertTrue(viewModel.isInWarningState)
        XCTAssertEqual(viewModel.sessionPhase, .warning)
    }
    
    func testSessionPhaseCritical() {
        // Given - session with < 1 minute remaining
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800) // 30 minutes total
        // Simulate 29 minutes elapsed (1 minute remaining)
        testSession.state = .active(startedAt: Date().addingTimeInterval(-1740))
        
        // When
        viewModel.updateSession(testSession)
        
        // Then
        XCTAssertTrue(viewModel.isInCriticalState)
        XCTAssertEqual(viewModel.sessionPhase, .critical)
    }
    
    // MARK: - Session Management Tests
    
    func testExtendSession() async {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        viewModel.updateSession(testSession)
        let originalDuration = testSession.duration
        var sessionExtended = false
        var extensionTime: TimeInterval = 0
        
        viewModel.onSessionExtended = { time in
            sessionExtended = true
            extensionTime = time
        }
        
        // When
        await viewModel.extendSession(by: 15) // 15 minutes
        
        // Then
        XCTAssertTrue(sessionExtended)
        XCTAssertEqual(extensionTime, 15 * 60) // 15 minutes in seconds
        XCTAssertEqual(viewModel.session?.duration, originalDuration + 900) // Original + 15 minutes
        XCTAssertFalse(viewModel.showingExtendDialog)
    }
    
    func testExtendSessionWithoutActiveSession() async {
        // Given - no active session
        var sessionExtended = false
        
        viewModel.onSessionExtended = { _ in
            sessionExtended = true
        }
        
        // When
        await viewModel.extendSession(by: 15)
        
        // Then
        XCTAssertFalse(sessionExtended)
    }
    
    func testEndSession() async {
        // Given
        let testSession = try! IntentionSession(appGroups: [], applications: [], duration: 1800)
        viewModel.updateSession(testSession)
        var sessionEnded = false
        
        viewModel.onSessionEnded = {
            sessionEnded = true
        }
        
        // When
        await viewModel.endSession()
        
        // Then
        XCTAssertTrue(sessionEnded)
        XCTAssertFalse(viewModel.session?.isActive == true)
    }
    
    func testEndSessionWithoutActiveSession() async {
        // Given - no active session
        var sessionEnded = false
        
        viewModel.onSessionEnded = {
            sessionEnded = true
        }
        
        // When
        await viewModel.endSession()
        
        // Then
        XCTAssertFalse(sessionEnded)
    }
    
    // MARK: - UI Actions Tests
    
    func testToggleControls() {
        // Given
        XCTAssertFalse(viewModel.showingControls)
        
        // When
        viewModel.toggleControls()
        
        // Then
        XCTAssertTrue(viewModel.showingControls)
        
        // When - toggle again
        viewModel.toggleControls()
        
        // Then
        XCTAssertFalse(viewModel.showingControls)
    }
    
    func testShowExtendDialog() {
        // Given
        viewModel.showingControls = true
        
        // When
        viewModel.showExtendDialog()
        
        // Then
        XCTAssertTrue(viewModel.showingExtendDialog)
        XCTAssertFalse(viewModel.showingControls) // Should hide controls
    }
    
    func testCancelExtendDialog() {
        // Given
        viewModel.showingExtendDialog = true
        
        // When
        viewModel.cancelExtendDialog()
        
        // Then
        XCTAssertFalse(viewModel.showingExtendDialog)
    }
    
    // MARK: - Extension Options Tests
    
    func testExtensionOptions() {
        // Then
        XCTAssertEqual(viewModel.extensionOptions, [5, 10, 15, 30])
        XCTAssertEqual(viewModel.selectedExtensionTime, 15) // Default
    }
    
    // MARK: - SessionPhase Tests
    
    func testSessionPhaseColors() {
        XCTAssertEqual(SessionPhase.inactive.color, .gray)
        XCTAssertEqual(SessionPhase.early.color, .green)
        XCTAssertEqual(SessionPhase.active.color, .blue)
        XCTAssertEqual(SessionPhase.warning.color, .orange)
        XCTAssertEqual(SessionPhase.critical.color, .red)
    }
    
    func testSessionPhaseDescriptions() {
        XCTAssertEqual(SessionPhase.inactive.description, "No active session")
        XCTAssertEqual(SessionPhase.early.description, "Session starting")
        XCTAssertEqual(SessionPhase.active.description, "Session active")
        XCTAssertEqual(SessionPhase.warning.description, "Session ending soon")
        XCTAssertEqual(SessionPhase.critical.description, "Session ending very soon")
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
    
    // MARK: - Constants Tests
    
    func testConstants() {
        XCTAssertEqual(AppConstants.Session.warningThreshold, 5 * 60) // 5 minutes
        XCTAssertEqual(AppConstants.Session.criticalThreshold, 1 * 60) // 1 minute
    }
}