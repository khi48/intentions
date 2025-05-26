// Models/ScreenTimeStatusInfo.swift
// Supporting Types for Screen Time Service

import Foundation
@preconcurrency import FamilyControls

/// Status information for the Screen Time service
struct ScreenTimeStatusInfo: Sendable {
    let authorizationStatus: AuthorizationStatus
    let currentlyAllowedAppsCount: Int
    let essentialSystemAppsCount: Int
    let hasActiveSession: Bool
    let isInitialized: Bool
    
    var isFullyOperational: Bool {
        return authorizationStatus == .approved && isInitialized
    }
    
    var statusDescription: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Authorization not requested"
        case .denied:
            return "Authorization denied by user"
        case .approved:
            return isInitialized ?
                "Fully operational - \(currentlyAllowedAppsCount) apps allowed" :
                "Authorized but not initialized"
        @unknown default:
            return "Unknown authorization status"
        }
    }
}
