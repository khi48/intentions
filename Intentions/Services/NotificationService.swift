//
//  NotificationService.swift
//  Intentions
//
//  Created by Claude on 12/10/2025.
//

import Foundation
@preconcurrency import UserNotifications
import UIKit

/// Service for managing app notifications including session warnings and completion alerts
@MainActor
final class NotificationService: NSObject, @unchecked Sendable {

    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - Properties

    private let notificationCenter = UNUserNotificationCenter.current()
    private var settings: NotificationSettings
    private let dataService: DataPersisting

    // MARK: - Authorization Status

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Initialization

    private override init() {
        self.settings = NotificationSettings()
        do {
            self.dataService = try DataPersistenceService()
        } catch {
            fatalError("Failed to initialize DataPersistenceService: \(error)")
        }
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
        } catch {
            // Use default settings
        }
    }

    func saveSettings() async {
        do {
            try await dataService.save(settings, forKey: "notificationSettings")
        } catch {
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

        // Debug: Check what was actually scheduled
        await debugPendingNotifications()
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

            let isCritical = warningMinutes <= 1

            let identifier = "session_warning_\(sessionId)_\(warningMinutes)min"

            let content = UNMutableNotificationContent()
            content.title = "Session Ending Soon"
            content.body = formatWarningMessage(minutes: warningMinutes)
            content.sound = isCritical ? .defaultCritical : .default
            content.categoryIdentifier = NotificationType.sessionWarning.rawValue

            if isCritical {
                content.interruptionLevel = .critical
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerTime, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await notificationCenter.add(request)
            } catch {
            }
        }
    }

    private func scheduleCompletionNotification(sessionId: String, remainingTime: TimeInterval) async {
        // Ensure remaining time is at least 1 second to avoid crash
        // UNTimeIntervalNotificationTrigger requires timeInterval >= 1.0
        guard remainingTime >= 1.0 else {
            return
        }

        let identifier = "session_completion_\(sessionId)"

        let content = UNMutableNotificationContent()
        content.title = "Session Complete"
        content.body = "Your focused session has ended. Great work!"
        content.sound = .default
        content.categoryIdentifier = NotificationType.sessionCompletion.rawValue

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remainingTime, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
        } catch {
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

        // Use a very small trigger time to send immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "session_expired_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
        }
    }

    // MARK: - Notification Cancellation

    func cancelSessionNotifications() async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let sessionIdentifiers = pendingRequests
            .map { $0.identifier }
            .filter { $0.contains("session_warning_") || $0.contains("session_completion_") }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: sessionIdentifiers)
    }

    func cancelAllNotifications() async {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    // MARK: - Debugging

    func debugPendingNotifications() async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        for request in pendingRequests {
            _ = request.trigger as? UNTimeIntervalNotificationTrigger
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