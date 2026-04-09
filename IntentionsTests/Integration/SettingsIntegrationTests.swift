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

        // 3. Try to update schedule settings - should fail
        let newSettings = ScheduleSettings()
        await viewModel.updateScheduleSettings(newSettings)
        XCTAssertNotNil(viewModel.errorMessage)

        // 4. Clear error
        viewModel.clearError()
        XCTAssertNil(viewModel.errorMessage)

        // 5. Reset mock and try again - should succeed
        mockDataService.shouldThrowError = false
        await viewModel.updateScheduleSettings(newSettings)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUIStateManagement() async throws {
        // 1. Test initial UI state
        XCTAssertFalse(viewModel.showingScheduleEditor)

        // 2. Test navigation state changes
        viewModel.showScheduleEditor()
        XCTAssertTrue(viewModel.showingScheduleEditor)

        viewModel.hideScheduleEditor()
        XCTAssertFalse(viewModel.showingScheduleEditor)
    }

    func testComputedPropertiesWithRealData() async throws {
        // 1. Test schedule status with different configurations
        viewModel.scheduleSettings.isEnabled = false
        XCTAssertEqual(viewModel.scheduleStatusText, "Disabled")
        XCTAssertEqual(viewModel.scheduleStatusColor, .gray)

        viewModel.scheduleSettings.isEnabled = true
        let statusText = viewModel.scheduleStatusText
        XCTAssertTrue(["Active", "Inactive"].contains(statusText))

        // 2. Test formatted hours
        viewModel.scheduleSettings.activeHours = 8...20
        let formattedHours = viewModel.formattedActiveHours
        XCTAssertTrue(formattedHours.contains("-"))

        // 3. Test different day configurations
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
