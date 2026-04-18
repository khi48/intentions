//
//  IntentionsApp.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 26/05/25.
//
// =============================================================================
// App/IntentionsApp.swift - Main App Entry Point
// =============================================================================

import SwiftUI
import FamilyControls
@preconcurrency import ManagedSettings
import BackgroundTasks
import UserNotifications
import OSLog

@main
struct IntentApp: App {
    private static let log = Logger(subsystem: "oh.Intent", category: "App")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        // Wake-up path for the DeviceActivity extension's shield-clear
        // hand-off. The extension writes to the shared ManagedSettingsStore,
        // but iOS only re-renders the springboard shield layer when the
        // main app process writes to the store (Apple DTS 807934). This
        // handler runs in the main app process so clearing shields here
        // actually lifts the lock screen visually.
        .backgroundTask(.appRefresh(AppConstants.BackgroundTasks.shieldClearIdentifier)) {
            await IntentApp.performShieldClearBackgroundTask()
        }
    }

    /// Background handler body. Intentionally standalone (no view-model
    /// access) so it can run without spinning up the full app UI.
    ///
    /// - Clears ManagedSettings shield entries from the main app process
    ///   (this is the only state change that makes the springboard
    ///   re-evaluate its shield layer).
    /// - Consumes the `intentions.shieldClear.pending` shared marker.
    /// - Cancels the fallback notification scheduled by the extension.
    /// - Re-applies default blocking based on the persisted schedule so
    ///   that if we somehow wake back up inside a blocked window we
    ///   don't leave apps open.
    private static func performShieldClearBackgroundTask() async {
        log.notice("🌀 BGTASK: shield-clear handler starting")

        // 1. Clear ManagedSettings entries. Using clearAllSettings() first
        //    because project_stale_shield_state.md calls out that per-key
        //    nilling alone can leave the cache stale.
        let store = ManagedSettingsStore()
        store.clearAllSettings()
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        store.webContent.blockedByFilter = nil

        // 2. Drain the shared marker and cancel the fallback notification.
        if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
            sharedDefaults.removeObject(forKey: AppConstants.Keys.shieldClearPending)
            sharedDefaults.removeObject(forKey: AppConstants.Keys.shieldClearRequestedAt)
            sharedDefaults.set(false, forKey: AppConstants.Keys.widgetBlockingStatus)
            sharedDefaults.set(Date(), forKey: AppConstants.Keys.widgetLastUpdate)
            sharedDefaults.synchronize()
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [AppConstants.BackgroundTasks.shieldClearFallbackNotificationId]
        )

        // 3. If the schedule currently says we SHOULD be blocking (e.g. user
        //    re-enabled it between extension fire and BGTask run), re-apply
        //    category blocking. Otherwise leave shields clear.
        if shouldReblockPerSchedule() {
            log.notice("🌀 BGTASK: schedule says block — re-applying category shields")
            store.webContent.blockedByFilter = .all()
            store.shield.applicationCategories = .all()
        } else {
            log.notice("🌀 BGTASK: schedule says free — leaving shields clear")
        }

        log.notice("✅ BGTASK: shield-clear handler complete")
    }

    /// Mirror of `isCurrentlyInProtectedHours` from the DeviceActivity
    /// extension. Kept inline here to avoid cross-target imports; logic is
    /// the same (JSON-encoded [FreeTimeIntervalLite] in shared defaults).
    private static func shouldReblockPerSchedule() -> Bool {
        guard let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) else {
            return true // fail safe
        }
        let isEnabled = sharedDefaults.bool(forKey: AppConstants.Keys.scheduleIsEnabled)
        guard isEnabled else { return false }

        guard let data = sharedDefaults.data(forKey: AppConstants.Keys.scheduleIntervalsData),
              let intervals = try? JSONDecoder().decode([BGShieldClearInterval].self, from: data) else {
            return true
        }

        let tzID = sharedDefaults.string(forKey: AppConstants.Keys.scheduleTimeZoneId) ?? TimeZone.current.identifier
        let tz = TimeZone(identifier: tzID) ?? TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let now = Date()
        let mow = minuteOfWeek(date: now, calendar: calendar)

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

/// Tiny mirror of FreeTimeInterval for decoding inside the BGTask handler
/// without pulling the full WeeklySchedule type into the early-launch path.
private struct BGShieldClearInterval: Codable, Sendable {
    let id: UUID
    let startMinuteOfWeek: Int
    let durationMinutes: Int
}
