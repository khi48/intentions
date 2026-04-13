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
    var hasLoadedOnce: Bool = false
    var errorMessage: String?

    // Schedule
    var weeklySchedule = WeeklySchedule()

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
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        errorMessage = nil

        do {
            weeklySchedule = try await dataService.loadWeeklySchedule() ?? WeeklySchedule()

            // Update statistics from persisted sessions
            await updateStatistics()

        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
        }
    }

    // MARK: - Schedule

    func updateSchedule(_ schedule: WeeklySchedule) async {
        do {
            try await dataService.saveWeeklySchedule(schedule)
            weeklySchedule = schedule
        } catch {
            errorMessage = "Failed to save schedule: \(error.localizedDescription)"
        }
    }

    func toggleScheduleEnabled() async {
        weeklySchedule.isEnabled.toggle()
        await updateSchedule(weeklySchedule)
    }

    func recordDisableAndToggle() async {
        weeklySchedule.lastDisabledAt = Date()
        weeklySchedule.isEnabled = false
        await updateSchedule(weeklySchedule)
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

    var scheduleSummary: String {
        guard weeklySchedule.isEnabled else { return "Blocking is off" }
        let count = weeklySchedule.intervals.count
        switch count {
        case 0: return "No free time set"
        case 1:
            let i = weeklySchedule.intervals[0]
            return "\(i.startDayOfWeek.shortName) \(formattedTime(hour: i.startHour, minute: i.startMinute))–\(formattedTime(hour: i.endHour, minute: i.endMinute))"
        default:
            return "\(count) free time blocks"
        }
    }

    private func formattedTime(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    // MARK: - Disable Confirmation Data

    var streakDays: Int? {
        weeklySchedule.streakDays
    }

    var formattedRemainingTime: String {
        let totalMinutes = weeklySchedule.remainingProtectedMinutes(at: Date())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else {
            return "\(minutes)m remaining"
        }
    }
}
