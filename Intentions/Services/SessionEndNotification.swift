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

    /// Decide whether/when to arm the per-session R3 mutex teardown banner (#30).
    ///
    /// Returns the boundary `Date` at which the banner should fire, or `nil`
    /// to skip arming entirely.
    ///
    /// Skip rules:
    /// - schedule disabled (no free-time semantics — R3 doesn't apply)
    /// - no boundary in the next week
    /// - boundary falls at-or-after session end (session ends naturally first)
    /// - boundary direction is free-time → blocking (i.e. session was started
    ///   inside a free-time window and the next boundary is the EXIT — #62 /
    ///   Q6: sub-rule 2 dropped, so we no longer terminate the session there,
    ///   and the banner copy "Free time started" would be misleading anyway).
    ///
    /// Direction is determined by probing the snapshot at the boundary moment
    /// and one minute before: the banner only arms when `isFreeTime(at:
    /// boundary)` is true and `isFreeTime(at: boundary - 60s)` is false
    /// (blocking → free-time entry).
    ///
    /// The settings/trigger-interval gating remains the responsibility of
    /// `sessionTerminatedByFreeTimeRequest(...)`; this spec-builder only
    /// decides scheduling.
    static func r3MutexTeardownBannerBoundary(
        schedule: ScheduleSnapshot,
        sessionStart: Date,
        sessionEnd: Date,
        now: Date = Date()
    ) -> Date? {
        guard schedule.isEnabled else { return nil }
        guard let boundary = schedule.nextBoundary(after: sessionStart) else { return nil }
        guard boundary < sessionEnd else { return nil }

        // Direction gate: only arm when the boundary is an ENTRY into free-time
        // (blocking → free-time). The inverse (free-time → blocking) is an exit
        // boundary; #62 dropped sub-rule 2 so the session is preserved across
        // that boundary and the "Free time started" copy doesn't apply.
        let before = boundary.addingTimeInterval(-60)
        guard schedule.isFreeTime(at: boundary), !schedule.isFreeTime(at: before) else {
            return nil
        }

        _ = now // reserved for future "skip if boundary already passed" guard; currently caller computes trigger interval from Date()
        return boundary
    }
}
