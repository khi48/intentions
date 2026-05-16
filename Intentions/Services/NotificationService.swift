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

    /// Send immediate notification when an active session was terminated because
    /// a free-time window started (R3, #27 — free-time and session are mutually
    /// exclusive). Single-shot with a fixed identifier so repeated mutex fires
    /// in the same window replace rather than stack.
    func sendSessionTerminatedByFreeTimeNotification() async {
        guard settings.isEnabled && isAuthorized else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Session Ended"
        content.body = "Free time started — your session ended."
        content.sound = .default
        content.categoryIdentifier = NotificationType.sessionCompletion.rawValue

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(
            identifier: "session_terminated_by_freetime",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            Self.log.error("Failed to schedule session-terminated-by-free-time notification: \(error.localizedDescription)")
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
                    || $0 == "session_terminated_by_freetime"
            }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: sessionIdentifiers)
    }

    /// Cancel every pending notification tied to a specific session — warnings AND
    /// the pre-scheduled completion trigger. Use for manual-end and replace flows
    /// where we explicitly do NOT want the "Session Complete" banner to fire.
    func cancelAllSessionNotifications(sessionId: UUID) async {
        let sessionIdString = sessionId.uuidString
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map { $0.identifier }
            .filter { id in
                // Session-specific identifiers end with the session UUID (warnings
                // also include a "_<N>min" suffix). Also sweep the generic
                // "session_expired" + "session_terminated_by_freetime" fallback
                // identifiers to be safe.
                id.contains("session_warning_\(sessionIdString)")
                    || id == "session_completion_\(sessionIdString)"
                    || id == "session_expired"
                    || id == "session_terminated_by_freetime"
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
        let sessionIdentifiers = pendingRequests
            .map { $0.identifier }
            .filter { $0.hasPrefix("session_") }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: sessionIdentifiers)
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