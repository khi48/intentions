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
final class QuickActionsViewModel: ObservableObject, Sendable {
    
    // MARK: - Published Properties
    
    /// Whether the view is currently loading
    @Published var isLoading: Bool = false
    
    /// Current error message to display
    @Published var errorMessage: String? = nil
    
    /// All quick actions
    @Published private(set) var quickActions: [QuickAction] = []
    
    /// Available app groups for quick action creation
    @Published private(set) var availableAppGroups: [AppGroup] = []
    
    /// Whether showing delete confirmation alert
    @Published var showingDeleteAlert: Bool = false
    
    /// Quick action pending deletion
    @Published var quickActionToDelete: QuickAction? = nil
    
    // MARK: - Dependencies
    
    private var dataService: DataPersisting?
    
    // MARK: - Initialization
    
    init() {}
    
    /// Set the data service (called from view)
    func setDataService(_ service: DataPersisting) {
        self.dataService = service
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        guard let dataService = dataService else { return }
        
        await withLoading {
            do {
                // Load quick actions
                let actions = try await dataService.load([QuickAction].self, forKey: "quickActions") ?? []
                quickActions = actions.sorted { $0.sortOrder < $1.sortOrder }
                
                // Load available app groups
                availableAppGroups = try await dataService.loadAppGroups()
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    // MARK: - Quick Action Management
    
    /// Save a quick action (create or update)
    func saveQuickAction(_ quickAction: QuickAction) async {
        guard let dataService = dataService else { return }
        
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
                await handleError(error)
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
                guard let dataService = dataService else { return }
                try await dataService.save(quickActions, forKey: "quickActions")

            } catch {
                await handleError(error)
            }
        }
    }

    /// Delete a quick action
    func deleteQuickAction(_ quickAction: QuickAction) async {
        guard let dataService = dataService else { return }
        
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
                await handleError(error)
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
                name: "Work Session",
                subtitle: "Focus on productivity apps",
                iconName: "laptopcomputer",
                color: Color.blue,
                duration: 30 * 60 // 30 minutes
            ),
            QuickAction(
                name: "Study Time",
                subtitle: "Learning and research",
                iconName: "book.fill",
                color: Color.green,
                duration: 60 * 60 // 1 hour
            ),
            QuickAction(
                name: "Break Time",
                subtitle: "Social and entertainment",
                iconName: "cup.and.saucer.fill",
                color: Color.orange,
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
    
    func handleError(_ error: Error) async {
        if let appError = error as? AppError {
            errorMessage = appError.errorDescription
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
}

// MARK: - Extensions

extension QuickActionsViewModel {
    
    /// Get quick actions filtered by availability (have valid app groups)
    func getAvailableQuickActions() -> [QuickAction] {
        return quickActions.filter { quickAction in
            quickAction.isEnabled && (
                quickAction.appGroupIds.isEmpty || // No groups required
                !quickAction.appGroupIds.isDisjoint(with: Set(availableAppGroups.map(\.id))) // Has valid groups
            )
        }.sorted { $0.sortOrder < $1.sortOrder }
    }
}