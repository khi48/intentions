//
//  ContentViewModel.swift
//  Intentions
//
//  Created by Claude on 12/07/2025.
//

import Foundation
import SwiftUI
@preconcurrency import FamilyControls

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
    
    /// Current selected tab for navigation
    var selectedTab: AppTab = .home
    
    /// Trigger to notify when app groups have changed
    var appGroupsDidChange: UUID = UUID()
    
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
            print("🗄️ CONTENT VM: Using provided data service")
        } else {
            self.dataService = try DataPersistenceService()
            print("✅ CONTENT VM: Successfully initialized real DataPersistenceService")
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
                print("🔐 CONTENT VM: Initial authorization status: \(authorizationStatus)")
                
                // If status is "Not Determined", double-check after a brief delay
                // This handles cases where the system needs time to return the correct status
                if authorizationStatus == .notDetermined {
                    print("🔄 CONTENT VM: Status is 'Not Determined', rechecking after delay...")
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    let recheckStatus = await screenTimeService.authorizationStatus()
                    print("🔐 CONTENT VM: Recheck authorization status: \(recheckStatus)")
                    
                    if recheckStatus != .notDetermined {
                        authorizationStatus = recheckStatus
                        print("✅ CONTENT VM: Updated authorization status to: \(authorizationStatus)")
                    }
                }
                
                // Load schedule settings
                await loadScheduleSettings()
                
                // Load any existing active session
                await loadActiveSession()
                
                // Clean up any stale sessions from previous app runs FIRST
                if activeSession == nil {
                    print("🧹 No active session found - cleaning up any stale sessions from previous runs...")
                    await cleanupOldSessions()
                }
                
                // Only initialize Screen Time service and proceed if already authorized
                if authorizationStatus == .approved {
                    print("✅ CONTENT VM: Authorization already approved - proceeding with ScreenTime initialization")
                    // Initialize the Screen Time service now that we're authorized
                    try await screenTimeService.initialize()
                    
                    // Configure category mapping service for intelligent blocking
                    await screenTimeService.setCategoryMappingService(categoryMappingService)
                    
                    // Apply blocking only if schedule is currently active (after cleanup)
                    await applyScheduleBasedBlocking()
                } else {
                    print("❌ CONTENT VM: Authorization not approved (\(authorizationStatus)) - deferring ScreenTime initialization to setup flow")
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
                print("📅 Loaded schedule settings - enabled: \(scheduleSettings.isEnabled), currently active: \(scheduleSettings.isCurrentlyActive)")
            } else {
                // Use default settings if none exist and save them
                scheduleSettings = ScheduleSettings()
                try await dataService.saveScheduleSettings(scheduleSettings)
                print("📅 No saved schedule settings found - created defaults with isEnabled = \(scheduleSettings.isEnabled)")
            }
        } catch {
            print("❌ Failed to load schedule settings, using defaults: \(error)")
            scheduleSettings = ScheduleSettings()
        }
    }
    
    /// Legacy method - now redirects to unified pipeline
    /// Apply blocking based on current schedule status
    private func applyScheduleBasedBlocking() async {
        print("🔄 LEGACY: applyScheduleBasedBlocking redirecting to unified pipeline")
        await applyDefaultBlocking()
    }
    
    /// Load any existing active session from persistence
    private func loadActiveSession() async {
        do {
            let sessions = try await dataService.loadIntentionSessions()
            let activeSessions = sessions.filter { $0.isActive }
            
            if activeSessions.count > 1 {
                print("⚠️ Multiple active sessions detected - cleaning up duplicates")
            }
            
            // Use the first active session (if any)
            activeSession = activeSessions.first
            if activeSession != nil {
                print("✅ Active session loaded")
            }
        } catch {
            // Non-critical error - just log it
            print("Failed to load active session: \(error)")
        }
    }
    
    // MARK: - Schedule Management
    
    /// Update schedule settings and apply blocking accordingly
    func updateScheduleSettings(_ newSettings: ScheduleSettings) async {
        print("🔧 ContentViewModel updating schedule settings - enabled: \(newSettings.isEnabled), currently active: \(newSettings.isCurrentlyActive)")
        scheduleSettings = newSettings
        
        // Save to persistence
        do {
            try await dataService.saveScheduleSettings(newSettings)
            print("✅ Schedule settings saved successfully")
        } catch {
            print("❌ Failed to save schedule settings in ContentViewModel: \(error)")
            await handleError(error)
        }
        
        // Apply blocking based on new schedule
        if authorizationStatus == .approved {
            print("📱 Applying schedule-based blocking...")
            await applyScheduleBasedBlocking()
        } else {
            print("⚠️ Screen Time not authorized, skipping blocking update")
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
                    
                    // Initialize the service now that we have authorization
                    try await screenTimeService.initialize()
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
        let ready = authorizationStatus == .approved
        print("🔍 CONTENT VM: isAppReady check - authorizationStatus: \(authorizationStatus), ready: \(ready)")
        return ready
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
                
                // Apply default blocking state (revert to block-all or allow-all based on schedule)
                print("🔄 Session ended - reverting to default blocking state...")
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
                
                print("⏰ Session extended by \(extensionTime.formattedMinutesSeconds)")
                print("📱 New total duration: \(session.duration.formattedMinutesSeconds)")
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Clean up any old/stale sessions that might still be running
    private func cleanupOldSessions() async {
        do {
            print("🔍 Loading all sessions to check for stale active sessions...")
            let allSessions = try await dataService.loadIntentionSessions()
            
            // Find any sessions that are marked as active but shouldn't be
            let staleSessions = allSessions.filter { session in
                session.isActive && session.id != activeSession?.id
            }
            
            if !staleSessions.isEmpty {
                print("⚠️ Found \(staleSessions.count) stale active sessions - cleaning up...")
                
                // Complete all stale sessions
                for staleSession in staleSessions {
                    print("   🧹 Completing stale session: \(staleSession.id)")
                    staleSession.complete()
                    try await dataService.saveIntentionSession(staleSession)
                }
                
                print("✅ All stale sessions cleaned up")
            } else {
                print("✅ No stale sessions found - clean state")
            }
            
            // Also ensure ScreenTimeService has no lingering session tasks
            print("🔧 Ensuring ScreenTimeService session cleanup...")
            await screenTimeService.cleanup()
            print("✅ ScreenTimeService session cleanup complete")
            
        } catch {
            print("❌ Error during session cleanup: \(error)")
            // Don't throw - this is cleanup, shouldn't block the main flow
        }
    }
    
    // MARK: - Unified Blocking Pipeline
    
    /// Apply session-based blocking - allows only the apps/categories specified in the session
    /// This is the core method used by both IntentionPrompt and QuickActions
    private func applySessionBlocking(for session: IntentionSession) async {
        do {
            // Collect all applications and categories for this session
            var allApplications = session.requestedApplications
            var allCategories = session.selectedCategories
            
            // If session has appGroups but no individual apps/categories (like QuickActions),
            // extract tokens from the app groups
            if !session.requestedAppGroups.isEmpty && allApplications.isEmpty && allCategories.isEmpty {
                let appGroups = try await dataService.loadAppGroups()
                for groupId in session.requestedAppGroups {
                    if let group = appGroups.first(where: { $0.id == groupId }) {
                        allApplications.formUnion(group.applications)
                        allCategories.formUnion(group.categories)
                    }
                }
                print("🎯 SESSION BLOCKING: Resolved \(session.requestedAppGroups.count) app groups to \(allApplications.count) apps and \(allCategories.count) categories")
            }
            
            // Apply Screen Time restrictions to allow only the specified apps/categories
            if !allApplications.isEmpty || !allCategories.isEmpty {
                // First clean up any previous session state
                await screenTimeService.cleanup()
                
                // Then allow only the session apps - this blocks everything else
                try await screenTimeService.allowApps(allApplications, categories: allCategories, duration: session.duration)
                print("✅ SESSION BLOCKING: Applied restrictions - allowing \(allApplications.count) apps and \(allCategories.count) categories, blocking all others")
            } else {
                print("⚠️ SESSION BLOCKING: No apps or categories found - session may not block effectively")
                // Fallback to default blocking
                await applyDefaultBlocking()
            }
            
        } catch {
            print("❌ SESSION BLOCKING: Failed to apply session blocking: \(error)")
            // Fallback to default blocking on error
            await applyDefaultBlocking()
        }
    }
    
    /// Apply default blocking state based on schedule settings
    /// Used when no session is active or when session ends
    private func applyDefaultBlocking() async {
        do {
            // Clean up any previous session state first
            await screenTimeService.cleanup()
            
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
            
            // Apply blocking based on schedule
            let currentlyActive = scheduleSettings.isCurrentlyActive
            
            if scheduleSettings.isEnabled && currentlyActive {
                // Schedule is active - block all apps (default behavior)
                try await screenTimeService.blockAllApps()
                print("✅ DEFAULT BLOCKING: Applied block-all (schedule is active)")
            } else {
                // Schedule is inactive - allow all access
                try await screenTimeService.allowAllAccess()
                print("✅ DEFAULT BLOCKING: Applied allow-all (schedule is inactive)")
            }
            
        } catch {
            print("❌ DEFAULT BLOCKING: Failed to apply default blocking: \(error)")
        }
    }
    
    /// Legacy method - now redirects to unified pipeline
    /// Atomic operation: Clean up old sessions and immediately reapply blocking
    /// This prevents any timing gaps where apps might slip through unblocked
    private func cleanupAndReapplyBlocking() async {
        print("🔄 LEGACY: cleanupAndReapplyBlocking redirecting to unified pipeline")
        await applyDefaultBlocking()
    }
    
    // MARK: - Category Mapping Setup
    
    /// Check if category mapping setup is required for smart blocking
    /// Check if comprehensive setup flow is required
    private func checkSetupRequired() async {
        print("🔧 CONTENT VM: Checking setup requirements...")
        
        // Validate setup state using the coordinator
        await setupCoordinator.validateSetupRequirements()
        
        // Use the coordinator's shouldShowSetup property which handles all the logic
        let needsSetup = setupCoordinator.shouldShowSetup &&
                        !showingIntentionPrompt &&
                        activeSession == nil
        
        let setupState = setupCoordinator.setupState
        print("🔧 CONTENT VM: Setup state sufficient: \(setupState?.isSetupSufficient == true), coordinator says show setup: \(setupCoordinator.shouldShowSetup), final decision: \(needsSetup)")
        
        if needsSetup {
            showingSetupFlow = true
            print("✅ CONTENT VM: Will show setup flow")
        } else {
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
            print("⚠️ CONTENT VM: Showing legacy category mapping setup")
        }
    }
    
    /// Handle completion of the unified setup flow
    func completeSetupFlow() {
        print("✅ SETUP FLOW: Completed successfully")
        showingSetupFlow = false
        
        // Re-initialize the app with the new authorization status
        Task {
            await reinitializeAfterSetup()
        }
    }
    
    /// Reinitialize app services after setup completion
    private func reinitializeAfterSetup() async {
        await withLoading {
            do {
                // Refresh authorization status
                authorizationStatus = await screenTimeService.authorizationStatus()
                print("🔐 CONTENT VM: Post-setup authorization status: \(authorizationStatus)")
                
                // If now authorized, initialize the Screen Time service
                if authorizationStatus == .approved {
                    print("✅ CONTENT VM: Now authorized - initializing ScreenTime service")
                    try await screenTimeService.initialize()
                    
                    // Configure category mapping service for intelligent blocking
                    await screenTimeService.setCategoryMappingService(categoryMappingService)
                    
                    // Apply blocking based on current schedule
                    await applyScheduleBasedBlocking()
                } else {
                    print("⚠️ CONTENT VM: Still not authorized after setup")
                }
                
                // Don't re-validate setup after completion - setup is already done
                print("🎉 CONTENT VM: Setup completed, skipping re-validation")
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Handle completion of category mapping setup
    func completeCategoryMappingSetup(_ mappingService: CategoryMappingService) {
        print("✅ CATEGORY MAPPING SETUP: Completed successfully")
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
        print("📢 CONTENT VM: App groups changed notification sent")
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
