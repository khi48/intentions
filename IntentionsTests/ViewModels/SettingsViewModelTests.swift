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
        XCTAssertFalse(viewModel.showingScheduleEditor)
    }

    func testDefaultScheduleSettings() {
        // Should initialize with default schedule settings
        XCTAssertTrue(viewModel.scheduleSettings.isEnabled)
        XCTAssertEqual(viewModel.scheduleSettings.startHour, AppConstants.Schedule.defaultStartHour)
        XCTAssertEqual(viewModel.scheduleSettings.endHour, AppConstants.Schedule.defaultEndHour)
        XCTAssertEqual(viewModel.scheduleSettings.activeDays.count, 7) // All days by default
    }

    // MARK: - Data Loading Tests

    func testLoadDataSuccess() async {
        await viewModel.loadData()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadDataFailure() async {
        // Setup mock to throw error
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Test error")

        await viewModel.loadData()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Failed to load settings") == true)
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
}

// MARK: - Mock Data Service Extensions

extension MockDataPersistenceService {
    var saveScheduleSettingsCalled: Bool {
        return methodCalls.contains("saveScheduleSettings")
    }
}
