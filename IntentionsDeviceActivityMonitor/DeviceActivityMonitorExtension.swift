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

/// Monitor extension that handles session expiration events
/// This runs even when the main app is not active
/// IMPORTANT: Class name must match NSExtensionPrincipalClass in Info.plist
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    let store = ManagedSettingsStore()

    /// Called when a scheduled interval starts
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        let timestamp = Date()
        print("🟢 MONITOR EXTENSION: intervalDidStart called at \(timestamp)")
        print("🟢 MONITOR EXTENSION: Activity name: \(activity.rawValue)")

        // Log to shared UserDefaults for debugging
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions") {
            sharedDefaults.set(timestamp, forKey: "intentions.lastIntervalStart")
            sharedDefaults.set(activity.rawValue, forKey: "intentions.lastIntervalStartActivity")
            sharedDefaults.synchronize()
            print("🟢 MONITOR EXTENSION: Logged start to UserDefaults")
        }
    }

    /// Called when a scheduled interval ends
    /// This is where we restore default blocking when the session expires
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        let timestamp = Date()
        print("🔴 MONITOR EXTENSION: intervalDidEnd called at \(timestamp)")
        print("🔴 MONITOR EXTENSION: Activity name: \(activity.rawValue)")

        // Log to shared UserDefaults for debugging
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions") {
            sharedDefaults.set(timestamp, forKey: "intentions.lastIntervalEnd")
            sharedDefaults.set(activity.rawValue, forKey: "intentions.lastIntervalEndActivity")

            // Check what was scheduled
            if let scheduledActivity = sharedDefaults.string(forKey: "intentions.lastScheduledActivity") {
                print("🔴 MONITOR EXTENSION: Expected activity: \(scheduledActivity)")
                print("🔴 MONITOR EXTENSION: Actual activity: \(activity.rawValue)")
                print("🔴 MONITOR EXTENSION: Match: \(scheduledActivity == activity.rawValue)")
            }

            if let scheduledEndTime = sharedDefaults.object(forKey: "intentions.lastScheduledEndTime") as? Date {
                print("🔴 MONITOR EXTENSION: Scheduled end time was: \(scheduledEndTime)")
                let delay = timestamp.timeIntervalSince(scheduledEndTime)
                print("🔴 MONITOR EXTENSION: Triggered \(delay) seconds after scheduled time")
            }

            sharedDefaults.synchronize()
        }

        // Check if this is an Intentions session that ended
        if activity.rawValue.hasPrefix("intentions.session.") {
            print("🔴 MONITOR EXTENSION: Confirmed this is an Intentions session")

            // Extract session ID from activity name (format: "intentions.session.{UUID}")
            let sessionId = String(activity.rawValue.dropFirst("intentions.session.".count))
            print("🔴 MONITOR EXTENSION: Extracted session ID: \(sessionId)")

            // Restore default blocking state with validation
            restoreDefaultBlocking(activitySessionId: sessionId)
        } else {
            print("⚠️ MONITOR EXTENSION: Activity name does NOT match intentions.session.* pattern")
        }
    }

    /// Called when a threshold event is reached
    /// This is the PRIMARY mechanism for session expiration - it fires reliably even for short sessions
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        let timestamp = Date()
        print("⚡ MONITOR EXTENSION: eventDidReachThreshold called at \(timestamp)")
        print("⚡ MONITOR EXTENSION: Event name: \(event.rawValue)")
        print("⚡ MONITOR EXTENSION: Activity name: \(activity.rawValue)")

        // Log to shared UserDefaults for debugging
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions") {
            sharedDefaults.set(timestamp, forKey: "intentions.lastThresholdReached")
            sharedDefaults.set(event.rawValue, forKey: "intentions.lastThresholdEvent")
            sharedDefaults.set(activity.rawValue, forKey: "intentions.lastThresholdActivity")

            // Check what was scheduled
            let scheduledDuration = sharedDefaults.double(forKey: "intentions.lastScheduledDuration")
            if scheduledDuration > 0 {
                print("⚡ MONITOR EXTENSION: Scheduled duration was: \(scheduledDuration) seconds")
            }

            sharedDefaults.synchronize()
        }

        // Check if this is the Intentions session expiration threshold
        if event.rawValue == "intentions.session.threshold" && activity.rawValue.hasPrefix("intentions.session.") {
            print("⚡ MONITOR EXTENSION: Confirmed this is the session expiration threshold!")

            // Extract session ID from activity name (format: "intentions.session.{UUID}")
            let sessionId = String(activity.rawValue.dropFirst("intentions.session.".count))
            print("⚡ MONITOR EXTENSION: Extracted session ID: \(sessionId)")

            // Restore default blocking state with validation
            restoreDefaultBlocking(activitySessionId: sessionId)
        } else {
            print("⚠️ MONITOR EXTENSION: Event name does NOT match expected threshold pattern")
        }
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
    private func restoreDefaultBlocking(activitySessionId: String) {
        let timestamp = Date()
        print("🔒 RESTORE BLOCKING: Starting at \(timestamp)")
        print("🔒 RESTORE BLOCKING: Activity session ID = \(activitySessionId)")

        // CRITICAL VALIDATION: Check if this session is still the current active session
        // If the session has been replaced, we should NOT block apps
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions") {
            if let currentSessionId = sharedDefaults.string(forKey: "intentions.currentSessionId") {
                print("🔒 RESTORE BLOCKING: Current session ID from UserDefaults = \(currentSessionId)")

                if currentSessionId != activitySessionId {
                    print("⚠️ RESTORE BLOCKING: Session ID mismatch! This is an OLD session - SKIPPING blocking")
                    print("⚠️ RESTORE BLOCKING: Activity wants to expire: \(activitySessionId)")
                    print("⚠️ RESTORE BLOCKING: Current active session: \(currentSessionId)")
                    return // Do NOT block - this is an old cancelled session
                } else {
                    print("✅ RESTORE BLOCKING: Session ID matches - proceeding with blocking")
                }
            } else {
                print("⚠️ RESTORE BLOCKING: No current session ID in UserDefaults - session may have been cancelled")
                print("⚠️ RESTORE BLOCKING: SKIPPING blocking to be safe")
                return // Do NOT block - session was cancelled
            }
        } else {
            print("❌ RESTORE BLOCKING: Failed to access shared UserDefaults - cannot validate session")
            return // Do NOT block if we can't validate
        }

        // During session, we used .all(except:tokens) to allow specific apps
        // Now we just need to remove the exception and restore full .all() blocking
        // No need to clear - ManagedSettingsStore is cumulative

        // Block all web content
        print("🔒 RESTORE BLOCKING: Setting webContent.blockedByFilter to .all()")
        store.webContent.blockedByFilter = .all()
        print("🔒 RESTORE BLOCKING: Web content blocking applied")

        // Block all app categories (removing any session exceptions)
        print("🔒 RESTORE BLOCKING: Setting shield.applicationCategories to .all()")
        store.shield.applicationCategories = .all()
        print("🔒 RESTORE BLOCKING: App category blocking applied")

        print("✅ RESTORE BLOCKING: Default blocking fully restored at \(timestamp)")

        // Update shared UserDefaults to notify the main app that the session ended
        // This allows the app to update its UI when reopened
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions") {
            sharedDefaults.set(true, forKey: "intentions.session.expired")
            sharedDefaults.set(timestamp, forKey: "intentions.session.expirationTime")
            sharedDefaults.set("DeviceActivityMonitor", forKey: "intentions.session.expiredBy")
            sharedDefaults.synchronize()
            print("✅ RESTORE BLOCKING: Notified main app via UserDefaults")

            // Log current state for debugging
            let webBlocking = sharedDefaults.bool(forKey: "intentions.session.expired")
            print("✅ RESTORE BLOCKING: Verified UserDefaults - expired flag: \(webBlocking)")
        } else {
            print("❌ RESTORE BLOCKING: Failed to access shared UserDefaults!")
        }

        print("🎉 RESTORE BLOCKING: Complete!")
    }
}
