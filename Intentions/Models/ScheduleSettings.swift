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

@Observable
final class ScheduleSettings: Codable, @unchecked Sendable {
    var isEnabled: Bool
    var activeHours: ClosedRange<Int> // 24-hour format: 9...17 means 9 AM to 5 PM
    var activeDays: Set<Weekday>
    var timeZone: TimeZone
    
    init() {
        self.isEnabled = true
        self.activeHours = AppConstants.Schedule.defaultActiveHours
        self.activeDays = Set(Weekday.allCases) // All days by default
        self.timeZone = AppConstants.Schedule.defaultTimeZone
    }
    
    // Check if current time falls within active schedule
    var isCurrentlyActive: Bool {
        guard isEnabled else { return false }
        
        let now = Date()
        let calendar = Calendar.current
        
        // Check day of week
        let weekdayComponent = calendar.component(.weekday, from: now)
        let currentWeekday = Weekday.from(calendarWeekday: weekdayComponent)
        guard activeDays.contains(currentWeekday) else { return false }
        
        // Check hour
        let hour = calendar.component(.hour, from: now)
        return activeHours.contains(hour)
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
    
    // Codable implementation
    enum CodingKeys: String, CodingKey {
        case isEnabled, activeHoursStart, activeHoursEnd, activeDays, timeZone
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
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(activeHours.lowerBound, forKey: .activeHoursStart)
        try container.encode(activeHours.upperBound, forKey: .activeHoursEnd)
        try container.encode(activeDays, forKey: .activeDays)
        try container.encode(timeZone.identifier, forKey: .timeZone)
    }
}
