//
//  SettingsViewModelTests.swift
//  IntentionsTests
//
//  Created by Claude on 13/07/2025.
//

import XCTest
import SwiftUI
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

@MainActor
final class SettingsViewModelTests: XCTestCase {
    
    var mockDataService: MockDataPersistenceService!
    var viewModel: SettingsViewModel!
    
    override func setUp() async throws {
        mockDataService = MockDataPersistenceService()
        viewModel = SettingsViewModel(dataService: mockDataService)
    }
    
    override func tearDown() async throws {
        viewModel = nil
        mockDataService = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
        XCTAssertFalse(viewModel.showingScheduleEditor)
        XCTAssertFalse(viewModel.showingAppGroupEditor)
        XCTAssertFalse(viewModel.showingDeleteConfirmation)
        XCTAssertNil(viewModel.groupToDelete)
    }
    
    func testDefaultScheduleSettings() {
        // Should initialize with default schedule settings
        XCTAssertTrue(viewModel.scheduleSettings.isEnabled)
        XCTAssertEqual(viewModel.scheduleSettings.activeHours, AppConstants.Schedule.defaultActiveHours)
        XCTAssertEqual(viewModel.scheduleSettings.activeDays.count, 7) // All days by default
    }
    
    // MARK: - Data Loading Tests
    
    func testLoadDataSuccess() async {
        // Setup mock data
        let testGroup = createTestAppGroup(name: "Work Apps")
        mockDataService.mockAppGroups = [testGroup]
        
        await viewModel.loadData()
        
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.appGroups.count, 1)
        XCTAssertEqual(viewModel.appGroups.first?.name, "Work Apps")
        XCTAssertEqual(viewModel.totalAppGroups, 1)
    }
    
    func testLoadDataFailure() async {
        // Setup mock to throw error
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Test error")
        
        await viewModel.loadData()
        
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Failed to load settings") == true)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
    }
    
    // MARK: - Schedule Settings Tests
    
    func testToggleScheduleEnabled() async {
        let initialState = viewModel.scheduleSettings.isEnabled
        
        await viewModel.toggleScheduleEnabled()
        
        XCTAssertEqual(viewModel.scheduleSettings.isEnabled, !initialState)
        XCTAssertTrue(mockDataService.saveScheduleSettingsCalled)
    }
    
    func testUpdateScheduleSettings() async {
        let newSettings = ScheduleSettings()
        newSettings.isEnabled = false
        newSettings.activeHours = 10...18
        newSettings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        
        await viewModel.updateScheduleSettings(newSettings)
        
        XCTAssertFalse(viewModel.scheduleSettings.isEnabled)
        XCTAssertEqual(viewModel.scheduleSettings.activeHours, 10...18)
        XCTAssertEqual(viewModel.scheduleSettings.activeDays.count, 5)
        XCTAssertTrue(mockDataService.saveScheduleSettingsCalled)
    }
    
    func testUpdateScheduleSettingsFailure() async {
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Save failed")
        
        let newSettings = ScheduleSettings()
        await viewModel.updateScheduleSettings(newSettings)
        
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Failed to save schedule settings") == true)
    }
    
    // MARK: - App Group Management Tests
    
    func testCreateAppGroupSuccess() async {
        let appTokens = Set<ApplicationToken>()
        
        await viewModel.createAppGroup(name: "Social Apps", applications: appTokens)
        
        XCTAssertTrue(mockDataService.saveAppGroupCalled)
        XCTAssertEqual(viewModel.appGroups.count, 1)
        XCTAssertEqual(viewModel.appGroups.first?.name, "Social Apps")
        XCTAssertEqual(viewModel.totalAppGroups, 1)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testCreateAppGroupEmptyName() async {
        await viewModel.createAppGroup(name: "", applications: Set())
        
        XCTAssertFalse(mockDataService.saveAppGroupCalled)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "App group name cannot be empty")
    }
    
    func testCreateAppGroupNameTooLong() async {
        let longName = String(repeating: "a", count: AppConstants.AppGroup.maxNameLength + 1)
        
        await viewModel.createAppGroup(name: longName, applications: Set())
        
        XCTAssertFalse(mockDataService.saveAppGroupCalled)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "App group name is too long")
    }
    
    func testCreateAppGroupReservedName() async {
        await viewModel.createAppGroup(name: "System", applications: Set())
        
        XCTAssertFalse(mockDataService.saveAppGroupCalled)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "This name is reserved and cannot be used")
    }
    
    func testCreateAppGroupFailure() async {
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Save failed")
        
        await viewModel.createAppGroup(name: "Test Group", applications: Set())
        
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Failed to create app group") == true)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
    }
    
    func testUpdateAppGroup() async {
        // Setup initial group
        let group = createTestAppGroup(name: "Original Name")
        viewModel.appGroups = [group]
        
        // Update the group
        let updatedGroup = group
        updatedGroup.name = "Updated Name"
        
        await viewModel.updateAppGroup(updatedGroup)
        
        XCTAssertTrue(mockDataService.saveAppGroupCalled)
        XCTAssertEqual(viewModel.appGroups.first?.name, "Updated Name")
    }
    
    func testDeleteAppGroup() async {
        // Setup initial group
        let group = createTestAppGroup(name: "To Delete")
        viewModel.appGroups = [group]
        
        await viewModel.deleteAppGroup(group)
        
        XCTAssertTrue(mockDataService.deleteAppGroupCalled)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
        XCTAssertEqual(viewModel.totalAppGroups, 0)
    }
    
    func testConfirmDeleteGroup() {
        let group = createTestAppGroup(name: "Test Group")
        
        viewModel.confirmDeleteGroup(group)
        
        XCTAssertEqual(viewModel.groupToDelete?.id, group.id)
        XCTAssertTrue(viewModel.showingDeleteConfirmation)
    }
    
    func testCancelDelete() {
        let group = createTestAppGroup(name: "Test Group")
        viewModel.groupToDelete = group
        viewModel.showingDeleteConfirmation = true
        
        viewModel.cancelDelete()
        
        XCTAssertNil(viewModel.groupToDelete)
        XCTAssertFalse(viewModel.showingDeleteConfirmation)
    }
    
    func testExecuteDelete() async {
        let group = createTestAppGroup(name: "Test Group")
        viewModel.appGroups = [group]
        viewModel.groupToDelete = group
        viewModel.showingDeleteConfirmation = true
        
        await viewModel.executeDelete()
        
        XCTAssertTrue(mockDataService.deleteAppGroupCalled)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
        XCTAssertNil(viewModel.groupToDelete)
        XCTAssertFalse(viewModel.showingDeleteConfirmation)
    }
    
    // MARK: - Statistics Tests
    
    func testStatisticsUpdate() async {
        // Setup test data
        let group1 = createTestAppGroup(name: "Group 1", appCount: 3)
        let group2 = createTestAppGroup(name: "Group 2", appCount: 5)
        mockDataService.mockAppGroups = [group1, group2]
        
        await viewModel.loadData()
        
        XCTAssertEqual(viewModel.totalAppGroups, 2)
        XCTAssertEqual(viewModel.totalManagedApps, 8) // 3 + 5 apps
    }
    
    // MARK: - Error Handling Tests
    
    func testClearError() {
        viewModel.errorMessage = "Test error"
        
        viewModel.clearError()
        
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testHandleError() {
        let testError = AppError.persistenceError("Test error")
        
        viewModel.handleError(testError)
        
        XCTAssertEqual(viewModel.errorMessage, testError.localizedDescription)
    }
    
    // MARK: - Navigation Tests
    
    func testShowHideScheduleEditor() {
        viewModel.showScheduleEditor()
        XCTAssertTrue(viewModel.showingScheduleEditor)
        
        viewModel.hideScheduleEditor()
        XCTAssertFalse(viewModel.showingScheduleEditor)
    }
    
    func testShowHideAppGroupEditor() {
        viewModel.showAppGroupEditor()
        XCTAssertTrue(viewModel.showingAppGroupEditor)
        
        viewModel.hideAppGroupEditor()
        XCTAssertFalse(viewModel.showingAppGroupEditor)
    }
    
    // MARK: - Computed Properties Tests
    
    func testScheduleStatusText() {
        // Test disabled
        viewModel.scheduleSettings.isEnabled = false
        XCTAssertEqual(viewModel.scheduleStatusText, "Disabled")
        
        // Test enabled but inactive (mock current time outside active hours)
        viewModel.scheduleSettings.isEnabled = true
        // Note: This test would need time mocking for proper testing of active/inactive states
        // For now, we test the enabled state
        XCTAssertTrue(["Active", "Inactive"].contains(viewModel.scheduleStatusText))
    }
    
    func testScheduleStatusColor() {
        // Test disabled
        viewModel.scheduleSettings.isEnabled = false
        XCTAssertEqual(viewModel.scheduleStatusColor, .gray)
        
        // Test enabled
        viewModel.scheduleSettings.isEnabled = true
        XCTAssertTrue([Color.green, Color.orange].contains(viewModel.scheduleStatusColor))
    }
    
    func testFormattedActiveHours() {
        viewModel.scheduleSettings.activeHours = 9...17
        let formatted = viewModel.formattedActiveHours
        
        // Should contain time format (basic check since exact format depends on locale)
        XCTAssertTrue(formatted.contains("-"))
        XCTAssertTrue(formatted.count > 5) // Should be something like "9:00 AM - 5:00 PM"
    }
    
    func testActiveDaysText() {
        // Test all days
        viewModel.scheduleSettings.activeDays = Set(Weekday.allCases)
        XCTAssertEqual(viewModel.activeDaysText, "Every day")
        
        // Test weekdays only
        viewModel.scheduleSettings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        XCTAssertEqual(viewModel.activeDaysText, "Weekdays")
        
        // Test weekends only
        viewModel.scheduleSettings.activeDays = [.saturday, .sunday]
        XCTAssertEqual(viewModel.activeDaysText, "Weekends")
        
        // Test custom days
        viewModel.scheduleSettings.activeDays = [.monday, .wednesday, .friday]
        let result = viewModel.activeDaysText
        XCTAssertTrue(result.contains("Mon"))
        XCTAssertTrue(result.contains("Wed"))
        XCTAssertTrue(result.contains("Fri"))
    }
    
    // MARK: - Helper Methods
    
    private func createTestAppGroup(name: String, appCount: Int = 1) -> AppGroup {
        do {
            let group = try AppGroup(id: UUID(), name: name, createdAt: Date(), lastModified: Date())
            
            // Add mock application tokens
            for _ in 0..<appCount {
                // Since ApplicationToken can't be easily created in tests, we'll use an empty set
                // In a real implementation, this would use proper mock tokens
            }
            
            return group
        } catch {
            fatalError("Failed to create test app group: \(error)")
        }
    }
}

// MARK: - Mock Data Service Extensions

extension MockDataPersistenceService {
    var saveScheduleSettingsCalled: Bool {
        return methodCalls.contains("saveScheduleSettings")
    }
    
    var saveAppGroupCalled: Bool {
        return methodCalls.contains("saveAppGroup")
    }
    
    var deleteAppGroupCalled: Bool {
        return methodCalls.contains("deleteAppGroup")
    }
}
