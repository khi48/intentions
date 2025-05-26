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
        
        // Request authorization first
        let authorized = await requestAuthorization()
        print("🔐 Authorization in initialize(): \(authorized)")
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
    
    /// Stored complete app/category discovery for "block everything except" calculations
    private var discoveredAppSelection: FamilyActivitySelection? = nil
    
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
            // Clear any existing restrictions to reset state
            managedSettingsStore.clearAllSettings()
            
            // INTENTIONS CORE CONCEPT: Block everything by default
            // Since we can't predetermine all app tokens, we use a different approach:
            // 1. Block all web content by default
            // 2. Use app category blocking for major categories
            // 3. Allow users to create specific exemptions via FamilyActivityPicker
            
            // Block all web content by default - this covers browsers and web-based apps
            managedSettingsStore.webContent.blockedByFilter = .all()
            
            // Block major distracting app categories by default
            // Users will need to explicitly allow categories they need via FamilyActivityPicker
            managedSettingsStore.shield.applicationCategories = .all()
            
            // Clear allowed apps tracking - nothing is allowed initially
            currentlyAllowedApps.removeAll()
            
            // Cancel any existing session expiration
            sessionExpirationTask?.cancel()
            sessionExpirationTask = nil
            
            print("🚫 INTENTIONS: DEFAULT BLOCKING ENABLED")
            print("🌐 Web content blocked by default")
            print("📱 App categories shielded by default")
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
            // SOPHISTICATED BLOCKING IMPLEMENTATION:
            // Use category mapping service to implement precise blocking:
            // 1. Block entire categories that contain no user-selected apps
            // 2. For categories with user-selected apps, block only the unselected individual apps
            
            print("🧠 SOPHISTICATED BLOCKING IMPLEMENTATION:")
            print("   - Apps to ALLOW: \(tokens.count)")
            print("   - Categories to ALLOW: \(categories.count)")
            print("   - Category mapping service available: \(categoryMappingService != nil)")
            
            if let mappingService = categoryMappingService {
                print("🔍 CATEGORY MAPPING SERVICE DEBUG:")
                await MainActor.run {
                    print("   - Setup completed: \(mappingService.isSetupCompleted)")
                    print("   - Truly setup completed: \(mappingService.isTrulySetupCompleted)")
                    print("   - Total categories: \(mappingService.completedCategories.count)")
                    let totalApps = mappingService.completedCategories.reduce(0) { sum, category in
                        sum + mappingService.getApps(for: category).count
                    }
                    print("   - Total mapped apps: \(totalApps)")
                }
            }
            
            // Step 1: Clear any existing restrictions to start fresh
            managedSettingsStore.clearAllSettings()
            
            // Step 2: Use category mapping service for intelligent blocking strategy
            if let mappingService = categoryMappingService {
                print("🗂️ Using category mapping service for sophisticated blocking")
                await MainActor.run {
                    print("🗂️ Category mapping service status: Setup completed = \(mappingService.isSetupCompleted)")
                    print("🗂️ Category mapping service status: Completed categories = \(mappingService.completedCategories.count)")
                }
                
                // Get the blocking strategy from category mapping service
                let blockingStrategy = await MainActor.run {
                    mappingService.analyzeBlockingStrategy(for: tokens)
                }
                
                let categoriesToBlock = blockingStrategy.categoriesToBlock
                let appsToBlockIndividually = blockingStrategy.appsToBlockInUsedCategories
                
                // Step 3: Apply category-level blocking for unused categories
                if !categoriesToBlock.isEmpty {
                    let categoryTokensToBlock = await MainActor.run {
                        mappingService.getCategoryTokensToBlock(for: categoriesToBlock)
                    }
                    
                    if !categoryTokensToBlock.isEmpty {
                        managedSettingsStore.shield.applicationCategories = .specific(categoryTokensToBlock)
                        print("🚫 CATEGORY BLOCKING: Blocked \(categoryTokensToBlock.count) entire categories")
                    } else {
                        print("⚠️ No category tokens available - cannot block categories")
                    }
                } else {
                    managedSettingsStore.shield.applicationCategories = nil
                    print("✅ No categories to block completely")
                }
                
                // Step 4: Apply individual app blocking within used categories
                if !appsToBlockIndividually.isEmpty {
                    // Check for Shield API 50-app limit
                    if appsToBlockIndividually.count > 50 {
                        print("⚠️ SHIELD API LIMIT: \(appsToBlockIndividually.count) apps exceeds 50-app limit")
                        print("🧠 Using smart prioritization for individual apps")
                        
                        let prioritizedApps = prioritizeAppsForBlocking(appsToBlockIndividually, limit: 50)
                        managedSettingsStore.shield.applications = prioritizedApps
                        
                        print("🛡️ INDIVIDUAL APP BLOCKING: Blocked \(prioritizedApps.count) prioritized apps")
                        print("   - \(appsToBlockIndividually.count - prioritizedApps.count) apps remain unblocked due to API limit")
                    } else {
                        managedSettingsStore.shield.applications = appsToBlockIndividually
                        print("📱 INDIVIDUAL APP BLOCKING: Blocked \(appsToBlockIndividually.count) individual apps")
                    }
                } else {
                    managedSettingsStore.shield.applications = nil
                    print("✅ No individual apps to block")
                }
                
                // Allow web content during focused session
                managedSettingsStore.webContent.blockedByFilter = nil
                print("🌐 Web content allowed during focused session")
                
                print("\n🎯 SOPHISTICATED BLOCKING SUMMARY:")
                print("   - Entire categories blocked: \(categoriesToBlock.count)")
                print("   - Individual apps blocked: \(min(appsToBlockIndividually.count, 50))")
                print("   - User apps allowed: \(tokens.count)")
                print("   - Strategy: Precise category + individual app blocking")
                
            } else {
                // Fallback when category mapping is not available
                print("⚠️ Category mapping service not available - using fallback blocking")
                await applyFallbackBlocking(tokens: tokens, categories: categories)
            }
            
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
        
        // Clear current state
        currentlyAllowedApps.removeAll()
        essentialSystemApps.removeAll()
        
        // Clear managed settings store
        managedSettingsStore.clearAllSettings()
        
        // Reset initialization state
        isInitialized = false
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
    
    /// Store discovered app/category selection for proper "block everything except" implementation
    /// This enables the service to calculate (all apps - selected apps) for Shield API
    func setDiscoveredAppSelection(_ allAvailable: FamilyActivitySelection) async {
        // Store the complete app/category discovery for use in allowApps
        // This will enable proper "block everything except selected" implementation
        
        let appCount = allAvailable.applications.compactMap { $0.token }.count
        let categoryCount = allAvailable.categories.compactMap { $0.token }.count
        
        print("🔍 ScreenTimeService received app discovery:")
        print("   - \(appCount) app tokens")
        print("   - \(categoryCount) category tokens")
        print("   - This enables proper 'block everything except selected' implementation")
        
        // Store this for use in allowApps method
        discoveredAppSelection = allAvailable
        print("   - Stored for proper 'block everything except selected' implementation")
    }
    
    /// Set the category mapping service for intelligent app blocking
    func setCategoryMappingService(_ service: CategoryMappingService) async {
        categoryMappingService = service
        print("🗂️ ScreenTimeService: Category mapping service configured")
        
        // Access MainActor-isolated properties from main thread
        await MainActor.run {
            print("   - Setup completed: \(service.isSetupCompleted)")
            print("   - Categories mapped: \(service.completedCategories.count)")
        }
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
    
    /// Calculate apps to block based on "allow only selected" approach
    /// This is where we'd implement proper Shield API semantics when we have complete app discovery
    private func calculateAppsToBlock(
        allAvailable: FamilyActivitySelection, 
        selectedToAllow: Set<ApplicationToken>
    ) -> Set<ApplicationToken> {
        // Extract all available app tokens
        let allAppTokens = Set(allAvailable.applications.compactMap { $0.token })
        
        // Calculate what to block = all apps - selected apps - essential system apps
        let appsToBlock = allAppTokens.subtracting(selectedToAllow).subtracting(essentialSystemApps)
        
        print("🧠 Block calculation:")
        print("   - All available: \(allAppTokens.count)")
        print("   - Selected to allow: \(selectedToAllow.count)")
        print("   - Essential system apps: \(essentialSystemApps.count)")
        print("   - Will block: \(appsToBlock.count)")
        
        // Additional debugging - show some examples of what will be blocked
        if appsToBlock.count > 0 {
            print("   - Examples of apps that will be blocked:")
            for (index, token) in appsToBlock.enumerated().prefix(5) {
                print("     • Token \(index + 1): \(token)")
            }
            if appsToBlock.count > 5 {
                print("     • ... and \(appsToBlock.count - 5) more apps")
            }
        }
        
        return appsToBlock
    }
    
    /// Prioritize which apps to block when we exceed the 50-app API limit
    /// Uses category mapping service for intelligent prioritization when available
    private func prioritizeAppsForBlocking(_ appsToBlock: Set<ApplicationToken>, limit: Int) -> Set<ApplicationToken> {
        guard appsToBlock.count > limit else { return appsToBlock }
        
        // Use category mapping service for smart prioritization if available
        if let mappingService = categoryMappingService {
            // Note: We need to access MainActor properties from the actor context
            // This is a limitation - for now, we'll use fallback prioritization
            // In the future, we could redesign this to be async or move the service to actor context
            print("🔄 CATEGORY MAPPING AVAILABLE: Using fallback due to MainActor constraints")
        }
        
        // Fallback to deterministic selection (always for now due to MainActor constraints)
        print("🎯 DETERMINISTIC PRIORITIZATION:")
        print("   - Total apps to block: \(appsToBlock.count)")
        print("   - API limit: \(limit)")
        print("   - Using deterministic selection")
        
        let sortedApps = Array(appsToBlock).sorted { token1, token2 in
            return token1.hashValue < token2.hashValue
        }
        
        let prioritizedApps = Set(sortedApps.prefix(limit))
        print("   - Selected for blocking: \(prioritizedApps.count) apps")
        return prioritizedApps
    }
    
    /// Calculate categories to block based on "allow only selected" approach
    private func calculateCategoriesToBlock(
        allAvailable: FamilyActivitySelection,
        selectedToAllow: Set<ActivityCategoryToken>
    ) -> Set<ActivityCategoryToken> {
        // Extract all available category tokens
        let allCategoryTokens = Set(allAvailable.categories.compactMap { $0.token })
        
        // Calculate what to block = all categories - selected categories
        let categoriesToBlock = allCategoryTokens.subtracting(selectedToAllow)
        
        print("🏷️ Category block calculation:")
        print("   - All available: \(allCategoryTokens.count)")
        print("   - Selected to allow: \(selectedToAllow.count)")
        print("   - Will block: \(categoriesToBlock.count)")
        
        return categoriesToBlock
    }
    
    /// Fallback blocking strategy when category mapping service is not available
    private func applyFallbackBlocking(tokens: Set<ApplicationToken>, categories: Set<ActivityCategoryToken>) async {
        print("🔄 FALLBACK BLOCKING STRATEGY:")
        
        if let allAvailable = discoveredAppSelection {
            // Use the old approach with complete app discovery
            print("   - Using complete app discovery for blocking")
            
            let appsToBlock = calculateAppsToBlock(allAvailable: allAvailable, selectedToAllow: tokens)
            if !appsToBlock.isEmpty && appsToBlock.count <= 50 {
                managedSettingsStore.shield.applications = appsToBlock
                print("   - Blocked \(appsToBlock.count) individual apps")
            } else if appsToBlock.count > 50 {
                let prioritizedApps = prioritizeAppsForBlocking(appsToBlock, limit: 50)
                managedSettingsStore.shield.applications = prioritizedApps
                print("   - Blocked \(prioritizedApps.count) prioritized apps (API limit)")
            }
            
            managedSettingsStore.shield.applicationCategories = nil
        } else {
            // Basic fallback - block all categories if none selected
            if categories.isEmpty {
                managedSettingsStore.shield.applicationCategories = .all()
                print("   - Blocking ALL categories (basic fallback)")
            } else {
                managedSettingsStore.shield.applicationCategories = nil
                print("   - Not blocking categories (compromise)")
            }
            
            managedSettingsStore.shield.applications = nil
        }
        
        // Allow web content during session
        managedSettingsStore.webContent.blockedByFilter = nil
        print("   - Web content allowed")
    }
}
