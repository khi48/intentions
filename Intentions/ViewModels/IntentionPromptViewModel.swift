//
//  IntentionPromptViewModel.swift
//  Intentions
//
//  Created by Claude on 13/07/2025.
//

import Foundation
import SwiftUI
@preconcurrency import FamilyControls
import ManagedSettings

/// ViewModel for the intention prompt interface
/// Handles app selection, duration settings, and session creation
@MainActor
@Observable
final class IntentionPromptViewModel: Sendable {
    
    // MARK: - Published Properties
    
    /// Whether the view is currently loading
    var isLoading: Bool = false
    
    /// Current error message to display
    var errorMessage: String? = nil
    
    /// Selected duration for the session
    var selectedDuration: TimeInterval = AppConstants.Session.defaultDuration
    
    /// Currently selected app groups
    var selectedAppGroups: Set<UUID> = []
    
    /// Currently selected individual apps
    var selectedApplications: Set<ApplicationToken> = []
    
    
    /// Available app groups loaded from persistence
    private(set) var availableAppGroups: [AppGroup] = []
    
    /// Available discovered apps
    private(set) var discoveredApps: [DiscoveredApp] = []
    
    /// Filtered discovered apps (excluding system apps by default)
    var filteredDiscoveredApps: [DiscoveredApp] {
        discoveredApps.filter { !$0.isSystemApp || showSystemApps }
    }
    
    /// Whether to show system apps in the app picker
    var showSystemApps: Bool = false
    
    /// Search text for filtering apps
    var searchText: String = "" {
        didSet {
            filterApps()
        }
    }
    
    /// Filtered apps based on search text
    private(set) var searchResults: [DiscoveredApp] = []
    
    /// Whether the view is showing app selection
    var showingAppSelection: Bool = false
    
    /// Whether the view is showing duration picker
    var showingDurationPicker: Bool = false
    
    /// Whether the Family Activity Picker is showing
    var showingFamilyActivityPicker: Bool = false
    
    /// Sheet presentation type for sheet management (excludes FamilyActivityPicker)
    enum SheetType: Identifiable {
        case durationPicker
        case appSelection
        
        var id: String {
            switch self {
            case .durationPicker: return "duration"
            case .appSelection: return "apps"
            }
        }
    }
    
    /// Current sheet being presented (if any)
    var currentSheet: SheetType? = nil
    
    /// Family Activity selection from picker (contains apps that will be ALLOWED)
    var familyActivitySelection = FamilyActivitySelection(includeEntireCategory: true)
    
    /// Whether app selection is ready (always true with category mapping)
    var hasDiscoveredAllApps: Bool = true
    
    // MARK: - Dependencies
    
    private let dataService: DataPersisting
    private let screenTimeService: ScreenTimeManaging
    private let categoryMappingService: CategoryMappingService
    private let onSessionStart: (IntentionSession) async -> Void
    private let onCancel: () -> Void
    
    // MARK: - Initialization
    
    init(
        dataService: DataPersisting,
        screenTimeService: ScreenTimeManaging,
        categoryMappingService: CategoryMappingService,
        onSessionStart: @escaping (IntentionSession) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.dataService = dataService
        self.screenTimeService = screenTimeService
        self.categoryMappingService = categoryMappingService
        self.onSessionStart = onSessionStart
        self.onCancel = onCancel
        
        // Initialize search results
        filterApps()
    }
    
    // MARK: - Lifecycle
    
    /// Load initial data when view appears
    func loadData() async {
        await withLoading {
            do {
                // Load app groups
                availableAppGroups = try await dataService.loadAppGroups()
                
                // For now, create some mock discovered apps since app discovery
                // requires Screen Time authorization and complex setup
                discoveredApps = createMockDiscoveredApps()
                
                // Update search results
                filterApps()
                
                // Try to load previously discovered "all apps" selection
                await loadAllAvailableApps()
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Initialize app selection - category mapping provides all discovery
    private func loadAllAvailableApps() async {
        // With category mapping completed, we don't need separate app discovery
        print("✅ CATEGORY MAPPING: Using category mapping for app discovery")
        print("📱 Individual app selection works directly through FamilyActivityPicker")
        
        // Initialize empty selection - user will select what they want to allow
        familyActivitySelection = FamilyActivitySelection(includeEntireCategory: true)
    }
    
    
    // MARK: - App Selection
    
    /// Toggle selection of an app group
    func toggleAppGroup(_ groupId: UUID) {
        if selectedAppGroups.contains(groupId) {
            selectedAppGroups.remove(groupId)
        } else {
            selectedAppGroups.insert(groupId)
        }
    }
    
    /// Toggle selection of an individual app
    func toggleApplication(_ token: ApplicationToken) {
        if selectedApplications.contains(token) {
            selectedApplications.remove(token)
        } else {
            selectedApplications.insert(token)
        }
    }
    
    /// Check if an app group is selected
    func isAppGroupSelected(_ groupId: UUID) -> Bool {
        selectedAppGroups.contains(groupId)
    }
    
    /// Check if an application is selected
    func isApplicationSelected(_ token: ApplicationToken) -> Bool {
        selectedApplications.contains(token)
    }
    
    /// Clear all selections
    func clearSelections() {
        selectedAppGroups.removeAll()
        selectedApplications.removeAll()
    }
    
    // MARK: - Duration Management
    
    /// Available preset durations for quick selection
    var presetDurations: [TimeInterval] {
        AppConstants.Session.presetDurations
    }
    
    /// Set duration to a preset value
    func selectPresetDuration(_ duration: TimeInterval) {
        selectedDuration = duration
    }
    
    /// Check if a preset duration is currently selected
    func isPresetSelected(_ duration: TimeInterval) -> Bool {
        selectedDuration == duration
    }
    
    /// Set custom duration (in minutes)
    func setCustomDuration(minutes: Int) {
        let duration = TimeInterval(minutes * 60)
        if duration >= AppConstants.Session.minimumDuration && 
           duration <= AppConstants.Session.maximumDuration {
            selectedDuration = duration
        }
    }
    
    // MARK: - Session Management
    
    /// Create and start a new intention session
    func startSession() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Ensure ScreenTimeService has the latest category mapping service
            await screenTimeService.setCategoryMappingService(categoryMappingService)
            var allApplications: Set<ApplicationToken> = []
            let allowedCategories: Set<ActivityCategoryToken> = []
            
            // Get apps from Family Activity Picker selection
            if !familyActivitySelection.applications.isEmpty {
                allApplications = Set(familyActivitySelection.applications.compactMap { $0.token })
                print("🎯 SESSION SETUP: \(allApplications.count) apps from FamilyActivityPicker")
            }
            
            // Also include any selected app groups
            for groupId in selectedAppGroups {
                if let group = availableAppGroups.first(where: { $0.id == groupId }) {
                    allApplications.formUnion(group.applications)
                }
            }
            
            // Include any manually selected individual apps
            allApplications.formUnion(selectedApplications)
            
            // Validate that something is selected to allow
            guard !allApplications.isEmpty else {
                await handleError(AppError.invalidConfiguration("Please select at least some apps to allow during your session"))
                return
            }
            
            print("🎯 FINAL SESSION SETUP:")
            print("   - Total apps to ALLOW: \(allApplications.count)")
            print("   - All other apps will be BLOCKED (sophisticated backend logic)")
            print("   - Session duration: \(selectedDuration.formattedMinutesSeconds)")
            
            // Create the session with apps to allow
            let session = try IntentionSession(
                appGroups: Array(selectedAppGroups),
                applications: allApplications,
                categories: allowedCategories,
                duration: selectedDuration
            )
            
            // Notify parent to start the session
            await onSessionStart(session)
            
        } catch {
            await handleError(error)
        }
    }
    
    /// Cancel the intention prompt
    func cancel() {
        // Add debugging to see if this is being called unexpectedly
        print("🚫 IntentionPromptViewModel.cancel() called")
        onCancel()
    }
    
    // MARK: - Computed Properties
    
    /// Whether the start button should be enabled
    var canStartSession: Bool {
        if isLoading { return false }
        
        // Check if any apps are selected for the session
        return !selectedAppGroups.isEmpty || !selectedApplications.isEmpty || 
               !familyActivitySelection.applications.isEmpty || !familyActivitySelection.categories.isEmpty
    }
    
    /// Total number of selected items
    var selectionCount: Int {
        return selectedAppGroups.count + selectedApplications.count + 
               familyActivitySelection.applications.count + familyActivitySelection.categories.count
    }
    
    /// Formatted duration string for display
    var formattedDuration: String {
        if selectedDuration < 3600 {
            return selectedDuration.formattedMinutesSeconds
        } else {
            return selectedDuration.formattedHoursMinutes
        }
    }
    
    // MARK: - Search & Filtering
    
    private func filterApps() {
        if searchText.isEmpty {
            searchResults = filteredDiscoveredApps
        } else {
            searchResults = filteredDiscoveredApps.filter { app in
                app.displayName.localizedCaseInsensitiveContains(searchText) ||
                app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
            }
        }
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
    
    private func withLoading<T: Sendable>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
    
    // MARK: - Mock Data (Temporary)
    
    private func createMockDiscoveredApps() -> [DiscoveredApp] {
        // Create mock apps for development/testing
        // In real implementation, this would come from app discovery service
        let mockTokenData = """
        {
            "data": "dGVzdERhdGE="
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        guard let mockToken = try? decoder.decode(ApplicationToken.self, from: mockTokenData) else {
            return []
        }
        
        return [
            DiscoveredApp(displayName: "Safari", bundleIdentifier: "com.apple.mobilesafari", token: mockToken, category: "Productivity"),
            DiscoveredApp(displayName: "Messages", bundleIdentifier: "com.apple.MobileSMS", token: mockToken, category: "Communication"),
            DiscoveredApp(displayName: "Mail", bundleIdentifier: "com.apple.mobilemail", token: mockToken, category: "Productivity"),
            DiscoveredApp(displayName: "Photos", bundleIdentifier: "com.apple.mobileslideshow", token: mockToken, category: "Media"),
            DiscoveredApp(displayName: "Notes", bundleIdentifier: "com.apple.mobilenotes", token: mockToken, category: "Productivity"),
            DiscoveredApp(displayName: "Calendar", bundleIdentifier: "com.apple.mobilecal", token: mockToken, category: "Productivity"),
            DiscoveredApp(displayName: "Settings", bundleIdentifier: "com.apple.Preferences", token: mockToken, category: "System", isSystemApp: true),
            DiscoveredApp(displayName: "Phone", bundleIdentifier: "com.apple.mobilephone", token: mockToken, category: "Communication", isSystemApp: true)
        ]
    }
}
