//
//  AppError.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//


// =============================================================================
// Models/AppError.swift - Shared Error Types
// =============================================================================

import Foundation

enum AppError: LocalizedError, Sendable, Equatable {
    case screenTimeAuthorizationFailed
    case screenTimeAuthorizationRequired(String)
    case screenTimeNotAvailable
    case appBlockingFailed(String)
    case sessionExpired
    case sessionNotFound
    case dataNotFound(String)
    case invalidConfiguration(String)
    case persistenceError(String)
    case appDiscoveryFailed(String)
    case timerError(String)
    
    var errorDescription: String? {
        switch self {
        case .screenTimeAuthorizationFailed:
            return String(localized: "Screen Time authorization was denied. Please enable it in Settings to use Intent.", comment: "Error when the user denies Screen Time permission")
        case .screenTimeAuthorizationRequired(let message):
            return message
        case .screenTimeNotAvailable:
            return String(localized: "Screen Time is not available on this device.", comment: "Error when Screen Time framework is unavailable (e.g. unsupported device)")
        case .appBlockingFailed(let details):
            return String(localized: "Failed to block apps: \(details).", comment: "Error when Screen Time blocking fails; placeholder is system error detail")
        case .sessionExpired:
            return String(localized: "Your session has expired and apps have been locked.", comment: "Error shown after a focus session ends and blocking resumes")
        case .sessionNotFound:
            return String(localized: "Could not find the active session.", comment: "Error when lookup of the current active session returns nothing")
        case .dataNotFound(let item):
            return String(localized: "Could not find \(item). It may have been deleted.", comment: "Error when a stored item cannot be loaded; placeholder is item type name")
        case .invalidConfiguration(let details):
            return String(localized: "Invalid configuration: \(details).", comment: "Error when a configuration value is invalid; placeholder is internal reason")
        case .persistenceError(let details):
            return String(localized: "Failed to save data: \(details).", comment: "Error when saving to persistent storage fails; placeholder is system error detail")
        case .appDiscoveryFailed(let details):
            return String(localized: "Failed to discover apps: \(details).", comment: "Error when listing installed apps fails; placeholder is system error detail")
        case .timerError(let details):
            return String(localized: "Timer error: \(details).", comment: "Error from the session countdown timer; placeholder is internal reason")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .screenTimeAuthorizationFailed:
            return String(localized: "Go to Settings > Screen Time > Content & Privacy Restrictions and enable access for Intent.", comment: "Recovery suggestion after Screen Time permission is denied")
        case .screenTimeAuthorizationRequired:
            return String(localized: "Please grant Screen Time permissions to use this feature.", comment: "Recovery suggestion when an action requires Screen Time permission")
        case .screenTimeNotAvailable:
            return String(localized: "This app requires iOS 16.0 or later with Screen Time support.", comment: "Recovery suggestion when device does not support Screen Time")
        case .appBlockingFailed:
            return String(localized: "Try restarting the app or check Screen Time settings.", comment: "Recovery suggestion when Screen Time blocking fails")
        case .sessionExpired:
            return String(localized: "Start a new session to access apps again.", comment: "Recovery suggestion after a focus session ends")
        case .sessionNotFound:
            return String(localized: "Start a new session from the main screen.", comment: "Recovery suggestion when the active session lookup fails")
        case .dataNotFound:
            return String(localized: "Try refreshing or recreating the item.", comment: "Recovery suggestion when a stored item is missing")
        case .invalidConfiguration:
            return String(localized: "Check your settings and try again.", comment: "Recovery suggestion when configuration is invalid")
        case .persistenceError:
            return String(localized: "Ensure the app has permission to store data and try again.", comment: "Recovery suggestion when persistence fails")
        case .appDiscoveryFailed:
            return String(localized: "Try refreshing the app list or restarting the app.", comment: "Recovery suggestion when app discovery fails")
        case .timerError:
            return String(localized: "Try starting a new session.", comment: "Recovery suggestion after a timer error")
        }
    }
}

// MARK: - Error Factory Methods
extension AppError {
    static func dataInitializationFailed(_ details: String) -> AppError {
        .invalidConfiguration("Data initialization failed: \(details)")
    }
    
    static func validationFailed(_ field: String, reason: String) -> AppError {
        .invalidConfiguration("Validation failed for \(field): \(reason)")
    }
    
    static func serviceUnavailable(_ serviceName: String) -> AppError {
        .invalidConfiguration("\(serviceName) is not available or not initialized")
    }
    
    static func operationTimeout(_ operation: String) -> AppError {
        .invalidConfiguration("\(operation) operation timed out")
    }
}

// MARK: - Error Context Extensions
extension AppError {
    /// Returns whether this error suggests the user should retry the operation
    var isRetryable: Bool {
        switch self {
        case .appBlockingFailed, .persistenceError, .appDiscoveryFailed, .timerError:
            return true
        case .screenTimeAuthorizationFailed, .screenTimeAuthorizationRequired, .screenTimeNotAvailable, .invalidConfiguration:
            return false
        case .sessionExpired, .sessionNotFound, .dataNotFound:
            return false
        }
    }
    
    /// Returns the appropriate log level for this error
    var logLevel: LogLevel {
        switch self {
        case .screenTimeAuthorizationFailed, .screenTimeAuthorizationRequired, .screenTimeNotAvailable:
            return .warning
        case .sessionExpired, .sessionNotFound:
            return .info
        case .dataNotFound:
            return .info
        case .invalidConfiguration, .appBlockingFailed, .persistenceError, .appDiscoveryFailed, .timerError:
            return .error
        }
    }
}

// MARK: - Supporting Types
enum LogLevel {
    case info, warning, error
}

// =============================================================================
// Supporting Types
// =============================================================================

// `Weekday` moved to `ShieldState/Weekday.swift` so both the main app and the
// DeviceActivityMonitor extension can share the type.
