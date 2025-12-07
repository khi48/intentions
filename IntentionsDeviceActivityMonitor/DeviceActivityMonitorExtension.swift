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
        print("📱 DeviceActivityMonitor: Warning before interval starts for \(activity)")
    }

    /// Called when a monitored application is blocked or unblocked
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        print("📱 DeviceActivityMonitor: Warning before interval ends for \(activity)")

        // Could be used to show user notification that session is about to end
    }

    /// Called when an event is about to reach its threshold
    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        print("📱 DeviceActivityMonitor: Warning before event reaches threshold for \(event)")
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
    }

    /// Check if current time is within protected hours based on schedule settings
    private func isCurrentlyInProtectedHours(sharedDefaults: UserDefaults) -> Bool {
        // Read schedule settings from UserDefaults
        let isEnabled = sharedDefaults.bool(forKey: "intentions.schedule.isEnabled")
        guard isEnabled else {
            logger.info("📅 SCHEDULE CHECK: Schedule is disabled - not blocking")
            return false
        }

        let startHour = sharedDefaults.integer(forKey: "intentions.schedule.startHour")
        let endHour = sharedDefaults.integer(forKey: "intentions.schedule.endHour")
        let activeDaysIntegers = sharedDefaults.array(forKey: "intentions.schedule.activeDays") as? [Int] ?? []

        let now = Date()
        let calendar = Calendar.current

        // Check day of week
        let weekdayComponent = calendar.component(.weekday, from: now)
        let dayMatches = activeDaysIntegers.contains(weekdayComponent)

        // Check hour
        let hour = calendar.component(.hour, from: now)
        let hourMatches = (startHour...endHour).contains(hour)

        let isActive = dayMatches && hourMatches

        logger.info("📅 SCHEDULE CHECK: enabled=\(isEnabled), day=\(weekdayComponent), dayMatches=\(dayMatches), hour=\(hour), hourMatches=\(hourMatches), isActive=\(isActive)")

        return isActive
    }
}
