//
//  QuickActionsViewModel.swift
//  Intentions
//
//  Created by Claude on 03/09/2025.
//

import Foundation
import SwiftUI

/// ViewModel for managing quick actions - pre-configured sessions for fast access
@MainActor
@Observable
final class QuickActionsViewModel: Sendable {

    // MARK: - Properties

    /// Whether the view is currently loading
    var isLoading: Bool = false

    /// Typed app-level error surfaced via AppErrorBanner (see #49, #53).
    /// Carries the recovery action (retry the failed call). Replaces the prior
    /// `errorMessage: String?` + .alert("OK") pattern.
    var bannerError: BannerError? = nil

    /// Plain-string error message (computed from `bannerError`). Kept for
    /// existing tests that inspect `errorMessage` directly.
    var errorMessage: String? { bannerError?.message }

    /// All quick actions
    private(set) var quickActions: [QuickAction] = []

    /// Whether showing delete confirmation alert
    var showingDeleteAlert: Bool = false

    /// Quick action pending deletion
    var quickActionToDelete: QuickAction? = nil

    /// Set once, when the stale-token migration has just wiped selections on
    /// this launch. Views observe this to show a one-time notice asking the
    /// user to re-pick apps.
    var showStaleTokenMigrationNotice: Bool = false

    private static let staleTokenMigrationKey = "staleTokenMigration_v1"
    
    // MARK: - Dependencies

    private let dataService: DataPersisting

    // MARK: - Initialization

    init(dataService: DataPersisting) {
        self.dataService = dataService
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        await withLoading {
            do {
                // Load quick actions
                let actions = try await dataService.load([QuickAction].self, forKey: "quickActions") ?? []
                quickActions = actions.sorted { $0.sortOrder < $1.sortOrder }

                await runStaleTokenMigrationIfNeeded()

            } catch {
                handleError(error, retry: { [weak self] in
                    await self?.loadData()
                })
            }
        }
    }

    /// One-time migration: clear app/category/webDomain tokens on all stored
    /// quick actions. Necessary because pre-migration actions may contain
    /// tokens for apps the user has since uninstalled; rendering those tokens
    /// crashes the FamilyActivityPicker extension on search. Users re-pick
    /// apps once after the update.
    private func runStaleTokenMigrationIfNeeded() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.staleTokenMigrationKey) else { return }

        guard !quickActions.isEmpty else {
            defaults.set(true, forKey: Self.staleTokenMigrationKey)
            return
        }

        for index in quickActions.indices {
            quickActions[index].individualApplications = []
            quickActions[index].individualCategories = []
            quickActions[index].individualWebDomains = []
            quickActions[index].lastModified = Date()
        }

        do {
            try await dataService.save(quickActions, forKey: "quickActions")
            defaults.set(true, forKey: Self.staleTokenMigrationKey)
            showStaleTokenMigrationNotice = true
        } catch {
            handleError(error, retry: { [weak self] in
                await self?.runStaleTokenMigrationIfNeeded()
            })
        }
    }
    
    // MARK: - Quick Action Management
    
    /// Save a quick action (create or update)
    func saveQuickAction(_ quickAction: QuickAction) async {
        await withLoading {
            do {
                // Update existing or add new
                if let index = quickActions.firstIndex(where: { $0.id == quickAction.id }) {
                    quickActions[index] = quickAction
                } else {
                    // Assign sortOrder for new quick action (highest value + 1)
                    var newQuickAction = quickAction
                    let maxSortOrder = quickActions.map(\.sortOrder).max() ?? -1
                    newQuickAction.sortOrder = maxSortOrder + 1
                    quickActions.append(newQuickAction)
                }

                // Keep array sorted by sortOrder
                quickActions.sort { $0.sortOrder < $1.sortOrder }

                // Save to persistence
                try await dataService.save(quickActions, forKey: "quickActions")

            } catch {
                handleError(error, retry: { [weak self] in
                    await self?.saveQuickAction(quickAction)
                })
            }
        }
    }

    /// Move a quick action to a new position (for reordering)
    func moveQuickAction(from sourceIndex: Int, to destinationIndex: Int) async {
        guard sourceIndex != destinationIndex &&
              sourceIndex < quickActions.count &&
              destinationIndex < quickActions.count else { return }

        await withLoading {
            do {
                // Move the item in the array
                let movedItem = quickActions.remove(at: sourceIndex)
                quickActions.insert(movedItem, at: destinationIndex)

                // Reassign sortOrder values based on new positions
                for (index, _) in quickActions.enumerated() {
                    quickActions[index].sortOrder = index
                }

                // Save to persistence
                try await dataService.save(quickActions, forKey: "quickActions")

            } catch {
                handleError(error, retry: { [weak self] in
                    await self?.moveQuickAction(from: sourceIndex, to: destinationIndex)
                })
            }
        }
    }

    /// Delete a quick action
    func deleteQuickAction(_ quickAction: QuickAction) async {
        await withLoading {
            do {
                // Remove from array
                quickActions.removeAll { $0.id == quickAction.id }
                
                // Save to persistence
                try await dataService.save(quickActions, forKey: "quickActions")
                
                // Clear delete state
                showingDeleteAlert = false
                quickActionToDelete = nil

            } catch {
                handleError(error, retry: { [weak self] in
                    await self?.deleteQuickAction(quickAction)
                })
            }
        }
    }
    
    /// Toggle quick action enabled state
    func toggleQuickActionEnabled(_ quickAction: QuickAction) async {
        guard let index = quickActions.firstIndex(where: { $0.id == quickAction.id }) else { return }
        quickActions[index].toggleEnabled()
        await saveQuickAction(quickActions[index])
    }
    
    /// Record usage of a quick action
    func recordQuickActionUsage(_ quickAction: QuickAction) async {
        guard let index = quickActions.firstIndex(where: { $0.id == quickAction.id }) else { return }
        quickActions[index].recordUsage()
        await saveQuickAction(quickActions[index])
    }
    
    /// Create a default quick action for getting started
    func createDefaultQuickActions() async -> [QuickAction] {
        let defaults = [
            QuickAction(
                name: String(localized: "Work Session", comment: "Seeded default quick action name"),
                subtitle: String(localized: "Focus on productivity apps", comment: "Seeded default quick action subtitle"),
                iconName: "laptopcomputer",
                duration: 30 * 60 // 30 minutes
            ),
            QuickAction(
                name: String(localized: "Study Time", comment: "Seeded default quick action name"),
                subtitle: String(localized: "Learning and research", comment: "Seeded default quick action subtitle"),
                iconName: "book.fill",
                duration: 60 * 60 // 1 hour
            ),
            QuickAction(
                name: String(localized: "Break Time", comment: "Seeded default quick action name"),
                subtitle: String(localized: "Social and entertainment", comment: "Seeded default quick action subtitle"),
                iconName: "cup.and.saucer.fill",
                duration: 15 * 60 // 15 minutes
            )
        ]
        
        // Save defaults
        for quickAction in defaults {
            await saveQuickAction(quickAction)
        }
        
        return defaults
    }
    
    // MARK: - Delete Confirmation
    
    /// Show delete confirmation for a quick action
    func confirmDeleteQuickAction(_ quickAction: QuickAction) {
        quickActionToDelete = quickAction
        showingDeleteAlert = true
    }
    
    /// Cancel delete operation
    func cancelDelete() {
        quickActionToDelete = nil
        showingDeleteAlert = false
    }
    
    // MARK: - Statistics
    
    /// Get total usage count across all quick actions
    var totalUsageCount: Int {
        quickActions.reduce(0) { $0 + $1.usageCount }
    }
    
    /// Get most used quick action
    var mostUsedQuickAction: QuickAction? {
        quickActions.max { $0.usageCount < $1.usageCount }
    }
    
    /// Get quick actions sorted by usage
    var quickActionsByUsage: [QuickAction] {
        quickActions.sorted { $0.usageCount > $1.usageCount }
    }
    
    /// Get quick actions for home page display (top 3)
    func getHomePageQuickActions() -> [QuickAction] {
        let enabledActions = quickActions.filter(\.isEnabled)
        return Array(enabledActions.sorted { $0.usageCount > $1.usageCount }.prefix(3))
    }
    
    // MARK: - Error Handling

    /// Surface an error via AppErrorBanner with an optional retry closure.
    /// Mirrors `ContentViewModel.handleError(_:retry:)` (see #49, #53).
    func handleError(_ error: Error, retry: (@Sendable () async -> Void)? = nil) {
        let message: String
        if let appError = error as? AppError {
            message = appError.errorDescription ?? error.localizedDescription
        } else {
            message = error.localizedDescription
        }

        let action: BannerError.Action
        if let retry {
            action = .retry(retry)
        } else {
            action = .retry({ })
        }

        bannerError = BannerError(message: message, action: action)
        isLoading = false
    }

    func clearError() {
        bannerError = nil
    }
    
    // MARK: - Helper Methods
    
    private func withLoading<T: Sendable>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
}

// MARK: - Extensions

extension QuickActionsViewModel {

    /// Get quick actions filtered by availability (enabled only)
    func getAvailableQuickActions() -> [QuickAction] {
        return quickActions.filter { $0.isEnabled }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}