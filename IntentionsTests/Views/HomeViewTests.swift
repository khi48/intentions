//
//  HomeViewTests.swift
//  IntentionsTests
//
//  Created by Claude on 13/07/2025.
//

import XCTest
import SwiftUI
@testable import Intentions

final class HomeViewTests: XCTestCase {
    
    private var viewModel: ContentViewModel!
    private var mockScreenTimeService: MockScreenTimeService!
    private var mockDataService: MockDataPersistenceService!
    
    override func setUp() {
        super.setUp()
        mockScreenTimeService = MockScreenTimeService()
        mockDataService = MockDataPersistenceService()
        
        // We'll initialize the viewModel in each test method that needs it
        // since ContentViewModel's init is @MainActor
    }
    
    override func tearDown() {
        viewModel = nil
        mockScreenTimeService = nil
        mockDataService = nil
        super.tearDown()
    }
    
    @MainActor
    private func createViewModel() {
        viewModel = ContentViewModel(
            screenTimeService: mockScreenTimeService,
            dataService: mockDataService
        )
    }
    
    @MainActor
    func testHomeViewCreation() {
        // Given
        createViewModel()
        
        // When
        let homeView = HomeView(viewModel: viewModel)
        
        // Then
        XCTAssertNotNil(homeView)
    }
    
    @MainActor
    func testHomeViewWithActiveSession() async {
        // Given
        createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.initializeApp()
        
        let testSession = try! IntentionSession(duration: 1800)
        await viewModel.startSession(testSession)
        
        // When
        let homeView = HomeView(viewModel: viewModel)
        
        // Then
        XCTAssertNotNil(homeView)
        XCTAssertNotNil(viewModel.activeSession)
    }
    
    @MainActor
    func testHomeViewWithoutActiveSession() async {
        // Given
        createViewModel()
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await viewModel.initializeApp()
        
        // When
        let homeView = HomeView(viewModel: viewModel)
        
        // Then
        XCTAssertNotNil(homeView)
        XCTAssertNil(viewModel.activeSession)
    }
}

// MARK: - AppTab Integration Tests

final class AppTabIntegrationTests: XCTestCase {
    
    func testAppTabNavigation() {
        // Test that all navigation tabs are properly configured
        let tabs = AppTab.allCases
        
        for tab in tabs {
            // Verify each tab has required properties
            XCTAssertFalse(tab.rawValue.isEmpty, "Tab \(tab) should have non-empty raw value")
            XCTAssertFalse(tab.systemImage.isEmpty, "Tab \(tab) should have non-empty system image")
            XCTAssertFalse(tab.id.isEmpty, "Tab \(tab) should have non-empty ID")
        }
    }
    
    func testAppTabUniqueness() {
        // Test that all tabs have unique identifiers
        let tabs = AppTab.allCases
        let rawValues = tabs.map { $0.rawValue }
        let uniqueRawValues = Set(rawValues)
        
        XCTAssertEqual(rawValues.count, uniqueRawValues.count, "All tab raw values should be unique")
        
        let systemImages = tabs.map { $0.systemImage }
        let uniqueSystemImages = Set(systemImages)
        
        XCTAssertEqual(systemImages.count, uniqueSystemImages.count, "All tab system images should be unique")
    }
}