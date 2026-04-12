//
//  ScheduleSettings.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//
// =============================================================================
// Models/ScheduleSettings.swift - Free Time Window Configuration
// =============================================================================
//
// Blocking model: apps are blocked by default 24/7.
// startHour/endHour/activeDays define a "free time" window when blocking is lifted.
// isCurrentlyActive returns true when blocking IS active (i.e., NOT in free time).

import Foundation

@MainActor
@Observable
final class ScheduleSettings: @preconcurrency Codable {
    var isEnabled: Bool
    var startHour: Int   // Free time start (24-hour format, 0-23)
    var endHour: Int     // Free time end (24-hour format, 0-23)
    var activeDays: Set<Weekday>  // Days that have a free time window
    var timeZone: TimeZone
    var lastDisabledAt: Date?
    var intentionQuote: String?

    init() {
        self.isEnabled = true
        self.startHour = AppConstants.Schedule.defaultStartHour
        self.endHour = AppConstants.Schedule.defaultEndHour
        self.activeDays = Set(Weekday.allCases)
        self.timeZone = AppConstants.Schedule.defaultTimeZone
        self.lastDisabledAt = nil
        self.intentionQuote = nil
    }

    /// Whether blocking is currently active (true = apps are blocked, false = in free time)
    var isCurrentlyActive: Bool {
        isActive(at: Date())
    }

    /// Returns true when blocking should be active at the given date.
    /// Blocking is the default state. It is only lifted during the free time window
    /// on days that are in `activeDays`.
    func isActive(at date: Date) -> Bool {
        guard isEnabled else { return false }

        var calendar = Calendar.current
        calendar.timeZone = timeZone

        // Check if today has a free time window
        let weekdayComponent = calendar.component(.weekday, from: date)
        let weekday = Weekday.from(calendarWeekday: weekdayComponent)

        // If today isn't a free-time day, blocking is active
        guard activeDays.contains(weekday) else { return true }

        // Check if current hour is within the free time window
        let hour = calendar.component(.hour, from: date)
        if isInFreeTimeRange(hour) {
            return false // In free time → blocking NOT active
        }
        return true // Outside free time → blocking active
    }

    /// Check if a given hour falls within the free time range
    func isInFreeTimeRange(_ hour: Int) -> Bool {
        if startHour <= endHour {
            return hour >= startHour && hour < endHour
        } else {
            // Overnight free time (rare, but supported)
            return hour >= startHour || hour < endHour
        }
    }

    /// Total hours in the free time window
    var totalFreeTimeHours: Int {
        if startHour <= endHour {
            return endHour - startHour
        } else {
            return (24 - startHour) + endHour
        }
    }

    /// Days since the user last disabled blocking. Nil if never disabled.
    var streakDays: Int? {
        guard let lastDisabledAt else { return nil }
        let calendar = Calendar.current
        let startOfLastDisable = calendar.startOfDay(for: lastDisabledAt)
        let startOfToday = calendar.startOfDay(for: Date())
        return calendar.dateComponents([.day], from: startOfLastDisable, to: startOfToday).day
    }

    /// Minutes of blocking elapsed today (time spent outside free window).
    var protectedMinutesToday: Int {
        guard isEnabled else { return 0 }

        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        // Total minutes elapsed today
        let totalMinutesElapsed = currentHour * 60 + currentMinute

        // Calculate free time minutes elapsed today
        let freeMinutesElapsed: Int
        if startHour <= endHour {
            if currentHour < startHour {
                freeMinutesElapsed = 0
            } else if currentHour < endHour {
                freeMinutesElapsed = (currentHour - startHour) * 60 + currentMinute
            } else {
                freeMinutesElapsed = (endHour - startHour) * 60
            }
        } else {
            // Overnight free time — unusual but handle it
            freeMinutesElapsed = 0 // Simplified for v1
        }

        return totalMinutesElapsed - freeMinutesElapsed
    }

    /// Minutes of blocking remaining today.
    var remainingProtectedMinutesToday: Int {
        guard isEnabled else { return 0 }

        let totalBlockingMinutes = (24 * 60) - (totalFreeTimeHours * 60)
        return max(0, totalBlockingMinutes - protectedMinutesToday)
    }

    // MARK: - Backward Compatibility

    /// Provides ClosedRange access for test code that still uses it
    var activeHours: ClosedRange<Int> {
        get {
            if startHour <= endHour {
                return startHour...endHour
            }
            return startHour...23
        }
        set {
            startHour = newValue.lowerBound
            endHour = newValue.upperBound
        }
    }

    // Codable implementation
    enum CodingKeys: String, CodingKey {
        case isEnabled, activeHoursStart, activeHoursEnd, activeDays, timeZone
        case lastDisabledAt, intentionQuote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        startHour = try container.decode(Int.self, forKey: .activeHoursStart)
        endHour = try container.decode(Int.self, forKey: .activeHoursEnd)
        activeDays = try container.decode(Set<Weekday>.self, forKey: .activeDays)

        let timeZoneIdentifier = try container.decode(String.self, forKey: .timeZone)
        timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone.current
        lastDisabledAt = try container.decodeIfPresent(Date.self, forKey: .lastDisabledAt)
        intentionQuote = try container.decodeIfPresent(String.self, forKey: .intentionQuote)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(startHour, forKey: .activeHoursStart)
        try container.encode(endHour, forKey: .activeHoursEnd)
        try container.encode(activeDays, forKey: .activeDays)
        try container.encode(timeZone.identifier, forKey: .timeZone)
        try container.encodeIfPresent(lastDisabledAt, forKey: .lastDisabledAt)
        try container.encodeIfPresent(intentionQuote, forKey: .intentionQuote)
    }
}
