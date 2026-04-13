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

    func testDefaultWeeklySchedule() {
        XCTAssertTrue(viewModel.weeklySchedule.isEnabled)
        XCTAssertEqual(viewModel.weeklySchedule.intervals.count, 5) // Mon-Fri seed
        XCTAssertTrue(viewModel.weeklySchedule.intervals.allSatisfy { $0.durationMinutes == 4 * 60 + 30 })
    }

    // MARK: - Data Loading Tests

    func testLoadDataSuccess() async {
        await viewModel.loadData()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadDataFailure() async {
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Test error")

        await viewModel.loadData()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Failed to load settings") == true)
    }

    // MARK: - Schedule Tests

    func testToggleScheduleEnabled() async {
        let initialState = viewModel.weeklySchedule.isEnabled

        await viewModel.toggleScheduleEnabled()

        XCTAssertEqual(viewModel.weeklySchedule.isEnabled, !initialState)
        XCTAssertTrue(mockDataService.saveWeeklyScheduleCalled)
    }

    func testUpdateSchedule() async {
        let newSchedule = WeeklySchedule()
        newSchedule.isEnabled = false
        newSchedule.intervals = [
            FreeTimeInterval(id: UUID(), startMinuteOfWeek: 9 * 60, durationMinutes: 8 * 60)
        ]

        await viewModel.updateSchedule(newSchedule)

        XCTAssertFalse(viewModel.weeklySchedule.isEnabled)
        XCTAssertEqual(viewModel.weeklySchedule.intervals.count, 1)
        XCTAssertTrue(mockDataService.saveWeeklyScheduleCalled)
    }

    func testUpdateScheduleFailure() async {
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Save failed")

        let newSchedule = WeeklySchedule()
        await viewModel.updateSchedule(newSchedule)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Failed to save schedule") == true)
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

    func testScheduleSummaryDisabled() {
        viewModel.weeklySchedule.isEnabled = false
        XCTAssertEqual(viewModel.scheduleSummary, "Blocking is off")
    }

    func testScheduleSummaryNoIntervals() {
        viewModel.weeklySchedule.isEnabled = true
        viewModel.weeklySchedule.intervals = []
        XCTAssertEqual(viewModel.scheduleSummary, "No free time set")
    }

    func testScheduleSummaryMultipleIntervals() {
        viewModel.weeklySchedule.isEnabled = true
        viewModel.weeklySchedule.intervals = [
            FreeTimeInterval(id: UUID(), startMinuteOfWeek: 9 * 60, durationMinutes: 60),
            FreeTimeInterval(id: UUID(), startMinuteOfWeek: 14 * 60, durationMinutes: 60)
        ]
        XCTAssertTrue(viewModel.scheduleSummary.contains("2"))
    }
}

// MARK: - Mock Data Service Extensions

extension MockDataPersistenceService {
    var saveWeeklyScheduleCalled: Bool {
        return methodCalls.contains("saveWeeklySchedule")
    }
}
