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
        guard !isInitialized else {
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
        logger.info("ScreenTimeService initialized successfully")
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
            logger.error("Authorization failed: \(error.localizedDescription)")
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

        // Capture current blocking state before starting session
        preSessionBlockingState = !currentlyAllowedApps.isEmpty || managedSettingsStore.shield.applications != nil || managedSettingsStore.shield.applicationCategories != nil

        // CRITICAL: Clear previous session's shields to prevent cumulative effects
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.webContent.blockedByFilter = nil

        // Brief delay to ensure clearing takes effect
        try? await Task.sleep(nanoseconds: 50_000_000)

        if let mappingService = categoryMappingService {
            await applySmartCategoryBlocking(allowedCategoryTokens: categories, allowedAppTokens: tokens, mappingService: mappingService)
        } else {
            // Fallback: Use .all(except:) to block everything EXCEPT the session apps
            if !tokens.isEmpty {
                managedSettingsStore.shield.applicationCategories = .all(except: tokens)
                managedSettingsStore.shield.applications = nil
            } else {
                managedSettingsStore.shield.applicationCategories = .all()
                managedSettingsStore.shield.applications = nil
            }
        }

        // Conditionally allow web content
        if allowWebsites {
            managedSettingsStore.shield.webDomains = nil
            managedSettingsStore.webContent.blockedByFilter = nil
        } else {
            managedSettingsStore.shield.webDomains = nil
            managedSettingsStore.webContent.blockedByFilter = .all()
        }

        // Update tracking
        currentlyAllowedApps = tokens

        // Cancel any existing expiration task
        if sessionExpirationTask != nil {
            sessionExpirationTask?.cancel()
            sessionExpirationTask = nil
        }

        do {
            try await scheduleDeviceActivityExpiration(duration: duration, sessionId: sessionId)
        } catch {
            logger.error("DeviceActivity scheduling failed: \(error.localizedDescription)")
            throw AppError.appBlockingFailed("Failed to schedule expiration: \(error.localizedDescription)")
        }

        // Keep in-app timer for immediate handling
        sessionExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: duration.nanoseconds)

                guard !Task.isCancelled else { return }
                guard let self = self else { return }

                let isReplacing = await self.isSessionBeingReplaced
                guard !isReplacing else { return }

                // Restore the original state
                if let callback = await self.restoreDefaultStateCallback {
                    await callback()
                } else {
                    try? await self.blockAllApps()
                }
            } catch {
                return
            }
        }

        // Clear the session replacement flag
        isSessionBeingReplaced = false

        // Brief delay to ensure changes propagate
        try? await Task.sleep(nanoseconds: 50_000_000)
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
        // Set flag to prevent any in-flight callbacks from executing
        isSessionBeingReplaced = true

        // Cancel in-app timer
        if sessionExpirationTask != nil {
            sessionExpirationTask?.cancel()
            sessionExpirationTask = nil
        }

        // Cancel DeviceActivity schedule
        cancelDeviceActivitySchedule()

        // CRITICAL: Clear the current session ID from UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intent") {
            sharedDefaults.removeObject(forKey: "intentions.currentSessionId")
            sharedDefaults.synchronize()
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

        logger.info("🔍 SMART BLOCKING: Starting analysis...")
        logger.info("🔍 SMART BLOCKING: Allowed apps count: \(allowedAppTokens.count)")
        logger.info("🔍 SMART BLOCKING: Allowed category tokens count: \(allowedCategoryTokens.count)")

        // DIAGNOSTIC: Log which apps we're trying to allow
        for (index, token) in allowedAppTokens.enumerated().prefix(5) {
            logger.info("🔍 SMART BLOCKING: Allowed app #\(index + 1): hashValue=\(token.hashValue)")
        }

        // Get the blocking strategy from category mapping service (MainActor context required)
        let (categoriesToBlockCompletely, appsToBlockWithinUsedCategories) = await MainActor.run {
            let blockingStrategy = mappingService.analyzeBlockingStrategy(for: allowedAppTokens)
            return (blockingStrategy.categoriesToBlock, blockingStrategy.appsToBlockInUsedCategories)
        }

        logger.info("🔍 SMART BLOCKING: Categories to block completely: \(categoriesToBlockCompletely.map { $0.rawValue }.joined(separator: ", "))")
        logger.info("🔍 SMART BLOCKING: Apps to block within used categories: \(appsToBlockWithinUsedCategories.count)")

        // Step 1: Block entire categories that have NO selected apps
        // This allows categories with selected apps to remain accessible
        if !categoriesToBlockCompletely.isEmpty {
            let categoryTokensToBlock = await MainActor.run {
                mappingService.getCategoryTokensToBlock(for: categoriesToBlockCompletely)
            }

            // Remove any explicitly allowed categories from the block list
            let finalCategoriesToBlock = categoryTokensToBlock.subtracting(allowedCategoryTokens)

            logger.info("🔍 SMART BLOCKING: Final category tokens to block: \(finalCategoriesToBlock.count)")

            if !finalCategoriesToBlock.isEmpty {
                managedSettingsStore.shield.applicationCategories = .specific(finalCategoriesToBlock)
            } else {
                managedSettingsStore.shield.applicationCategories = nil
            }
        } else {
            logger.info("🔍 SMART BLOCKING: No categories to block completely")
            managedSettingsStore.shield.applicationCategories = nil
        }

        // Step 2: Within categories that have selected apps, block the unselected individual apps
        // This allows the selected apps to work while blocking distracting apps in the same category
        if !appsToBlockWithinUsedCategories.isEmpty {
            let appsToBlock = appsToBlockWithinUsedCategories.subtracting(allowedAppTokens)

            logger.info("🔍 SMART BLOCKING: Individual apps to block: \(appsToBlock.count)")

            if !appsToBlock.isEmpty {
                if appsToBlock.count <= 50 {
                    managedSettingsStore.shield.applications = appsToBlock
                    logger.info("✅ SMART BLOCKING: Blocking \(appsToBlock.count) individual apps (within limit)")
                } else {
                    let prioritizedApps = prioritizeAppsForBlocking(appsToBlock, limit: 50)
                    managedSettingsStore.shield.applications = prioritizedApps
                    logger.warning("⚠️ SMART BLOCKING: Hit 50-app limit - blocking \(prioritizedApps.count) prioritized apps, \(appsToBlock.count - prioritizedApps.count) apps may remain unblocked")
                }
            } else {
                logger.info("🔍 SMART BLOCKING: No individual apps to block")
                managedSettingsStore.shield.applications = nil
            }
        } else {
            logger.info("🔍 SMART BLOCKING: No apps in used categories to block")
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
        // Cancel any existing DeviceActivity FIRST
        if let oldActivityName = activeDeviceActivityName {
            deviceActivityCenter.stopMonitoring([oldActivityName])
            activeDeviceActivityName = nil
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        // Create a unique activity name for this session
        let activityName = DeviceActivityName("intentions.session.\(sessionId.uuidString)")
        activeDeviceActivityName = activityName

        // Calculate start and end times
        let now = Date()
        let endDate = now.addingTimeInterval(duration)

        // Create date components for the schedule
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let startComponents = calendar.dateComponents(components, from: now)

        // Use extended end to avoid intervalTooShort
        let scheduledEndDate = now.addingTimeInterval(max(duration, 15 * 60) + 60)
        let endComponents = calendar.dateComponents(components, from: scheduledEndDate)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        // Create threshold event for exact expiration
        let thresholdComponents = DateComponents(second: Int(duration))
        let thresholdEventName = DeviceActivityEvent.Name("intentions.session.threshold")

        let event = DeviceActivityEvent(
            applications: Set<ApplicationToken>(),
            categories: Set<ActivityCategoryToken>(),
            webDomains: Set<WebDomainToken>(),
            threshold: thresholdComponents
        )

        let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [thresholdEventName: event]

        do {
            try deviceActivityCenter.startMonitoring(activityName, during: schedule, events: events)

            // Write to shared UserDefaults for extension
            if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intent") {
                sharedDefaults.set(activityName.rawValue, forKey: "intentions.lastScheduledActivity")
                sharedDefaults.set(endDate, forKey: "intentions.lastScheduledEndTime")
                sharedDefaults.set(Date(), forKey: "intentions.lastScheduleTime")
                sharedDefaults.set(duration, forKey: "intentions.lastScheduledDuration")
                sharedDefaults.set(sessionId.uuidString, forKey: "intentions.currentSessionId")
                sharedDefaults.synchronize()
            }
        } catch {
            logger.error("DeviceActivity scheduling failed: \(error.localizedDescription)")
            // Don't throw - fall back to in-app timer only
        }
    }

    /// Cancel the active DeviceActivity schedule
    private func cancelDeviceActivitySchedule() {
        if let activityName = activeDeviceActivityName {
            deviceActivityCenter.stopMonitoring([activityName])
            activeDeviceActivityName = nil
        }
    }

    // MARK: - Widget Data Sharing

    /// Update widget with current blocking status
    private func updateWidgetBlockingStatus(isBlocking: Bool) {
        let appGroupId = "group.oh.Intent"

        // Force CFPreferences synchronization
        CFPreferencesSynchronize(appGroupId as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            // Fallback to standard UserDefaults only
            UserDefaults.standard.set(isBlocking, forKey: "intentions.widget.blockingStatus")
            UserDefaults.standard.set(Date(), forKey: "intentions.widget.lastUpdate")
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        // Set the data
        sharedDefaults.set(isBlocking, forKey: "intentions.widget.blockingStatus")
        sharedDefaults.set(Date(), forKey: "intentions.widget.lastUpdate")
        sharedDefaults.synchronize()

        // Also set in standard UserDefaults as fallback
        UserDefaults.standard.set(isBlocking, forKey: "intentions.widget.blockingStatus")
        UserDefaults.standard.set(Date(), forKey: "intentions.widget.lastUpdate")

        // Force widget timeline refresh
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: "IntentionsWidget")
    }

}
