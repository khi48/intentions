//
//  IntentionPromptViewModelTests.swift
//  IntentionsTests
//
//  Created by Claude on 13/07/2025.
//

import XCTest
import SwiftUI
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions


final class IntentionPromptViewModelTests: XCTestCase {
    
    var mockDataService: MockDataPersistenceService!
    var viewModel: IntentionPromptViewModel!
    var sessionStartCalled = false
    var cancelCalled = false
    var capturedSession: IntentionSession?
    
    override func setUp() {
        super.setUp()
        mockDataService = MockDataPersistenceService()
        sessionStartCalled = false
        cancelCalled = false
        capturedSession = nil
    }
    
    @MainActor
    private func createViewModel() {
        viewModel = IntentionPromptViewModel(
            dataService: mockDataService,
            onSessionStart: { [weak self] session in
                await MainActor.run {
                    self?.sessionStartCalled = true
                    self?.capturedSession = session
                }
            },
            onCancel: { [weak self] in
                self?.cancelCalled = true
            }
        )
    }
    
    override func tearDown() {
        viewModel = nil
        mockDataService = nil
        capturedSession = nil
    }
    
    // MARK: - Initialization Tests
    
    @MainActor
    func testInitialization() {
        createViewModel()
        
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedDuration, AppConstants.Session.defaultDuration)
        XCTAssertTrue(viewModel.selectedAppGroups.isEmpty)
        XCTAssertTrue(viewModel.selectedApplications.isEmpty)
        XCTAssertTrue(viewModel.availableAppGroups.isEmpty)
        XCTAssertTrue(viewModel.discoveredApps.isEmpty)
        XCTAssertFalse(viewModel.showingDurationPicker)
        XCTAssertFalse(viewModel.showingAppSelection)
        XCTAssertTrue(viewModel.searchText.isEmpty)
        XCTAssertFalse(viewModel.showSystemApps)
    }
    
    // MARK: - Data Loading Tests
    
    @MainActor
    func testLoadDataSuccess() async {
        createViewModel()
        
        // Setup mock data
        let testGroup = createTestAppGroup(name: "Work Apps")
        mockDataService.mockAppGroups = [testGroup]
        
        await viewModel.loadData()
        
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.availableAppGroups.count, 1)
        XCTAssertEqual(viewModel.availableAppGroups.first?.name, "Work Apps")
        XCTAssertFalse(viewModel.discoveredApps.isEmpty) // Should have mock apps
    }
    
    @MainActor
    func testLoadDataFailure() async {
        createViewModel()
        
        // Setup mock to throw error
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Load failed")
        
        await viewModel.loadData()
        
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Failed to load data") == true)
    }
    
    // MARK: - Duration Selection Tests
    
    @MainActor
    func testSelectPresetDuration() {
        createViewModel()
        let testDuration: TimeInterval = 60 * 60 // 1 hour
        
        viewModel.selectPresetDuration(testDuration)
        
        XCTAssertEqual(viewModel.selectedDuration, testDuration)
    }
    
    @MainActor
    func testIsPresetSelected() {
        createViewModel()
        let testDuration: TimeInterval = 30 * 60 // 30 minutes
        viewModel.selectedDuration = testDuration
        
        XCTAssertTrue(viewModel.isPresetSelected(testDuration))
        XCTAssertFalse(viewModel.isPresetSelected(60 * 60)) // 1 hour
    }
    
    @MainActor
    func testFormattedDuration() {
        createViewModel()
        // Test minutes
        viewModel.selectedDuration = 30 * 60 // 30 minutes
        XCTAssertEqual(viewModel.formattedDuration, "30 minutes")
        
        // Test singular minute
        viewModel.selectedDuration = 60 // 1 minute
        XCTAssertEqual(viewModel.formattedDuration, "1 minute")
        
        // Test hours
        viewModel.selectedDuration = 2 * 60 * 60 // 2 hours
        XCTAssertEqual(viewModel.formattedDuration, "2 hours")
        
        // Test singular hour
        viewModel.selectedDuration = 60 * 60 // 1 hour
        XCTAssertEqual(viewModel.formattedDuration, "1 hour")
        
        // Test mixed hours and minutes
        viewModel.selectedDuration = 90 * 60 // 1.5 hours
        XCTAssertEqual(viewModel.formattedDuration, "1 hour 30 minutes")
    }
    
    @MainActor
    func testPresetDurations() {
        createViewModel()
        let expectedDurations = AppConstants.Session.presetDurations
        XCTAssertEqual(viewModel.presetDurations, expectedDurations)
    }
    
    // MARK: - App Group Selection Tests
    
    @MainActor
    func testToggleAppGroup() async {
        // Setup test data
        let testGroup = createTestAppGroup(name: "Work Apps")
        await setupViewModelWithGroups([testGroup])
        
        // Toggle selection on
        viewModel.toggleAppGroup(testGroup.id)
        XCTAssertTrue(viewModel.selectedAppGroups.contains(testGroup.id))
        XCTAssertTrue(viewModel.isAppGroupSelected(testGroup.id))
        
        // Toggle selection off
        viewModel.toggleAppGroup(testGroup.id)
        XCTAssertFalse(viewModel.selectedAppGroups.contains(testGroup.id))
        XCTAssertFalse(viewModel.isAppGroupSelected(testGroup.id))
    }
    
    @MainActor
    func testIsAppGroupSelected() async {
        let testGroup = createTestAppGroup(name: "Work Apps")
        await setupViewModelWithGroups([testGroup])
        
        XCTAssertFalse(viewModel.isAppGroupSelected(testGroup.id))
        
        viewModel.selectedAppGroups.insert(testGroup.id)
        XCTAssertTrue(viewModel.isAppGroupSelected(testGroup.id))
    }
    
    // MARK: - Application Selection Tests
    
    @MainActor
    func testToggleApplication() {
        createViewModel()
        let mockToken = createMockApplicationToken()
        
        // Toggle selection on
        viewModel.toggleApplication(mockToken)
        XCTAssertTrue(viewModel.selectedApplications.contains(mockToken))
        XCTAssertTrue(viewModel.isApplicationSelected(mockToken))
        
        // Toggle selection off
        viewModel.toggleApplication(mockToken)
        XCTAssertFalse(viewModel.selectedApplications.contains(mockToken))
        XCTAssertFalse(viewModel.isApplicationSelected(mockToken))
    }
    
    @MainActor
    func testIsApplicationSelected() {
        createViewModel()
        let mockToken = createMockApplicationToken()
        
        XCTAssertFalse(viewModel.isApplicationSelected(mockToken))
        
        viewModel.selectedApplications.insert(mockToken)
        XCTAssertTrue(viewModel.isApplicationSelected(mockToken))
    }
    
    // MARK: - Search and Filtering Tests
    
    @MainActor
    func testFilteredDiscoveredApps() async {
        createViewModel()
        await viewModel.loadData()
        
        // Test initial state (should show non-system apps)
        let initialCount = viewModel.filteredDiscoveredApps.count
        XCTAssertGreaterThan(initialCount, 0)
        
        // Test system apps toggle
        viewModel.showSystemApps = true
        let withSystemApps = viewModel.filteredDiscoveredApps.count
        XCTAssertGreaterThanOrEqual(withSystemApps, initialCount)
        
        // Test search filtering
        viewModel.searchText = "test"
        let searchResults = viewModel.filteredDiscoveredApps
        // Should filter to apps containing "test" in the name
        for app in searchResults {
            XCTAssertTrue(app.displayName.lowercased().contains("test"))
        }
    }
    
    @MainActor
    func testSearchResults() async {
        createViewModel()
        await viewModel.loadData()
        
        // Test empty search
        viewModel.searchText = ""
        let emptySearchResults = viewModel.searchResults
        XCTAssertEqual(emptySearchResults.count, viewModel.filteredDiscoveredApps.count)
        
        // Test specific search
        viewModel.searchText = "mock"
        let searchResults = viewModel.searchResults
        for app in searchResults {
            XCTAssertTrue(app.displayName.lowercased().contains("mock") || 
                         app.bundleIdentifier.lowercased().contains("mock"))
        }
    }
    
    // MARK: - Selection Management Tests
    
    @MainActor
    func testSelectionCount() async {
        let testGroup = createTestAppGroup(name: "Work Apps")
        await setupViewModelWithGroups([testGroup])
        
        XCTAssertEqual(viewModel.selectionCount, 0)
        
        // Add app group
        viewModel.selectedAppGroups.insert(testGroup.id)
        XCTAssertEqual(viewModel.selectionCount, 1)
        
        // Add individual app
        let mockToken = createMockApplicationToken()
        viewModel.selectedApplications.insert(mockToken)
        XCTAssertEqual(viewModel.selectionCount, 2)
    }
    
    @MainActor
    func testClearSelections() async {
        let testGroup = createTestAppGroup(name: "Work Apps")
        await setupViewModelWithGroups([testGroup])
        
        // Setup selections
        viewModel.selectedAppGroups.insert(testGroup.id)
        viewModel.selectedApplications.insert(createMockApplicationToken())
        XCTAssertGreaterThan(viewModel.selectionCount, 0)
        
        // Clear selections
        viewModel.clearSelections()
        XCTAssertEqual(viewModel.selectionCount, 0)
        XCTAssertTrue(viewModel.selectedAppGroups.isEmpty)
        XCTAssertTrue(viewModel.selectedApplications.isEmpty)
    }
    
    // MARK: - Session Management Tests
    
    @MainActor
    func testCanStartSession() async {
        createViewModel()
        // Initially should not be able to start (no selections)
        XCTAssertFalse(viewModel.canStartSession)
        
        // Add a selection
        let mockToken = createMockApplicationToken()
        viewModel.selectedApplications.insert(mockToken)
        XCTAssertTrue(viewModel.canStartSession)
        
        // Test loading state
        viewModel.isLoading = true
        XCTAssertFalse(viewModel.canStartSession)
    }
    
    @MainActor
    func testStartSessionSuccess() async {
        createViewModel()
        // Setup selections
        let mockToken = createMockApplicationToken()
        viewModel.selectedApplications.insert(mockToken)
        viewModel.selectedDuration = 30 * 60 // 30 minutes
        
        await viewModel.startSession()
        
        XCTAssertTrue(sessionStartCalled)
        XCTAssertNotNil(capturedSession)
        XCTAssertEqual(capturedSession?.duration, 30 * 60)
        XCTAssertTrue(capturedSession?.requestedApplications.contains(mockToken) == true)
    }
    
    @MainActor
    func testStartSessionWithNoSelections() async {
        createViewModel()
        // Try to start session without selections
        await viewModel.startSession()
        
        XCTAssertFalse(sessionStartCalled)
        XCTAssertNil(capturedSession)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Please select at least one app or app group") == true)
    }
    
    @MainActor
    func testStartSessionFailure() async {
        createViewModel()
        // Setup selections with invalid duration to trigger IntentionSession validation error
        viewModel.selectedApplications.insert(createMockApplicationToken())
        viewModel.selectedDuration = 0 // Invalid duration should cause session creation to fail
        
        await viewModel.startSession()
        
        XCTAssertFalse(sessionStartCalled)
        XCTAssertNotNil(viewModel.errorMessage)
        // The exact error message will depend on IntentionSession validation
        XCTAssertFalse(viewModel.errorMessage?.isEmpty == true)
    }
    
    @MainActor
    func testCancel() {
        createViewModel()
        viewModel.cancel()
        
        XCTAssertTrue(cancelCalled)
    }
    
    // MARK: - Error Handling Tests
    
    @MainActor
    func testClearError() {
        createViewModel()
        viewModel.errorMessage = "Test error"
        
        viewModel.clearError()
        
        XCTAssertNil(viewModel.errorMessage)
    }
    
    @MainActor
    func testHandleError() async {
        createViewModel()
        let testError = AppError.sessionNotFound
        
        await viewModel.handleError(testError)
        
        XCTAssertEqual(viewModel.errorMessage, testError.localizedDescription)
    }
    
    // MARK: - Helper Methods
    
    @MainActor
    private func createTestAppGroup(name: String) -> AppGroup {
        do {
            return try AppGroup(id: UUID(), name: name, createdAt: Date(), lastModified: Date())
        } catch {
            fatalError("Failed to create test app group: \(error)")
        }
    }
    
    @MainActor
    private func createMockApplicationToken() -> ApplicationToken {
        // Create a mock token using JSON decoding approach
        let tokenData = """
        {
            "data": "dGVzdERhdGE="
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ApplicationToken.self, from: tokenData)
        } catch {
            // If JSON approach fails, this is a fallback that will need proper implementation
            // In real tests, you'd mock ApplicationToken creation properly
            fatalError("Failed to create mock ApplicationToken: \(error)")
        }
    }
    
    @MainActor
    private func setupViewModelWithGroups(_ groups: [AppGroup]) async {
        createViewModel()
        mockDataService.mockAppGroups = groups
        await viewModel.loadData()
    }
}
