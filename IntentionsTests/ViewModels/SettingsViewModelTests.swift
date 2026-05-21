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
        XCTAssertFalse(viewModel.showingScheduleEditor)
    }

    func testDefaultWeeklySchedule() {
        // FreeTimeRoutine migration: WeeklySchedule.init starts with no
        // routines. The Mon-Fri seed previously baked into the default was
        // dropped — routine creation is now user-driven.
        XCTAssertTrue(viewModel.weeklySchedule.isEnabled)
        XCTAssertTrue(viewModel.weeklySchedule.routines.isEmpty)
    }

    // MARK: - Data Loading Tests

    func testLoadDataSuccess() async {
        var capturedError: Error?
        viewModel.onError = { error, _ in capturedError = error }

        await viewModel.loadData()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(capturedError)
    }

    func testLoadDataFailure() async {
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Test error")

        var capturedMessage: String?
        var capturedRetry: (@Sendable () async -> Void)?
        viewModel.onError = { error, retry in
            capturedMessage = error.localizedDescription
            capturedRetry = retry
        }

        await viewModel.loadData()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(capturedMessage)
        XCTAssertTrue(capturedMessage?.contains("Failed to load settings") == true)
        XCTAssertNotNil(capturedRetry)
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
        newSchedule.routines = [
            FreeTimeRoutine(
                id: UUID(),
                name: nil,
                startMinute: 9 * 60,
                durationMinutes: 8 * 60,
                days: [.monday],
                sortIndex: 0
            )
        ]

        await viewModel.updateSchedule(newSchedule)

        XCTAssertFalse(viewModel.weeklySchedule.isEnabled)
        XCTAssertEqual(viewModel.weeklySchedule.routines.count, 1)
        XCTAssertTrue(mockDataService.saveWeeklyScheduleCalled)
    }

    func testUpdateScheduleFailure() async {
        mockDataService.shouldThrowError = true
        mockDataService.errorToThrow = AppError.persistenceError("Save failed")

        var capturedMessage: String?
        var capturedRetry: (@Sendable () async -> Void)?
        viewModel.onError = { error, retry in
            capturedMessage = error.localizedDescription
            capturedRetry = retry
        }

        let newSchedule = WeeklySchedule()
        await viewModel.updateSchedule(newSchedule)

        XCTAssertNotNil(capturedMessage)
        XCTAssertTrue(capturedMessage?.contains("Failed to save schedule") == true)
        XCTAssertNotNil(capturedRetry)
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

    func testScheduleSummaryNoRoutines() {
        viewModel.weeklySchedule.isEnabled = true
        viewModel.weeklySchedule.routines = []
        XCTAssertEqual(viewModel.scheduleSummary, "No routines set")
    }

    func testScheduleSummaryMultipleRoutines() {
        viewModel.weeklySchedule.isEnabled = true
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
    }
}

// MARK: - Mock Data Service Extensions

extension MockDataPersistenceService {
    var saveWeeklyScheduleCalled: Bool {
        return methodCalls.contains("saveWeeklySchedule")
    }
}
