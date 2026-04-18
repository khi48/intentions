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
import BackgroundTasks
import UserNotifications
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

        // Log to shared UserDefaults for debugging + clear stale end-of-previous-session
        // flags so the NEW session's intervalDidEnd is not suppressed by the
        // "already handled" dedupe guard.
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intent") {
            sharedDefaults.set(timestamp, forKey: "intentions.lastIntervalStart")
            sharedDefaults.set(activity.rawValue, forKey: "intentions.lastIntervalStartActivity")
            sharedDefaults.set(false, forKey: "intentions.session.expired")
            sharedDefaults.removeObject(forKey: "intentions.session.expiredBy")
            sharedDefaults.synchronize()
            logger.info("🟢 MONITOR EXTENSION: Logged start to UserDefaults; cleared dedupe flag")
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

    /// Restore default blocking - either re-apply full blocking (if we're inside
    /// protected hours) OR clear shields (if the user is currently in a free
    /// window / has disabled the schedule entirely).
    ///
    /// - Parameter activitySessionId: The session ID extracted from the activity name
    /// - Note: This method assumes ALL validations have already been performed by the caller
    ///
    /// Why the branch matters: when blocking is disabled and a session ends, iOS
    /// will NOT re-render the springboard shield layer if only this extension
    /// process writes shield removal to the shared store (Apple DTS 807934). We
    /// therefore also (a) raise a shared marker, (b) submit a BGAppRefresh task
    /// so the main app can clear shields from its own process, and (c) schedule
    /// a user-tap fallback notification.
    private func restoreDefaultBlocking(activitySessionId: String) {
        let timestamp = Date()
        logger.notice("🔒 RESTORE BLOCKING: Starting at \(timestamp, privacy: .public)")
        logger.notice("🔒 RESTORE BLOCKING: Activity session ID = \(activitySessionId, privacy: .public)")

        guard let sharedDefaults = UserDefaults(suiteName: "group.oh.Intent") else {
            logger.error("❌ RESTORE BLOCKING: Failed to access shared UserDefaults!")
            return
        }

        // Check schedule to determine correct post-session state
        let shouldBeBlocking = isCurrentlyInProtectedHours(sharedDefaults: sharedDefaults)
        logger.notice("🔒 RESTORE BLOCKING: Schedule check - shouldBeBlocking = \(shouldBeBlocking)")

        if shouldBeBlocking {
            // Re-block path must always run. Direct overwrite replaces the session's
            // `.all(except: tokens)` with `.all()`. Do NOT call clearAllSettings()
            // here — it creates a brief no-shields window that detaches the custom
            // ShieldConfiguration extension binding.
            logger.notice("🔒 RESTORE BLOCKING: In protected hours - blocking all apps")
            store.shield.applications = nil
            store.shield.applicationCategories = .all()
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = .all()
        } else {
            // Session ended OUTSIDE protected hours — clear shields and hand off
            // to the main app. Extension-only writes to ManagedSettingsStore do
            // NOT cause the springboard shield layer to re-render (Apple DTS 807934);
            // only the main app process writing does.
            logger.notice("🔒 RESTORE BLOCKING: Clearing all shields (schedule disabled or free time)")
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            store.webContent.blockedByFilter = nil
            store.clearAllSettings()

            // Write the shared marker so the app can honor it on foreground reconcile too.
            sharedDefaults.set(true, forKey: "intentions.shieldClear.pending")
            sharedDefaults.set(timestamp, forKey: "intentions.shieldClear.requestedAt")

            // Wake the main app via BGAppRefresh so it can clear the store from its own
            // process — the only write that actually re-renders the springboard.
            submitShieldClearBackgroundTask()

            // Schedule a user-tap fallback notification. If the BGTask fires
            // within its grace period, the app cancels this pending request.
            scheduleShieldClearFallbackNotification()
        }

        // App-side bookkeeping for the reconcile-on-foreground path.
        sharedDefaults.set(true, forKey: "intentions.session.expired")
        sharedDefaults.set(timestamp, forKey: "intentions.session.expirationTime")
        sharedDefaults.set("DeviceActivityMonitor", forKey: "intentions.session.expiredBy")
        sharedDefaults.removeObject(forKey: "intentions.currentSessionId")
        sharedDefaults.removeObject(forKey: "intentions.widget.sessionTitle")
        sharedDefaults.removeObject(forKey: "intentions.widget.sessionEndTime")
        sharedDefaults.set(shouldBeBlocking, forKey: "intentions.widget.blockingStatus")
        sharedDefaults.set(timestamp, forKey: "intentions.widget.lastUpdate")
        sharedDefaults.synchronize()

        WidgetCenter.shared.reloadAllTimelines()
        logger.notice("✅ RESTORE BLOCKING: Applied post-session state, widgetBlocking=\(shouldBeBlocking)")

        // Notification is handled by the app-scheduled UNTimeIntervalNotificationTrigger
        // (`session_completion_<id>`) which fires reliably at the exact expire time.
        // Scheduling a second notification here produced duplicates.

        logger.notice("🎉 RESTORE BLOCKING: Complete!")
    }

    /// Submit a BGAppRefreshTaskRequest so iOS can wake the main app and have
    /// IT clear shield state from its own process. Extension-only store
    /// writes do NOT cause the springboard shield layer to re-render.
    private func submitShieldClearBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: "oh.Intent.shieldClear")
        // earliestBeginDate = nil runs ASAP subject to iOS discretion.
        request.earliestBeginDate = nil
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("🌀 BGTASK: Submitted oh.Intent.shieldClear request")
        } catch {
            // Extension still cleared the store; nothing more to do if submit
            // fails. The foreground reconcile marker + fallback notification
            // still cover this case.
            logger.error("❌ BGTASK: submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Schedule a visible fallback notification. If the BGTask runs first,
    /// the app cancels this request before it fires.
    private func scheduleShieldClearFallbackNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Apps unlocked"
        content.body = "Tap to finish clearing the lock screen."
        content.sound = nil
        content.interruptionLevel = .active

        // 30s gives BGTask a chance to run first under normal device conditions.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30.0, repeats: false)
        let request = UNNotificationRequest(
            identifier: "shield_clear_fallback",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error = error {
                logger.error("Failed to schedule shield-clear fallback notification: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("🛎️ FALLBACK: Scheduled shield-clear fallback notification")
            }
        }
    }

    /// Check if blocking should be active based on schedule settings.
    /// Blocking is the default state. It is only lifted during free time intervals
    /// stored as a JSON-encoded [FreeTimeIntervalLite] in shared UserDefaults.
    private func isCurrentlyInProtectedHours(sharedDefaults: UserDefaults) -> Bool {
        let isEnabled = sharedDefaults.bool(forKey: "intentions.schedule.isEnabled")
        guard isEnabled else {
            logger.notice("📅 SCHEDULE CHECK: Schedule is disabled (isEnabled=false) - not blocking")
            return false
        }

        guard let data = sharedDefaults.data(forKey: "intentions.schedule.intervalsData"),
              let intervals = try? JSONDecoder().decode([FreeTimeIntervalLite].self, from: data) else {
            logger.notice("📅 SCHEDULE CHECK: No intervals data — defaulting to blocking")
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
