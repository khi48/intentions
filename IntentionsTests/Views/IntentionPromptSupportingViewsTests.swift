//
//  IntentionPromptSupportingViewsTests.swift
//  IntentionsTests
//
//  Created by Claude on 13/07/2025.
//

import XCTest
import SwiftUI
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@testable import Intentions

// MARK: - IntentionPrompt Supporting Component Tests

final class IntentionPromptViewTests: XCTestCase {
    
    var mockDataService: MockDataPersistenceService!
    var sessionStartCalled = false
    var cancelCalled = false
    
    override func setUp() async throws {
        mockDataService = MockDataPersistenceService()
        sessionStartCalled = false
        cancelCalled = false
    }
    
    override func tearDown() {
        mockDataService = nil
    }
    
    @MainActor
    func testIntentionPromptViewInitialization() {
        let view = IntentionPromptView(
            dataService: mockDataService,
            onSessionStart: { _ in
                self.sessionStartCalled = true
            },
            onCancel: {
                self.cancelCalled = true
            }
        )
        
        XCTAssertNotNil(view)
    }
    
    @MainActor
    func testIntentionPromptViewWithMockData() {
        // Setup mock data
        let testGroup = createTestAppGroup()
        mockDataService.mockAppGroups = [testGroup]
        
        let view = IntentionPromptView(
            dataService: mockDataService,
            onSessionStart: { _ in
                self.sessionStartCalled = true
            },
            onCancel: {
                self.cancelCalled = true
            }
        )
        
        XCTAssertNotNil(view)
    }
    
    @MainActor
    private func createTestAppGroup() -> AppGroup {
        do {
            return try AppGroup(
                id: UUID(),
                name: "Test Work Apps",
                createdAt: Date(),
                lastModified: Date()
            )
        } catch {
            fatalError("Failed to create test app group: \(error)")
        }
    }
}

final class DurationPresetButtonTests: XCTestCase {
    
    @MainActor
    func testInitialization() {
        let button = DurationPresetButton(
            duration: 30 * 60, // 30 minutes
            isSelected: false,
            action: { }
        )
        
        XCTAssertNotNil(button)
    }
    
    @MainActor
    func testSelectedState() {
        let button = DurationPresetButton(
            duration: 60 * 60, // 1 hour
            isSelected: true,
            action: { }
        )
        
        XCTAssertNotNil(button)
    }
}

final class AppGroupSelectionCardTests: XCTestCase {
    
    @MainActor
    func testInitialization() {
        let testGroup = createTestAppGroup()
        
        let card = AppGroupSelectionCard(
            group: testGroup,
            isSelected: false,
            action: { }
        )
    
        XCTAssertNotNil(card)
    }
    
    @MainActor
    func testSelectedState() {
        let testGroup = createTestAppGroup()
        
        let card = AppGroupSelectionCard(
            group: testGroup,
            isSelected: true,
            action: { }
        )
        
        XCTAssertNotNil(card)
    }
    
    @MainActor
    private func createTestAppGroup() -> AppGroup {
        do {
            return try AppGroup(
                id: UUID(),
                name: "Test Group",
                createdAt: Date(),
                lastModified: Date()
            )
        } catch {
            fatalError("Failed to create test app group: \(error)")
        }
    }
}

final class AppSelectionCardTests: XCTestCase {
    
    private func createTestToken() throws -> ApplicationToken {
        let tokenData = """
        {
            "data": "dGVzdERhdGE="
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        return try decoder.decode(ApplicationToken.self, from: tokenData)
    }
    
    @MainActor
    func testInitialization() throws {
        let testApp = try createTestDiscoveredApp()
        
        let card = AppSelectionCard(
            app: testApp,
            isSelected: false,
            action: { }
        )
        
        XCTAssertNotNil(card)
    }
    
    @MainActor
    func testSelectedState() throws {
        let testApp = try createTestDiscoveredApp()
        
        let card = AppSelectionCard(
            app: testApp,
            isSelected: true,
            action: { }
        )
        
        XCTAssertNotNil(card)
    }
    
    @MainActor
    private func createTestDiscoveredApp() throws -> DiscoveredApp {
        let token = try createTestToken()
        
        return DiscoveredApp(
            displayName: "Test App",
            bundleIdentifier: "com.test.app",
            token: token,
            category: "Productivity"
        )
    }
}

final class CustomDurationPickerTests: XCTestCase {
    
    func testInitialization() {
        @State var duration: TimeInterval = 30 * 60
        
        let picker = CustomDurationPicker(selectedDuration: $duration)
        
        XCTAssertNotNil(picker)
    }
}

final class AppSelectionSheetTests: XCTestCase {
    
    @MainActor
    func testInitialization() {
        let mockDataService = MockDataPersistenceService()
        let viewModel = IntentionPromptViewModel(
            dataService: mockDataService,
            onSessionStart: { _ in },
            onCancel: { }
        )
        
        let sheet = AppSelectionSheet(viewModel: viewModel)
        
        XCTAssertNotNil(sheet)
    }
}

final class AppSelectionRowTests: XCTestCase {
    
    private func createTestToken() throws -> ApplicationToken {
        let tokenData = """
        {
            "data": "dGVzdERhdGE="
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        return try decoder.decode(ApplicationToken.self, from: tokenData)
    }
    
    @MainActor
    func testInitialization() throws {
        let testApp = try createTestDiscoveredApp()
        
        let row = AppSelectionRow(
            app: testApp,
            isSelected: false,
            action: { }
        )
        
        XCTAssertNotNil(row)
    }
    
    @MainActor
    func testSelectedState() throws {
        let testApp = try createTestDiscoveredApp()
        
        let row = AppSelectionRow(
            app: testApp,
            isSelected: true,
            action: { }
        )
        
        XCTAssertNotNil(row)
    }
    
    @MainActor
    private func createTestDiscoveredApp() throws -> DiscoveredApp {
        let token = try createTestToken()
        
        return DiscoveredApp(
            displayName: "Test App",
            bundleIdentifier: "com.test.app",
            token: token,
            category: "Social Networking"
        )
    }
}