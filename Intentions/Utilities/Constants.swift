//
//  Constants.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/07/2025.
//

import Foundation
import SwiftUI

enum AppConstants {

    // MARK: - App Group

    static let appGroupId = SharedConstants.appGroupId

    // MARK: - UserDefaults Keys

    enum Keys {
        // Widget (shared with widget extension via SharedConstants)
        static let widgetBlockingStatus = SharedConstants.WidgetKeys.blockingStatus
        static let widgetLastUpdate = SharedConstants.WidgetKeys.lastUpdate
        static let widgetSessionTitle = SharedConstants.WidgetKeys.sessionTitle
        static let widgetSessionEndTime = SharedConstants.WidgetKeys.sessionEndTime

        // Session
        static let currentSessionId = "intentions.currentSessionId"
        static let sessionExpired = "intentions.session.expired"
        static let sessionExpirationTime = "intentions.session.expirationTime"
        static let sessionExpiredBy = "intentions.session.expiredBy"

        // Schedule
        static let scheduleIsEnabled = "intentions.schedule.isEnabled"
        static let scheduleStartHour = "intentions.schedule.startHour"
        static let scheduleEndHour = "intentions.schedule.endHour"
        static let scheduleActiveDays = "intentions.schedule.activeDays"

        // DeviceActivity
        static let lastScheduledActivity = "intentions.lastScheduledActivity"
        static let lastScheduledEndTime = "intentions.lastScheduledEndTime"
        static let lastScheduleTime = "intentions.lastScheduleTime"
        static let lastScheduledDuration = "intentions.lastScheduledDuration"

        // Activity naming
        static let sessionActivityPrefix = "intentions.session."
        static let sessionThresholdEvent = "intentions.session.threshold"
    }
    
    // MARK: - Session Management
    enum Session {
        /// Default session duration (5 minutes)
        static let defaultDuration: TimeInterval = 5 * 60

        /// Minimum allowed session duration (1 minute)
        static let minimumDuration: TimeInterval = 1 * 60

        /// Maximum allowed session duration (2 hours)
        static let maximumDuration: TimeInterval = 2 * 60 * 60
        
        /// Warning notification intervals before session expiry
        static let warningIntervals: [TimeInterval] = [5 * 60, 1 * 60] // 5min, 1min
        
        /// Available preset durations for quick selection
        static let presetDurations: [TimeInterval] = [
            5 * 60,     // 5 minutes
            15 * 60,    // 15 minutes
            30 * 60,    // 30 minutes
            60 * 60,    // 1 hour
            2 * 60 * 60 // 2 hours
        ]
    }
    
    // MARK: - Schedule Settings
    enum Schedule {
        /// Default start hour (6 AM)
        static let defaultStartHour: Int = 6

        /// Default end hour (10 PM)
        static let defaultEndHour: Int = 22
        
        /// Valid hour range for scheduling
        static let validHourRange: ClosedRange<Int> = 0...23
        
        /// Default timezone (current system timezone)
        static var defaultTimeZone: TimeZone { TimeZone.current }
    }
    
    // MARK: - Time Conversion
    enum Time {
        /// Nanoseconds per second for Task.sleep()
        static let nanosPerSecond: UInt64 = 1_000_000_000
        
        /// Seconds per minute
        static let secondsPerMinute: TimeInterval = 60
        
        /// Minutes per hour
        static let minutesPerHour: TimeInterval = 60
        
        /// Hours per day
        static let hoursPerDay: TimeInterval = 24
    }
    
    // MARK: - App Group Management
    enum AppGroup {
        /// Maximum allowed name length
        static let maxNameLength: Int = 50
        
        /// Minimum required name length
        static let minNameLength: Int = 1
        
        /// Maximum number of apps per group
        static let maxAppsPerGroup: Int = 100
        
        /// Reserved group names that cannot be used
        static let reservedNames: Set<String> = [
            "System",
            "Essential",
            "Emergency",
            "All Apps"
        ]
    }
    
    // MARK: - Data Management
    enum DataCleanup {
        /// Number of days to retain old sessions
        static let sessionRetentionDays: Int = 7
        
        /// Time interval for session retention (7 days)
        static let retentionInterval: TimeInterval = 24 * 60 * 60 * 7
        
        /// Frequency of automatic cleanup operations
        static let cleanupFrequency: TimeInterval = 24 * 60 * 60 // Daily
    }
    
    // MARK: - User Interface
    enum UI {
        /// Animation duration for standard transitions
        static let standardAnimationDuration: TimeInterval = 0.3
        
        /// Animation duration for quick feedback
        static let quickAnimationDuration: TimeInterval = 0.15
        
        /// Haptic feedback delay
        static let hapticFeedbackDelay: TimeInterval = 0.05
        
        /// Default corner radius for cards
        static let cornerRadius: CGFloat = 12
        
        /// Standard padding for UI elements
        static let standardPadding: CGFloat = 16
    }
    
    // MARK: - Network & Performance
    enum Performance {
        /// Maximum concurrent app discovery operations
        static let maxConcurrentDiscovery: Int = 3
        
        /// Timeout for Screen Time operations
        static let screenTimeTimeout: TimeInterval = 10
        
        /// Cache refresh interval for app discovery
        static let appDiscoveryCacheInterval: TimeInterval = 60 * 60 // 1 hour
    }
    
    // MARK: - CloudKit & Storage
    enum Storage {
        /// CloudKit database name
        static let cloudKitDatabase = "IntentAppDatabase"

        /// UserDefaults key prefix
        static let userDefaultsPrefix = "intent."
        
        /// Maximum file size for exports
        static let maxExportFileSize: Int = 10 * 1024 * 1024 // 10MB
    }
    
    // MARK: - Notifications
    enum Notifications {
        /// Identifier for session warning notifications
        static let sessionWarningIdentifier = "session.warning"
        
        /// Identifier for session expiry notifications
        static let sessionExpiryIdentifier = "session.expired"
        
        /// Notification category for session management
        static let sessionCategory = "SESSION_MANAGEMENT"
    }

    // MARK: - Color Scheme
    enum Colors {
        /// Primary background color (very dark grey, not black)
        static let background = Color(red: 0.08, green: 0.08, blue: 0.08)

        /// Secondary background color (dark grey)
        static let backgroundSecondary = Color(red: 0.12, green: 0.12, blue: 0.12)

        /// Card/surface background color (darker for better contrast)
        static let surface = Color(red: 0.15, green: 0.15, blue: 0.15)

        /// Primary text color (white)
        static let text = Color.white

        /// Secondary text color (light grey)
        static let textSecondary = Color(red: 0.6, green: 0.6, blue: 0.6)

        /// Accent color for buttons and highlights
        static let accent = Color(red: 0.7, green: 0.7, blue: 0.7)

        /// Destructive action color (light grey for monochrome)
        static let destructive = Color(red: 0.7, green: 0.7, blue: 0.7)

        /// Success/positive action color (light grey)
        static let positive = Color(red: 0.7, green: 0.7, blue: 0.7)

        /// Border and separator color (medium dark grey)
        static let border = Color(red: 0.25, green: 0.25, blue: 0.25)

        /// Disabled state color (medium grey)
        static let disabled = Color(red: 0.4, green: 0.4, blue: 0.4)

        /// Tab bar icon color (lighter for better visibility)
        static let tabBarIcon = Color(red: 0.8, green: 0.8, blue: 0.8)

        /// Button background for primary actions
        static let buttonPrimary = Color(red: 0.3, green: 0.3, blue: 0.3)
    }
}

// MARK: - Convenience Extensions
extension TimeInterval {
    /// Convert seconds to nanoseconds for Task.sleep()
    var nanoseconds: UInt64 {
        UInt64(self * Double(AppConstants.Time.nanosPerSecond))
    }
    
    /// Format time interval as duration string (e.g., "5m", "1h 30m")
    var formattedDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        } else {
            return "\(minutes)m"
        }
    }
}

extension String {
    /// UserDefaults key with app prefix
    var prefixedKey: String {
        AppConstants.Storage.userDefaultsPrefix + self
    }
}
