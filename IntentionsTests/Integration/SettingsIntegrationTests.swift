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

    func testCompleteScheduleWorkflow() async throws {
        // 1. Load initial data
        await viewModel.loadData()
        XCTAssertTrue(viewModel.weeklySchedule.isEnabled) // Default is enabled

        // 2. Toggle schedule off
        await viewModel.toggleScheduleEnabled()
        XCTAssertFalse(viewModel.weeklySchedule.isEnabled)

        // 3. Create a weekday-only schedule
        let weekdaySchedule = WeeklySchedule()
        weekdaySchedule.isEnabled = true
        weekdaySchedule.intervals = (0...4).map { dayIndex in
            FreeTimeInterval(
                id: UUID(),
                startMinuteOfWeek: dayIndex * FreeTimeInterval.minutesPerDay + 9 * 60,
                durationMinutes: 8 * 60
            )
        }

        // 4. Update schedule
        await viewModel.updateSchedule(weekdaySchedule)
        XCTAssertTrue(viewModel.weeklySchedule.isEnabled)
        XCTAssertEqual(viewModel.weeklySchedule.intervals.count, 5)
    }

    func testErrorHandlingWorkflow() async throws {
        // 1. Test successful operation first
        await viewModel.loadData()
        XCTAssertNil(viewModel.errorMessage)

        // 2. Set up mock to throw errors
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Test error")

        // 3. Try to update schedule — should fail
        let newSchedule = WeeklySchedule()
        await viewModel.updateSchedule(newSchedule)
        XCTAssertNotNil(viewModel.errorMessage)

        // 4. Clear error
        viewModel.clearError()
        XCTAssertNil(viewModel.errorMessage)

        // 5. Reset mock and try again — should succeed
        mockDataService.shouldThrowError = false
        await viewModel.updateSchedule(newSchedule)
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
        // 1. Test schedule summary with different configurations
        viewModel.weeklySchedule.isEnabled = false
        XCTAssertEqual(viewModel.scheduleSummary, "Blocking is off")

        viewModel.weeklySchedule.isEnabled = true
        viewModel.weeklySchedule.intervals = []
        XCTAssertEqual(viewModel.scheduleSummary, "No free time set")

        // 2. Test multiple intervals
        viewModel.weeklySchedule.intervals = [
            FreeTimeInterval(id: UUID(), startMinuteOfWeek: 9 * 60, durationMinutes: 60),
            FreeTimeInterval(id: UUID(), startMinuteOfWeek: 14 * 60, durationMinutes: 60)
        ]
        XCTAssertTrue(viewModel.scheduleSummary.contains("2"))

        // 3. Test single interval produces a non-empty summary
        viewModel.weeklySchedule.intervals = [
            FreeTimeInterval(id: UUID(), startMinuteOfWeek: 17 * 60, durationMinutes: 4 * 60 + 30)
        ]
        XCTAssertFalse(viewModel.scheduleSummary.isEmpty)
        XCTAssertNotEqual(viewModel.scheduleSummary, "No free time set")
        XCTAssertNotEqual(viewModel.scheduleSummary, "Blocking is off")
    }
}
