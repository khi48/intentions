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
        XCTAssertEqual(settings.activeHours, 6...22)
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
        XCTAssertFalse(settings.isCurrentlyActive) // Disabled schedule is not active
    }
    
    func testIsCurrentlyActiveWithFullFreeTime() {
        // Given - free all day, every day
        let settings = ScheduleSettings()
        settings.isEnabled = true
        settings.activeHours = 0...23 // Free all hours
        settings.activeDays = Set(Weekday.allCases) // All days

        // When & Then - should NOT be blocking (in free time)
        XCTAssertFalse(settings.isCurrentlyActive)
    }

    func testIsActiveAtSpecificDate() {
        // Given - free from 9 AM to 5 PM on weekdays
        let settings = ScheduleSettings()
        settings.isEnabled = true
        settings.activeHours = 9...17
        settings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]

        // Monday at 10 AM → in free window → blocking NOT active
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1 // Monday
        components.hour = 10
        components.minute = 0
        let calendar = Calendar.current
        let mondayAt10AM = calendar.date(from: components)!
        XCTAssertFalse(settings.isActive(at: mondayAt10AM))

        // Monday at 6 AM → outside free window → blocking active
        components.hour = 6
        let mondayAt6AM = calendar.date(from: components)!
        XCTAssertTrue(settings.isActive(at: mondayAt6AM))

        // Sunday at 10 AM → no free window on Sunday → blocking active
        components.day = 7 // Sunday
        components.hour = 10
        let sundayAt10AM = calendar.date(from: components)!
        XCTAssertTrue(settings.isActive(at: sundayAt10AM))
    }

    func testBlockingActiveOutsideFreeWindow() {
        // Given - free from 12 PM to 1 PM on weekdays
        let settings = ScheduleSettings()
        settings.isEnabled = true
        settings.activeHours = 12...13
        settings.activeDays = [.monday, .tuesday, .wednesday, .thursday, .friday]

        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1 // Monday
        let calendar = Calendar.current

        // Monday at noon → in free window → not blocking
        components.hour = 12
        XCTAssertFalse(settings.isActive(at: calendar.date(from: components)!))

        // Monday at 1 PM → outside free window (endHour is exclusive) → blocking
        components.hour = 13
        XCTAssertTrue(settings.isActive(at: calendar.date(from: components)!))

        // Monday at 8 AM → outside free window → blocking
        components.hour = 8
        XCTAssertTrue(settings.isActive(at: calendar.date(from: components)!))
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
        
        // When & Then — free from midnight to 2 AM, so 1 AM is in free time → NOT blocking
        XCTAssertFalse(settings.isActive(at: dateAt1AM))

        // Test hour 23 (11 PM) — free from 23 to 23 is invalid (startHour == endHour)
        // Use 22...23 instead
        settings.activeHours = 22...23
        components.hour = 22
        let dateAt10PM = calendar.date(from: components)!
        XCTAssertFalse(settings.isActive(at: dateAt10PM))
    }
    
    func testEmptyActiveDays() {
        // Given — no free time days = always blocking
        let settings = ScheduleSettings()
        settings.activeDays = []

        // When & Then — blocking should be active (no free days)
        XCTAssertTrue(settings.isCurrentlyActive)
        
        // No free days → always blocking
        let now = Date()
        XCTAssertTrue(settings.isActive(at: now))
    }
    
    func testSingleFreeDay() {
        // Given — only Friday has free time
        let settings = ScheduleSettings()
        settings.activeDays = [.friday]

        // Create a Friday date at noon (within default free window 6-22)
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 5 // Friday
        components.hour = 12
        let calendar = Calendar.current
        let friday = calendar.date(from: components)!

        // Friday at noon → in free window → blocking NOT active
        XCTAssertFalse(settings.isActive(at: friday))

        // Saturday → no free time → blocking active
        components.day = 6 // Saturday
        let saturday = calendar.date(from: components)!
        XCTAssertTrue(settings.isActive(at: saturday))
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

    // MARK: - Streak Tests

    func testStreakDaysWhenNeverDisabled() {
        let settings = ScheduleSettings()
        settings.lastDisabledAt = nil
        XCTAssertNil(settings.streakDays)
    }

    func testStreakDaysWhenDisabledToday() {
        let settings = ScheduleSettings()
        settings.lastDisabledAt = Date()
        XCTAssertEqual(settings.streakDays, 0)
    }

    func testStreakDaysWhenDisabledDaysAgo() {
        let settings = ScheduleSettings()
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        settings.lastDisabledAt = threeDaysAgo
        XCTAssertEqual(settings.streakDays, 3)
    }

    // MARK: - Time Stats Tests

    func testProtectedMinutesTodayBeforeSchedule() {
        let settings = ScheduleSettings()
        settings.activeHours = 22...23 // Late night schedule

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())

        if hour < 22 {
            XCTAssertEqual(settings.protectedMinutesToday, 0)
        }
    }

    func testRemainingProtectedMinutesAfterSchedule() {
        let settings = ScheduleSettings()
        settings.activeHours = 0...1 // Early morning schedule

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())

        if hour >= 1 {
            XCTAssertEqual(settings.remainingProtectedMinutesToday, 0)
        }
    }

    // MARK: - Codable Tests for New Fields

    func testCodableWithNewFields() throws {
        let settings = ScheduleSettings()
        settings.lastDisabledAt = Date(timeIntervalSince1970: 1700000000)
        settings.intentionQuote = "Be more present"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ScheduleSettings.self, from: data)

        XCTAssertEqual(decoded.lastDisabledAt, settings.lastDisabledAt)
        XCTAssertEqual(decoded.intentionQuote, "Be more present")
    }

    func testCodableBackwardsCompatibility() throws {
        let settings = ScheduleSettings()
        settings.lastDisabledAt = nil
        settings.intentionQuote = nil

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ScheduleSettings.self, from: data)

        XCTAssertNil(decoded.lastDisabledAt)
        XCTAssertNil(decoded.intentionQuote)
    }
}