//
//  AppGroupsViewModel.swift
//  Intentions
//
//  Created by Claude on 13/07/2025.
//

import Foundation
import SwiftUI
@preconcurrency import FamilyControls
import ManagedSettings

/// ViewModel for managing app groups and collections
/// Handles CRUD operations for app groups and integration with app discovery
@MainActor
@Observable
final class AppGroupsViewModel: Sendable {
    
    // MARK: - Published Properties
    
    /// Whether the view is currently loading
    var isLoading: Bool = false
    
    /// Current error message to display
    var errorMessage: String? = nil
    
    /// List of app groups loaded from persistence
    private(set) var appGroups: [AppGroup] = []
    
    /// Available discovered apps for group creation
    private(set) var discoveredApps: [DiscoveredApp] = []
    
    /// Filtered discovered apps (excluding system apps by default)
    var filteredDiscoveredApps: [DiscoveredApp] {
        discoveredApps.filter { !$0.isSystemApp || showSystemApps }
    }
    
    /// Search text for filtering apps
    var searchText: String = "" {
        didSet {
            filterApps()
        }
    }
    
    /// Filtered apps based on search text
    private(set) var searchResults: [DiscoveredApp] = []
    
    /// Whether to show system apps in the app picker
    var showSystemApps: Bool = false {
        didSet {
            filterApps()
        }
    }
    
    /// Whether showing the app group editor
    var showingGroupEditor: Bool = false
    
    /// Whether showing the delete confirmation alert
    var showingDeleteAlert: Bool = false
    
    /// App group selected for deletion
    private(set) var groupToDelete: AppGroup? = nil
    
    /// Currently editing group (nil for new group creation)
    private(set) var editingGroup: AppGroup? = nil
    
    // MARK: - Dependencies
    
    private let dataService: DataPersisting
    private weak var contentViewModel: ContentViewModel?
    
    // MARK: - Initialization
    
    init(dataService: DataPersisting, contentViewModel: ContentViewModel? = nil) {
        self.dataService = dataService
        self.contentViewModel = contentViewModel
        self.searchResults = []
        print("🗄️ APP GROUPS VM: Initialized with dataService: \(type(of: dataService))")
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        await withLoading {
            do {
                // Load existing app groups
                appGroups = try await dataService.loadAppGroups()
                
                // Generate mock discovered apps for development
                discoveredApps = generateMockDiscoveredApps()
                filterApps()
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    // MARK: - App Group Management
    
    /// Create a new app group
    func createAppGroup(name: String, applicationTokens: Set<ApplicationToken>, categoryTokens: Set<ActivityCategoryToken> = []) async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await handleError(AppError.invalidConfiguration("Group name cannot be empty"))
            return
        }
        
        await withLoading {
            do {
                let newGroup = try AppGroup(
                    id: UUID(),
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    applications: applicationTokens,
                    categories: categoryTokens,
                    createdAt: Date(),
                    lastModified: Date()
                )
                
                try await dataService.saveAppGroup(newGroup)
                appGroups.append(newGroup)
                print("✅ APP GROUP CREATED: '\(newGroup.name)' saved to persistence")
                print("📊 CURRENT APP GROUPS: \(appGroups.count) total")
                print("🗄️ APP GROUPS VM: Using dataService: \(type(of: dataService))")
                
                // Notify that app groups have changed
                await MainActor.run {
                    contentViewModel?.notifyAppGroupsChanged()
                }
                
                // Close editor
                showingGroupEditor = false
                editingGroup = nil
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Update an existing app group
    func updateAppGroup(id: UUID, name: String, applicationTokens: Set<ApplicationToken>, categoryTokens: Set<ActivityCategoryToken> = []) async {
        guard let groupIndex = appGroups.firstIndex(where: { $0.id == id }) else {
            await handleError(AppError.invalidConfiguration("Group not found"))
            return
        }
        
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await handleError(AppError.invalidConfiguration("Group name cannot be empty"))
            return
        }
        
        await withLoading {
            do {
                let updatedGroup = try AppGroup(
                    id: id,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    applications: applicationTokens,
                    categories: categoryTokens,
                    createdAt: appGroups[groupIndex].createdAt,
                    lastModified: Date()
                )
                
                try await dataService.saveAppGroup(updatedGroup)
                appGroups[groupIndex] = updatedGroup
                
                // Close editor
                showingGroupEditor = false
                editingGroup = nil
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Delete an app group
    func deleteAppGroup(_ group: AppGroup) async {
        await withLoading {
            do {
                try await dataService.deleteAppGroup(group.id)
                appGroups.removeAll { $0.id == group.id }
                
                // Clear delete state
                groupToDelete = nil
                showingDeleteAlert = false
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    // MARK: - UI Actions
    
    /// Show editor for creating new group
    func showCreateGroupEditor() {
        editingGroup = nil
        showingGroupEditor = true
    }
    
    /// Show editor for editing existing group
    func showEditGroupEditor(for group: AppGroup) {
        editingGroup = group
        showingGroupEditor = true
    }
    
    /// Show delete confirmation for group
    func confirmDeleteGroup(_ group: AppGroup) {
        groupToDelete = group
        showingDeleteAlert = true
    }
    
    /// Cancel delete operation
    func cancelDelete() {
        groupToDelete = nil
        showingDeleteAlert = false
    }
    
    /// Cancel group editing
    func cancelGroupEditor() {
        editingGroup = nil
        showingGroupEditor = false
    }
    
    // MARK: - Search and Filtering
    
    private func filterApps() {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResults = filteredDiscoveredApps
        } else {
            let searchQuery = searchText.lowercased()
            searchResults = filteredDiscoveredApps.filter { app in
                app.displayName.lowercased().contains(searchQuery) ||
                app.bundleIdentifier.lowercased().contains(searchQuery) ||
                (app.category?.lowercased().contains(searchQuery) ?? false)
            }
        }
    }
    
    // MARK: - Error Handling
    
    func handleError(_ error: Error) async {
        if let appError = error as? AppError {
            errorMessage = appError.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
    
    private func generateMockDiscoveredApps() -> [DiscoveredApp] {
        let mockApps = [
            ("Safari", "com.apple.mobilesafari", "Web Browser", false),
            ("Messages", "com.apple.MobileSMS", "Communication", true),
            ("Mail", "com.apple.mobilemail", "Communication", true),
            ("Notes", "com.apple.mobilenotes", "Productivity", false),
            ("Calendar", "com.apple.mobilecal", "Productivity", false),
            ("Photos", "com.apple.mobileslideshow", "Photo & Video", false),
            ("Settings", "com.apple.Preferences", "Utilities", true),
            ("Clock", "com.apple.mobiletimer", "Utilities", true),
            ("Calculator", "com.apple.calculator", "Utilities", true),
            ("Weather", "com.apple.weather", "Weather", false),
            ("Slack", "com.tinyspeck.chatlyio", "Business", false),
            ("Zoom", "us.zoom.videomeetings", "Business", false),
            ("Twitter", "com.twitter.twitter", "Social Networking", false),
            ("Instagram", "com.burbn.instagram", "Photo & Video", false),
            ("YouTube", "com.google.ios.youtube", "Photo & Video", false)
        ]
        
        return mockApps.compactMap { (name, bundleId, category, isSystem) in
            do {
                // Create mock ApplicationToken using JSON decoding approach
                let tokenData = """
                {
                    "data": "\(bundleId.data(using: .utf8)?.base64EncodedString() ?? "dGVzdA==")"
                }
                """.data(using: .utf8)!
                
                let decoder = JSONDecoder()
                let token = try decoder.decode(ApplicationToken.self, from: tokenData)
                
                return DiscoveredApp(
                    displayName: name,
                    bundleIdentifier: bundleId,
                    token: token,
                    category: category,
                    isSystemApp: isSystem
                )
            } catch {
                print("Failed to create mock app \(name): \(error)")
                return nil
            }
        }
    }
}

// MARK: - Statistics

extension AppGroupsViewModel {
    
    /// Total number of app groups
    var totalAppGroups: Int {
        appGroups.count
    }
    
    /// Total number of managed apps across all groups
    var totalManagedApps: Int {
        Set(appGroups.flatMap { $0.applications }).count
    }
    
    /// Most recently modified group
    var recentlyModifiedGroup: AppGroup? {
        appGroups.max(by: { $0.lastModified < $1.lastModified })
    }
    
    /// Groups with the most applications
    var largestGroups: [AppGroup] {
        appGroups.sorted(by: { $0.applications.count > $1.applications.count })
    }
}