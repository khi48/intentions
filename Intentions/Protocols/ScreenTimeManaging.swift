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

    /// Update the set of all app tokens the user has ever selected across QuickActions.
    /// Used as a second blocking layer via `shield.applications` to catch apps that
    /// escape category-based blocking.
    func updateKnownAppTokens(_ tokens: Set<ApplicationToken>) async

    /// Clear all shield-related ManagedSettings entries from the main app process.
    /// Used to re-render the springboard shield layer after the DeviceActivity
    /// extension writes a removal — in this codebase's iOS 26 testing, the
    /// equivalent extension-process flush has not been observed updating the
    /// springboard cache, so the main-app write is the known-working path
    /// today. Does NOT cancel DeviceActivity schedules or session timers.
    func clearAllShields() async

    /// Push the latest weekly-schedule snapshot into the shield engine. Causes
    /// the engine to persist it in the App Group log (visible to DAM extension),
    /// (re-)register the next schedule-boundary DAM monitor, and re-apply the
    /// current shield config via `compute()`. Call on schedule edits and on
    /// scenePhase → .active.
    ///
    /// Returns the engine's transition result so callers (ContentViewModel)
    /// can react to mutex-driven session termination — e.g. fire the
    /// "free time started — your session ended" banner (R3, #27).
    @discardableResult
    func refreshSchedule(_ snapshot: ScheduleSnapshot) async -> ScheduleTransitionResult
}
