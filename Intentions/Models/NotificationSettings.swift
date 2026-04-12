//
//  NotificationSettings.swift
//  Intentions
//
//  Created by Claude on 12/10/2025.
//

import Foundation

struct NotificationSettings: Codable, Sendable {
    /// Whether notifications are enabled at all
    var isEnabled: Bool

    /// Whether to show session warning notifications (1min remaining)
    var sessionWarningsEnabled: Bool

    /// Whether to show session completion notifications
    var sessionCompletionEnabled: Bool

    /// Time intervals for session warnings (in minutes before session ends)
    var warningIntervals: [Int]

    init() {
        self.isEnabled = true
        self.sessionWarningsEnabled = true
        self.sessionCompletionEnabled = true
        self.warningIntervals = [1] // Only 1 min before end
    }

    // MARK: - Codable Implementation

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case sessionWarningsEnabled
        case sessionCompletionEnabled
        case warningIntervals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sessionWarningsEnabled = try container.decodeIfPresent(Bool.self, forKey: .sessionWarningsEnabled) ?? true
        sessionCompletionEnabled = try container.decodeIfPresent(Bool.self, forKey: .sessionCompletionEnabled) ?? true
        warningIntervals = try container.decodeIfPresent([Int].self, forKey: .warningIntervals) ?? [1]
    }

    // MARK: - Helper Methods

    /// Whether any notifications are effectively enabled
    var hasAnyNotificationsEnabled: Bool {
        isEnabled && (sessionWarningsEnabled || sessionCompletionEnabled)
    }

    /// Get warning intervals sorted in descending order (furthest to nearest)
    var sortedWarningIntervals: [Int] {
        warningIntervals.sorted { $0 > $1 }
    }

    /// Add a custom warning interval
    mutating func addWarningInterval(_ minutes: Int) {
        guard minutes > 0 && minutes <= 60 && !warningIntervals.contains(minutes) else { return }
        warningIntervals.append(minutes)
        warningIntervals.sort { $0 > $1 }
    }

    /// Remove a warning interval
    mutating func removeWarningInterval(_ minutes: Int) {
        warningIntervals.removeAll { $0 == minutes }
    }

    /// Reset to default settings
    mutating func resetToDefaults() {
        self = NotificationSettings()
    }
}

// MARK: - Notification Types

enum NotificationType: String, CaseIterable, Identifiable {
    case sessionWarning = "session_warning"
    case sessionCompletion = "session_completion"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sessionWarning:
            return "Session Warnings"
        case .sessionCompletion:
            return "Session Complete"
        }
    }

    var description: String {
        switch self {
        case .sessionWarning:
            return "Get notified 1 minute before your session ends"
        case .sessionCompletion:
            return "Know when your session is complete"
        }
    }

    var systemImage: String {
        switch self {
        case .sessionWarning:
            return "clock.badge.exclamationmark"
        case .sessionCompletion:
            return "checkmark.circle"
        }
    }
}
