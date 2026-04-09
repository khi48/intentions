//
//  NotificationSettings.swift
//  Intentions
//
//  Created by Claude on 12/10/2025.
//

import Foundation

@MainActor
@Observable
final class NotificationSettings: @preconcurrency Codable {
    /// Whether notifications are enabled at all
    var isEnabled: Bool

    /// Whether to show session warning notifications (1min remaining)
    var sessionWarningsEnabled: Bool

    /// Whether to show session completion notifications
    var sessionCompletionEnabled: Bool


    /// Custom notification sound (system sound identifier)
    var notificationSound: String


    /// Time intervals for session warnings (in minutes before session ends)
    var warningIntervals: [Int]

    init() {
        self.isEnabled = true
        self.sessionWarningsEnabled = true
        self.sessionCompletionEnabled = true
        self.notificationSound = "default"
        self.warningIntervals = [1] // Only 1 min before end
    }

    // MARK: - Codable Implementation

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case sessionWarningsEnabled
        case sessionCompletionEnabled
        case notificationSound
        case warningIntervals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sessionWarningsEnabled = try container.decodeIfPresent(Bool.self, forKey: .sessionWarningsEnabled) ?? true
        sessionCompletionEnabled = try container.decodeIfPresent(Bool.self, forKey: .sessionCompletionEnabled) ?? true
        notificationSound = try container.decodeIfPresent(String.self, forKey: .notificationSound) ?? "default"
        warningIntervals = try container.decodeIfPresent([Int].self, forKey: .warningIntervals) ?? [1]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(sessionWarningsEnabled, forKey: .sessionWarningsEnabled)
        try container.encode(sessionCompletionEnabled, forKey: .sessionCompletionEnabled)
        try container.encode(notificationSound, forKey: .notificationSound)
        try container.encode(warningIntervals, forKey: .warningIntervals)
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
    func addWarningInterval(_ minutes: Int) {
        guard minutes > 0 && minutes <= 60 && !warningIntervals.contains(minutes) else { return }
        warningIntervals.append(minutes)
        warningIntervals.sort { $0 > $1 }
    }

    /// Remove a warning interval
    func removeWarningInterval(_ minutes: Int) {
        warningIntervals.removeAll { $0 == minutes }
    }

    /// Reset to default settings
    func resetToDefaults() {
        isEnabled = true
        sessionWarningsEnabled = true
        sessionCompletionEnabled = true
        notificationSound = "default"
        warningIntervals = [1]
    }
}

// MARK: - Notification Types

enum NotificationType: String, CaseIterable, Identifiable {
    case sessionWarning = "session_warning"
    case sessionCompletion = "session_completion"
    case criticalWarning = "critical_warning"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sessionWarning:
            return "Session Warnings"
        case .sessionCompletion:
            return "Session Complete"
        case .criticalWarning:
            return "Critical Warnings"
        }
    }

    var description: String {
        switch self {
        case .sessionWarning:
            return "Get notified 1 minute before your session ends"
        case .sessionCompletion:
            return "Know when your session is complete"
        case .criticalWarning:
            return "Urgent notifications for the final minute"
        }
    }

    var systemImage: String {
        switch self {
        case .sessionWarning:
            return "clock.badge.exclamationmark"
        case .sessionCompletion:
            return "checkmark.circle"
        case .criticalWarning:
            return "exclamationmark.triangle"
        }
    }
}