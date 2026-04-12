//
//  NotificationSettingsTests.swift
//  IntentionsTests
//
//  Created by Claude on 12/04/2026.
//

import XCTest
@testable import Intentions

final class NotificationSettingsTests: XCTestCase {

    // MARK: - Default Initialization Tests

    func testDefaultInitialization() {
        let settings = NotificationSettings()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.sessionWarningsEnabled)
        XCTAssertTrue(settings.sessionCompletionEnabled)
        XCTAssertEqual(settings.warningIntervals, [1])
    }

    // MARK: - hasAnyNotificationsEnabled Tests

    func testHasAnyNotificationsEnabledAllOn() {
        var settings = NotificationSettings()
        settings.isEnabled = true
        settings.sessionWarningsEnabled = true
        settings.sessionCompletionEnabled = true

        XCTAssertTrue(settings.hasAnyNotificationsEnabled)
    }

    func testHasAnyNotificationsEnabledMasterOff() {
        var settings = NotificationSettings()
        settings.isEnabled = false
        settings.sessionWarningsEnabled = true
        settings.sessionCompletionEnabled = true

        XCTAssertFalse(settings.hasAnyNotificationsEnabled)
    }

    func testHasAnyNotificationsEnabledOnlyWarnings() {
        var settings = NotificationSettings()
        settings.isEnabled = true
        settings.sessionWarningsEnabled = true
        settings.sessionCompletionEnabled = false

        XCTAssertTrue(settings.hasAnyNotificationsEnabled)
    }

    func testHasAnyNotificationsEnabledOnlyCompletion() {
        var settings = NotificationSettings()
        settings.isEnabled = true
        settings.sessionWarningsEnabled = false
        settings.sessionCompletionEnabled = true

        XCTAssertTrue(settings.hasAnyNotificationsEnabled)
    }

    func testHasAnyNotificationsEnabledSubSettingsOff() {
        var settings = NotificationSettings()
        settings.isEnabled = true
        settings.sessionWarningsEnabled = false
        settings.sessionCompletionEnabled = false

        XCTAssertFalse(settings.hasAnyNotificationsEnabled)
    }

    func testHasAnyNotificationsEnabledAllOff() {
        var settings = NotificationSettings()
        settings.isEnabled = false
        settings.sessionWarningsEnabled = false
        settings.sessionCompletionEnabled = false

        XCTAssertFalse(settings.hasAnyNotificationsEnabled)
    }

    // MARK: - sortedWarningIntervals Tests

    func testSortedWarningIntervalsDefault() {
        let settings = NotificationSettings()
        // Default is [1], already sorted descending
        XCTAssertEqual(settings.sortedWarningIntervals, [1])
    }

    func testSortedWarningIntervalsMultiple() {
        var settings = NotificationSettings()
        settings.warningIntervals = [1, 5, 10, 3]

        XCTAssertEqual(settings.sortedWarningIntervals, [10, 5, 3, 1])
    }

    func testSortedWarningIntervalsEmpty() {
        var settings = NotificationSettings()
        settings.warningIntervals = []

        XCTAssertEqual(settings.sortedWarningIntervals, [])
    }

    // MARK: - addWarningInterval Tests

    func testAddWarningIntervalValid() {
        var settings = NotificationSettings()
        settings.addWarningInterval(5)

        XCTAssertTrue(settings.warningIntervals.contains(5))
        XCTAssertTrue(settings.warningIntervals.contains(1))
        // Should be sorted descending after add
        XCTAssertEqual(settings.warningIntervals, [5, 1])
    }

    func testAddWarningIntervalDuplicate() {
        var settings = NotificationSettings()
        settings.addWarningInterval(1) // 1 already exists by default

        // Should not add duplicate
        XCTAssertEqual(settings.warningIntervals.filter { $0 == 1 }.count, 1)
    }

    func testAddWarningIntervalZero() {
        var settings = NotificationSettings()
        settings.addWarningInterval(0)

        // Zero is out of range (guard: minutes > 0)
        XCTAssertEqual(settings.warningIntervals, [1])
    }

    func testAddWarningIntervalNegative() {
        var settings = NotificationSettings()
        settings.addWarningInterval(-5)

        XCTAssertEqual(settings.warningIntervals, [1])
    }

    func testAddWarningIntervalAtMaxBoundary() {
        var settings = NotificationSettings()
        settings.addWarningInterval(60)

        // 60 is at boundary (minutes <= 60)
        XCTAssertTrue(settings.warningIntervals.contains(60))
    }

    func testAddWarningIntervalAboveMax() {
        var settings = NotificationSettings()
        settings.addWarningInterval(61)

        // 61 is above max
        XCTAssertFalse(settings.warningIntervals.contains(61))
        XCTAssertEqual(settings.warningIntervals, [1])
    }

    func testAddWarningIntervalMaintainsSortOrder() {
        var settings = NotificationSettings()
        settings.addWarningInterval(10)
        settings.addWarningInterval(3)
        settings.addWarningInterval(30)

        XCTAssertEqual(settings.warningIntervals, [30, 10, 3, 1])
    }

    // MARK: - removeWarningInterval Tests

    func testRemoveWarningInterval() {
        var settings = NotificationSettings()
        settings.addWarningInterval(5)
        XCTAssertTrue(settings.warningIntervals.contains(5))

        settings.removeWarningInterval(5)
        XCTAssertFalse(settings.warningIntervals.contains(5))
    }

    func testRemoveWarningIntervalDefault() {
        var settings = NotificationSettings()
        settings.removeWarningInterval(1)

        XCTAssertEqual(settings.warningIntervals, [])
    }

    func testRemoveWarningIntervalNotPresent() {
        var settings = NotificationSettings()
        let originalIntervals = settings.warningIntervals
        settings.removeWarningInterval(99)

        XCTAssertEqual(settings.warningIntervals, originalIntervals)
    }

    // MARK: - resetToDefaults Tests

    func testResetToDefaults() {
        var settings = NotificationSettings()
        settings.isEnabled = false
        settings.sessionWarningsEnabled = false
        settings.sessionCompletionEnabled = false
        settings.warningIntervals = [5, 10, 15]

        settings.resetToDefaults()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.sessionWarningsEnabled)
        XCTAssertTrue(settings.sessionCompletionEnabled)
        XCTAssertEqual(settings.warningIntervals, [1])
    }

    // MARK: - Codable Round-Trip Tests

    func testCodableRoundTrip() throws {
        var settings = NotificationSettings()
        settings.isEnabled = false
        settings.sessionWarningsEnabled = true
        settings.sessionCompletionEnabled = false
        settings.warningIntervals = [15, 5, 1]

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NotificationSettings.self, from: data)

        XCTAssertEqual(decoded.isEnabled, settings.isEnabled)
        XCTAssertEqual(decoded.sessionWarningsEnabled, settings.sessionWarningsEnabled)
        XCTAssertEqual(decoded.sessionCompletionEnabled, settings.sessionCompletionEnabled)
        XCTAssertEqual(decoded.warningIntervals, settings.warningIntervals)
    }

    func testCodableRoundTripDefaultValues() throws {
        let settings = NotificationSettings()

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: data)

        XCTAssertEqual(decoded.isEnabled, true)
        XCTAssertEqual(decoded.sessionWarningsEnabled, true)
        XCTAssertEqual(decoded.sessionCompletionEnabled, true)
        XCTAssertEqual(decoded.warningIntervals, [1])
    }

    // MARK: - Backward Compatibility Tests

    func testDecodeFromJSONWithExtraKeys() throws {
        // Simulate JSON that has an old field like "notificationSound"
        let json = """
        {
            "isEnabled": true,
            "sessionWarningsEnabled": false,
            "sessionCompletionEnabled": true,
            "warningIntervals": [5, 1],
            "notificationSound": "default"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: json)

        XCTAssertTrue(decoded.isEnabled)
        XCTAssertFalse(decoded.sessionWarningsEnabled)
        XCTAssertTrue(decoded.sessionCompletionEnabled)
        XCTAssertEqual(decoded.warningIntervals, [5, 1])
    }

    func testDecodeFromJSONWithMissingKeys() throws {
        // Simulate JSON missing optional keys (backward compat via decodeIfPresent)
        let json = """
        {}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: json)

        // Should fall back to defaults
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertTrue(decoded.sessionWarningsEnabled)
        XCTAssertTrue(decoded.sessionCompletionEnabled)
        XCTAssertEqual(decoded.warningIntervals, [1])
    }

    func testDecodeFromJSONWithPartialKeys() throws {
        let json = """
        {
            "isEnabled": false,
            "warningIntervals": [10, 5]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: json)

        XCTAssertFalse(decoded.isEnabled)
        XCTAssertTrue(decoded.sessionWarningsEnabled) // default
        XCTAssertTrue(decoded.sessionCompletionEnabled) // default
        XCTAssertEqual(decoded.warningIntervals, [10, 5])
    }

    // MARK: - NotificationType Tests

    func testNotificationTypeCases() {
        let allCases = NotificationType.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.sessionWarning))
        XCTAssertTrue(allCases.contains(.sessionCompletion))
    }

    func testNotificationTypeRawValues() {
        XCTAssertEqual(NotificationType.sessionWarning.rawValue, "session_warning")
        XCTAssertEqual(NotificationType.sessionCompletion.rawValue, "session_completion")
    }

    func testNotificationTypeIdentifiable() {
        XCTAssertEqual(NotificationType.sessionWarning.id, "session_warning")
        XCTAssertEqual(NotificationType.sessionCompletion.id, "session_completion")
    }

    func testNotificationTypeDisplayNames() {
        XCTAssertEqual(NotificationType.sessionWarning.displayName, "Session Warnings")
        XCTAssertEqual(NotificationType.sessionCompletion.displayName, "Session Complete")
    }

    func testNotificationTypeSystemImages() {
        XCTAssertEqual(NotificationType.sessionWarning.systemImage, "clock.badge.exclamationmark")
        XCTAssertEqual(NotificationType.sessionCompletion.systemImage, "checkmark.circle")
    }
}
