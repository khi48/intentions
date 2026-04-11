//
//  ScheduleSettings.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//
// =============================================================================
// Models/ScheduleSettings.swift - When App Is Active
// =============================================================================

import Foundation

@MainActor
@Observable
final class ScheduleSettings: @preconcurrency Codable {
    var isEnabled: Bool
    var activeHours: ClosedRange<Int> // 24-hour format: 9...17 means 9 AM to 5 PM
    var activeDays: Set<Weekday>
    var timeZone: TimeZone
    var lastDisabledAt: Date?
    var intentionQuote: String?

    init() {
        self.isEnabled = true
        self.activeHours = AppConstants.Schedule.defaultActiveHours
        self.activeDays = Set(Weekday.allCases) // All days by default
        self.timeZone = AppConstants.Schedule.defaultTimeZone
        self.lastDisabledAt = nil
        self.intentionQuote = nil
    }
    
    // Check if current time falls within active schedule
    var isCurrentlyActive: Bool {
        guard isEnabled else { 
            return false 
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // Check day of week
        let weekdayComponent = calendar.component(.weekday, from: now)
        let currentWeekday = Weekday.from(calendarWeekday: weekdayComponent)
        let dayMatches = activeDays.contains(currentWeekday)
        
        // Check hour
        let hour = calendar.component(.hour, from: now)
        let hourMatches = activeHours.contains(hour)

        return dayMatches && hourMatches
    }
    
    func isActive(at date: Date) -> Bool {
        guard isEnabled else { return false }

        let calendar = Calendar.current

        // Check day of week
        let weekdayComponent = calendar.component(.weekday, from: date)
        let weekday = Weekday.from(calendarWeekday: weekdayComponent)
        guard activeDays.contains(weekday) else { return false }

        // Check hour
        let hour = calendar.component(.hour, from: date)
        return activeHours.contains(hour)
    }

    /// Days since the user last disabled blocking. Nil if never disabled.
    var streakDays: Int? {
        guard let lastDisabledAt else { return nil }
        let calendar = Calendar.current
        let startOfLastDisable = calendar.startOfDay(for: lastDisabledAt)
        let startOfToday = calendar.startOfDay(for: Date())
        return calendar.dateComponents([.day], from: startOfLastDisable, to: startOfToday).day
    }

    /// Minutes the user has been within protected hours today.
    var protectedMinutesToday: Int {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        let startHour = activeHours.lowerBound
        let endHour = activeHours.upperBound

        guard currentHour >= startHour else { return 0 }

        let effectiveEndHour = min(currentHour, endHour)
        let fullHoursMinutes = max(0, effectiveEndHour - startHour) * 60

        if currentHour < endHour {
            return fullHoursMinutes + currentMinute
        } else {
            return max(0, endHour - startHour) * 60
        }
    }

    /// Minutes remaining in today's protected hours.
    var remainingProtectedMinutesToday: Int {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        let endHour = activeHours.upperBound

        guard currentHour < endHour else { return 0 }

        return (endHour - currentHour) * 60 - currentMinute
    }

    // Codable implementation
    enum CodingKeys: String, CodingKey {
        case isEnabled, activeHoursStart, activeHoursEnd, activeDays, timeZone
        case lastDisabledAt, intentionQuote
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        let start = try container.decode(Int.self, forKey: .activeHoursStart)
        let end = try container.decode(Int.self, forKey: .activeHoursEnd)
        activeHours = start...end
        activeDays = try container.decode(Set<Weekday>.self, forKey: .activeDays)
        
        let timeZoneIdentifier = try container.decode(String.self, forKey: .timeZone)
        timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone.current
        lastDisabledAt = try container.decodeIfPresent(Date.self, forKey: .lastDisabledAt)
        intentionQuote = try container.decodeIfPresent(String.self, forKey: .intentionQuote)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(activeHours.lowerBound, forKey: .activeHoursStart)
        try container.encode(activeHours.upperBound, forKey: .activeHoursEnd)
        try container.encode(activeDays, forKey: .activeDays)
        try container.encode(timeZone.identifier, forKey: .timeZone)
        try container.encodeIfPresent(lastDisabledAt, forKey: .lastDisabledAt)
        try container.encodeIfPresent(intentionQuote, forKey: .intentionQuote)
    }
}
