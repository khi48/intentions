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
    
    /// Whether we're showing settings
    var showingSettings: Bool = false
    
    /// Whether we're showing the category mapping setup
    var showingCategoryMappingSetup: Bool = false
    
    /// Category mapping service for smart app blocking
    let categoryMappingService = CategoryMappingService()
    
    /// Current selected tab for navigation
    var selectedTab: AppTab = .home
    
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
    ) {
        self.screenTimeService = screenTimeService ?? ScreenTimeService()
        self.dataService = dataService ?? (try? DataPersistenceService()) ?? MockDataPersistenceService()
    }
    
    // MARK: - App Lifecycle
    
    /// Initialize the app when it launches
    func initializeApp() async {
        await withLoading {
            do {
                // Check authorization status
                authorizationStatus = await screenTimeService.authorizationStatus()
                
                // Load schedule settings
                await loadScheduleSettings()
                
                // Initialize the Screen Time service if authorized
                if authorizationStatus == .approved {
                    try await screenTimeService.initialize()
                    
                    // Configure category mapping service for intelligent blocking
                    await screenTimeService.setCategoryMappingService(categoryMappingService)
                    
                    // Apply blocking only if schedule is currently active
                    await applyScheduleBasedBlocking()
                }
                
                // Load any existing active session
                await loadActiveSession()
                
                // Clean up any stale sessions from previous app runs
                if activeSession == nil {
                    print("🧹 No active session found - cleaning up any stale sessions from previous runs...")
                    await cleanupOldSessions()
                }
                
                // Check if category mapping setup is needed
                checkCategoryMappingSetupRequired()
                
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
                // Use default settings if none exist
                scheduleSettings = ScheduleSettings()
                print("📅 Using default schedule settings - enabled: \(scheduleSettings.isEnabled)")
            }
        } catch {
            print("❌ Failed to load schedule settings, using defaults: \(error)")
            scheduleSettings = ScheduleSettings()
        }
    }
    
    /// Apply blocking based on current schedule status
    private func applyScheduleBasedBlocking() async {
        do {
            let currentlyActive = scheduleSettings.isCurrentlyActive
            print("🔍 Schedule evaluation:")
            print("   - isEnabled: \(scheduleSettings.isEnabled)")
            print("   - isCurrentlyActive: \(currentlyActive)")
            
            if currentlyActive {
                print("🚫 Schedule is active - applying blocking")
                try await screenTimeService.blockAllApps()
                print("✅ Blocking applied successfully")
            } else {
                print("✅ Schedule is inactive - allowing all apps")
                try await screenTimeService.allowAllAccess()
                print("✅ Blocking removed successfully")
            }
        } catch {
            print("❌ Error in applyScheduleBasedBlocking: \(error)")
            await handleError(error)
        }
    }
    
    /// Load any existing active session from persistence
    private func loadActiveSession() async {
        do {
            let sessions = try await dataService.loadIntentionSessions()
            let activeSessions = sessions.filter { $0.isActive }
            
            print("🔍 SESSION LOADING ANALYSIS:")
            print("   📊 Total sessions in database: \(sessions.count)")
            print("   📈 Active sessions found: \(activeSessions.count)")
            
            if activeSessions.count > 1 {
                print("   ⚠️ MULTIPLE ACTIVE SESSIONS DETECTED - this could cause persistent app allowances!")
                for (index, session) in activeSessions.enumerated() {
                    let sessionId = session.id.uuidString.prefix(8)
                    print("     Active Session \(index + 1): \(sessionId)")
                    print("       - Apps: \(session.requestedApplications.count)")
                    print("       - Categories: \(session.selectedCategories.count)")
                    print("       - Remaining: \(session.remainingTime.formattedMinutesSeconds)")
                }
            }
            
            // Use the first active session (if any)
            activeSession = activeSessions.first
            if let session = activeSession {
                print("   ✅ Loaded active session: \(session.id.uuidString.prefix(8))")
            } else {
                print("   ✅ No active session found")
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
        authorizationStatus == .approved
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
    
    /// Show settings screen
    func showSettings() {
        showingSettings = true
    }
    
    /// Navigate to specific tab
    func navigateToTab(_ tab: AppTab) {
        selectedTab = tab
    }
    
    // MARK: - Session Management
    
    /// Start a new intention session
    func startSession(_ session: IntentionSession) async {
        await withLoading {
            do {
                // Save session to persistence
                try await dataService.saveIntentionSession(session)
                
                // Apply Screen Time restrictions if apps or categories are specified
                if !session.requestedApplications.isEmpty || !session.selectedCategories.isEmpty {
                    try await screenTimeService.allowApps(session.requestedApplications, categories: session.selectedCategories, duration: session.duration)
                }
                
                // Update local state
                activeSession = session
                showingIntentionPrompt = false
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// End the current session
    func endCurrentSession() async {
        guard let session = activeSession else { return }
        
        await withLoading {
            do {
                // Complete the session
                session.complete()
                try await dataService.saveIntentionSession(session)
                
                // Clear local state
                activeSession = nil
                
                // ATOMIC OPERATION: Clean up old sessions and immediately apply blocking
                print("🔄 Session ended - performing atomic cleanup and blocking...")
                await cleanupAndReapplyBlocking()
                
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
    
    /// Atomic operation: Clean up old sessions and immediately reapply blocking
    /// This prevents any timing gaps where apps might slip through unblocked
    private func cleanupAndReapplyBlocking() async {
        do {
            print("🔄 ATOMIC CLEANUP AND BLOCKING:")
            
            // Step 1: DETAILED analysis of all sessions in database
            print("   📋 Step 1: Analyzing ALL sessions in database...")
            let allSessions = try await dataService.loadIntentionSessions()
            
            print("   🔍 DETAILED SESSION ANALYSIS:")
            print("   📊 Total sessions in database: \(allSessions.count)")
            print("   🎯 Current activeSession ID: \(activeSession?.id.uuidString.prefix(8) ?? "none")")
            
            // Categorize all sessions
            let activeSessions = allSessions.filter { $0.isActive }
            let completedSessions = allSessions.filter { !$0.isActive }
            
            print("   📈 Active sessions: \(activeSessions.count)")
            print("   ✅ Completed sessions: \(completedSessions.count)")
            
            // Show details of each active session
            if !activeSessions.isEmpty {
                print("   🔍 ACTIVE SESSIONS DETAILS:")
                for (index, session) in activeSessions.enumerated() {
                    let sessionId = session.id.uuidString.prefix(8)
                    let isCurrentSession = session.id == activeSession?.id
                    let sessionApps = session.requestedApplications.count
                    let sessionCategories = session.selectedCategories.count
                    let remainingTime = session.remainingTime
                    
                    print("     Session \(index + 1): \(sessionId) \(isCurrentSession ? "(CURRENT)" : "(STALE)")")
                    print("       - Apps allowed: \(sessionApps)")
                    print("       - Categories allowed: \(sessionCategories)")
                    print("       - Remaining time: \(remainingTime.formattedMinutesSeconds)")
                    print("       - Start time: \(session.startTime)")
                    print("       - Duration: \(session.duration.formattedMinutesSeconds)")
                    
                    // Show specific apps if any
                    if sessionApps > 0 {
                        print("       - App tokens: \(session.requestedApplications.count) tokens")
                        // Don't print actual tokens as they're opaque, just count
                    }
                }
            }
            
            // Find stale sessions (active but not current)
            let staleSessions = activeSessions.filter { session in
                session.id != activeSession?.id
            }
            
            if !staleSessions.isEmpty {
                print("   ⚠️ Found \(staleSessions.count) STALE active sessions - these could be causing persistent app allowances!")
                for staleSession in staleSessions {
                    print("     🧹 Completing stale session: \(staleSession.id.uuidString.prefix(8))")
                    staleSession.complete()
                    try await dataService.saveIntentionSession(staleSession)
                }
                print("   ✅ All stale sessions completed")
            } else {
                print("   ✅ No stale sessions found - only current session is active")
            }
            
            // Step 2: Clean up ScreenTime state BEFORE applying new blocking
            print("   🧹 Step 2: Cleaning up ScreenTime background tasks...")
            await screenTimeService.cleanup()
            
            // Step 3: IMMEDIATELY apply fresh blocking after cleanup
            print("   🛡️ Step 3: Applying fresh blocking after cleanup...")
            let currentlyActive = scheduleSettings.isCurrentlyActive
            
            if scheduleSettings.isEnabled && currentlyActive {
                print("   🚫 Schedule is active - applying comprehensive blocking")
                try await screenTimeService.blockAllApps()
                print("   ✅ All apps blocked successfully")
            } else {
                print("   ✅ Schedule is inactive - allowing all apps")
                try await screenTimeService.allowAllAccess()
                print("   ✅ All restrictions removed")
            }
            
            print("✅ ATOMIC CLEANUP AND BLOCKING COMPLETED")
            
        } catch {
            print("❌ Error during atomic cleanup and blocking: \(error)")
            await handleError(error)
        }
    }
    
    // MARK: - Category Mapping Setup
    
    /// Check if category mapping setup is required for smart blocking
    private func checkCategoryMappingSetupRequired() {
        // Only show setup if:
        // 1. We have Screen Time authorization
        // 2. Category mapping setup is not completed
        // 3. We're not already showing other critical flows
        
        let needsSetup = authorizationStatus == .approved && 
                        !categoryMappingService.isTrulySetupCompleted &&
                        !showingIntentionPrompt &&
                        activeSession == nil
        
        if needsSetup {
            print("🔧 CATEGORY MAPPING: Setup required for smart app blocking")
            print("🔧 isSetupCompleted: \(categoryMappingService.isSetupCompleted), isTrulySetupCompleted: \(categoryMappingService.isTrulySetupCompleted)")
            showingCategoryMappingSetup = true
        } else {
            print("✅ CATEGORY MAPPING: No setup required - Truly completed: \(categoryMappingService.isTrulySetupCompleted)")
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
}

// MARK: - App Navigation

/// Represents the main navigation tabs in the app
enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case groups = "Groups"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .groups: return "square.stack.3d.up.fill"
        case .settings: return "gear"
        }
    }
}
