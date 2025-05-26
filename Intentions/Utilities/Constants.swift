//
//  Constants.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/07/2025.
//

import Foundation

enum AppConstants {
    
    // MARK: - Session Management
    enum Session {
        /// Default session duration (30 minutes)
        static let defaultDuration: TimeInterval = 30 * 60
        
        /// Minimum allowed session duration (5 minutes)
        static let minimumDuration: TimeInterval = 5 * 60
        
        /// Maximum allowed session duration (8 hours)
        static let maximumDuration: TimeInterval = 8 * 60 * 60
        
        /// Warning notification intervals before session expiry
        static let warningIntervals: [TimeInterval] = [5 * 60, 1 * 60] // 5min, 1min
        
        /// Available preset durations for quick selection
        static let presetDurations: [TimeInterval] = [
            15 * 60,    // 15 minutes
            30 * 60,    // 30 minutes
            60 * 60,    // 1 hour
            2 * 60 * 60, // 2 hours
            4 * 60 * 60  // 4 hours
        ]
    }
    
    // MARK: - Schedule Settings
    enum Schedule {
        /// Default active hours (6 AM to 10 PM)
        static let defaultActiveHours: ClosedRange<Int> = 6...22
        
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
        static let cloudKitDatabase = "IntentionsAppDatabase"
        
        /// UserDefaults key prefix
        static let userDefaultsPrefix = "intentions."
        
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
}

// MARK: - Convenience Extensions
extension TimeInterval {
    /// Convert seconds to nanoseconds for Task.sleep()
    var nanoseconds: UInt64 {
        UInt64(self * Double(AppConstants.Time.nanosPerSecond))
    }
    
    /// Format time interval as MM:SS string
    var formattedMinutesSeconds: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Format time interval as HH:MM string
    var formattedHoursMinutes: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}

extension String {
    /// UserDefaults key with app prefix
    var prefixedKey: String {
        AppConstants.Storage.userDefaultsPrefix + self
    }
}
