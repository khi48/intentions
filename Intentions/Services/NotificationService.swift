//
//  NotificationService.swift
//  Intentions
//
//  Created by Claude on 12/10/2025.
//

import Foundation
@preconcurrency import UserNotifications
import OSLog

/// Service for managing app notifications including session warnings and completion alerts
@MainActor
final class NotificationService: NSObject, Sendable {

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Intentions", category: "NotificationService")

    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - Properties

    private let notificationCenter = UNUserNotificationCenter.current()
    private var settings: NotificationSettings
    private let dataService: DataPersisting

    // MARK: - Authorization Status

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Initialization

    private(set) var settingsLoaded = false
    private(set) var settingsLoadFailed = false

    private override init() {
        // Try to create DataPersistenceService; fall back to mock if it fails
        let service: DataPersisting
        do {
            service = try DataPersistenceService()
        } catch {
            Self.log.error("Failed to initialize DataPersistenceService, using in-memory fallback: \(error.localizedDescription)")
            service = MockDataPersistenceService()
        }
        self.dataService = service
        self.settings = NotificationSettings()
        super.init()

        // Set up notification center delegate
        notificationCenter.delegate = self

        // Load settings asynchronously
        Task {
            await loadSettings()
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Settings Management

    func loadSettings() async {
        do {
            if let loadedSettings = try await dataService.load(NotificationSettings.self, forKey: "notificationSettings") {
                settings = loadedSettings
            }
            settingsLoaded = true
            settingsLoadFailed = false
        } catch {
            Self.log.warning("Failed to load notification settings, using defaults: \(error.localizedDescription)")
            settingsLoaded = true
            settingsLoadFailed = true
        }
    }

    func saveSettings() async {
        do {
            try await dataService.save(settings, forKey: "notificationSettings")
        } catch {
            Self.log.error("Failed to save notification settings: \(error.localizedDescription)")
        }
    }

    func updateSettings(_ newSettings: NotificationSettings) async {
        settings = newSettings
        await saveSettings()

        // If notifications were disabled, cancel all scheduled notifications
        if !newSettings.isEnabled {
            await cancelAllNotifications()
            return
        }

        // Rebuild free-time pending state to match the new settings. Session
        // notifications are scheduled per-session-start so they self-heal on
        // the next session; free-time notifications are persistent (repeats:true)
        // and need to be re-synced explicitly on every settings change.
        if let schedule = try? await dataService.loadWeeklySchedule() {
            await rescheduleFreeTimeNotifications(schedule: schedule)
            // Re-sync R3 pre-scheduled banner against the new settings — a
            // settings toggle (e.g. completion-disabled) must wipe a stale
            // pending banner; re-enabling must rebuild it.
            await rescheduleR3MutexTeardownBannerForActiveSession(schedule: schedule)
        }
    }

    var currentSettings: NotificationSettings {
        settings
    }

    // MARK: - Permission Management

    func requestPermissions() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()


            return granted
        } catch {
            return false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus

    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: - Session Notifications

    /// Schedule notifications for an active session
    func scheduleSessionNotifications(for session: IntentionSession) async {

        guard settings.isEnabled && isAuthorized else {
            return
        }

        // Cancel any existing session notifications first
        await cancelSessionNotifications()

        let sessionId = session.id.uuidString
        let remainingTime = session.remainingTime


        // Schedule warning notifications
        if settings.sessionWarningsEnabled {
            await scheduleWarningNotifications(sessionId: sessionId, remainingTime: remainingTime)
        }

        // Schedule completion notification
        if settings.sessionCompletionEnabled {
            await scheduleCompletionNotification(sessionId: sessionId, remainingTime: remainingTime)
        }

        // Pre-schedule R3 mutex teardown banner (#30) — fires at the first
        // free-time boundary inside the session window. iOS owns the trigger
        // so it fires reliably even when the main app is killed at the boundary.
        if let schedule = try? await dataService.loadWeeklySchedule() {
            await addR3MutexTeardownBanner(for: session, schedule: schedule)
        }
    }

    /// Re-schedule the per-session R3 mutex teardown banner against a freshly-edited
    /// schedule. Looks up the currently-active session via persistence; no-op if
    /// none is active. Wipes the existing per-session R3 banner and re-pre-schedules
    /// against the new free-time boundary. Call from schedule-mutation paths
    /// (`ContentViewModel.updateWeeklySchedule`, hydration, `SettingsViewModel`,
    /// settings hook) so mid-session schedule edits move the banner to the new
    /// boundary time.
    func rescheduleR3MutexTeardownBannerForActiveSession(schedule: WeeklySchedule) async {
        guard settings.isEnabled && isAuthorized else { return }
        guard let activeSession = await loadActiveSessionForR3Reschedule() else { return }
        await cancelR3MutexTeardownBanner(sessionId: activeSession.id)
        await addR3MutexTeardownBanner(for: activeSession, schedule: schedule)
    }

    private func loadActiveSessionForR3Reschedule() async -> IntentionSession? {
        do {
            let sessions = try await dataService.loadIntentionSessions()
            return sessions.first { $0.isActive }
        } catch {
            Self.log.warning("R3 reschedule: failed to load active session: \(error.localizedDescription)")
            return nil
        }
    }

    /// Post the R3 mutex teardown banner with an immediate (1s) trigger. Used by
    /// the CASE B path where the user edits the schedule mid-session to introduce
    /// free-time at `now`: the pre-scheduled banner was for the ORIGINAL boundary
    /// and was wiped alongside the session by `cancelAllSessionNotifications`,
    /// so this re-adds a fresh per-session banner that fires immediately.
    /// CASE A (boundary arrives naturally) is handled by the pre-scheduled banner
    /// owned by iOS, with no need for this path.
    func postImmediateR3MutexTeardownBanner(sessionId: UUID) async {
        guard isAuthorized,
              let request = SessionEndNotification.sessionTerminatedByFreeTimeRequest(
                settings: settings,
                sessionId: sessionId,
                triggerInterval: 1.0
              ) else { return }
        do {
            try await notificationCenter.add(request)
        } catch {
            Self.log.error("Failed to post immediate R3 mutex teardown banner: \(error.localizedDescription)")
        }
    }

    /// Pure decision + add for the R3 mutex teardown banner. Skip cases:
    /// - schedule disabled (R3 doesn't apply without a schedule)
    /// - session start moment is NOT in blocking (defensive — #27 guard prevents
    ///   session start during free time, but session may have been hydrated past
    ///   the boundary)
    /// - no boundary in the next week
    /// - boundary falls at or after session end (session ends naturally first)
    /// - trigger interval < 1.0s (UNTimeIntervalNotificationTrigger requirement)
    /// - spec-builder gating denies (settings master / completion toggle off)
    private func addR3MutexTeardownBanner(for session: IntentionSession, schedule: WeeklySchedule) async {
        guard schedule.isEnabled else {
            Self.log.notice("R3 pre-schedule skipped: schedule disabled")
            return
        }
        guard schedule.isBlocking(at: session.startTime) else {
            Self.log.notice("R3 pre-schedule skipped: session start \(session.startTime) not in blocking state")
            return
        }
        guard let boundary = schedule.nextBoundary(after: session.startTime) else {
            Self.log.notice("R3 pre-schedule skipped: no boundary in next week")
            return
        }
        guard boundary < session.endTime else {
            Self.log.notice("R3 pre-schedule skipped: boundary \(boundary) at-or-after session end \(session.endTime)")
            return
        }

        let triggerInterval = boundary.timeIntervalSince(Date())
        guard let request = SessionEndNotification.sessionTerminatedByFreeTimeRequest(
            settings: settings,
            sessionId: session.id,
            triggerInterval: triggerInterval
        ) else {
            Self.log.notice("R3 pre-schedule skipped: spec-builder denied (gating or trigger<1.0s, interval=\(triggerInterval))")
            return
        }

        do {
            try await notificationCenter.add(request)
            Self.log.notice("R3 pre-scheduled: session \(session.id.uuidString) boundary \(boundary) interval \(triggerInterval)s")
        } catch {
            Self.log.error("Failed to pre-schedule R3 mutex teardown banner: \(error.localizedDescription)")
        }
    }

    /// Cancel just the per-session R3 mutex teardown banner. Used by the
    /// reschedule path so warning + completion banners are untouched.
    private func cancelR3MutexTeardownBanner(sessionId: UUID) async {
        let identifier = SessionEndNotification.sessionTerminatedByFreeTimeIdentifier(sessionId: sessionId)
        let pending = await notificationCenter.pendingNotificationRequests()
        guard pending.contains(where: { $0.identifier == identifier }) else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func scheduleWarningNotifications(sessionId: String, remainingTime: TimeInterval) async {
        for warningMinutes in settings.sortedWarningIntervals {
            let warningSeconds = TimeInterval(warningMinutes * 60)

            // Only schedule if there's enough time left
            guard remainingTime > warningSeconds else {
                continue
            }

            let triggerTime = remainingTime - warningSeconds

            // Ensure trigger time is at least 1 second to avoid crash
            guard triggerTime > 0 else {
                continue
            }

            let isUrgent = warningMinutes <= 1

            let identifier = "session_warning_\(sessionId)_\(warningMinutes)min"

            let content = UNMutableNotificationContent()
            content.title = "Session Ending Soon"
            content.body = formatWarningMessage(minutes: warningMinutes)
            content.sound = .default
            content.categoryIdentifier = NotificationType.sessionWarning.rawValue

            if isUrgent {
                content.interruptionLevel = .timeSensitive
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerTime, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await notificationCenter.add(request)
            } catch {
                Self.log.error("Failed to schedule warning notification: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleCompletionNotification(sessionId: String, remainingTime: TimeInterval) async {
        // UNTimeIntervalNotificationTrigger requires timeInterval >= 1.0
        guard remainingTime >= 1.0 else {
            return
        }

        let identifier = "session_completion_\(sessionId)"

        let content = UNMutableNotificationContent()
        content.title = "Session Complete"
        content.body = "Your focused session has ended. Apps are now blocked again."
        content.sound = .default
        content.categoryIdentifier = NotificationType.sessionCompletion.rawValue

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remainingTime, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
        } catch {
            Self.log.error("Failed to schedule completion notification: \(error.localizedDescription)")
        }
    }

    private func formatWarningMessage(minutes: Int) -> String {
        switch minutes {
        case 1:
            return "Only 1 minute left in your session"
        case 2:
            return "2 minutes remaining in your session"
        case 5:
            return "5 minutes left - time to wrap up"
        case 10:
            return "10 minutes remaining in your session"
        default:
            return "\(minutes) minutes left in your session"
        }
    }

    /// Send immediate notification when session expires automatically
    /// This is triggered when the background task expires the session
    func sendSessionExpiredNotification() async {
        guard settings.isEnabled && isAuthorized else {
            return
        }


        let content = UNMutableNotificationContent()
        content.title = "Session Expired"
        content.body = "Your session has ended. Apps are now blocked again."
        content.sound = .default
        content.categoryIdentifier = NotificationType.sessionCompletion.rawValue

        // Use a fixed identifier so duplicate expiration notifications (from in-app
        // timer, intervalDidEnd, and eventDidReachThreshold) replace each other
        // instead of stacking.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(
            identifier: "session_expired",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            Self.log.error("Failed to schedule expiration notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Notification Cancellation

    /// Cancel ALL pending session notifications for any session.
    /// Used when notifications get disabled globally.
    func cancelSessionNotifications() async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let sessionIdentifiers = pendingRequests
            .map { $0.identifier }
            .filter {
                $0.contains("session_warning_")
                    || $0.contains("session_completion_")
                    || $0.hasPrefix("session_expired")
                    || $0.hasPrefix(SessionEndNotification.sessionTerminatedByFreeTimeIdentifierPrefix)
            }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: sessionIdentifiers)
    }

    /// Cancel every pending notification tied to a specific session — warnings AND
    /// the pre-scheduled completion trigger AND the pre-scheduled R3 banner. Use
    /// for manual-end and replace flows where we explicitly do NOT want any
    /// session banner to fire.
    func cancelAllSessionNotifications(sessionId: UUID) async {
        let sessionIdString = sessionId.uuidString
        let r3Identifier = SessionEndNotification.sessionTerminatedByFreeTimeIdentifier(sessionId: sessionId)
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map { $0.identifier }
            .filter { id in
                id.contains("session_warning_\(sessionIdString)")
                    || id == "session_completion_\(sessionIdString)"
                    || id == "session_expired"
                    || id == r3Identifier
            }

        if !identifiers.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
            Self.log.info("Cancelled \(identifiers.count) session notifications for \(sessionIdString)")
        }
    }

    /// Cancel only the warning notifications for a session. Leaves the pre-scheduled
    /// completion trigger in place so it can fire at the real end time — this is the
    /// natural-completion path.
    func cancelSessionWarnings(sessionId: UUID) async {
        let sessionIdString = sessionId.uuidString
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map { $0.identifier }
            .filter { $0.contains("session_warning_\(sessionIdString)") }

        if !identifiers.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
            Self.log.info("Cancelled \(identifiers.count) session warnings for \(sessionIdString)")
        }
    }

    /// Check if the pre-scheduled completion notification for a session has already
    /// been delivered OR is still pending delivery. Used as a dedupe guard: if the
    /// banner has already appeared (or is about to in the next fraction of a second),
    /// the fallback `sendSessionExpiredNotification` should not be posted.
    ///
    /// Checks both:
    /// 1. `deliveredNotifications` — trigger has fired, banner shown.
    /// 2. `pendingNotificationRequests` — trigger is still armed and will fire soon.
    ///    This catches the race where the in-app timer finalises milliseconds before
    ///    the `UNTimeIntervalNotificationTrigger` delivery.
    func hasDeliveredCompletionNotification(sessionId: UUID) async -> Bool {
        let identifier = "session_completion_\(sessionId.uuidString)"

        let delivered = await notificationCenter.deliveredNotifications()
        if delivered.contains(where: { $0.request.identifier == identifier }) {
            return true
        }

        let pending = await notificationCenter.pendingNotificationRequests()
        if pending.contains(where: { $0.identifier == identifier }) {
            return true
        }

        return false
    }

    func cancelAllNotifications() async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map { $0.identifier }
            .filter { $0.hasPrefix("session_") || $0.hasPrefix(Self.freeTimeIdentifierPrefix) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: - Free-Time Notifications (#24)

    /// All free-time-related identifiers start with this. Wipe-by-prefix relies
    /// on it; do not change without migrating delivered/pending state.
    static let freeTimeIdentifierPrefix = "freetime_"
    static let freeTimeWarningIdentifierPrefix = "freetime_warning_"
    static let freeTimeCompletionIdentifierPrefix = "freetime_completion_"

    /// Rebuild the pending free-time notifications from the current schedule +
    /// settings. Wipes every pending `freetime_*` identifier first, then re-adds
    /// fresh ones built by `freeTimeNotificationRequests(schedule:settings:)`.
    ///
    /// Call on every mutation that could change the set of free-time intervals
    /// (schedule save, hydration on app launch, notification-settings toggle).
    /// No-op when the schedule is disabled or notifications are turned off —
    /// the wipe still runs so toggling off cancels pending notifications.
    func rescheduleFreeTimeNotifications(schedule: WeeklySchedule) async {
        // Always wipe first so toggle-off / schedule-disabled paths clear pending.
        await cancelFreeTimeNotifications()

        guard settings.isEnabled && isAuthorized && schedule.isEnabled else {
            return
        }

        let requests = Self.freeTimeNotificationRequests(
            isScheduleEnabled: schedule.isEnabled,
            routines: schedule.routines,
            timeZone: schedule.timeZone,
            settings: settings
        )

        for request in requests {
            do {
                try await notificationCenter.add(request)
            } catch {
                Self.log.error("Failed to schedule free-time notification \(request.identifier): \(error.localizedDescription)")
            }
        }

        if !requests.isEmpty {
            Self.log.info("Scheduled \(requests.count) free-time notifications across \(schedule.routines.count) routines")
        }
    }

    /// Cancel every pending free-time notification (both warnings and completions).
    /// Used internally by `rescheduleFreeTimeNotifications` and as the cancel path
    /// when the schedule is toggled off entirely.
    func cancelFreeTimeNotifications() async {
        let pending = await notificationCenter.pendingNotificationRequests()
        let identifiers = pending
            .map { $0.identifier }
            .filter { $0.hasPrefix(Self.freeTimeIdentifierPrefix) }

        if !identifiers.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
            Self.log.info("Cancelled \(identifiers.count) free-time notifications")
        }
    }

    /// Pure spec-builder for free-time-window warning + completion notifications.
    ///
    /// Inputs are value types; no UNUserNotificationCenter contact. The returned
    /// `UNNotificationRequest`s use `UNCalendarNotificationTrigger` with
    /// `repeats: true` and `DateComponents` carrying the schedule's `timeZone`
    /// so the trigger fires weekly at the wall-clock end of each routine occurrence.
    ///
    /// Per-routine-per-day logic:
    ///   - For each weekday `d` in `routine.days`, emit a separate weekly trigger
    ///     keyed by (routine.id, weekday).
    ///   - End-of-day minute = `routine.endMinute`. If this equals 1440 (routine
    ///     ends at midnight), the trigger rolls into the next weekday at 00:00.
    ///   - Warnings: skip when `routine.durationMinutes <= warningMinutes` (the
    ///     warning would land at-or-before the routine start). Otherwise fire at
    ///     `endMinute - warningMinutes` on the same day as the routine.
    ///   - Completion fires at end minute on the same day (gated only by
    ///     `sessionCompletionEnabled`).
    ///
    /// Returns an empty array when notifications are off, master toggle is off,
    /// or the schedule is disabled — callers still need to wipe pending state
    /// separately.
    static func freeTimeNotificationRequests(
        isScheduleEnabled: Bool,
        routines: [FreeTimeRoutine],
        timeZone: TimeZone,
        settings: NotificationSettings
    ) -> [UNNotificationRequest] {
        guard settings.isEnabled && isScheduleEnabled else { return [] }
        guard settings.sessionWarningsEnabled || settings.sessionCompletionEnabled else { return [] }

        var requests: [UNNotificationRequest] = []

        for routine in routines {
            let endMinute = routine.endMinute

            for weekday in routine.days {
                // Warnings — one per configured interval, skipped per-warning when
                // the routine is too short to make the warning meaningful.
                if settings.sessionWarningsEnabled {
                    for warningMinutes in settings.sortedWarningIntervals {
                        guard warningMinutes > 0 else { continue }
                        guard routine.durationMinutes > warningMinutes else { continue }

                        let warningMinuteOfDay = endMinute - warningMinutes
                        let components = dateComponents(
                            weekday: weekday,
                            minuteOfDay: warningMinuteOfDay,
                            timeZone: timeZone
                        )

                        let content = UNMutableNotificationContent()
                        content.title = "Free Time Ending Soon"
                        content.body = formatFreeTimeWarningBody(minutes: warningMinutes)
                        content.sound = .default
                        content.categoryIdentifier = NotificationType.sessionWarning.rawValue
                        if warningMinutes <= 1 {
                            content.interruptionLevel = .timeSensitive
                        }

                        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                        let identifier = "\(freeTimeWarningIdentifierPrefix)\(routine.id.uuidString)_\(weekday.rawValue)_\(warningMinutes)min"
                        requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                    }
                }

                // Completion — at routine end. If endMinute == 1440 the components
                // roll into the next weekday at 00:00.
                if settings.sessionCompletionEnabled {
                    let components = dateComponents(weekday: weekday, minuteOfDay: endMinute, timeZone: timeZone)

                    let content = UNMutableNotificationContent()
                    content.title = "Free Time Ended"
                    content.body = "Apps are now blocked again."
                    content.sound = .default
                    content.categoryIdentifier = NotificationType.sessionCompletion.rawValue

                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let identifier = "\(freeTimeCompletionIdentifierPrefix)\(routine.id.uuidString)_\(weekday.rawValue)"
                    requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                }
            }
        }

        return requests
    }

    /// Build `DateComponents` suitable for `UNCalendarNotificationTrigger(dateMatching:repeats:)`
    /// for a given weekday + minute-of-day. Weekday output is the Foundation convention
    /// (Sun=1..Sat=7). If `minuteOfDay >= 1440` the components roll forward into the next
    /// calendar weekday at 00:00 — used by completion notifications for routines that
    /// end exactly at midnight.
    static func dateComponents(weekday: Weekday, minuteOfDay: Int, timeZone: TimeZone) -> DateComponents {
        var adjustedMinute = minuteOfDay
        var adjustedWeekday = weekday
        if adjustedMinute >= FreeTimeRoutine.minutesPerDay {
            adjustedMinute -= FreeTimeRoutine.minutesPerDay
            let nextCalendarWeekday = (adjustedWeekday.calendarWeekday % 7) + 1
            adjustedWeekday = Weekday.from(calendarWeekday: nextCalendarWeekday)
        }
        let hour = adjustedMinute / 60
        let minute = adjustedMinute % 60

        var components = DateComponents()
        components.weekday = adjustedWeekday.calendarWeekday
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = timeZone
        return components
    }

    private static func formatFreeTimeWarningBody(minutes: Int) -> String {
        switch minutes {
        case 1:
            return "1 minute left of free time"
        default:
            return "\(minutes) minutes left of free time"
        }
    }

}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {

        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier

        // Handle different notification types
        if identifier.contains("session_warning_") {
            // User tapped a session warning - maybe open the app to session status
            handleSessionWarningTap()
        } else if identifier.contains("session_completion_") {
            // User tapped session completion - maybe show session summary
            handleSessionCompletionTap()
        }

        completionHandler()
    }

    nonisolated private func handleSessionWarningTap() {
        // Post notification to bring user to session status
        NotificationCenter.default.post(name: .showSessionStatus, object: nil)
    }

    nonisolated private func handleSessionCompletionTap() {
        // Post notification to maybe show session summary
        NotificationCenter.default.post(name: .sessionCompleted, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showSessionStatus = Notification.Name("showSessionStatus")
    static let sessionCompleted = Notification.Name("sessionCompleted")
}