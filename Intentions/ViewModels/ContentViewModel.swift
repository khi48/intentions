//
//  ContentViewModel.swift
//  Intentions
//
//  Created by Claude on 12/07/2025.
//

import Foundation
import SwiftUI
@preconcurrency import FamilyControls
import WidgetKit

/// Main app state coordinator and navigation controller
/// Manages global app state, authorization status, and navigation flow
@MainActor
@Observable
final class ContentViewModel: Sendable {
    
    // MARK: - Published Properties
    
    /// Current authorization status for Screen Time
    private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    
    /// Whether the app is currently loading or performing operations
    var isLoading: Bool = false
    
    /// Current error message to display to user
    var errorMessage: String? = nil
    
    /// Current active session if any
    private(set) var activeSession: IntentionSession? = nil
    
    /// Current schedule settings
    private var scheduleSettings: ScheduleSettings = ScheduleSettings()
    
    /// Whether we're showing the intention prompt
    var showingIntentionPrompt: Bool = false
    
    /// Whether we're showing the category mapping setup
    var showingCategoryMappingSetup: Bool = false
    
    /// Whether we're showing the unified setup flow
    var showingSetupFlow: Bool = false
    
    /// Category mapping service for smart app blocking
    let categoryMappingService = CategoryMappingService()
    
    /// Setup coordinator for managing app configuration
    let setupCoordinator: SetupCoordinator

    /// Shared quick actions view model for consistency across Home and QuickActions tabs
    let sharedQuickActionsViewModel = QuickActionsViewModel()

    /// Current selected tab for navigation
    var selectedTab: AppTab = .home
    
    /// Trigger to notify when app groups have changed
    var appGroupsDidChange: UUID = UUID()

    /// Flag to prevent infinite loops in applyDefaultBlocking
    private var isApplyingDefaultBlocking: Bool = false

    /// Track the currently applied session to prevent duplicate session blocking
    private var currentlyAppliedSessionId: UUID? = nil

    // MARK: - Dependencies
    
    let screenTimeService: ScreenTimeManaging
    private let dataService: DataPersisting
    
    /// Public access to data service for child views
    var dataServiceProvider: DataPersisting {
        dataService
    }
    
    // MARK: - Initialization
    
    init(
        screenTimeService: ScreenTimeManaging? = nil,
        dataService: DataPersisting? = nil
    ) throws {
        self.screenTimeService = screenTimeService ?? ScreenTimeService()
        
        if let providedService = dataService {
            self.dataService = providedService
        } else {
            self.dataService = try DataPersistenceService()
        }
        
        // Initialize setup coordinator
        self.setupCoordinator = SetupCoordinator(
            screenTimeService: self.screenTimeService,
            categoryMappingService: categoryMappingService
        )
    }
    
    // MARK: - App Lifecycle
    
    /// Initialize the app when it launches
    func initializeApp() async {
        await withLoading {
            do {
                // Check authorization status
                authorizationStatus = await screenTimeService.authorizationStatus()

                // If status is "Not Determined", double-check after a brief delay
                // This handles cases where the system needs time to return the correct status
                if authorizationStatus == .notDetermined {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    let recheckStatus = await screenTimeService.authorizationStatus()

                    if recheckStatus != .notDetermined {
                        authorizationStatus = recheckStatus
                    }
                }
                
                // Initialize notification service and request permissions if needed
                // Do this early in app startup to establish notification capabilities
                await NotificationService.shared.checkAuthorizationStatus()

                // Request notification permissions on first launch if not determined
                let notificationStatus = NotificationService.shared.authorizationStatus
                if notificationStatus == .notDetermined {
                    print("🔔 ContentViewModel: Requesting notification permissions on app startup")
                    let granted = await NotificationService.shared.requestPermissions()
                    if granted {
                        print("✅ ContentViewModel: Notification permissions granted")
                    } else {
                        print("❌ ContentViewModel: Notification permissions denied")
                    }
                }

                // Load schedule settings
                await loadScheduleSettings()

                // Load any existing active session
                await loadActiveSession()
                
                // Clean up any stale sessions from previous app runs FIRST
                if activeSession == nil {
                    await cleanupOldSessions()
                }
                
                // Only configure Screen Time service if authorized AND setup is complete
                if authorizationStatus == .approved {
                    print("🔧 ContentViewModel: Authorized - waiting for setup completion to initialize")

                    // Test widget communication after a brief delay to avoid App Group cache issues
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                    await testWidgetCommunication()
                }
                
                // Retry category mapping validation after initialization delay
                // This addresses the iOS ApplicationToken loading issue
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
                    categoryMappingService.retrySetupValidation()

                    // Re-check setup requirements after retry
                    await checkSetupRequired()
                }

                // Check if comprehensive setup is needed
                await checkSetupRequired()
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Load schedule settings from persistence
    private func loadScheduleSettings() async {
        do {
            if let savedSettings = try await dataService.loadScheduleSettings() {
                scheduleSettings = savedSettings
            } else {
                // Use default settings if none exist and save them
                scheduleSettings = ScheduleSettings()
                try await dataService.saveScheduleSettings(scheduleSettings)
            }
        } catch {
            print("Failed to load schedule settings, using defaults: \(error)")
            scheduleSettings = ScheduleSettings()
        }
    }
    
    /// Legacy method - now redirects to unified pipeline
    /// Apply blocking based on current schedule status
    private func applyScheduleBasedBlocking() async {
        await applyDefaultBlocking()
    }
    
    /// Load any existing active session from persistence
    private func loadActiveSession() async {
        do {
            let sessions = try await dataService.loadIntentionSessions()
            let activeSessions = sessions.filter { $0.isActive }

            if activeSessions.count > 1 {
                print("Multiple active sessions detected - cleaning up duplicates")
            }

            // Check if DeviceActivityMonitor extension expired a session while app was closed
            if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions"),
               sharedDefaults.bool(forKey: "intentions.session.expired") {
                print("🔔 Extension expired a session - cleaning up and applying default blocking")
                // Clear the flag
                sharedDefaults.set(false, forKey: "intentions.session.expired")
                sharedDefaults.synchronize()

                // Mark any active sessions as completed
                for session in activeSessions {
                    session.complete()
                    try await dataService.saveIntentionSession(session)
                }

                activeSession = nil

                // Apply default blocking since session expired
                await applyDefaultBlocking()
                return
            }

            // Check if the active session has expired while app was in background/closed
            if let loadedSession = activeSessions.first {
                if loadedSession.isExpired {
                    print("🕐 Session expired while app was in background - ending session")
                    // Session expired while app wasn't running - complete it now
                    loadedSession.complete()
                    try await dataService.saveIntentionSession(loadedSession)
                    activeSession = nil

                    // Apply default blocking since session expired
                    await applyDefaultBlocking()
                } else {
                    // Session is still active
                    activeSession = loadedSession
                }
            } else {
                activeSession = nil
            }
        } catch {
            // Non-critical error - just log it
            print("Failed to load active session: \(error)")
        }
    }
    
    // MARK: - Schedule Management
    
    /// Update schedule settings and apply blocking accordingly
    func updateScheduleSettings(_ newSettings: ScheduleSettings) async {
        scheduleSettings = newSettings

        // Save to persistence
        do {
            try await dataService.saveScheduleSettings(newSettings)
        } catch {
            print("Failed to save schedule settings: \(error)")
            await handleError(error)
        }

        // Apply blocking based on new schedule
        if authorizationStatus == .approved {
            await applyScheduleBasedBlocking()
        }
    }
    
    // MARK: - Authorization Management
    
    /// Request Screen Time authorization from user
    func requestAuthorization() async {
        await withLoading {
            do {
                let success = await screenTimeService.requestAuthorization()
                if success {
                    authorizationStatus = await screenTimeService.authorizationStatus()
                    print("✅ ContentViewModel: Authorization successful - service will be initialized after setup completion")
                } else {
                    await handleError(AppError.screenTimeAuthorizationFailed)
                }
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Check if app is ready to use (authorized and initialized)
    var isAppReady: Bool {
        return authorizationStatus == .approved
    }
    
    // MARK: - Navigation Actions
    
    /// Show the intention prompt to create a new session
    func showIntentionPrompt() {
        guard isAppReady else {
            Task {
                await handleError(AppError.screenTimeAuthorizationRequired("Please authorize Screen Time access first"))
            }
            return
        }
        showingIntentionPrompt = true
    }
    
    /// Navigate to Settings tab and ensure we're at the home page
    func showSettings() {
        // Navigate to Settings tab and reset navigation to home page
        selectedTab = .settings
        // The navigation reset will be handled by the TabView's selection binding
        // which already has logic to reset navigation when navigating TO Settings
    }
    
    /// Navigate to specific tab
    func navigateToTab(_ tab: AppTab) {
        selectedTab = tab
    }
    
    // Callback to reset Settings state when navigating away
    var onSettingsTabExit: (() -> Void)?
    
    // MARK: - Session Management
    
    /// Start a new intention session using unified blocking pipeline
    func startSession(_ session: IntentionSession) async {
        await withLoading {
            do {
                // If there's an existing active session, cancel its timers FIRST
                // This prevents the old session's expiration callback from re-blocking apps
                if let existingSession = activeSession, existingSession.isActive {
                    print("🔄 START SESSION: Cancelling timers for existing session \(existingSession.id.uuidString.prefix(8))")

                    // Cancel the old session's timers WITHOUT triggering re-blocking
                    await screenTimeService.cancelSessionTimers()

                    // Now complete the session and save
                    print("🔄 START SESSION: Completing existing session")
                    existingSession.complete()
                    try await dataService.saveIntentionSession(existingSession)

                    // Clear the session state to force re-application
                    activeSession = nil
                    currentlyAppliedSessionId = nil

                    // Explicitly block all apps to ensure clean slate between sessions
                    // This prevents cumulative ManagedSettingsStore issues
                    print("🔄 START SESSION: Blocking all apps before applying new session")
                    try await screenTimeService.blockAllApps()

                    // Brief delay to ensure blocking takes effect
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    print("🔄 START SESSION: Ready to apply new session")
                }

                // Save new session to persistence
                try await dataService.saveIntentionSession(session)

                // Apply session-based blocking using unified pipeline
                await applySessionBlocking(for: session)

                // Update local state
                activeSession = session
                showingIntentionPrompt = false

            } catch {
                await handleError(error)
            }
        }
    }
    
    /// End the current session using unified blocking pipeline
    func endCurrentSession() async {
        guard let session = activeSession else { return }

        await withLoading {
            do {
                // Complete the session
                session.complete()
                try await dataService.saveIntentionSession(session)

                // Clear local state
                activeSession = nil
                currentlyAppliedSessionId = nil

                // Apply default blocking state (revert to block-all or allow-all based on schedule)
                await applyDefaultBlocking()

            } catch {
                await handleError(error)
            }
        }
    }

    /// Handle automatic session expiration (called by ScreenTimeService background task)
    /// This is triggered when the session timer expires automatically
    private func handleSessionExpiration() async {
        print("⏰ SESSION EXPIRED: Automatic expiration triggered by background task")

        guard let session = activeSession else {
            print("⚠️ SESSION EXPIRED: No active session found - already expired")
            return
        }

        print("⏰ SESSION EXPIRED: Completing session \(session.id.uuidString.prefix(8))")

        do {
            // Complete the session
            session.complete()
            try await dataService.saveIntentionSession(session)

            // Clear local state
            activeSession = nil
            currentlyAppliedSessionId = nil

            print("✅ SESSION EXPIRED: Session marked as complete and cleared from state")

            // Apply default blocking state (revert to block-all or allow-all based on schedule)
            await applyDefaultBlocking()

            // Send notification to user
            await NotificationService.shared.sendSessionExpiredNotification()

            print("✅ SESSION EXPIRED: Re-blocking applied and notification sent")

        } catch {
            print("❌ SESSION EXPIRED: Error completing session: \(error)")
            // Still apply default blocking even if save fails
            await applyDefaultBlocking()
        }
    }

    /// Extend the current session by additional time
    func extendCurrentSession(by extensionTime: TimeInterval) async {
        guard let session = activeSession else { return }
        
        await withLoading {
            do {
                // Extend the session duration
                session.duration += extensionTime
                try await dataService.saveIntentionSession(session)
                
                // Update local state
                activeSession = session
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Clean up any old/stale sessions that might still be running
    private func cleanupOldSessions() async {
        do {
            let allSessions = try await dataService.loadIntentionSessions()

            // Find any sessions that are marked as active but shouldn't be
            let staleSessions = allSessions.filter { session in
                session.isActive && session.id != activeSession?.id
            }

            if !staleSessions.isEmpty {
                // Complete all stale sessions
                for staleSession in staleSessions {
                    staleSession.complete()
                    try await dataService.saveIntentionSession(staleSession)
                }
            }

            // Also ensure ScreenTimeService has no lingering session tasks
            await screenTimeService.cleanup()

        } catch {
            print("Error during session cleanup: \(error)")
            // Don't throw - this is cleanup, shouldn't block the main flow
        }
    }
    
    // MARK: - Unified Blocking Pipeline
    
    /// Apply session-based blocking - allows only the apps/categories specified in the session
    /// This is the core method used by both IntentionPrompt and QuickActions
    private func applySessionBlocking(for session: IntentionSession) async {
        // Check if ScreenTimeService is initialized before using it
        guard screenTimeService.isReady else {
            print("❌ APPLY SESSION: ScreenTimeService not initialized - cannot start session")
            await handleError(AppError.serviceUnavailable("Screen Time service is not ready. Please complete setup first."))
            return
        }

        // Prevent re-applying the same session repeatedly
        if currentlyAppliedSessionId == session.id {
            print("🔄 SESSION ALREADY APPLIED: Session \(session.id.uuidString.prefix(8)) already applied - skipping duplicate")
            return
        }

        print("🎯 APPLYING SESSION BLOCKING: Starting session \(session.id.uuidString.prefix(8))")
        currentlyAppliedSessionId = session.id

        do {
            // Collect all applications, categories, and website preferences for this session
            var allApplications = session.requestedApplications
            var allCategories = session.selectedCategories
            var allowWebsites = session.allowAllWebsites

            // If session has appGroups but no individual apps/categories (like QuickActions),
            // extract tokens from the app groups
            if !session.requestedAppGroups.isEmpty && allApplications.isEmpty && allCategories.isEmpty {
                let appGroups = try await dataService.loadAppGroups()
                for groupId in session.requestedAppGroups {
                    if let group = appGroups.first(where: { $0.id == groupId }) {
                        allApplications.formUnion(group.applications)
                        allCategories.formUnion(group.categories)
                        // If any group allows websites, enable website access for the session
                        if group.allowAllWebsites {
                            allowWebsites = true
                        }
                    }
                }
            }

            // Apply Screen Time restrictions to allow only the specified apps/categories
            // NOTE: allowApps() handles cleanup internally - no need for explicit cleanup() call
            if !allApplications.isEmpty || !allCategories.isEmpty {
                // Allow only the session apps - this blocks everything else
                // Pass session ID for tracking and validation in DeviceActivity extension
                try await screenTimeService.allowApps(allApplications, categories: allCategories, allowWebsites: allowWebsites, duration: session.duration, sessionId: session.id)
            } else {
                // Fallback to default blocking
                await applyDefaultBlocking()
            }
            
        } catch {
            print("Failed to apply session blocking: \(error)")
            // Fallback to default blocking on error
            await applyDefaultBlocking()
        }
    }
    
    /// Apply default blocking state based on schedule settings
    /// Used when no session is active or when session ends
    /// IMPORTANT: If a session is active, preserves session blocking regardless of schedule settings
    private func applyDefaultBlocking() async {
        print("🔧 DEFAULT BLOCKING: Starting applyDefaultBlocking()")

        // Prevent infinite loops from recursive calls
        guard !isApplyingDefaultBlocking else {
            print("⚠️ LOOP PREVENTION: applyDefaultBlocking already in progress - skipping recursive call")
            return
        }

        // Check if ScreenTimeService is initialized before using it
        guard screenTimeService.isReady else {
            print("⏳ DEFAULT BLOCKING: ScreenTimeService not initialized yet - skipping")
            return
        }

        // Set flag to prevent recursive calls
        isApplyingDefaultBlocking = true
        defer { isApplyingDefaultBlocking = false }

        do {
            // CRITICAL: If there's an active session, preserve its blocking state
            // This prevents users from bypassing active sessions by disabling Intentions
            if let activeSession = activeSession, activeSession.isActive {
                print("🔒 DEFAULT BLOCKING: Active session detected - preserving session blocking")
                await applySessionBlocking(for: activeSession)
                return
            }

            // Clear any previously applied session since we're applying default blocking
            currentlyAppliedSessionId = nil
            print("🔧 DEFAULT BLOCKING: Cleared session tracking (no active session)")

            // Clean up any stale sessions in the database
            do {
                let allSessions = try await dataService.loadIntentionSessions()
                let staleSessions = allSessions.filter { session in
                    session.isActive && session.id != activeSession?.id
                }

                if !staleSessions.isEmpty {
                    print("🧹 DEFAULT BLOCKING: Cleaning up \(staleSessions.count) stale sessions")
                    for staleSession in staleSessions {
                        staleSession.complete()
                        try await dataService.saveIntentionSession(staleSession)
                    }
                }
            } catch {
                print("❌ DEFAULT BLOCKING: Error cleaning stale sessions: \(error)")
            }

            // Apply blocking based on schedule only when no session is active
            // NOTE: blockAllApps() and allowAllAccess() handle cleanup internally - no need for explicit cleanup() call
            let currentlyActive = scheduleSettings.isCurrentlyActive

            print("🔧 DEFAULT BLOCKING: Schedule settings - enabled: \(scheduleSettings.isEnabled), currentlyActive: \(currentlyActive)")

            if scheduleSettings.isEnabled && currentlyActive {
                // Schedule is active - block all apps (default behavior)
                print("🚫 DEFAULT BLOCKING: Blocking all apps (schedule active)")
                try await screenTimeService.blockAllApps()
                print("✅ DEFAULT BLOCKING: Successfully blocked all apps")
            } else {
                // Schedule is inactive - allow all access
                print("✅ DEFAULT BLOCKING: Allowing all access (schedule inactive)")
                try await screenTimeService.allowAllAccess()
                print("✅ DEFAULT BLOCKING: Successfully allowed all access")
            }

        } catch {
            print("❌ DEFAULT BLOCKING: Failed to apply default blocking: \(error)")
        }
    }
    
    /// Legacy method - now redirects to unified pipeline
    /// Atomic operation: Clean up old sessions and immediately reapply blocking
    /// This prevents any timing gaps where apps might slip through unblocked
    private func cleanupAndReapplyBlocking() async {
        await applyDefaultBlocking()
    }
    
    // MARK: - Category Mapping Setup
    
    /// Check if category mapping setup is required for smart blocking
    /// Check if comprehensive setup flow is required
    private func checkSetupRequired() async {
        // Validate setup state using the coordinator
        await setupCoordinator.validateSetupRequirements()

        // Use the coordinator's shouldShowSetup property which handles all the logic
        let needsSetup = setupCoordinator.shouldShowSetup &&
                        !showingIntentionPrompt &&
                        activeSession == nil

        if needsSetup {
            showingSetupFlow = true
        } else {
            // Setup is complete - initialize ScreenTimeService if needed
            await initializeScreenTimeServiceAfterSetup()

            // Fallback to legacy category mapping setup if needed
            checkLegacyCategoryMappingSetupRequired()
        }
    }
    
    /// Legacy fallback for category mapping setup (to be removed later)
    private func checkLegacyCategoryMappingSetupRequired() {
        // Only show setup if:
        // 1. We have Screen Time authorization
        // 2. Category mapping setup is not completed
        // 3. We're not already showing other critical flows
        
        let needsSetup = authorizationStatus == .approved && 
                        !categoryMappingService.isTrulySetupCompleted &&
                        !showingIntentionPrompt &&
                        activeSession == nil
        
        if needsSetup {
            showingCategoryMappingSetup = true
        }
    }
    
    /// Handle completion of the unified setup flow
    func completeSetupFlow() {
        showingSetupFlow = false

        // Re-initialize the app with the new authorization status
        Task {
            await initializeScreenTimeServiceAfterSetup()
        }
    }
    
    /// Initialize and configure ScreenTimeService after setup completion
    /// This is THE ONLY place where ScreenTimeService should be initialized
    private func initializeScreenTimeServiceAfterSetup() async {
        print("🔍 INIT CHECK: initializeScreenTimeServiceAfterSetup() called")
        print("🔍 INIT CHECK: authorizationStatus = \(authorizationStatus)")
        print("🔍 INIT CHECK: setupState = \(String(describing: setupCoordinator.setupState))")
        print("🔍 INIT CHECK: isSetupSufficient = \(setupCoordinator.setupState?.isSetupSufficient ?? false)")
        print("🔍 INIT CHECK: screenTimeService.isReady = \(screenTimeService.isReady)")

        await withLoading {
            do {
                // Refresh authorization status
                authorizationStatus = await screenTimeService.authorizationStatus()
                print("🔍 INIT CHECK: Refreshed authorizationStatus = \(authorizationStatus)")

                // Only initialize and configure if authorized and setup is complete
                if authorizationStatus == .approved && setupCoordinator.setupState?.isSetupSufficient == true {
                    // Initialize the service if not already done
                    if !screenTimeService.isReady {
                        print("🔧 ContentViewModel: Initializing ScreenTimeService after setup completion")
                        try await screenTimeService.initialize()
                        print("✅ ContentViewModel: ScreenTimeService initialized successfully")
                    } else {
                        print("✅ ContentViewModel: ScreenTimeService already initialized")
                    }

                    // Configure category mapping service for intelligent blocking
                    await screenTimeService.setCategoryMappingService(categoryMappingService)

                    // Configure restore callback for session expiration
                    await screenTimeService.setRestoreDefaultStateCallback { [weak self] in
                        await self?.handleSessionExpiration()
                    }

                    // IMPORTANT: Do NOT call applyScheduleBasedBlocking() here
                    // If there's an active session, it's already been loaded and applied
                    // If there's no active session, the ManagedSettingsStore should already be in the correct state
                    // Calling this would re-trigger allowApps() which resets timers!
                    print("🔧 ContentViewModel: ScreenTimeService initialized - NOT applying blocking (would interfere with active session)")
                } else if authorizationStatus != .approved {
                    print("⏳ ContentViewModel: Not authorized - skipping ScreenTimeService initialization")
                    print("   Current status: \(authorizationStatus)")
                } else {
                    print("⏳ ContentViewModel: Setup not complete - skipping ScreenTimeService initialization")
                    print("   isSetupSufficient: \(setupCoordinator.setupState?.isSetupSufficient ?? false)")
                }

            } catch {
                print("❌ ContentViewModel: Error during initialization: \(error)")
                await handleError(error)
            }
        }
    }
    
    /// Handle completion of category mapping setup
    func completeCategoryMappingSetup(_ mappingService: CategoryMappingService) {
        showingCategoryMappingSetup = false

        // The mapping service is already shared, so smart blocking is now available
        // Future session starts will use the category-based prioritization
    }
    
    // MARK: - Error Handling
    
    func handleError(_ error: Error) async {
        await MainActor.run {
            if let appError = error as? AppError {
                errorMessage = appError.errorDescription
            } else {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Helper Methods
    
    /// Execute an operation with loading state management
    private func withLoading<T: Sendable>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
    
    // MARK: - App Group Notifications
    
    /// Notify that app groups have been modified
    func notifyAppGroupsChanged() {
        appGroupsDidChange = UUID()
    }
    
    /// Test widget communication by manually writing data
    private func testWidgetCommunication() async {
        let appGroupId = "group.oh.Intentions"

        // Force CFPreferences synchronization before creating UserDefaults
        CFPreferencesSynchronize(appGroupId as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            print("⚠️ ContentViewModel: Failed to access App Group \(appGroupId), using standard UserDefaults for test")
            // Fallback to standard UserDefaults only
            UserDefaults.standard.set(true, forKey: "intentions.widget.blockingStatus")
            UserDefaults.standard.set(Date(), forKey: "intentions.widget.lastUpdate")
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        // Write test data
        let testStatus = true
        let testDate = Date()

        // Try shared UserDefaults
        sharedDefaults.set(testStatus, forKey: "intentions.widget.blockingStatus")
        sharedDefaults.set(testDate, forKey: "intentions.widget.lastUpdate")
        sharedDefaults.synchronize()

        // Also try standard UserDefaults
        UserDefaults.standard.set(testStatus, forKey: "intentions.widget.blockingStatus")
        UserDefaults.standard.set(testDate, forKey: "intentions.widget.lastUpdate")
        UserDefaults.standard.synchronize()
    }
}

// MARK: - App Navigation

/// Represents the main navigation tabs in the app
enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case groups = "Groups"
    case quickActions = "Quick Actions"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .groups: return "square.stack.3d.up.fill"
        case .quickActions: return "bolt.fill"
        case .settings: return "gear"
        }
    }
}
