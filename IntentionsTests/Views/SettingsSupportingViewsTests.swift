//
//  SettingsSupportingViewsTests.swift
//  IntentionsTests
//
//  Created by Claude on 13/07/2025.
//

import XCTest
import SwiftUI
@testable import Intentions

// MARK: - Supporting View Component Tests

final class ScheduleDetailsRowTests: XCTestCase {
    
    @MainActor
    func testInitialization() {
        let row = ScheduleDetailsRow(
            title: "Test Title",
            value: "Test Value",
            action: { }
        )
        
        XCTAssertNotNil(row)
    }
}

final class StatisticRowTests: XCTestCase {
    
    @MainActor
    func testInitialization() {
        let row = StatisticRow(
            title: "Test Statistic",
            value: "42",
            icon: "chart.bar.fill"
        )
        
        XCTAssertNotNil(row)
    }
}

final class SettingsRowTests: XCTestCase {
    
    @MainActor
    func testInitialization() {
        let row = SettingsRow(
            title: "Test Setting",
            subtitle: "Test Description",
            icon: "gear"
        )
        
        XCTAssertNotNil(row)
    }
}

final class AppGroupRowTests: XCTestCase {
    
    @MainActor
    func testInitialization() {
        let testGroup = createTestAppGroup()
        
        let row = AppGroupRow(
            group: testGroup,
            onEdit: { },
            onDelete: { }
        )
        
        XCTAssertNotNil(row)
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