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
            return "Screen Time authorization was denied. Please enable it in Settings to use Intent."
        case .screenTimeAuthorizationRequired(let message):
            return message
        case .screenTimeNotAvailable:
            return "Screen Time is not available on this device."
        case .appBlockingFailed(let details):
            return "Failed to block apps: \(details)."
        case .sessionExpired:
            return "Your session has expired and apps have been locked."
        case .sessionNotFound:
            return "Could not find the active session."
        case .dataNotFound(let item):
            return "Could not find \(item). It may have been deleted."
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)."
        case .persistenceError(let details):
            return "Failed to save data: \(details)."
        case .appDiscoveryFailed(let details):
            return "Failed to discover apps: \(details)."
        case .timerError(let details):
            return "Timer error: \(details)."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .screenTimeAuthorizationFailed:
            return "Go to Settings > Screen Time > Content & Privacy Restrictions and enable access for Intent."
        case .screenTimeAuthorizationRequired:
            return "Please grant Screen Time permissions to use this feature."
        case .screenTimeNotAvailable:
            return "This app requires iOS 16.0 or later with Screen Time support."
        case .appBlockingFailed:
            return "Try restarting the app or check Screen Time settings."
        case .sessionExpired:
            return "Start a new session to access apps again."
        case .sessionNotFound:
            return "Start a new session from the main screen."
        case .dataNotFound:
            return "Try refreshing or recreating the item."
        case .invalidConfiguration:
            return "Check your settings and try again."
        case .persistenceError:
            return "Ensure the app has permission to store data and try again."
        case .appDiscoveryFailed:
            return "Try refreshing the app list or restarting the app."
        case .timerError:
            return "Try starting a new session."
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

enum Weekday: String, CaseIterable, Codable, Sendable {
    case sunday = "Sunday"
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
    
    static func from(calendarWeekday: Int) -> Weekday {
        switch calendarWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .sunday
        }
    }
    
    var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }
    
    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }
    
    var displayName: String {
        return rawValue
    }
}
