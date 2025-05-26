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
            activeSession = sessions.first { $0.isActive }
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
                
                // Apply appropriate blocking based on schedule
                print("🔄 Session ended - applying schedule-based state")
                await applyScheduleBasedBlocking()
                
            } catch {
                await handleError(error)
            }
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
