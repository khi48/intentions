//
//  AppGroupsViewModelTests.swift
//  IntentionsTests
//
//  Created by Claude on 13/07/2025.
//

import XCTest
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

@MainActor
final class AppGroupsViewModelTests: XCTestCase {
    
    var viewModel: AppGroupsViewModel!
    var mockDataService: MockDataPersistenceService!
    
    override func setUp() async throws {
        mockDataService = MockDataPersistenceService()
        viewModel = AppGroupsViewModel(dataService: mockDataService)
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
        XCTAssertTrue(viewModel.discoveredApps.isEmpty)
        XCTAssertFalse(viewModel.showSystemApps)
        XCTAssertFalse(viewModel.showingGroupEditor)
        XCTAssertFalse(viewModel.showingDeleteAlert)
    }
    
    // MARK: - Data Loading Tests
    
    func testLoadData() async {
        // Given
        let testGroup = createTestAppGroup()
        mockDataService.mockAppGroups = [testGroup]
        
        // When
        await viewModel.loadData()
        
        // Then
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.appGroups.count, 1)
        XCTAssertEqual(viewModel.appGroups.first?.name, testGroup.name)
        XCTAssertFalse(viewModel.discoveredApps.isEmpty) // Mock apps generated
        XCTAssertFalse(viewModel.searchResults.isEmpty)
    }
    
    func testLoadDataError() async {
        // Given
        mockDataService.shouldThrowLoadError = true
        
        // When
        await viewModel.loadData()
        
        // Then
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
    }
    
    // MARK: - App Group Management Tests
    
    func testCreateAppGroup() async {
        // Given
        let groupName = "Test Work Apps"
        let tokens = Set<ApplicationToken>()
        
        // When
        await viewModel.createAppGroup(name: groupName, applicationTokens: tokens)
        
        // Then
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.appGroups.count, 1)
        XCTAssertEqual(viewModel.appGroups.first?.name, groupName)
        XCTAssertFalse(viewModel.showingGroupEditor)
    }
    
    func testCreateAppGroupEmptyName() async {
        // Given
        let emptyName = "   "
        let tokens = Set<ApplicationToken>()
        
        // When
        await viewModel.createAppGroup(name: emptyName, applicationTokens: tokens)
        
        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
        XCTAssertTrue(viewModel.errorMessage?.contains("empty") == true)
    }
    
    func testCreateAppGroupError() async {
        // Given
        mockDataService.shouldThrowSaveError = true
        let groupName = "Test Group"
        let tokens = Set<ApplicationToken>()
        
        // When
        await viewModel.createAppGroup(name: groupName, applicationTokens: tokens)
        
        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
    }
    
    func testUpdateAppGroup() async {
        // Given
        let testGroup = createTestAppGroup()
        try! await mockDataService.saveAppGroup(testGroup)
        await viewModel.loadData()
        let newName = "Updated Group Name"
        let tokens = Set<ApplicationToken>()
        
        // When
        await viewModel.updateAppGroup(id: testGroup.id, name: newName, applicationTokens: tokens)
        
        // Then
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.appGroups.count, 1)
        XCTAssertEqual(viewModel.appGroups.first?.name, newName)
        XCTAssertFalse(viewModel.showingGroupEditor)
    }
    
    func testUpdateAppGroupNotFound() async {
        // Given
        let nonExistentId = UUID()
        let tokens = Set<ApplicationToken>()
        
        // When
        await viewModel.updateAppGroup(id: nonExistentId, name: "Test", applicationTokens: tokens)
        
        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("not found") == true)
    }
    
    func testDeleteAppGroup() async {
        // Given
        let testGroup = createTestAppGroup()
        try! await mockDataService.saveAppGroup(testGroup)
        await viewModel.loadData()
        
        // When
        await viewModel.deleteAppGroup(testGroup)
        
        // Then
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.appGroups.isEmpty)
        XCTAssertFalse(viewModel.showingDeleteAlert)
    }
    
    func testDeleteAppGroupError() async {
        // Given
        let testGroup = createTestAppGroup()
        try! await mockDataService.saveAppGroup(testGroup)
        await viewModel.loadData()
        mockDataService.shouldThrowDeleteError = true
        
        // When
        await viewModel.deleteAppGroup(testGroup)
        
        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.appGroups.count, 1) // Should still be there
    }
    
    // MARK: - UI Actions Tests
    
    func testShowCreateGroupEditor() {
        // When
        viewModel.showCreateGroupEditor()
        
        // Then
        XCTAssertTrue(viewModel.showingGroupEditor)
        XCTAssertNil(viewModel.editingGroup)
    }
    
    func testShowEditGroupEditor() {
        // Given
        let testGroup = createTestAppGroup()
        
        // When
        viewModel.showEditGroupEditor(for: testGroup)
        
        // Then
        XCTAssertTrue(viewModel.showingGroupEditor)
        XCTAssertEqual(viewModel.editingGroup?.id, testGroup.id)
    }
    
    func testConfirmDeleteGroup() {
        // Given
        let testGroup = createTestAppGroup()
        
        // When
        viewModel.confirmDeleteGroup(testGroup)
        
        // Then
        XCTAssertTrue(viewModel.showingDeleteAlert)
        XCTAssertEqual(viewModel.groupToDelete?.id, testGroup.id)
    }
    
    func testCancelDelete() {
        // Given
        let testGroup = createTestAppGroup()
        viewModel.confirmDeleteGroup(testGroup)
        
        // When
        viewModel.cancelDelete()
        
        // Then
        XCTAssertFalse(viewModel.showingDeleteAlert)
        XCTAssertNil(viewModel.groupToDelete)
    }
    
    func testCancelGroupEditor() {
        // Given
        viewModel.showCreateGroupEditor()
        
        // When
        viewModel.cancelGroupEditor()
        
        // Then
        XCTAssertFalse(viewModel.showingGroupEditor)
        XCTAssertNil(viewModel.editingGroup)
    }
    
    // MARK: - Search and Filtering Tests
    
    func testSearchFiltering() async {
        // Given
        await viewModel.loadData() // Loads mock apps
        
        // When
        viewModel.searchText = "Safari"
        
        // Then
        XCTAssertTrue(viewModel.searchResults.contains { $0.displayName.contains("Safari") })
        XCTAssertFalse(viewModel.searchResults.contains { $0.displayName == "Messages" })
    }
    
    func testShowSystemAppsFiltering() async {
        // Given
        await viewModel.loadData()
        let initialCount = viewModel.filteredDiscoveredApps.count
        
        // When
        viewModel.showSystemApps = true
        
        // Then
        XCTAssertGreaterThanOrEqual(viewModel.filteredDiscoveredApps.count, initialCount)
    }
    
    func testEmptySearchReturnsAll() async {
        // Given
        await viewModel.loadData()
        viewModel.searchText = "NonExistentApp"
        
        // When
        viewModel.searchText = ""
        
        // Then
        XCTAssertEqual(viewModel.searchResults.count, viewModel.filteredDiscoveredApps.count)
    }
    
    // MARK: - Statistics Tests
    
    func testStatistics() async {
        // Given
        let group1 = createTestAppGroup(name: "Group 1", appCount: 3)
        let group2 = createTestAppGroup(name: "Group 2", appCount: 5)
        try! await mockDataService.saveAppGroup(group1)
        try! await mockDataService.saveAppGroup(group2)
        await viewModel.loadData()
        
        // Then
        XCTAssertEqual(viewModel.totalAppGroups, 2)
        XCTAssertEqual(viewModel.totalManagedApps, 8) // Unique apps across groups
    }
    
    func testRecentlyModifiedGroup() async {
        // Given
        let olderGroup = createTestAppGroup(name: "Older")
        let newerGroup = createTestAppGroup(name: "Newer")
        // Simulate newer group being modified later
        let modifiedNewerGroup = try! AppGroup(
            id: newerGroup.id,
            name: newerGroup.name,
            applications: newerGroup.applications,
            createdAt: newerGroup.createdAt,
            lastModified: Date().addingTimeInterval(100)
        )
        try! await mockDataService.saveAppGroup(olderGroup)
        try! await mockDataService.saveAppGroup(modifiedNewerGroup)
        await viewModel.loadData()
        
        // Then
        XCTAssertEqual(viewModel.recentlyModifiedGroup?.name, "Newer")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() async {
        // Given
        let testError = AppError.sessionNotFound
        
        // When
        await viewModel.handleError(testError)
        
        // Then
        XCTAssertEqual(viewModel.errorMessage, testError.localizedDescription)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testClearError() async {
        // Given
        await viewModel.handleError(AppError.sessionNotFound)
        XCTAssertNotNil(viewModel.errorMessage)
        
        // When
        viewModel.clearError()
        
        // Then
        XCTAssertNil(viewModel.errorMessage)
    }
    
    // MARK: - Helper Methods
    
    private func createTestAppGroup(name: String = "Test Group", appCount: Int = 2) -> AppGroup {
        let tokens = Set((0..<appCount).map { index in
            try! createMockApplicationToken(uniqueId: "\(name)-\(index)")
        })
        
        return try! AppGroup(
            id: UUID(),
            name: name,
            applications: tokens,
            createdAt: Date(),
            lastModified: Date()
        )
    }
    
    private func createMockApplicationToken(uniqueId: String = "testData") throws -> ApplicationToken {
        let tokenData = """
        {
            "data": "\(uniqueId.data(using: .utf8)?.base64EncodedString() ?? "dGVzdERhdGE=")"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        return try decoder.decode(ApplicationToken.self, from: tokenData)
    }
}