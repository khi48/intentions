// Services/ScreenTimeService.swift
// Core Screen Time Service Implementation

import Foundation
import OSLog
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@preconcurrency import DeviceActivity
import WidgetKit

/// Implementation of Screen Time management using Apple's Family Controls framework
/// Uses actor isolation for thread safety without blocking the main thread
actor ScreenTimeService: ScreenTimeManaging {

    // MARK: - Properties

    /// Logger for Console.app debugging
    private nonisolated let logger = Logger(subsystem: "oh.Intent", category: "ScreenTimeService")

    /// The managed settings store for applying restrictions
    private let managedSettingsStore = ManagedSettingsStore()
    
    /// Currently allowed applications - protected by actor isolation
    private var currentlyAllowedApps: Set<ApplicationToken> = []
    
    /// Timer for tracking session expiration - protected by actor isolation
    private var sessionExpirationTask: Task<Void, Never>?

    /// Flag to prevent callbacks from executing when session is being replaced
    private var isSessionBeingReplaced: Bool = false

    /// DeviceActivity center for scheduling background expiration
    private let deviceActivityCenter = DeviceActivityCenter()

    /// Currently active DeviceActivity name (for cancellation)
    private var activeDeviceActivityName: DeviceActivityName?

    /// Essential system apps that should never be blocked
    private var essentialSystemApps: Set<ApplicationToken> = []
    
    /// Track initialization state
    nonisolated(unsafe) private var isInitialized = false

    /// Track the state before a session started (was Intentions blocking or allowing?)
    private var preSessionBlockingState: Bool?

    /// Callback to restore proper default state when session ends
    private var restoreDefaultStateCallback: (@Sendable () async -> Void)?
    
    // MARK: - Initialization
    
    init() {
        // Clean initialization - no async work
        // Call initialize() after creating the service
    }
    
    deinit {
        logger.info("🧹 DEINIT: ScreenTimeService being deallocated - clearing all settings")
        // Cancel any running session expiration tasks
        sessionExpirationTask?.cancel()
        // Clean up managed settings store
        managedSettingsStore.clearAllSettings()
    }
    
    /// Initialize the service without applying any blocking
    /// Must be called after creating the service before any other operations
    /// Blocking should be applied separately based on schedule settings
    func initialize() async throws {
        print("🔧 ScreenTimeService.initialize() called - Current isInitialized: \(isInitialized)")
        guard !isInitialized else {
            print("⚠️ ScreenTimeService already initialized - skipping duplicate initialization")
            return // Don't throw error, just return - this is idempotent
        }

        // Check current authorization status first
        let currentStatus = await authorizationStatus()

        let authorized: Bool
        if currentStatus == .approved {
            // Already authorized - no need to request again
            authorized = true
        } else {
            // Need to request authorization
            authorized = await requestAuthorization()
        }

        guard authorized else {
            throw AppError.screenTimeAuthorizationFailed
        }

        // Mark as initialized - blocking will be applied separately by ContentViewModel
        isInitialized = true
        print("✅ ScreenTimeService successfully initialized")
    }
    
    /// Check if the service has been properly initialized
    nonisolated var isReady: Bool {
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
    /// Uses comprehensive blocking: category-based blocking + web content blocking
    /// This is the DEFAULT STATE when no session is active during protected hours
    func blockAllApps() async throws {
        try ensureInitialized()

        let status = await authorizationStatus()
        guard status == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }

        logger.notice("🚫 BLOCK ALL: Starting comprehensive default blocking")

        // CRITICAL: Update widget FIRST, before clearing shields
        // This prevents the widget from reading "no blocking" state during the clear/reblock window
        logger.info("🚫 BLOCK ALL: Step 0 - Updating widget to 'Blocked' BEFORE clearing shields")
        updateWidgetBlockingStatus(isBlocking: true)

        // Clear allowed apps tracking - nothing is allowed initially
        currentlyAllowedApps.removeAll()

        // Cancel any existing session expiration
        sessionExpirationTask?.cancel()
        sessionExpirationTask = nil

        // Cancel any DeviceActivity schedule
        cancelDeviceActivitySchedule()

        // INTENTIONS CORE CONCEPT: Block everything by default during protected hours
        // IMPORTANT: ManagedSettingsStore is cumulative, so we must explicitly clear
        // any previously set shields from sessions BEFORE applying new blocking

        // CRITICAL: Clear ALL shields first to remove any session exceptions
        logger.info("🚫 BLOCK ALL: Step 1 - Clearing ALL existing shields to remove session exceptions")
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.webContent.blockedByFilter = nil

        // Brief delay to ensure clearing takes effect before applying new blocking
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // COMPREHENSIVE BLOCKING STRATEGY:
        // We use a multi-layered approach to ensure ALL apps are blocked:
        // 1. Category-based blocking (.all()) - blocks most apps by category
        // 2. Web content blocking (.all()) - blocks browsers and web-based apps

        logger.info("🚫 BLOCK ALL: Step 2 - Applying category-based blocking (.all())")
        managedSettingsStore.shield.applicationCategories = .all()

        logger.info("🚫 BLOCK ALL: Step 3 - Applying web content blocking (.all())")
        managedSettingsStore.webContent.blockedByFilter = .all()

        // Brief delay to ensure all settings propagate to iOS
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // DIAGNOSTIC: Verify settings after applying
        logger.info("🔍 BLOCK ALL: Verification - shield.applicationCategories is set: \(self.managedSettingsStore.shield.applicationCategories != nil)")
        logger.info("🔍 BLOCK ALL: Verification - webContent.blockedByFilter is set: \(self.managedSettingsStore.webContent.blockedByFilter != nil)")
        logger.info("🔍 BLOCK ALL: Verification - shield.applications is: \(self.managedSettingsStore.shield.applications?.count ?? 0) apps")

        logger.notice("✅ BLOCK ALL: Comprehensive default blocking applied successfully")
        logger.info("   - Category blocking: .all()")
        logger.info("   - Web content blocking: .all()")
        logger.info("   - Widget was updated at the START to prevent race condition")
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
    
    func allowApps(_ tokens: sending Set<ApplicationToken>, categories: Set<ActivityCategoryToken> = [], allowWebsites: Bool = false, duration: TimeInterval, sessionId: UUID) async throws {
        try ensureInitialized()

        // Log memory at the start to catch high memory before operations
        logMemoryUsage(context: "allowApps() - START")

        let status = await authorizationStatus()
        guard status == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }

        guard duration >= AppConstants.Session.minimumDuration else {
            throw AppError.validationFailed("duration", reason: "Must be at least \(AppConstants.Session.minimumDuration.formattedDuration)")
        }

        guard duration <= AppConstants.Session.maximumDuration else {
            throw AppError.validationFailed("duration", reason: "Cannot exceed \(AppConstants.Session.maximumDuration.formattedDuration)")
        }

        guard !tokens.isEmpty || !categories.isEmpty else {
            throw AppError.validationFailed("applications", reason: "At least one application or category must be specified")
        }

        print("🔧 ALLOW APPS: Session ID = \(sessionId.uuidString)")

        // Capture current blocking state before starting session
        // We need this to restore the proper state when the session ends
        preSessionBlockingState = !currentlyAllowedApps.isEmpty || managedSettingsStore.shield.applications != nil || managedSettingsStore.shield.applicationCategories != nil

        // CRITICAL: Clear previous session's shields to prevent cumulative effects
        // ManagedSettingsStore can be cumulative, so we MUST clear old settings first
        print("🔧 ALLOW APPS: Clearing previous shields to prevent cumulative blocking")
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.webContent.blockedByFilter = nil

        // Brief delay to ensure clearing takes effect before applying new settings
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        print("🔧 ALLOW APPS: Starting to apply blocking restrictions")
        print("🔧 ALLOW APPS: Tokens count: \(tokens.count), Categories count: \(categories.count)")

        // Log memory after collecting tokens
        logMemoryUsage(context: "allowApps() - After token collection")

        if let mappingService = categoryMappingService {
            print("🔧 ALLOW APPS: Using CategoryMappingService for smart blocking")
            // Use sophisticated blocking - determine which categories contain selected apps
            await applySmartCategoryBlocking(allowedCategoryTokens: categories, allowedAppTokens: tokens, mappingService: mappingService)
        } else {
            print("🔧 ALLOW APPS: Using fallback blocking strategy")
            // Fallback when no category mapping service is available
            // Use .all(except:) to block everything EXCEPT the session apps
            // This is more precise than re-blocking everything with .all()
            if !tokens.isEmpty {
                // Validate token set size to prevent memory issues
                if tokens.count > 100 {
                    print("⚠️ ALLOW APPS: Large token set (\(tokens.count) tokens) - potential memory pressure")
                }

                print("🔧 ALLOW APPS: Setting .all(except: \(tokens.count) tokens)")
                // Block all app categories except these specific apps
                // .all(except:) accepts ApplicationTokens to allow specific apps through
                managedSettingsStore.shield.applicationCategories = .all(except: tokens)
                managedSettingsStore.shield.applications = nil
                print("✅ ALLOW APPS: Successfully set applicationCategories exception")
            } else {
                print("🔧 ALLOW APPS: No tokens, keeping everything blocked with .all()")
                // No specific apps selected - keep everything blocked
                // Note: If categories are provided but no tokens, we still block everything
                // The app would need to convert categories to tokens first
                managedSettingsStore.shield.applicationCategories = .all()
                managedSettingsStore.shield.applications = nil
                print("✅ ALLOW APPS: Successfully set applicationCategories to .all()")
            }
        }

        // Conditionally allow web content based on session preference
        print("🔧 ALLOW APPS: Setting web content filter (allowWebsites: \(allowWebsites))")
        if allowWebsites {
            // Clear ALL web-related restrictions
            managedSettingsStore.shield.webDomains = nil  // Clear specific domain shields
            managedSettingsStore.webContent.blockedByFilter = nil  // Clear category-based web blocking
            print("✅ ALLOW APPS: Web content and domains allowed")
        } else {
            managedSettingsStore.shield.webDomains = nil  // Clear specific domain blocks
            managedSettingsStore.webContent.blockedByFilter = .all()  // Block via category filter
            print("✅ ALLOW APPS: Web content blocked via category filter")
        }

        // Update our tracking
        currentlyAllowedApps = tokens
        print("🔧 ALLOW APPS: Updated tracking - currently allowed apps: \(tokens.count)")

        // Cancel any existing expiration task from previous session
        if sessionExpirationTask != nil {
            print("🔧 ALLOW APPS: Cancelling existing session expiration task")
            sessionExpirationTask?.cancel()
            sessionExpirationTask = nil
        }

        // Log memory usage before DeviceActivity scheduling
        logMemoryUsage(context: "Before DeviceActivity scheduling")

        do {
            // Schedule DeviceActivity for background expiration
            // This ensures blocking is restored even if app isn't running
            // Note: May show "intervalTooShort" error for sessions < 15 min, but appears to work anyway
            print("🔧 ALLOW APPS: Scheduling DeviceActivity expiration")
            try await scheduleDeviceActivityExpiration(duration: duration, sessionId: sessionId)
            print("✅ ALLOW APPS: DeviceActivity scheduling completed")

            // Log memory usage after DeviceActivity scheduling
            logMemoryUsage(context: "After DeviceActivity scheduling")
        } catch {
            print("❌ ALLOW APPS: DeviceActivity scheduling failed: \(error)")
            throw AppError.appBlockingFailed("Failed to schedule expiration: \(error.localizedDescription)")
        }

        // Also keep in-app timer for immediate handling when app is active
        sessionExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: duration.nanoseconds)

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    print("⚠️ SESSION TIMER: Task was cancelled - exiting")
                    return
                }

                // Check if session is being replaced
                guard let self = self else {
                    print("⚠️ SESSION TIMER: Self is nil - exiting")
                    return
                }

                let isReplacing = await self.isSessionBeingReplaced
                guard !isReplacing else {
                    print("⚠️ SESSION TIMER: Callback skipped - session being replaced")
                    return
                }

                print("⏰ SESSION TIMER: Executing expiration callback")

                // Restore the original state before the session started
                if let callback = await self.restoreDefaultStateCallback {
                    await callback()
                } else {
                    // Fallback to blockAllApps if no callback is set
                    try? await self.blockAllApps()
                }
            } catch {
                // Task.sleep can throw if cancelled
                print("⚠️ SESSION TIMER: Task sleep interrupted - \(error)")
                return
            }
        }

        // Clear the session replacement flag - new session is now active
        isSessionBeingReplaced = false

        // Brief delay to ensure ManagedSettingsStore changes propagate to iOS
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        print("✅ ALLOW APPS: Session setup complete with propagation delay")
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

        logger.notice("🧹 ALLOW ALL ACCESS: Clearing all settings to remove all restrictions")

        // Cancel session expiration task
        sessionExpirationTask?.cancel()
        sessionExpirationTask = nil

        // Cancel any DeviceActivity schedule
        cancelDeviceActivitySchedule()

        // Clear tracking
        currentlyAllowedApps.removeAll()

        // Actually remove all restrictions (clear managed settings)
        do {
            managedSettingsStore.clearAllSettings()

            // Update widget with blocking status
            updateWidgetBlockingStatus(isBlocking: false)
        } catch {
            throw AppError.appBlockingFailed("Failed to clear restrictions: \(error.localizedDescription)")
        }
    }
    
    /// Clean up all resources and reset service state
    func cleanup() async {
        logger.notice("🧹 CLEANUP: Clearing all settings during cleanup")

        // Cancel any running tasks
        sessionExpirationTask?.cancel()
        sessionExpirationTask = nil

        // Cancel any DeviceActivity schedule
        cancelDeviceActivitySchedule()

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
    }

    /// Set callback to restore default state when sessions end
    func setRestoreDefaultStateCallback(_ callback: @escaping @Sendable () async -> Void) async {
        restoreDefaultStateCallback = callback
    }

    /// Cancel session timers without triggering re-blocking
    /// Used when starting a new session to prevent the old session's timer from firing
    func cancelSessionTimers() async {
        print("🛑 CANCEL TIMERS: Cancelling session expiration task and DeviceActivity schedule")

        // Set flag to prevent any in-flight callbacks from executing
        isSessionBeingReplaced = true
        print("🛑 CANCEL TIMERS: Set session replacement flag to prevent callbacks")

        // Cancel in-app timer
        if sessionExpirationTask != nil {
            sessionExpirationTask?.cancel()
            sessionExpirationTask = nil
            print("✅ CANCEL TIMERS: In-app timer cancelled")
        }

        // Cancel DeviceActivity schedule
        cancelDeviceActivitySchedule()

        // CRITICAL: Clear the current session ID from UserDefaults
        // This prevents the extension from executing if it fires after cancellation
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intent") {
            sharedDefaults.removeObject(forKey: "intentions.currentSessionId")
            sharedDefaults.synchronize()
            print("✅ CANCEL TIMERS: Cleared current session ID from UserDefaults")
        }

        print("✅ CANCEL TIMERS: All session timers cancelled successfully")
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
                    // Note: Some apps may remain unblocked due to API limit
                }
            } else {
                managedSettingsStore.shield.applications = nil
            }
        } else {
            managedSettingsStore.shield.applications = nil
        }
    }
    
    // MARK: - DeviceActivity Scheduling

    /// Schedule a DeviceActivity interval that will trigger the monitor extension when the session expires
    /// This ensures blocking is restored even if the app isn't running
    ///
    /// **Strategy**: Uses a combination of intervalDidEnd AND a threshold event to work around iOS limitations:
    /// - For long sessions (≥15 min): intervalDidEnd works reliably
    /// - For short sessions (<15 min): threshold event triggers at exact expiration time
    /// - This dual approach ensures the extension fires regardless of session duration
    ///
    /// - Parameter duration: Session duration in seconds
    /// - Parameter sessionId: UUID of the session being scheduled
    private func scheduleDeviceActivityExpiration(duration: TimeInterval, sessionId: UUID) async throws {
        print("🔵 DEVICE ACTIVITY: Starting to schedule session expiration")
        print("🔵 DEVICE ACTIVITY: Session duration = \(duration) seconds (\(Int(duration/60)) minutes)")
        print("🔵 DEVICE ACTIVITY: Session ID = \(sessionId.uuidString)")

        // CRITICAL: Cancel any existing DeviceActivity FIRST to prevent old session timers from firing
        // This must happen BEFORE creating the new activity
        if let oldActivityName = activeDeviceActivityName {
            print("🔵 DEVICE ACTIVITY: Cancelling old activity: \(oldActivityName.rawValue)")
            deviceActivityCenter.stopMonitoring([oldActivityName])
            activeDeviceActivityName = nil

            // Brief delay to ensure iOS processes the cancellation
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            print("✅ DEVICE ACTIVITY: Old activity cancelled with propagation delay")
        }

        // Create a unique activity name for this session
        // Include session ID in the activity name for validation in the extension
        let activityName = DeviceActivityName("intentions.session.\(sessionId.uuidString)")
        activeDeviceActivityName = activityName
        print("🔵 DEVICE ACTIVITY: Created activity name: \(activityName)")

        // Calculate start and end times
        let now = Date()
        let endDate = now.addingTimeInterval(duration)

        print("🔵 DEVICE ACTIVITY: Current time: \(now)")
        print("🔵 DEVICE ACTIVITY: Session will end at: \(endDate)")
        print("🔵 DEVICE ACTIVITY: Time until expiration: \(duration) seconds")

        // Create date components for the schedule
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let startComponents = calendar.dateComponents(components, from: now)

        // For the schedule end, use a time well beyond the session duration to avoid intervalTooShort
        // We'll rely on the threshold event for the actual expiration trigger
        let scheduledEndDate = now.addingTimeInterval(max(duration, 15 * 60) + 60) // Add 1 minute buffer
        let endComponents = calendar.dateComponents(components, from: scheduledEndDate)

        print("🔵 DEVICE ACTIVITY: Start components: \(startComponents)")
        print("🔵 DEVICE ACTIVITY: End components (extended): \(endComponents)")

        // Create the schedule - this will trigger intervalDidEnd when it expires
        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false // One-time schedule for this session
        )

        print("🔵 DEVICE ACTIVITY: Created schedule (repeats: false)")

        // Create a threshold event that triggers at the exact session expiration time
        // This is the workaround for short sessions - the threshold event fires even if intervalDidEnd doesn't
        let thresholdComponents = DateComponents(second: Int(duration))
        let thresholdEventName = DeviceActivityEvent.Name("intentions.session.threshold")

        // Event monitors all apps/categories (we're using it just as a timer)
        let event = DeviceActivityEvent(
            applications: Set<ApplicationToken>(), // Empty - we're not monitoring specific apps
            categories: Set<ActivityCategoryToken>(), // Empty - just using as a timer
            webDomains: Set<WebDomainToken>(), // Empty
            threshold: thresholdComponents
        )

        let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [thresholdEventName: event]

        print("🔵 DEVICE ACTIVITY: Created threshold event at \(duration) seconds")

        do {
            // Start monitoring with both schedule AND threshold event
            print("🔵 DEVICE ACTIVITY: Calling deviceActivityCenter.startMonitoring() with threshold event...")
            try deviceActivityCenter.startMonitoring(activityName, during: schedule, events: events)
            print("✅ DEVICE ACTIVITY: Successfully scheduled with threshold event!")
            print("✅ DEVICE ACTIVITY: Extension will trigger via eventDidReachThreshold at \(endDate)")
            print("✅ DEVICE ACTIVITY: Activity name: \(activityName)")

            // Write to shared UserDefaults so we can verify in extension
            if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intent") {
                sharedDefaults.set(activityName.rawValue, forKey: "intentions.lastScheduledActivity")
                sharedDefaults.set(endDate, forKey: "intentions.lastScheduledEndTime")
                sharedDefaults.set(Date(), forKey: "intentions.lastScheduleTime")
                sharedDefaults.set(duration, forKey: "intentions.lastScheduledDuration")
                // CRITICAL: Store current session ID for validation in extension
                sharedDefaults.set(sessionId.uuidString, forKey: "intentions.currentSessionId")
                sharedDefaults.synchronize()
                print("✅ DEVICE ACTIVITY: Wrote schedule info to shared UserDefaults (including session ID)")
            }
        } catch {
            print("❌ DEVICE ACTIVITY: Failed to schedule: \(error)")
            print("❌ DEVICE ACTIVITY: Error details: \(error.localizedDescription)")
            // Don't throw - fall back to in-app timer only
        }
    }

    /// Cancel the active DeviceActivity schedule
    private func cancelDeviceActivitySchedule() {
        if let activityName = activeDeviceActivityName {
            deviceActivityCenter.stopMonitoring([activityName])
            activeDeviceActivityName = nil
            print("✅ DeviceActivity schedule cancelled")
        }
    }

    // MARK: - Widget Data Sharing

    /// Update widget with current blocking status
    private func updateWidgetBlockingStatus(isBlocking: Bool) {
        // Use shared UserDefaults for communication with widget extension
        let appGroupId = "group.oh.Intent"

        // Debug: Check current user context in main app
        let currentUser = getuid()
        let effectiveUser = geteuid()
        print("🔍 Main App User Context - UID: \(currentUser), EUID: \(effectiveUser)")

        // Debug: Check if we're in a sandbox
        let isSandboxed = getenv("APP_SANDBOX_CONTAINER_ID") != nil
        print("🔍 Main App Sandbox Status: \(isSandboxed ? "Sandboxed" : "Not Sandboxed")")

        // Force CFPreferences synchronization before creating UserDefaults
        CFPreferencesSynchronize(appGroupId as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            print("⚠️ ScreenTimeService: Failed to access App Group \(appGroupId), using standard UserDefaults")
            // Fallback to standard UserDefaults only
            UserDefaults.standard.set(isBlocking, forKey: "intentions.widget.blockingStatus")
            UserDefaults.standard.set(Date(), forKey: "intentions.widget.lastUpdate")
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        // Debug: Check UserDefaults access (avoid dictionaryRepresentation which triggers kCFPreferencesAnyUser)
        print("🔍 Main App UserDefaults Suite: Access successful")

        // Set the data
        print("📱 WIDGET STATUS UPDATE: Setting isBlocking = \(isBlocking)")
        sharedDefaults.set(isBlocking, forKey: "intentions.widget.blockingStatus")
        sharedDefaults.set(Date(), forKey: "intentions.widget.lastUpdate")

        // Force synchronization
        sharedDefaults.synchronize()

        // Also try setting in standard UserDefaults as fallback
        UserDefaults.standard.set(isBlocking, forKey: "intentions.widget.blockingStatus")
        UserDefaults.standard.set(Date(), forKey: "intentions.widget.lastUpdate")

        print("📱 WIDGET STATUS UPDATE: Reloading widget timelines...")
        // Force widget timeline refresh with multiple strategies
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: "IntentionsWidget")
        print("📱 WIDGET STATUS UPDATE: Complete - widget should now show \(isBlocking ? "Blocked" : "Open")")
    }

    // MARK: - Memory Monitoring

    /// Log current memory usage for debugging potential SpringBoard crashes
    private func logMemoryUsage(context: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMemoryMB = Double(info.resident_size) / 1024.0 / 1024.0
            print("📊 MEMORY [\(context)]: \(String(format: "%.2f", usedMemoryMB)) MB used")

            // Warn if memory usage is high (> 150 MB could trigger jetsam on some devices)
            if usedMemoryMB > 150.0 {
                print("⚠️ MEMORY WARNING: High memory usage detected - SpringBoard crash risk!")
            }
        } else {
            print("❌ MEMORY: Failed to get memory info (error: \(kerr))")
        }
    }

}
