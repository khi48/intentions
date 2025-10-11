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
                
                // Load schedule settings
                await loadScheduleSettings()
                
                // Load any existing active session
                await loadActiveSession()
                
                // Clean up any stale sessions from previous app runs FIRST
                if activeSession == nil {
                    await cleanupOldSessions()
                }
                
                // Only configure Screen Time service if authorized (setup completion is checked elsewhere)
                if authorizationStatus == .approved {
                    print("🔧 ContentViewModel: Authorized - will initialize ScreenTimeService after setup completion")

                    // Apply blocking only if schedule is currently active (after cleanup)
                    // Note: ScreenTimeService initialization happens in initializeScreenTimeServiceAfterSetup()
                    await applyScheduleBasedBlocking()

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

            // Use the first active session (if any)
            activeSession = activeSessions.first
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
                // Save session to persistence
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
            if !allApplications.isEmpty || !allCategories.isEmpty {
                // First clean up any previous session state
                await screenTimeService.cleanup()

                // Then allow only the session apps - this blocks everything else
                try await screenTimeService.allowApps(allApplications, categories: allCategories, allowWebsites: allowWebsites, duration: session.duration)
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
        // Prevent infinite loops from recursive calls
        guard !isApplyingDefaultBlocking else {
            print("⚠️ LOOP PREVENTION: applyDefaultBlocking already in progress - skipping recursive call")
            return
        }

        // Check if ScreenTimeService is initialized before using it
        guard screenTimeService.isReady else {
            print("⏳ ScreenTimeService not initialized yet - skipping default blocking")
            return
        }

        // Set flag to prevent recursive calls
        isApplyingDefaultBlocking = true
        defer { isApplyingDefaultBlocking = false }

        do {
            // CRITICAL: If there's an active session, preserve its blocking state
            // This prevents users from bypassing active sessions by disabling Intentions
            if let activeSession = activeSession, activeSession.isActive {
                print("🔒 Active session detected - preserving session blocking despite schedule change")
                await applySessionBlocking(for: activeSession)
                return
            }

            // Clear any previously applied session since we're applying default blocking
            currentlyAppliedSessionId = nil

            // Clean up any previous session state first
            await screenTimeService.cleanup()

            // Clean up any stale sessions in the database
            do {
                let allSessions = try await dataService.loadIntentionSessions()
                let staleSessions = allSessions.filter { session in
                    session.isActive && session.id != activeSession?.id
                }

                if !staleSessions.isEmpty {
                    for staleSession in staleSessions {
                        staleSession.complete()
                        try await dataService.saveIntentionSession(staleSession)
                    }
                }
            } catch {
                print("Error cleaning stale sessions: \(error)")
            }

            // Apply blocking based on schedule only when no session is active
            let currentlyActive = scheduleSettings.isCurrentlyActive

            if scheduleSettings.isEnabled && currentlyActive {
                // Schedule is active - block all apps (default behavior)
                try await screenTimeService.blockAllApps()
            } else {
                // Schedule is inactive - allow all access
                try await screenTimeService.allowAllAccess()
            }

        } catch {
            print("Failed to apply default blocking: \(error)")
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
    
    /// Initialize ScreenTimeService after setup completion - THE ONLY place initialization should happen
    private func initializeScreenTimeServiceAfterSetup() async {
        await withLoading {
            do {
                // Refresh authorization status
                authorizationStatus = await screenTimeService.authorizationStatus()

                // Only initialize if setup is complete and authorized
                if authorizationStatus == .approved && setupCoordinator.setupState?.isSetupSufficient == true {
                    if !screenTimeService.isReady {
                        print("🔧 ContentViewModel: Initializing ScreenTimeService after setup completion")
                        try await screenTimeService.initialize()
                    } else {
                        print("✅ ContentViewModel: ScreenTimeService already initialized after setup completion")
                    }

                    // Configure category mapping service for intelligent blocking
                    await screenTimeService.setCategoryMappingService(categoryMappingService)

                    // Configure restore callback for session expiration
                    await screenTimeService.setRestoreDefaultStateCallback { [weak self] in
                        await self?.applyDefaultBlocking()
                    }

                    // Apply blocking based on current schedule
                    await applyScheduleBasedBlocking()
                } else {
                    print("⏳ ContentViewModel: Setup not complete or not authorized - skipping ScreenTimeService initialization")
                }

            } catch {
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
