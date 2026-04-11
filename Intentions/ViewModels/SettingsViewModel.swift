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

    // UI State
    var showingScheduleEditor = false

    // Statistics
    var todaySessionCount: Int = 0
    var weeklySessionCount: Int = 0
    
    // MARK: - Initialization
    
    init(dataService: DataPersisting) {
        self.dataService = dataService
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            // Load schedule settings
            if let savedSettings = try await dataService.loadScheduleSettings() {
                scheduleSettings = savedSettings
            } else {
                // No saved settings exist - use defaults (isEnabled = true) and save them
                scheduleSettings = ScheduleSettings()
                try await dataService.saveScheduleSettings(scheduleSettings)
            }

            // Update statistics from persisted sessions
            await updateStatistics()

        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Schedule Settings
    
    func updateScheduleSettings(_ settings: ScheduleSettings) async {
        do {
            try await dataService.saveScheduleSettings(settings)
            scheduleSettings = settings
        } catch {
            errorMessage = "Failed to save schedule settings: \(error.localizedDescription)"
        }
    }
    
    func toggleScheduleEnabled() async {
        scheduleSettings.isEnabled.toggle()
        await updateScheduleSettings(scheduleSettings)
    }

    func recordDisableAndToggle() async {
        scheduleSettings.lastDisabledAt = Date()
        scheduleSettings.isEnabled = false
        await updateScheduleSettings(scheduleSettings)
    }

    // MARK: - Statistics
    
    private func updateStatistics() async {
        do {
            let calendar = Calendar.current
            let now = Date()
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now

            let sessions = try await dataService.loadIntentionSessionsSince(startOfWeek)

            let startOfToday = calendar.startOfDay(for: now)
            todaySessionCount = sessions.filter { $0.createdAt >= startOfToday }.count
            weeklySessionCount = sessions.count
        } catch {
            todaySessionCount = 0
            weeklySessionCount = 0
        }
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

    func resetSheetState() {
        showingScheduleEditor = false
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

    var intentionsStateText: String {
        if !scheduleSettings.isEnabled {
            return "Disabled"
        }

        if scheduleSettings.isCurrentlyActive {
            return "Enabled"
        } else {
            return "Open Access"
        }
    }

    var intentionsStateColor: Color {
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

    // MARK: - Disable Confirmation Data

    var streakDays: Int? {
        scheduleSettings.streakDays
    }

    var formattedRemainingTime: String {
        let totalMinutes = scheduleSettings.remainingProtectedMinutesToday
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else {
            return "\(minutes)m remaining"
        }
    }
}

