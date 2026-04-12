//
//  QuickActionsViewModelTests.swift
//  IntentionsTests
//
//  Created by Claude on 12/04/2026.
//

import XCTest
import SwiftUI
@testable import Intentions

@MainActor
final class QuickActionsViewModelTests: XCTestCase {

    private var viewModel: QuickActionsViewModel!
    private var mockDataService: MockDataPersistenceService!

    override func setUp() {
        super.setUp()
        mockDataService = MockDataPersistenceService()
        viewModel = QuickActionsViewModel(dataService: mockDataService)
    }

    override func tearDown() {
        viewModel = nil
        mockDataService = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createQuickAction(
        name: String = "Test Action",
        subtitle: String? = "Test subtitle",
        duration: TimeInterval = 30 * 60
    ) -> QuickAction {
        QuickAction(
            name: name,
            subtitle: subtitle,
            iconName: "star.fill",
            color: Color.blue,
            duration: duration
        )
    }

    // MARK: - loadData Tests

    func testLoadDataLoadsAndSortsBySortOrder() async {
        // Given - MockDataPersistenceService has 3 default quick actions
        // They all have sortOrder = 0 by default

        // When
        await viewModel.loadData()

        // Then
        XCTAssertEqual(viewModel.quickActions.count, 3)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadDataWithEmptyStore() async {
        // Given - Clear default data
        await mockDataService.reset()

        // When
        await viewModel.loadData()

        // Then
        XCTAssertEqual(viewModel.quickActions.count, 0)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadDataSortsBySortOrder() async {
        // Given - Create actions with specific sort orders
        await mockDataService.reset()
        var action1 = createQuickAction(name: "Third")
        action1.sortOrder = 2
        var action2 = createQuickAction(name: "First")
        action2.sortOrder = 0
        var action3 = createQuickAction(name: "Second")
        action3.sortOrder = 1

        try! await mockDataService.save([action1, action2, action3], forKey: "quickActions")

        // When
        await viewModel.loadData()

        // Then
        XCTAssertEqual(viewModel.quickActions.count, 3)
        XCTAssertEqual(viewModel.quickActions[0].name, "First")
        XCTAssertEqual(viewModel.quickActions[1].name, "Second")
        XCTAssertEqual(viewModel.quickActions[2].name, "Third")
    }

    // MARK: - saveQuickAction Tests

    func testSaveNewQuickActionAssignsSortOrder() async {
        // Given - Start with empty data
        await mockDataService.reset()
        await viewModel.loadData()
        XCTAssertEqual(viewModel.quickActions.count, 0)

        let newAction = createQuickAction(name: "New Action")

        // When
        await viewModel.saveQuickAction(newAction)

        // Then
        XCTAssertEqual(viewModel.quickActions.count, 1)
        XCTAssertEqual(viewModel.quickActions[0].name, "New Action")
        XCTAssertEqual(viewModel.quickActions[0].sortOrder, 0)
    }

    func testSaveSecondQuickActionGetsSortOrderIncremented() async {
        // Given - One action already exists
        await mockDataService.reset()
        await viewModel.loadData()

        let first = createQuickAction(name: "First")
        await viewModel.saveQuickAction(first)

        // When
        let second = createQuickAction(name: "Second")
        await viewModel.saveQuickAction(second)

        // Then
        XCTAssertEqual(viewModel.quickActions.count, 2)
        XCTAssertEqual(viewModel.quickActions[0].sortOrder, 0)
        XCTAssertEqual(viewModel.quickActions[1].sortOrder, 1)
    }

    func testSaveExistingQuickActionUpdates() async {
        // Given
        await mockDataService.reset()
        await viewModel.loadData()

        var action = createQuickAction(name: "Original")
        await viewModel.saveQuickAction(action)
        XCTAssertEqual(viewModel.quickActions.count, 1)

        // When - Update the same action (same id)
        action = viewModel.quickActions[0]
        var updatedAction = action
        updatedAction.name = "Updated"
        await viewModel.saveQuickAction(updatedAction)

        // Then
        XCTAssertEqual(viewModel.quickActions.count, 1)
        XCTAssertEqual(viewModel.quickActions[0].name, "Updated")
    }

    // MARK: - deleteQuickAction Tests

    func testDeleteQuickAction() async {
        // Given
        await viewModel.loadData()
        let initialCount = viewModel.quickActions.count
        XCTAssertTrue(initialCount > 0)

        let actionToDelete = viewModel.quickActions[0]

        // When
        await viewModel.deleteQuickAction(actionToDelete)

        // Then
        XCTAssertEqual(viewModel.quickActions.count, initialCount - 1)
        XCTAssertFalse(viewModel.quickActions.contains(where: { $0.id == actionToDelete.id }))
        XCTAssertFalse(viewModel.showingDeleteAlert)
        XCTAssertNil(viewModel.quickActionToDelete)
    }

    func testDeleteQuickActionPersists() async {
        // Given
        await viewModel.loadData()
        let actionToDelete = viewModel.quickActions[0]

        // When
        await viewModel.deleteQuickAction(actionToDelete)

        // Then - Reload and verify deletion persisted
        let freshViewModel = QuickActionsViewModel(dataService: mockDataService)
        await freshViewModel.loadData()
        XCTAssertFalse(freshViewModel.quickActions.contains(where: { $0.id == actionToDelete.id }))
    }

    // MARK: - moveQuickAction Tests

    func testMoveQuickAction() async {
        // Given
        await viewModel.loadData()
        XCTAssertTrue(viewModel.quickActions.count >= 3)

        let firstActionName = viewModel.quickActions[0].name
        let secondActionName = viewModel.quickActions[1].name

        // When - Move first to second position
        await viewModel.moveQuickAction(from: 0, to: 1)

        // Then
        XCTAssertEqual(viewModel.quickActions[0].name, secondActionName)
        XCTAssertEqual(viewModel.quickActions[1].name, firstActionName)
        // Sort orders should be reassigned
        XCTAssertEqual(viewModel.quickActions[0].sortOrder, 0)
        XCTAssertEqual(viewModel.quickActions[1].sortOrder, 1)
    }

    func testMoveQuickActionSameIndex() async {
        // Given
        await viewModel.loadData()
        let originalOrder = viewModel.quickActions.map(\.name)

        // When - Move to same position (no-op)
        await viewModel.moveQuickAction(from: 0, to: 0)

        // Then - Nothing should change
        XCTAssertEqual(viewModel.quickActions.map(\.name), originalOrder)
    }

    func testMoveQuickActionOutOfBounds() async {
        // Given
        await viewModel.loadData()
        let originalOrder = viewModel.quickActions.map(\.name)

        // When - Out of bounds index
        await viewModel.moveQuickAction(from: 0, to: 100)

        // Then - Nothing should change
        XCTAssertEqual(viewModel.quickActions.map(\.name), originalOrder)
    }

    // MARK: - toggleQuickActionEnabled Tests

    func testToggleQuickActionEnabled() async {
        // Given
        await viewModel.loadData()
        let action = viewModel.quickActions[0]
        let wasEnabled = action.isEnabled

        // When
        await viewModel.toggleQuickActionEnabled(action)

        // Then
        let toggledAction = viewModel.quickActions.first(where: { $0.id == action.id })
        XCTAssertNotNil(toggledAction)
        XCTAssertEqual(toggledAction?.isEnabled, !wasEnabled)
    }

    // MARK: - recordQuickActionUsage Tests

    func testRecordQuickActionUsage() async {
        // Given
        await viewModel.loadData()
        let action = viewModel.quickActions[0]
        let originalUsageCount = action.usageCount

        // When
        await viewModel.recordQuickActionUsage(action)

        // Then
        let updatedAction = viewModel.quickActions.first(where: { $0.id == action.id })
        XCTAssertNotNil(updatedAction)
        XCTAssertEqual(updatedAction?.usageCount, originalUsageCount + 1)
        XCTAssertNotNil(updatedAction?.lastUsed)
    }

    func testRecordQuickActionUsageMultipleTimes() async {
        // Given
        await viewModel.loadData()
        let action = viewModel.quickActions[0]

        // When
        await viewModel.recordQuickActionUsage(action)
        let afterFirst = viewModel.quickActions.first(where: { $0.id == action.id })!
        await viewModel.recordQuickActionUsage(afterFirst)

        // Then
        let updatedAction = viewModel.quickActions.first(where: { $0.id == action.id })
        XCTAssertEqual(updatedAction?.usageCount, 2)
    }

    // MARK: - confirmDeleteQuickAction / cancelDelete Tests

    func testConfirmDeleteQuickAction() async {
        // Given
        await viewModel.loadData()
        let action = viewModel.quickActions[0]

        // When
        viewModel.confirmDeleteQuickAction(action)

        // Then
        XCTAssertTrue(viewModel.showingDeleteAlert)
        XCTAssertEqual(viewModel.quickActionToDelete?.id, action.id)
    }

    func testCancelDelete() async {
        // Given
        await viewModel.loadData()
        let action = viewModel.quickActions[0]
        viewModel.confirmDeleteQuickAction(action)
        XCTAssertTrue(viewModel.showingDeleteAlert)

        // When
        viewModel.cancelDelete()

        // Then
        XCTAssertFalse(viewModel.showingDeleteAlert)
        XCTAssertNil(viewModel.quickActionToDelete)
    }

    // MARK: - getAvailableQuickActions Tests

    func testGetAvailableQuickActionsReturnsOnlyEnabled() async {
        // Given
        await viewModel.loadData()
        // Disable first action
        let action = viewModel.quickActions[0]
        await viewModel.toggleQuickActionEnabled(action)

        // When
        let available = viewModel.getAvailableQuickActions()

        // Then
        XCTAssertFalse(available.contains(where: { $0.id == action.id }))
        for a in available {
            XCTAssertTrue(a.isEnabled)
        }
    }

    func testGetAvailableQuickActionsSortedBySortOrder() async {
        // Given
        await viewModel.loadData()

        // When
        let available = viewModel.getAvailableQuickActions()

        // Then - Should be sorted by sortOrder ascending
        for i in 0..<(available.count - 1) {
            XCTAssertLessThanOrEqual(available[i].sortOrder, available[i + 1].sortOrder)
        }
    }

    // MARK: - getHomePageQuickActions Tests

    func testGetHomePageQuickActionsReturnsTop3ByUsage() async {
        // Given - Create 4 actions with different usage counts
        await mockDataService.reset()
        await viewModel.loadData()

        var a1 = createQuickAction(name: "Low Usage")
        var a2 = createQuickAction(name: "Medium Usage")
        var a3 = createQuickAction(name: "High Usage")
        var a4 = createQuickAction(name: "Highest Usage")

        await viewModel.saveQuickAction(a1)
        await viewModel.saveQuickAction(a2)
        await viewModel.saveQuickAction(a3)
        await viewModel.saveQuickAction(a4)

        // Record different usage counts
        a1 = viewModel.quickActions.first(where: { $0.name == "Low Usage" })!
        a2 = viewModel.quickActions.first(where: { $0.name == "Medium Usage" })!
        a3 = viewModel.quickActions.first(where: { $0.name == "High Usage" })!
        a4 = viewModel.quickActions.first(where: { $0.name == "Highest Usage" })!

        // Record usage: a4=3, a3=2, a2=1, a1=0
        await viewModel.recordQuickActionUsage(a4)
        let a4Updated1 = viewModel.quickActions.first(where: { $0.name == "Highest Usage" })!
        await viewModel.recordQuickActionUsage(a4Updated1)
        let a4Updated2 = viewModel.quickActions.first(where: { $0.name == "Highest Usage" })!
        await viewModel.recordQuickActionUsage(a4Updated2)

        await viewModel.recordQuickActionUsage(a3)
        let a3Updated1 = viewModel.quickActions.first(where: { $0.name == "High Usage" })!
        await viewModel.recordQuickActionUsage(a3Updated1)

        await viewModel.recordQuickActionUsage(a2)

        // When
        let homeActions = viewModel.getHomePageQuickActions()

        // Then - Should return top 3 by usage (Highest, High, Medium)
        XCTAssertEqual(homeActions.count, 3)
        XCTAssertEqual(homeActions[0].name, "Highest Usage")
        XCTAssertEqual(homeActions[1].name, "High Usage")
        XCTAssertEqual(homeActions[2].name, "Medium Usage")
    }

    func testGetHomePageQuickActionsExcludesDisabled() async {
        // Given
        await viewModel.loadData()
        // Disable the first action
        let action = viewModel.quickActions[0]
        await viewModel.toggleQuickActionEnabled(action)

        // When
        let homeActions = viewModel.getHomePageQuickActions()

        // Then
        XCTAssertFalse(homeActions.contains(where: { $0.id == action.id }))
    }

    func testGetHomePageQuickActionsFewerThan3() async {
        // Given - Only 1 action
        await mockDataService.reset()
        await viewModel.loadData()

        let action = createQuickAction(name: "Only One")
        await viewModel.saveQuickAction(action)

        // When
        let homeActions = viewModel.getHomePageQuickActions()

        // Then
        XCTAssertEqual(homeActions.count, 1)
    }

    // MARK: - Error Handling Tests

    func testLoadDataErrorSetsErrorMessage() async {
        // Given
        mockDataService.shouldThrowLoadError = true

        // When
        await viewModel.loadData()

        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testSaveQuickActionErrorSetsErrorMessage() async {
        // Given
        await mockDataService.reset()
        await viewModel.loadData()
        mockDataService.shouldThrowSaveError = true

        let action = createQuickAction(name: "Will Fail")

        // When
        await viewModel.saveQuickAction(action)

        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testDeleteQuickActionErrorSetsErrorMessage() async {
        // Given
        await viewModel.loadData()
        let action = viewModel.quickActions[0]
        mockDataService.shouldThrowSaveError = true

        // When
        await viewModel.deleteQuickAction(action)

        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testClearError() async {
        // Given
        mockDataService.shouldThrowLoadError = true
        await viewModel.loadData()
        XCTAssertNotNil(viewModel.errorMessage)

        // When
        viewModel.clearError()

        // Then
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Statistics Tests

    func testTotalUsageCount() async {
        // Given
        await viewModel.loadData()
        let action = viewModel.quickActions[0]
        await viewModel.recordQuickActionUsage(action)

        // When
        let total = viewModel.totalUsageCount

        // Then
        XCTAssertEqual(total, 1)
    }

    func testMostUsedQuickAction() async {
        // Given
        await viewModel.loadData()
        let action = viewModel.quickActions[0]
        await viewModel.recordQuickActionUsage(action)
        let updatedAction = viewModel.quickActions.first(where: { $0.id == action.id })!
        await viewModel.recordQuickActionUsage(updatedAction)

        // When
        let mostUsed = viewModel.mostUsedQuickAction

        // Then
        XCTAssertNotNil(mostUsed)
        XCTAssertEqual(mostUsed?.id, action.id)
        XCTAssertEqual(mostUsed?.usageCount, 2)
    }
}
