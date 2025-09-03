//
//  SettingsViewModel.swift
//  Intentions
//
//  Created by Claude on 13/07/2025.
//

import Foundation
import SwiftUI
@preconcurrency import FamilyControls
import ManagedSettings

/// ViewModel for managing app settings and configuration
@MainActor
@Observable 
final class SettingsViewModel: Sendable {
    
    // MARK: - Dependencies
    private let dataService: DataPersisting
    
    // MARK: - Published State
    var isLoading: Bool = false
    var errorMessage: String?
    
    // Schedule Settings
    var scheduleSettings = ScheduleSettings()
    
    // App Groups
    var appGroups: [AppGroup] = []
    
    // UI State
    var showingScheduleEditor = false
    var showingAppGroupEditor = false
    var showingDeleteConfirmation = false
    var groupToDelete: AppGroup?
    
    // Statistics
    var totalAppGroups: Int = 0
    var totalManagedApps: Int = 0
    var todaySessionCount: Int = 0
    var weeklySessionCount: Int = 0
    
    // MARK: - Initialization
    
    init(dataService: DataPersisting = MockDataPersistenceService()) {
        self.dataService = dataService
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Load app groups
            appGroups = try await dataService.loadAppGroups()
            
            // Load schedule settings
            if let savedSettings = try await dataService.loadScheduleSettings() {
                scheduleSettings = savedSettings
            }
            
            // Update statistics
            updateStatistics()
            
        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Schedule Settings
    
    func updateScheduleSettings(_ settings: ScheduleSettings) async {
        do {
            print("📅 Saving schedule settings - enabled: \(settings.isEnabled), currently active: \(settings.isCurrentlyActive)")
            try await dataService.saveScheduleSettings(settings)
            scheduleSettings = settings
        } catch {
            print("❌ Failed to save schedule settings: \(error)")
            errorMessage = "Failed to save schedule settings: \(error.localizedDescription)"
        }
    }
    
    func toggleScheduleEnabled() async {
        let oldValue = scheduleSettings.isEnabled
        scheduleSettings.isEnabled.toggle()
        let newValue = scheduleSettings.isEnabled
        print("📅 Schedule toggle: \(oldValue) -> \(newValue)")
        await updateScheduleSettings(scheduleSettings)
    }
    
    // MARK: - App Group Management
    
    func createAppGroup(name: String, applications: Set<ApplicationToken>) async {
        guard !name.isEmpty else {
            errorMessage = "App group name cannot be empty"
            return
        }
        
        guard name.count <= AppConstants.AppGroup.maxNameLength else {
            errorMessage = "App group name is too long"
            return
        }
        
        guard !AppConstants.AppGroup.reservedNames.contains(name) else {
            errorMessage = "This name is reserved and cannot be used"
            return
        }
        
        let newGroup: AppGroup
        do {
            newGroup = try AppGroup(
                id: UUID(),
                name: name,
                applications: applications,
                createdAt: Date(),
                lastModified: Date()
            )
        } catch {
            errorMessage = "Failed to create app group: \(error.localizedDescription)"
            return
        }
        
        do {
            try await dataService.saveAppGroup(newGroup)
            appGroups.append(newGroup)
            updateStatistics()
        } catch {
            errorMessage = "Failed to create app group: \(error.localizedDescription)"
        }
    }
    
    func updateAppGroup(_ group: AppGroup) async {
        do {
            try await dataService.saveAppGroup(group)
            if let index = appGroups.firstIndex(where: { $0.id == group.id }) {
                appGroups[index] = group
            }
            updateStatistics()
        } catch {
            errorMessage = "Failed to update app group: \(error.localizedDescription)"
        }
    }
    
    func deleteAppGroup(_ group: AppGroup) async {
        do {
            try await dataService.deleteAppGroup(group.id)
            appGroups.removeAll { $0.id == group.id }
            updateStatistics()
        } catch {
            errorMessage = "Failed to delete app group: \(error.localizedDescription)"
        }
    }
    
    func confirmDeleteGroup(_ group: AppGroup) {
        groupToDelete = group
        showingDeleteConfirmation = true
    }
    
    func cancelDelete() {
        groupToDelete = nil
        showingDeleteConfirmation = false
    }
    
    func executeDelete() async {
        guard let group = groupToDelete else { return }
        await deleteAppGroup(group)
        cancelDelete()
    }
    
    // MARK: - Statistics
    
    private func updateStatistics() {
        totalAppGroups = appGroups.count
        totalManagedApps = appGroups.reduce(0) { $0 + $1.applications.count }
        
        // TODO: Load actual session statistics from data service
        // These are placeholder values for now
        todaySessionCount = 0
        weeklySessionCount = 0
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        errorMessage = nil
    }
    
    func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
    }
    
    // MARK: - Navigation
    
    func showScheduleEditor() {
        showingScheduleEditor = true
    }
    
    func hideScheduleEditor() {
        showingScheduleEditor = false
    }
    
    func showAppGroupEditor() {
        showingAppGroupEditor = true
    }
    
    func hideAppGroupEditor() {
        showingAppGroupEditor = false
    }
    
    func resetSheetState() {
        print("🔄 SETTINGS VM: Resetting sheet state")
        print("   - Schedule editor was: \(showingScheduleEditor)")
        print("   - App group editor was: \(showingAppGroupEditor)")
        print("   - Delete confirmation was: \(showingDeleteConfirmation)")
        
        // Force dismiss any active sheets with explicit state changes
        if showingScheduleEditor {
            print("   🚫 Force dismissing schedule editor")
            showingScheduleEditor = false
        }
        if showingAppGroupEditor {
            print("   🚫 Force dismissing app group editor")
            showingAppGroupEditor = false
        }
        if showingDeleteConfirmation {
            print("   🚫 Force dismissing delete confirmation")
            showingDeleteConfirmation = false
        }
        
        // Reset all states regardless
        showingScheduleEditor = false
        showingAppGroupEditor = false
        showingDeleteConfirmation = false
        groupToDelete = nil
        
        print("   ✅ All sheet states reset to false")
        
        // Add a small delay to ensure UI updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("   🔄 Double-check: Schedule=\(self.showingScheduleEditor), AppGroup=\(self.showingAppGroupEditor)")
        }
    }
    
    // MARK: - Computed Properties
    
    var scheduleStatusText: String {
        if !scheduleSettings.isEnabled {
            return "Disabled"
        }
        
        if scheduleSettings.isCurrentlyActive {
            return "Active"
        } else {
            return "Inactive"
        }
    }
    
    var scheduleStatusColor: Color {
        if !scheduleSettings.isEnabled {
            return .gray
        }
        
        return scheduleSettings.isCurrentlyActive ? .green : .orange
    }
    
    var formattedActiveHours: String {
        let start = scheduleSettings.activeHours.lowerBound
        let end = scheduleSettings.activeHours.upperBound
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        let startTime = Calendar.current.date(bySettingHour: start, minute: 0, second: 0, of: Date()) ?? Date()
        let endTime = Calendar.current.date(bySettingHour: end, minute: 0, second: 0, of: Date()) ?? Date()
        
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    var activeDaysText: String {
        if scheduleSettings.activeDays.count == 7 {
            return "Every day"
        } else if scheduleSettings.activeDays.count == 5 && 
                  scheduleSettings.activeDays.isDisjoint(with: [.saturday, .sunday]) {
            return "Weekdays"
        } else if scheduleSettings.activeDays.count == 2 && 
                  scheduleSettings.activeDays == [.saturday, .sunday] {
            return "Weekends"
        } else {
            let sortedDays = scheduleSettings.activeDays.sorted { $0.rawValue < $1.rawValue }
            return sortedDays.map { $0.shortName }.joined(separator: ", ")
        }
    }
}

