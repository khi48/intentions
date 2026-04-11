// Protocols/ScreenTimeManaging.swift
// Screen Time Service Protocol Definition

import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Protocol defining the interface for Screen Time management operations
protocol ScreenTimeManaging: Sendable {
    /// Request authorization from the user to use Family Controls
    /// - Returns: True if authorization was granted, false otherwise
    func requestAuthorization() async -> Bool
    
    /// Check current authorization status
    /// - Returns: Current authorization status
    func authorizationStatus() async -> AuthorizationStatus
    
    /// Block all non-essential apps by default
    /// - Throws: AppError if blocking fails
    func blockAllApps() async throws
    
    /// Allow specific apps for a limited duration
    /// - Parameters:
    ///   - tokens: Set of ApplicationTokens to allow
    ///   - allowWebsites: Whether to allow access to all websites (default false)
    ///   - duration: How long to allow access (in seconds)
    ///   - sessionId: UUID of the session for tracking and validation
    /// - Throws: AppError if allowing apps fails
    func allowApps(_ tokens: sending Set<ApplicationToken>, webDomains: Set<WebDomainToken>, allowWebsites: Bool, duration: TimeInterval, sessionId: UUID) async throws
    
    /// Get currently allowed apps
    /// - Returns: Set of ApplicationTokens that are currently allowed
    func getCurrentlyAllowedApps() async -> Set<ApplicationToken>
    
    /// Allow access to all apps (remove all restrictions)
    /// - Throws: AppError if allowing access fails
    func allowAllAccess() async throws
    
    /// Check if a specific app is currently allowed
    /// - Parameter token: ApplicationToken to check
    /// - Returns: True if the app is currently allowed
    func isAppAllowed(_ token: sending ApplicationToken) async -> Bool
    
    /// Get system apps that should never be blocked (Phone, Messages, etc.)
    /// - Returns: Set of essential system app tokens
    func getEssentialSystemApps() async -> Set<ApplicationToken>
    
    /// Initialize the service - call after creation
    /// - Throws: AppError if initialization fails
    func initialize() async throws

    /// Check if the service has been properly initialized
    var isReady: Bool { get }
    
    /// Get detailed status information for debugging and UI
    /// - Returns: Current status information
    func getStatusInfo() async -> ScreenTimeStatusInfo
    
    
    /// Set callback to restore default state when sessions end
    /// - Parameter callback: Async closure to call when sessions expire or end
    func setRestoreDefaultStateCallback(_ callback: @escaping @Sendable () async -> Void) async

    /// Cancel session timers without triggering re-blocking
    /// Used when starting a new session to prevent the old session's timer from firing
    func cancelSessionTimers() async

    /// Clean up all resources and reset service state
    /// Cancels running tasks, clears settings, and resets internal state
    func cleanup() async
}
