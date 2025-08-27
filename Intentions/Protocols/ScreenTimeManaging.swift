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
    
    /// Allow specific apps and categories for a limited duration
    /// - Parameters:
    ///   - tokens: Set of ApplicationTokens to allow
    ///   - categories: Set of ActivityCategoryTokens to allow (default empty)
    ///   - duration: How long to allow access (in seconds)
    /// - Throws: AppError if allowing apps fails
    func allowApps(_ tokens: sending Set<ApplicationToken>, categories: Set<ActivityCategoryToken>, duration: TimeInterval) async throws
    
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
    
    /// Get detailed status information for debugging and UI
    /// - Returns: Current status information
    func getStatusInfo() async -> ScreenTimeStatusInfo
    
    
    /// Set the category mapping service for intelligent app blocking
    /// - Parameter service: CategoryMappingService to use for prioritized blocking
    func setCategoryMappingService(_ service: CategoryMappingService) async
    
    /// Clean up all resources and reset service state
    /// Cancels running tasks, clears settings, and resets internal state
    func cleanup() async
}
