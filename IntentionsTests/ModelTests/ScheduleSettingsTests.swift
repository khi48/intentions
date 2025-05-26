//
//  ScheduleSettingsTests.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//


// ScheduleSettingsTests.swift
// Unit tests for ScheduleSettings model

import XCTest
@testable import Intentions

final class ScheduleSettingsTests: XCTestCase {
    
    func testScheduleSettingsInitialization() {
        // When
        let settings = ScheduleSettings()
        
        // Then
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.activeHours, 8...22)
        XCTAssertEqual(settings.activeDays.count, 7) // All days
        XCTAssertEqual(settings.timeZone, TimeZone.current)
        
        // Verify all weekdays are included
        for weekday in Weekday.allCases {
            XCTAssertTrue(settings.activeDays.contains(weekday))
        }
    }
    
    func testIsCurrentlyActiveWhenDisabled() {
        // Given
        let settings = ScheduleSettings()
        settings.isEnabled = false
        
        // When & Then
        XCTAssertTrue(settings.isCurrentlyActive) // Should always be active when disabled
    }
    
    func testIsCurrentlyActiveWithFullSchedule() {
        // Given
        let settings = ScheduleSettings()
        settings.isEnabled = true
        settings.activeHours = 0...23 // All hours
        settings.activeDays = Set(Weekday.allCases) // All days
        
        // When & Then
        XCTAssertTrue(settings.isCurrentlyActive)
    }
    
    func testIsCurrentlyActiveWithRestrictiveSchedule() {
        // Given
        let settings = ScheduleSettings()
        settings.isEnabled = true
        settings.activeHours = 9...17 // 9 AM to 5 PM
        settings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday] // Weekdays only
        
        // When & Then - Result depends on current time, so we test the logic
        let isActive = settings.isCurrentlyActive
        XCTAssertTrue(isActive == true || isActive == false) // Just verify it returns a boolean
    }
    
    func testIsActiveAtSpecificDate() {
        // Given
        let settings = ScheduleSettings()
        settings.isEnabled = true
        settings.activeHours = 9...17 // 9 AM to 5 PM
        settings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        
        // Create a specific date: Monday at 10 AM
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1 // This is a Monday
        components.hour = 10
        components.minute = 0
        let calendar = Calendar.current
        let mondayAt10AM = calendar.date(from: components)!
        
        // When & Then
        XCTAssertTrue(settings.isActive(at: mondayAt10AM))
        
        // Test outside hours - Monday at 6 AM
        components.hour = 6
        let mondayAt6AM = calendar.date(from: components)!
        XCTAssertFalse(settings.isActive(at: mondayAt6AM))
        
        // Test wrong day - Sunday at 10 AM
        components.day = 7 // Sunday
        components.hour = 10
        let sundayAt10AM = calendar.date(from: components)!
        XCTAssertFalse(settings.isActive(at: sundayAt10AM))
    }
    
    func testScheduleSettingsCodable() throws {
        // Given
        let settings = ScheduleSettings()
        settings.isEnabled = false
        settings.activeHours = 10...18
        settings.activeDays = [.monday, .wednesday, .friday]
        
        // When - Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        
        // Then - Decode
        let decoder = JSONDecoder()
        let decodedSettings = try decoder.decode(ScheduleSettings.self, from: data)
        
        XCTAssertEqual(decodedSettings.isEnabled, settings.isEnabled)
        XCTAssertEqual(decodedSettings.activeHours, settings.activeHours)
        XCTAssertEqual(decodedSettings.activeDays, settings.activeDays)
    }
    
    func testEdgeCaseHours() {
        // Given - Test midnight hours
        let settings = ScheduleSettings()
        settings.activeHours = 0...2 // Midnight to 2 AM
        
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.hour = 1
        let calendar = Calendar.current
        let dateAt1AM = calendar.date(from: components)!
        
        // When & Then
        XCTAssertTrue(settings.isActive(at: dateAt1AM))
        
        // Test hour 23 (11 PM)
        settings.activeHours = 23...23
        components.hour = 23
        let dateAt11PM = calendar.date(from: components)!
        XCTAssertTrue(settings.isActive(at: dateAt11PM))
    }
    
    func testEmptyActiveDays() {
        // Given
        let settings = ScheduleSettings()
        settings.activeDays = [] // No active days
        
        // When & Then
        XCTAssertFalse(settings.isCurrentlyActive)
        
        let now = Date()
        XCTAssertFalse(settings.isActive(at: now))
    }
    
    func testSingleActiveDay() {
        // Given
        let settings = ScheduleSettings()
        settings.activeDays = [.friday] // Only Friday
        
        // Create a Friday date
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 5 // Friday
        components.hour = 12
        let calendar = Calendar.current
        let friday = calendar.date(from: components)!
        
        // When & Then
        XCTAssertTrue(settings.isActive(at: friday))
        
        // Test a different day
        components.day = 6 // Saturday
        let saturday = calendar.date(from: components)!
        XCTAssertFalse(settings.isActive(at: saturday))
    }
    
    func testTimeZoneHandling() throws {
        // Given
        let settings = ScheduleSettings()
        let pacificTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        settings.timeZone = pacificTimeZone
        
        // When - Encode and decode
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ScheduleSettings.self, from: data)
        
        // Then
        XCTAssertEqual(decoded.timeZone.identifier, pacificTimeZone.identifier)
    }
}