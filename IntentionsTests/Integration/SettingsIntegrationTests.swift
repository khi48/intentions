//
//  SettingsIntegrationTests.swift
//  IntentionsTests
//
//  Created by Claude on 13/07/2025.
//

import XCTest
import SwiftUI
import FamilyControls
@testable import Intentions

@MainActor
final class SettingsIntegrationTests: XCTestCase {
    
    var mockDataService: MockDataPersistenceService!
    var viewModel: SettingsViewModel!
    
    override func setUp() async throws {
        mockDataService = MockDataPersistenceService()
        await mockDataService.reset()
        viewModel = SettingsViewModel(dataService: mockDataService)
    }
    
    override func tearDown() async throws {
        await mockDataService.reset()
        viewModel = nil
        mockDataService = nil
    }
    
    // MARK: - Full Workflow Tests
    
    func testCompleteAppGroupCreationWorkflow() async throws {
        // 1. Load initial data
        await viewModel.loadData()
        XCTAssertEqual(viewModel.totalAppGroups, 0)
        
        // 2. Create an app group
        await viewModel.createAppGroup(name: "Work Apps", applications: Set())
        XCTAssertEqual(viewModel.totalAppGroups, 1)
        XCTAssertEqual(viewModel.appGroups.first?.name, "Work Apps")
        
        // 3. Create another app group
        await viewModel.createAppGroup(name: "Social Apps", applications: Set())
        XCTAssertEqual(viewModel.totalAppGroups, 2)
        
        // 4. Delete an app group
        let groupToDelete = viewModel.appGroups.first!
        await viewModel.deleteAppGroup(groupToDelete)
        XCTAssertEqual(viewModel.totalAppGroups, 1)
        
        // 5. Verify final state
        XCTAssertEqual(viewModel.appGroups.count, 1)
        XCTAssertNotEqual(viewModel.appGroups.first?.name, groupToDelete.name)
    }
    
    func testCompleteScheduleSettingsWorkflow() async throws {
        // 1. Load initial data
        await viewModel.loadData()
        XCTAssertTrue(viewModel.scheduleSettings.isEnabled) // Default is enabled
        
        // 2. Toggle schedule off
        await viewModel.toggleScheduleEnabled()
        XCTAssertFalse(viewModel.scheduleSettings.isEnabled)
        XCTAssertEqual(viewModel.scheduleStatusText, "Disabled")
        
        // 3. Create custom schedule settings
        let customSettings = ScheduleSettings()
        customSettings.isEnabled = true
        customSettings.activeHours = 9...17 // 9 AM to 5 PM
        customSettings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday] // Weekdays only
        
        // 4. Update settings
        await viewModel.updateScheduleSettings(customSettings)
        XCTAssertTrue(viewModel.scheduleSettings.isEnabled)
        XCTAssertEqual(viewModel.scheduleSettings.activeHours, 9...17)
        XCTAssertEqual(viewModel.scheduleSettings.activeDays.count, 5)
        XCTAssertEqual(viewModel.activeDaysText, "Weekdays")
    }
    
    func testErrorHandlingWorkflow() async throws {
        // 1. Test successful operation first
        await viewModel.loadData()
        XCTAssertNil(viewModel.errorMessage)
        
        // 2. Set up mock to throw errors
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Test error")
        
        // 3. Try to create app group - should fail
        await viewModel.createAppGroup(name: "Test Group", applications: Set())
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Failed to create app group") == true)
        
        // 4. Clear error
        viewModel.clearError()
        XCTAssertNil(viewModel.errorMessage)
        
        // 5. Reset mock and try again - should succeed
        mockDataService.shouldThrowError = false
        await viewModel.createAppGroup(name: "Test Group", applications: Set())
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.totalAppGroups, 1)
    }
    
    func testUIStateManagement() async throws {
        // 1. Test initial UI state
        XCTAssertFalse(viewModel.showingScheduleEditor)
        XCTAssertFalse(viewModel.showingAppGroupEditor)
        XCTAssertFalse(viewModel.showingDeleteConfirmation)
        XCTAssertNil(viewModel.groupToDelete)
        
        // 2. Test navigation state changes
        viewModel.showScheduleEditor()
        XCTAssertTrue(viewModel.showingScheduleEditor)
        
        viewModel.hideScheduleEditor()
        XCTAssertFalse(viewModel.showingScheduleEditor)
        
        viewModel.showAppGroupEditor()
        XCTAssertTrue(viewModel.showingAppGroupEditor)
        
        viewModel.hideAppGroupEditor()
        XCTAssertFalse(viewModel.showingAppGroupEditor)
        
        // 3. Test delete confirmation workflow
        await viewModel.createAppGroup(name: "Test Group", applications: Set())
        let testGroup = viewModel.appGroups.first!
        
        viewModel.confirmDeleteGroup(testGroup)
        XCTAssertTrue(viewModel.showingDeleteConfirmation)
        XCTAssertEqual(viewModel.groupToDelete?.id, testGroup.id)
        
        viewModel.cancelDelete()
        XCTAssertFalse(viewModel.showingDeleteConfirmation)
        XCTAssertNil(viewModel.groupToDelete)
        
        // 4. Test actual delete execution
        viewModel.confirmDeleteGroup(testGroup)
        await viewModel.executeDelete()
        XCTAssertFalse(viewModel.showingDeleteConfirmation)
        XCTAssertNil(viewModel.groupToDelete)
        XCTAssertEqual(viewModel.totalAppGroups, 0)
    }
    
    func testComputedPropertiesWithRealData() async throws {
        // 1. Create test data
        await viewModel.createAppGroup(name: "Work Apps", applications: Set())
        await viewModel.createAppGroup(name: "Social Apps", applications: Set())
        
        // 2. Test statistics computation
        XCTAssertEqual(viewModel.totalAppGroups, 2)
        XCTAssertEqual(viewModel.totalManagedApps, 0) // No apps in groups yet
        
        // 3. Test schedule status with different configurations
        viewModel.scheduleSettings.isEnabled = false
        XCTAssertEqual(viewModel.scheduleStatusText, "Disabled")
        XCTAssertEqual(viewModel.scheduleStatusColor, .gray)
        
        viewModel.scheduleSettings.isEnabled = true
        let statusText = viewModel.scheduleStatusText
        XCTAssertTrue(["Active", "Inactive"].contains(statusText))
        
        // 4. Test formatted hours
        viewModel.scheduleSettings.activeHours = 8...20
        let formattedHours = viewModel.formattedActiveHours
        XCTAssertTrue(formattedHours.contains("-"))
        
        // 5. Test different day configurations
        viewModel.scheduleSettings.activeDays = Set(Weekday.allCases)
        XCTAssertEqual(viewModel.activeDaysText, "Every day")
        
        viewModel.scheduleSettings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        XCTAssertEqual(viewModel.activeDaysText, "Weekdays")
        
        viewModel.scheduleSettings.activeDays = [.saturday, .sunday]
        XCTAssertEqual(viewModel.activeDaysText, "Weekends")
        
        viewModel.scheduleSettings.activeDays = [.monday, .wednesday]
        let customDays = viewModel.activeDaysText
        XCTAssertTrue(customDays.contains("Mon"))
        XCTAssertTrue(customDays.contains("Wed"))
    }
}
