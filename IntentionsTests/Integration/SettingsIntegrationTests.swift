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

        // 3. Create a weekday-only schedule: one routine recurring Mon-Fri.
        let weekdaySchedule = WeeklySchedule()
        weekdaySchedule.isEnabled = true
        weekdaySchedule.routines = [
            FreeTimeRoutine(
                id: UUID(),
                name: nil,
                startMinute: 9 * 60,
                durationMinutes: 8 * 60,
                days: [.monday, .tuesday, .wednesday, .thursday, .friday],
                sortIndex: 0
            )
        ]

        // 4. Update schedule
        await viewModel.updateSchedule(weekdaySchedule)
        XCTAssertTrue(viewModel.weeklySchedule.isEnabled)
        XCTAssertEqual(viewModel.weeklySchedule.routines.count, 1)
        XCTAssertEqual(viewModel.weeklySchedule.routines.first?.days.count, 5)
    }

    func testErrorHandlingWorkflow() async throws {
        // Errors bubble up via onError callback (#53). Capture invocations and
        // assert on what was forwarded to the parent ContentViewModel.
        var capturedErrors: [Error] = []
        viewModel.onError = { error, _ in capturedErrors.append(error) }

        // 1. Successful operation does not invoke onError
        await viewModel.loadData()
        XCTAssertTrue(capturedErrors.isEmpty)

        // 2. Set up mock to throw errors
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Test error")

        // 3. Try to update schedule — should fail and bubble
        let newSchedule = WeeklySchedule()
        await viewModel.updateSchedule(newSchedule)
        XCTAssertEqual(capturedErrors.count, 1)
        XCTAssertTrue(capturedErrors.last?.localizedDescription.contains("Failed to save schedule") == true)

        // 4. Reset mock and try again — should succeed (no new error)
        mockDataService.shouldThrowError = false
        await viewModel.updateSchedule(newSchedule)
        XCTAssertEqual(capturedErrors.count, 1)
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
        viewModel.weeklySchedule.routines = []
        XCTAssertEqual(viewModel.scheduleSummary, "No routines set")

        // 2. Test multiple routines
        viewModel.weeklySchedule.routines = [
            FreeTimeRoutine(
                id: UUID(),
                name: nil,
                startMinute: 9 * 60,
                durationMinutes: 60,
                days: [.monday],
                sortIndex: 0
            ),
            FreeTimeRoutine(
                id: UUID(),
                name: nil,
                startMinute: 14 * 60,
                durationMinutes: 60,
                days: [.monday],
                sortIndex: 1
            )
        ]
        XCTAssertTrue(viewModel.scheduleSummary.contains("2"))

        // 3. Test single routine produces a non-empty summary
        viewModel.weeklySchedule.routines = [
            FreeTimeRoutine(
                id: UUID(),
                name: nil,
                startMinute: 17 * 60,
                durationMinutes: 4 * 60 + 30,
                days: [.friday],
                sortIndex: 0
            )
        ]
        XCTAssertFalse(viewModel.scheduleSummary.isEmpty)
        XCTAssertNotEqual(viewModel.scheduleSummary, "No routines set")
        XCTAssertNotEqual(viewModel.scheduleSummary, "Blocking is off")
    }
}
