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
            errorMessage = String(localized: "Failed to load settings: \(error.localizedDescription)", comment: "Error toast when settings load fails; placeholder is system error description")
        }
    }

    // MARK: - Schedule

    func updateSchedule(_ schedule: WeeklySchedule) async {
        do {
            try await dataService.saveWeeklySchedule(schedule)
            weeklySchedule = schedule
            // Free-time end notifications (#24) are persistent (repeats:true).
            // Re-sync pending state on every schedule mutation so warnings +
            // completions match the new set of intervals. Wipes by `freetime_`
            // prefix internally — covers the schedule-disabled toggle-off case.
            await NotificationService.shared.rescheduleFreeTimeNotifications(schedule: schedule)
            // Re-sync the R3 pre-scheduled banner (#30) if a session is active.
            // Edits via the Settings tab follow the same pattern as the
            // home-tab edit: shift the banner to the new boundary time so it
            // still fires correctly if the session outlives the edit.
            await NotificationService.shared.rescheduleR3MutexTeardownBannerForActiveSession(schedule: schedule)
        } catch {
            errorMessage = String(localized: "Failed to save schedule: \(error.localizedDescription)", comment: "Error toast when saving schedule fails; placeholder is system error description")
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
        guard weeklySchedule.isEnabled else {
            return String(localized: "Blocking is off", comment: "Settings summary when blocking is disabled")
        }
        let count = weeklySchedule.routines.count
        switch count {
        case 0:
            return String(localized: "No routines set", comment: "Settings summary when blocking is enabled but no routines exist")
        case 1:
            let r = weeklySchedule.routines[0]
            let dayLabel = r.days.count == 1
                ? r.days.first!.shortName
                : String(localized: "\(r.days.count) days", comment: "Day-count label for a routine that runs on multiple days")
            return String(localized: "\(dayLabel) \(r.startTimeOfDayString)–\(r.endTimeOfDayString)", comment: "Single-routine summary: day label and time range")
        default:
            return String(localized: "\(count) routines", comment: "Settings summary showing total routine count")
        }
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
            return String(localized: "\(hours)h \(minutes)m remaining", comment: "Remaining protected time: hours + minutes")
        } else {
            return String(localized: "\(minutes)m remaining", comment: "Remaining protected time: minutes only")
        }
    }

    var isCurrentlyBlocking: Bool {
        weeklySchedule.isBlocking(at: Date())
    }

    /// Time until the next free-time window starts. Returns `nil` when the user is currently
    /// in free time (no blocking session active).
    var timeUntilFreeTimeText: String? {
        let now = Date()
        guard weeklySchedule.isBlocking(at: now) else { return nil }
        guard let boundary = weeklySchedule.nextBoundary(after: now) else { return nil }
        let mins = max(0, Int(boundary.timeIntervalSince(now) / 60))
        let hours = mins / 60
        let minutes = mins % 60
        if hours > 0 {
            return String(localized: "\(hours)h \(minutes)m", comment: "Compact duration: hours and minutes")
        } else {
            return String(localized: "\(minutes)m", comment: "Compact duration: minutes only")
        }
    }
}
