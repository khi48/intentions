//
//  DeviceActivityMonitorExtension.swift
//  IntentionsDeviceActivityMonitor
//
//  Device Activity Monitor Extension for handling scheduled session expiration
//  This extension runs in the background and is triggered by iOS when scheduled events occur
//

import Foundation
import DeviceActivity
import ManagedSettings
import FamilyControls
import UserNotifications
import WidgetKit
import OSLog

/// Monitor extension that handles session expiration events
/// This runs even when the main app is not active
/// IMPORTANT: Class name must match NSExtensionPrincipalClass in Info.plist
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    let store = ManagedSettingsStore()
    let logger = Logger(subsystem: "oh.Intent", category: "DeviceActivityMonitor")

    /// Called when a scheduled interval starts
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        let timestamp = Date()
        logger.notice("🟢 MONITOR EXTENSION: intervalDidStart called at \(timestamp, privacy: .public)")
        logger.notice("🟢 MONITOR EXTENSION: Activity name: \(activity.rawValue, privacy: .public)")

        // Log to shared UserDefaults for debugging
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intent") {
            sharedDefaults.set(timestamp, forKey: "intentions.lastIntervalStart")
            sharedDefaults.set(activity.rawValue, forKey: "intentions.lastIntervalStartActivity")
            sharedDefaults.synchronize()
            logger.info("🟢 MONITOR EXTENSION: Logged start to UserDefaults")
        }
    }

    /// Called when a scheduled interval ends
    /// This is where we restore default blocking when the session expires
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        let timestamp = Date()
        logger.error("🔴 MONITOR EXTENSION: intervalDidEnd called at \(timestamp, privacy: .public)")
        logger.error("🔴 MONITOR EXTENSION: Activity name: \(activity.rawValue, privacy: .public)")

        // STEP 1: VALIDATE BEFORE ACTING - Check if this is a legitimate expiration
        guard let sharedDefaults = UserDefaults(suiteName: "group.oh.Intent") else {
            logger.error("❌ MONITOR EXTENSION: Cannot access UserDefaults - aborting")
            return
        }

        // Log for debugging
        sharedDefaults.set(timestamp, forKey: "intentions.lastIntervalEnd")
        sharedDefaults.set(activity.rawValue, forKey: "intentions.lastIntervalEndActivity")

        // Validate 1: Check activity name matches what was scheduled
        if let scheduledActivity = sharedDefaults.string(forKey: "intentions.lastScheduledActivity") {
            logger.notice("🔴 MONITOR EXTENSION: Expected activity: \(scheduledActivity, privacy: .public)")
            logger.notice("🔴 MONITOR EXTENSION: Actual activity: \(activity.rawValue, privacy: .public)")

            if scheduledActivity != activity.rawValue {
                logger.warning("⚠️ MONITOR EXTENSION: Activity mismatch - this is a stale event, IGNORING")
                return
            }
            logger.notice("✅ MONITOR EXTENSION: Activity matches")
        }

        // Validate 2: Check if this fired at the correct time (not too early)
        guard let scheduledEndTime = sharedDefaults.object(forKey: "intentions.lastScheduledEndTime") as? Date else {
            logger.warning("⚠️ MONITOR EXTENSION: No scheduled end time found - cannot validate timing, IGNORING")
            return
        }

        logger.notice("🔴 MONITOR EXTENSION: Scheduled end time was: \(scheduledEndTime, privacy: .public)")
        let delay = timestamp.timeIntervalSince(scheduledEndTime)
        logger.notice("🔴 MONITOR EXTENSION: Triggered \(delay, privacy: .public) seconds after scheduled time")

        // CRITICAL: Only process if this is a legitimate expiration (not an early trigger)
        // Negative delay means iOS fired intervalDidEnd early (e.g., when app reopens)
        // Allow small tolerance for timing variations (5 seconds early is acceptable)
        if delay < -5.0 {
            logger.warning("⚠️ MONITOR EXTENSION: intervalDidEnd fired TOO EARLY (\(delay, privacy: .public)s before scheduled time)")
            logger.warning("⚠️ MONITOR EXTENSION: This is likely due to app lifecycle - ABORTING, not blocking apps")
            return // Do NOT process early triggers
        }

        logger.info("✅ MONITOR EXTENSION: Timing validation passed - this is a legitimate expiration")

        // Validate 3: Check if this is an Intentions session
        guard activity.rawValue.hasPrefix("intentions.session.") else {
            logger.warning("⚠️ MONITOR EXTENSION: Activity name does NOT match intentions.session.* pattern - IGNORING")
            return
        }

        logger.notice("✅ MONITOR EXTENSION: Confirmed this is an Intentions session")

        // Validate 4: Extract and validate session ID
        let sessionId = String(activity.rawValue.dropFirst("intentions.session.".count))
        logger.notice("🔴 MONITOR EXTENSION: Extracted session ID: \(sessionId, privacy: .public)")

        // Validate 5: Check if this session is still the current active session
        guard let currentSessionId = sharedDefaults.string(forKey: "intentions.currentSessionId") else {
            logger.warning("⚠️ MONITOR EXTENSION: No current session ID in UserDefaults - session was cancelled, IGNORING")
            return
        }

        guard currentSessionId == sessionId else {
            logger.warning("⚠️ MONITOR EXTENSION: Session ID mismatch!")
            logger.warning("⚠️   Extension wants to expire: \(sessionId, privacy: .public)")
            logger.warning("⚠️   Current active session: \(currentSessionId, privacy: .public)")
            logger.warning("⚠️ MONITOR EXTENSION: This is an old session - ABORTING, not blocking apps")
            return
        }

        logger.info("✅ MONITOR EXTENSION: Session ID validation passed")
        logger.notice("🎯 MONITOR EXTENSION: ALL VALIDATIONS PASSED - proceeding to block apps")

        sharedDefaults.synchronize()

        // STEP 2: ALL VALIDATIONS PASSED - Now restore blocking
        restoreDefaultBlocking(activitySessionId: sessionId)
    }

    /// Called when a threshold event is reached
    /// This is the PRIMARY mechanism for session expiration - it fires reliably even for short sessions
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        let timestamp = Date()
        logger.error("⚡ MONITOR EXTENSION: eventDidReachThreshold called at \(timestamp, privacy: .public)")
        logger.error("⚡ MONITOR EXTENSION: Event name: \(event.rawValue, privacy: .public)")
        logger.error("⚡ MONITOR EXTENSION: Activity name: \(activity.rawValue, privacy: .public)")

        // STEP 1: VALIDATE BEFORE ACTING
        guard let sharedDefaults = UserDefaults(suiteName: "group.oh.Intent") else {
            logger.error("❌ MONITOR EXTENSION: Cannot access UserDefaults - aborting")
            return
        }

        // Log for debugging
        sharedDefaults.set(timestamp, forKey: "intentions.lastThresholdReached")
        sharedDefaults.set(event.rawValue, forKey: "intentions.lastThresholdEvent")
        sharedDefaults.set(activity.rawValue, forKey: "intentions.lastThresholdActivity")

        let scheduledDuration = sharedDefaults.double(forKey: "intentions.lastScheduledDuration")
        if scheduledDuration > 0 {
            logger.notice("⚡ MONITOR EXTENSION: Scheduled duration was: \(scheduledDuration, privacy: .public) seconds")
        }

        // Validate 1: Check if this is the correct event type
        guard event.rawValue == "intentions.session.threshold" else {
            logger.warning("⚠️ MONITOR EXTENSION: Event does NOT match 'intentions.session.threshold' - IGNORING")
            return
        }

        // Validate 2: Check if this is an Intentions session
        guard activity.rawValue.hasPrefix("intentions.session.") else {
            logger.warning("⚠️ MONITOR EXTENSION: Activity does NOT match 'intentions.session.*' pattern - IGNORING")
            return
        }

        logger.notice("✅ MONITOR EXTENSION: Confirmed this is the session expiration threshold")

        // Validate 3: Extract and validate session ID
        let sessionId = String(activity.rawValue.dropFirst("intentions.session.".count))
        logger.notice("⚡ MONITOR EXTENSION: Extracted session ID: \(sessionId, privacy: .public)")

        // Validate 4: Check if this session is still the current active session
        guard let currentSessionId = sharedDefaults.string(forKey: "intentions.currentSessionId") else {
            logger.warning("⚠️ MONITOR EXTENSION: No current session ID in UserDefaults - session was cancelled, IGNORING")
            return
        }

        guard currentSessionId == sessionId else {
            logger.warning("⚠️ MONITOR EXTENSION: Session ID mismatch!")
            logger.warning("⚠️   Extension wants to expire: \(sessionId, privacy: .public)")
            logger.warning("⚠️   Current active session: \(currentSessionId, privacy: .public)")
            logger.warning("⚠️ MONITOR EXTENSION: This is an old session - ABORTING, not blocking apps")
            return
        }

        logger.info("✅ MONITOR EXTENSION: Session ID validation passed")
        logger.notice("🎯 MONITOR EXTENSION: ALL VALIDATIONS PASSED - proceeding to block apps")

        sharedDefaults.synchronize()

        // STEP 2: ALL VALIDATIONS PASSED - Now restore blocking
        restoreDefaultBlocking(activitySessionId: sessionId)
    }

    /// Called when a monitored application is blocked or unblocked
    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        logger.info("Warning before interval starts for \(activity.rawValue, privacy: .public)")
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        logger.info("Warning before interval ends for \(activity.rawValue, privacy: .public)")
    }

    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        logger.info("Warning before event reaches threshold for \(event.rawValue, privacy: .public)")
    }

    // MARK: - Helper Methods

    /// Restore default blocking - remove session exceptions to block all apps again
    /// - Parameter activitySessionId: The session ID extracted from the activity name
    /// - Note: This method assumes ALL validations have already been performed by the caller
    private func restoreDefaultBlocking(activitySessionId: String) {
        let timestamp = Date()
        logger.notice("🔒 RESTORE BLOCKING: Starting at \(timestamp, privacy: .public)")
        logger.notice("🔒 RESTORE BLOCKING: Activity session ID = \(activitySessionId, privacy: .public)")

        // During session, we used .all(except:tokens) to allow specific apps
        // Now we just need to remove the exception and restore full .all() blocking
        // No need to clear - ManagedSettingsStore is cumulative

        // Block all web content
        logger.info("🔒 RESTORE BLOCKING: Setting webContent.blockedByFilter to .all()")
        store.webContent.blockedByFilter = .all()
        logger.info("🔒 RESTORE BLOCKING: Web content blocking applied")

        // Block all app categories (removing any session exceptions)
        logger.info("🔒 RESTORE BLOCKING: Setting shield.applicationCategories to .all()")
        store.shield.applicationCategories = .all()
        logger.info("🔒 RESTORE BLOCKING: App category blocking applied")

        logger.notice("✅ RESTORE BLOCKING: Default blocking fully restored at \(timestamp, privacy: .public)")

        // Update shared UserDefaults to notify the main app that the session ended
        // This allows the app to update its UI when reopened
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intent") {
            sharedDefaults.set(true, forKey: "intentions.session.expired")
            sharedDefaults.set(timestamp, forKey: "intentions.session.expirationTime")
            sharedDefaults.set("DeviceActivityMonitor", forKey: "intentions.session.expiredBy")

            // CRITICAL: Update widget to show correct state based on schedule
            // Clear session data
            sharedDefaults.removeObject(forKey: "intentions.widget.sessionTitle")
            sharedDefaults.removeObject(forKey: "intentions.widget.sessionEndTime")

            // Determine if we should be blocking based on schedule settings
            let shouldBeBlocking = isCurrentlyInProtectedHours(sharedDefaults: sharedDefaults)
            logger.info("📱 WIDGET UPDATE: Schedule check - shouldBeBlocking = \(shouldBeBlocking)")

            // Set widget blocking status based on schedule
            sharedDefaults.set(shouldBeBlocking, forKey: "intentions.widget.blockingStatus")
            sharedDefaults.set(timestamp, forKey: "intentions.widget.lastUpdate")

            sharedDefaults.synchronize()
            logger.info("✅ RESTORE BLOCKING: Notified main app via UserDefaults")
            logger.info("✅ RESTORE BLOCKING: Updated widget to show blocked state")

            // Reload widget timelines to immediately reflect session expiration
            WidgetCenter.shared.reloadAllTimelines()
            logger.info("📱 WIDGET UPDATE: Reloaded widget timelines after session expiration")

            // Log current state for debugging
            let expiredFlag = sharedDefaults.bool(forKey: "intentions.session.expired")
            let blockingStatus = sharedDefaults.bool(forKey: "intentions.widget.blockingStatus")
            logger.info("✅ RESTORE BLOCKING: Verified UserDefaults - expired flag: \(expiredFlag), blocking: \(blockingStatus)")
        } else {
            logger.error("❌ RESTORE BLOCKING: Failed to access shared UserDefaults!")
        }

        logger.notice("🎉 RESTORE BLOCKING: Complete!")

        // Notify the user that their session has expired
        sendSessionExpiredNotification()
    }

    /// Send a local notification informing the user their session has ended
    private func sendSessionExpiredNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Session Expired"
        content.body = "Your session has ended. Apps are now blocked again."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(
            identifier: "session_expired_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error = error {
                logger.error("Failed to send session expired notification from extension: \(error.localizedDescription)")
            } else {
                logger.info("✅ Session expired notification scheduled from extension")
            }
        }
    }

    /// Check if blocking should be active based on schedule settings.
    /// Blocking is the default state. It is only lifted during free time intervals
    /// stored as a JSON-encoded [FreeTimeIntervalLite] in shared UserDefaults.
    private func isCurrentlyInProtectedHours(sharedDefaults: UserDefaults) -> Bool {
        let isEnabled = sharedDefaults.bool(forKey: "intentions.schedule.isEnabled")
        guard isEnabled else {
            logger.info("📅 SCHEDULE CHECK: Schedule is disabled - not blocking")
            return false
        }

        guard let data = sharedDefaults.data(forKey: "intentions.schedule.intervalsData"),
              let intervals = try? JSONDecoder().decode([FreeTimeIntervalLite].self, from: data) else {
            logger.info("📅 SCHEDULE CHECK: No intervals data — defaulting to blocking")
            return true
        }

        let tzID = sharedDefaults.string(forKey: "intentions.schedule.timeZoneId") ?? TimeZone.current.identifier
        let tz = TimeZone(identifier: tzID) ?? TimeZone.current

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let now = Date()
        let mow = Self.minuteOfWeek(date: now, calendar: calendar)

        let inFree = intervals.contains { interval in
            let start = interval.startMinuteOfWeek
            let end = start + interval.durationMinutes
            if end <= 10080 {
                return mow >= start && mow < end
            } else {
                return mow >= start || mow < (end - 10080)
            }
        }
        return !inFree
    }

    /// Minimal mirror of FreeTimeInterval so the extension target does not have to import the main target.
    private struct FreeTimeIntervalLite: Codable {
        let id: UUID
        let startMinuteOfWeek: Int
        let durationMinutes: Int
    }

    private static func minuteOfWeek(date: Date, calendar: Calendar) -> Int {
        let calendarWeekday = calendar.component(.weekday, from: date)
        let mondayZero: Int
        switch calendarWeekday {
        case 1: mondayZero = 6
        case 2: mondayZero = 0
        case 3: mondayZero = 1
        case 4: mondayZero = 2
        case 5: mondayZero = 3
        case 6: mondayZero = 4
        case 7: mondayZero = 5
        default: mondayZero = 0
        }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return mondayZero * 1440 + hour * 60 + minute
    }
}
