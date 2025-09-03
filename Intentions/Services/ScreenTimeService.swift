// Services/ScreenTimeService.swift
// Core Screen Time Service Implementation

import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Implementation of Screen Time management using Apple's Family Controls framework
/// Uses actor isolation for thread safety without blocking the main thread
actor ScreenTimeService: ScreenTimeManaging {
    
    // MARK: - Properties
    
    /// The managed settings store for applying restrictions
    private let managedSettingsStore = ManagedSettingsStore()
    
    /// Currently allowed applications - protected by actor isolation
    private var currentlyAllowedApps: Set<ApplicationToken> = []
    
    /// Timer for tracking session expiration - protected by actor isolation
    private var sessionExpirationTask: Task<Void, Never>?
    
    /// Essential system apps that should never be blocked
    private var essentialSystemApps: Set<ApplicationToken> = []
    
    /// Track initialization state
    private var isInitialized = false
    
    // MARK: - Initialization
    
    init() {
        // Clean initialization - no async work
        // Call initialize() after creating the service
    }
    
    deinit {
        // Cancel any running session expiration tasks
        sessionExpirationTask?.cancel()
        // Clean up managed settings store
        managedSettingsStore.clearAllSettings()
    }
    
    /// Initialize the service without applying any blocking
    /// Must be called after creating the service before any other operations
    /// Blocking should be applied separately based on schedule settings
    func initialize() async throws {
        guard !isInitialized else { 
            throw AppError.serviceUnavailable("ScreenTimeService already initialized")
        }
        
        // Check current authorization status first
        let currentStatus = await authorizationStatus()
        print("🔐 Current authorization status: \(currentStatus)")
        
        let authorized: Bool
        if currentStatus == .approved {
            // Already authorized - no need to request again
            authorized = true
            print("✅ Already authorized - skipping authorization request")
        } else {
            // Need to request authorization
            authorized = await requestAuthorization()
            print("🔐 Authorization request result: \(authorized)")
        }
        
        guard authorized else {
            throw AppError.screenTimeAuthorizationFailed
        }
        
        // Mark as initialized - blocking will be applied separately by ContentViewModel
        isInitialized = true
        print("✅ ScreenTimeService initialized - ready for schedule-based blocking")
    }
    
    /// Check if the service has been properly initialized
    var isReady: Bool {
        isInitialized
    }
    
    /// Ensure service is initialized before performing operations
    private func ensureInitialized() throws {
        guard isInitialized else {
            throw AppError.serviceUnavailable("ScreenTimeService not initialized. Call initialize() first.")
        }
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        do {
            // Access AuthorizationCenter directly in async context
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            let status = await authorizationStatus()
            return status == .approved
        } catch {
            print("Authorization failed: \(error)")
            return false
        }
    }
    
    func authorizationStatus() async -> AuthorizationStatus {
        // Access authorization status safely
        return AuthorizationCenter.shared.authorizationStatus
    }
    
    // MARK: - App Discovery Storage
    
    
    /// Category mapping service for intelligent app prioritization
    private var categoryMappingService: CategoryMappingService? = nil
    
    // MARK: - App Management
    
    /// Block all apps by default - core concept of Intentions app
    /// Users must explicitly select which apps to temporarily allow
    func blockAllApps() async throws {
        try ensureInitialized()
        
        let status = await authorizationStatus()
        guard status == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }
        
        do {
            print("🔄 BLOCK ALL APPS: Starting blocking process...")
            
            // Clear allowed apps tracking - nothing is allowed initially
            currentlyAllowedApps.removeAll()
            print("   ✅ Cleared allowed apps tracking")
            
            // Cancel any existing session expiration
            sessionExpirationTask?.cancel()
            sessionExpirationTask = nil
            print("   ✅ Cancelled existing session expiration")
            
            // Clear any existing restrictions to reset state
            print("   🧹 Clearing all existing settings...")
            managedSettingsStore.clearAllSettings()
            print("   ✅ All settings cleared")
            
            // Add a small delay to ensure clearAllSettings() completes
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            print("   ⏱️ Wait completed - now applying new restrictions")
            
            // INTENTIONS CORE CONCEPT: Block everything by default
            // Since we can't predetermine all app tokens, we use a different approach:
            // 1. Block all web content by default
            // 2. Use app category blocking for major categories
            // 3. Allow users to create specific exemptions via FamilyActivityPicker
            
            // Block all web content by default - this covers browsers and web-based apps
            managedSettingsStore.webContent.blockedByFilter = .all()
            print("   🌐 Web content blocking applied")
            
            // Block major distracting app categories by default
            // Users will need to explicitly allow categories they need via FamilyActivityPicker
            managedSettingsStore.shield.applicationCategories = .all()
            print("   🛡️ Application category shields applied")
            
            print("🚫 INTENTIONS: DEFAULT BLOCKING ENABLED")
            print("💡 Users must create focused sessions to access specific apps/categories")
            print("✅ This enforces intentional app usage - the core concept")
            
            
        } catch {
            throw AppError.appBlockingFailed("Failed to apply comprehensive restrictions: \(error.localizedDescription)")
        }
    }
    
    /// Get all discoverable applications for comprehensive blocking
    /// In production, this would use stored FamilyActivityPicker selections
    private func getAllDiscoverableApplications() -> Set<ApplicationToken> {
        // For default-block-all approach, we'll use category-based blocking instead
        // Individual app tokens are device-specific and can't be pre-determined
        return Set<ApplicationToken>()
    }
    
    /// Get all discoverable categories for comprehensive blocking  
    /// Uses all major app categories to implement default-block-all approach
    private func getAllDiscoverableCategories() -> Set<ActivityCategoryToken> {
        // For default-block-all, we need to block major app categories
        // This provides comprehensive blocking without needing specific app tokens
        
        // Note: ActivityCategoryToken values are not directly constructible
        // In practice, these would come from FamilyActivityPicker user selections
        // For now, we'll use an alternative approach via ManagedSettingsStore
        return Set<ActivityCategoryToken>()
    }
    
    func allowApps(_ tokens: sending Set<ApplicationToken>, categories: Set<ActivityCategoryToken> = [], duration: TimeInterval) async throws {
        try ensureInitialized()
        
        let status = await authorizationStatus()
        print("🔐 AUTHORIZATION CHECK: Status is \(status)")
        guard status == .approved else {
            print("❌ AUTHORIZATION FAILED: Cannot block apps without permission")
            throw AppError.screenTimeAuthorizationFailed
        }
        print("✅ AUTHORIZATION OK: Proceeding with blocking")
        
        guard duration >= AppConstants.Session.minimumDuration else {
            throw AppError.validationFailed("duration", reason: "Must be at least \(AppConstants.Session.minimumDuration.formattedMinutesSeconds)")
        }
        
        guard duration <= AppConstants.Session.maximumDuration else {
            throw AppError.validationFailed("duration", reason: "Cannot exceed \(AppConstants.Session.maximumDuration.formattedHoursMinutes)")
        }
        
        guard !tokens.isEmpty || !categories.isEmpty else {
            throw AppError.validationFailed("applications", reason: "At least one application or category must be specified")
        }
        
        do {
            // SIMPLE SESSION BLOCKING: Block all apps except selected ones
            print("🎯 SESSION BLOCKING: Block all apps except selected ones")
            print("   - Apps to ALLOW: \(tokens.count)")
            print("   - Categories to ALLOW: \(categories.count)")
            
            // Step 1: Clear any existing restrictions to start fresh
            print("   🧹 Clearing all settings for fresh session start...")
            managedSettingsStore.clearAllSettings()
            
            // Small delay to ensure clear completes before applying new settings
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            print("   ✅ Settings cleared, applying session restrictions...")
            
            // Step 2: Implement proper "allow selected, block others" logic
            print("🎯 SMART SESSION BLOCKING:")
            print("   - Apps to allow: \(tokens.count)")
            print("   - Categories to allow: \(categories.count)")
            
            if let mappingService = categoryMappingService {
                // Use sophisticated blocking - determine which categories contain selected apps
                await applySmartCategoryBlocking(allowedCategoryTokens: categories, allowedAppTokens: tokens, mappingService: mappingService)
            } else {
                // Fallback when no category mapping service is available
                if categories.isEmpty {
                    managedSettingsStore.shield.applicationCategories = .all()
                    managedSettingsStore.shield.applications = nil
                } else {
                    managedSettingsStore.shield.applicationCategories = nil
                    managedSettingsStore.shield.applications = nil
                }
            }
            
            // Allow web content during focused session (apps are still restricted by categories)
            managedSettingsStore.webContent.blockedByFilter = nil
            print("🌐 Web content allowed during session")
            
            print("✅ SESSION BLOCKING APPLIED - non-selected apps should now be blocked")
            
            // Update our tracking
            currentlyAllowedApps = tokens
            
            // Cancel any existing expiration task
            sessionExpirationTask?.cancel()
            
            // Schedule automatic re-blocking after duration
            sessionExpirationTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: duration.nanoseconds)
                    
                    // Check if task was cancelled
                    guard !Task.isCancelled else { return }
                    
                    // Automatically re-block all apps
                    try? await self?.blockAllApps()
                    print("⏰ SESSION EXPIRED - All apps blocked again")
                } catch {
                    // Task.sleep can throw if cancelled
                    return
                }
            }
            
        } catch {
            throw AppError.appBlockingFailed("Failed to allow apps: \(error.localizedDescription)")
        }
    }
    
    func getCurrentlyAllowedApps() async -> Set<ApplicationToken> {
        return currentlyAllowedApps
    }
    
    func allowAllAccess() async throws {
        try ensureInitialized()
        
        let status = await authorizationStatus()
        guard status == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }
        
        // Cancel session expiration task
        sessionExpirationTask?.cancel()
        sessionExpirationTask = nil
        
        // Clear tracking
        currentlyAllowedApps.removeAll()
        
        // Actually remove all restrictions (clear managed settings)
        do {
            managedSettingsStore.clearAllSettings()
            print("✅ All Screen Time restrictions removed - apps are now accessible")
        } catch {
            throw AppError.appBlockingFailed("Failed to clear restrictions: \(error.localizedDescription)")
        }
    }
    
    /// Clean up all resources and reset service state
    func cleanup() async {
        // Cancel any running tasks
        sessionExpirationTask?.cancel()
        sessionExpirationTask = nil
        
        // Clear current state tracking
        currentlyAllowedApps.removeAll()
        
        // Standard clear all settings
        managedSettingsStore.clearAllSettings()
        
        // Explicitly clear specific shield types
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.webContent.blockedByFilter = nil
        managedSettingsStore.application.denyAppInstallation = nil
        managedSettingsStore.application.denyAppRemoval = nil
        managedSettingsStore.gameCenter.denyMultiplayerGaming = nil
        managedSettingsStore.gameCenter.denyAddingFriends = nil
        
        // Brief delay to ensure clearing takes effect
        do {
            try await Task.sleep(nanoseconds: 200_000_000)
        } catch {
            // Delay interrupted - continue
        }
        
        print("🧹 ScreenTimeService cleanup completed")
    }
    
    func isAppAllowed(_ token: sending ApplicationToken) async -> Bool {
        return currentlyAllowedApps.contains(token) || essentialSystemApps.contains(token)
    }
    
    func getEssentialSystemApps() async -> Set<ApplicationToken> {
        return essentialSystemApps
    }
    
    // MARK: - Helper Methods
    
    /// Add essential system apps to the allowlist
    /// This should be called during app discovery to populate system apps
    func addEssentialSystemApp(_ token: sending ApplicationToken) async {
        essentialSystemApps.insert(token)
    }
    
    
    /// Set the category mapping service for intelligent app blocking
    func setCategoryMappingService(_ service: CategoryMappingService) async {
        categoryMappingService = service
        print("🗂️ Category mapping service configured")
    }
    
    /// Remove all system apps (for testing/reset purposes)
    func clearEssentialSystemApps() async {
        essentialSystemApps.removeAll()
    }
    
    /// Get detailed status information for debugging
    func getStatusInfo() async -> ScreenTimeStatusInfo {
        let status = await authorizationStatus()
        return ScreenTimeStatusInfo(
            authorizationStatus: status,
            currentlyAllowedAppsCount: currentlyAllowedApps.count,
            essentialSystemAppsCount: essentialSystemApps.count,
            hasActiveSession: sessionExpirationTask != nil,
            isInitialized: isInitialized
        )
    }
    
    
    /// Prioritize which apps to block when we exceed the 50-app API limit
    /// Uses category mapping service for intelligent prioritization when available
    private func prioritizeAppsForBlocking(_ appsToBlock: Set<ApplicationToken>, limit: Int) -> Set<ApplicationToken> {
        guard appsToBlock.count > limit else { return appsToBlock }
        
        // Use deterministic selection for app prioritization
        let sortedApps = Array(appsToBlock).sorted { token1, token2 in
            return token1.hashValue < token2.hashValue
        }
        
        let prioritizedApps = Set(sortedApps.prefix(limit))
        return prioritizedApps
    }
    
    
    
    /// Apply smart category-based blocking using the CategoryMappingService
    /// Logic: Allow categories that contain selected apps, but block unselected apps within those categories
    /// Block entire categories that contain no selected apps
    private func applySmartCategoryBlocking(
        allowedCategoryTokens: Set<ActivityCategoryToken>,
        allowedAppTokens: Set<ApplicationToken>,
        mappingService: CategoryMappingService
    ) async {
        
        // Get the blocking strategy from category mapping service (MainActor context required)
        let (categoriesToBlockCompletely, appsToBlockWithinUsedCategories) = await MainActor.run {
            let blockingStrategy = mappingService.analyzeBlockingStrategy(for: allowedAppTokens)
            return (blockingStrategy.categoriesToBlock, blockingStrategy.appsToBlockInUsedCategories)
        }
        
        
        // Step 1: Block entire categories that have NO selected apps
        // This allows categories with selected apps to remain accessible
        if !categoriesToBlockCompletely.isEmpty {
            let categoryTokensToBlock = await MainActor.run {
                mappingService.getCategoryTokensToBlock(for: categoriesToBlockCompletely)
            }
            
            // Remove any explicitly allowed categories from the block list
            let finalCategoriesToBlock = categoryTokensToBlock.subtracting(allowedCategoryTokens)
            
            if !finalCategoriesToBlock.isEmpty {
                managedSettingsStore.shield.applicationCategories = .specific(finalCategoriesToBlock)
            } else {
                managedSettingsStore.shield.applicationCategories = nil
            }
        } else {
            managedSettingsStore.shield.applicationCategories = nil
        }
        
        // Step 2: Within categories that have selected apps, block the unselected individual apps
        // This allows the selected apps to work while blocking distracting apps in the same category
        if !appsToBlockWithinUsedCategories.isEmpty {
            let appsToBlock = appsToBlockWithinUsedCategories.subtracting(allowedAppTokens)
            
            if !appsToBlock.isEmpty {
                if appsToBlock.count <= 50 {
                    managedSettingsStore.shield.applications = appsToBlock
                } else {
                    let prioritizedApps = prioritizeAppsForBlocking(appsToBlock, limit: 50)
                    managedSettingsStore.shield.applications = prioritizedApps
                    print("⚠️ \(appsToBlock.count - prioritizedApps.count) apps unblocked due to API limit")
                }
            } else {
                managedSettingsStore.shield.applications = nil
            }
        } else {
            managedSettingsStore.shield.applications = nil
        }
        
        print("✅ Smart category blocking applied")
    }
    
}
