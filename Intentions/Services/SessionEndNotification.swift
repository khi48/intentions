//
//  SessionEndNotification.swift
//  Intentions
//

import Foundation
import UserNotifications

/// Pure spec-builders for session-end banners.
///
/// All entries are static, value-type-in/value-type-out so they can be unit
/// tested without `UNUserNotificationCenter` contact. Callers (`NotificationService`)
/// own the `notificationCenter.add` side effect.
enum SessionEndNotification {

    /// Per-session identifier for the R3 mutex teardown banner (#30).
    /// Format: `session_terminated_by_freetime_<sessionUUID>`. Per-session so
    /// `cancelAllSessionNotifications(sessionId:)` can wipe it cleanly and
    /// `cancelSessionNotifications()` master sweep catches all instances via
    /// `session_terminated_by_freetime_` prefix.
    static func sessionTerminatedByFreeTimeIdentifier(sessionId: UUID) -> String {
        "session_terminated_by_freetime_\(sessionId.uuidString)"
    }

    /// Prefix used by master cancel sweeps to match all per-session R3 banners.
    static let sessionTerminatedByFreeTimeIdentifierPrefix = "session_terminated_by_freetime_"

    /// Build a pre-scheduled R3 mutex teardown banner request.
    ///
    /// Fires at the first free-time boundary that falls inside an active
    /// session's window. Pre-scheduled at session start (#30) — iOS owns the
    /// trigger so it fires reliably even when the main app is killed at the
    /// boundary moment.
    ///
    /// Returns nil when:
    /// - settings gating denies (master toggle or completion toggle off), OR
    /// - `triggerInterval < 1.0` (UNTimeIntervalNotificationTrigger requirement).
    ///
    /// Gating uses `sessionCompletionEnabled` — this is a session-end event, so
    /// it follows the same toggle as the regular completion banner.
    /// Authorization is checked separately by the caller (instance-only state).
    static func sessionTerminatedByFreeTimeRequest(
        settings: NotificationSettings,
        sessionId: UUID,
        triggerInterval: TimeInterval
    ) -> UNNotificationRequest? {
        guard settings.isEnabled && settings.sessionCompletionEnabled else { return nil }
        guard triggerInterval >= 1.0 else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Session Ended"
        content.body = "Free time started — your session ended."
        content.sound = .default
        content.categoryIdentifier = NotificationType.sessionCompletion.rawValue

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerInterval, repeats: false)
        return UNNotificationRequest(
            identifier: sessionTerminatedByFreeTimeIdentifier(sessionId: sessionId),
            content: content,
            trigger: trigger
        )
    }
}
