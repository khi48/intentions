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
    var startHour: Int   // Free time start hour (24-hour format, 0-23)
    var startMinute: Int // Free time start minute (0-59)
    var endHour: Int     // Free time end hour (24-hour format, 0-23)
    var endMinute: Int   // Free time end minute (0-59)
    var activeDays: Set<Weekday>  // Days that have a free time window
    var timeZone: TimeZone
    var lastDisabledAt: Date?
    var intentionQuote: String?

    init() {
        self.isEnabled = true
        self.startHour = 17
        self.startMinute = 0
        self.endHour = 21
        self.endMinute = 30
        self.activeDays = Set(Weekday.allCases)
        self.timeZone = TimeZone.current
        self.lastDisabledAt = nil
        self.intentionQuote = nil
    }

    /// Total minutes of the day where free time starts
    var startTotalMinutes: Int { startHour * 60 + startMinute }

    /// Total minutes of the day where free time ends
    var endTotalMinutes: Int { endHour * 60 + endMinute }

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

        // Check if current minute-of-day is within the free time window
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minuteOfDay = hour * 60 + minute
        if isInFreeTimeRange(minuteOfDay: minuteOfDay) {
            return false // In free time → blocking NOT active
        }
        return true // Outside free time → blocking active
    }

    /// Check if a given minute-of-day falls within the free time range
    func isInFreeTimeRange(minuteOfDay: Int) -> Bool {
        let start = startTotalMinutes
        let end = endTotalMinutes
        if start <= end {
            return minuteOfDay >= start && minuteOfDay < end
        } else {
            // Overnight free time (rare, but supported)
            return minuteOfDay >= start || minuteOfDay < end
        }
    }

    /// Legacy hour-only check retained for backward compatibility
    func isInFreeTimeRange(_ hour: Int) -> Bool {
        isInFreeTimeRange(minuteOfDay: hour * 60)
    }

    /// Total minutes in the free time window
    var totalFreeTimeMinutes: Int {
        let start = startTotalMinutes
        let end = endTotalMinutes
        if start <= end {
            return end - start
        } else {
            return (24 * 60 - start) + end
        }
    }

    /// Total hours in the free time window (rounded down, retained for API compat)
    var totalFreeTimeHours: Int {
        totalFreeTimeMinutes / 60
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
        protectedMinutes(at: Date())
    }

    /// Minutes of blocking remaining today.
    var remainingProtectedMinutesToday: Int {
        remainingProtectedMinutes(at: Date())
    }

    /// Minutes of blocking elapsed on the calendar day containing `date`, up to `date`.
    func protectedMinutes(at date: Date) -> Int {
        guard isEnabled else { return 0 }

        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let nowMinuteOfDay = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        // If today isn't a free-time day, blocking is active all day so far.
        let weekday = Weekday.from(calendarWeekday: calendar.component(.weekday, from: date))
        guard activeDays.contains(weekday) else {
            return nowMinuteOfDay
        }

        let start = startTotalMinutes
        let end = endTotalMinutes
        let freeMinutesElapsed: Int
        if start <= end {
            // Daytime window: free is [start, end)
            if nowMinuteOfDay <= start {
                freeMinutesElapsed = 0
            } else if nowMinuteOfDay < end {
                freeMinutesElapsed = nowMinuteOfDay - start
            } else {
                freeMinutesElapsed = end - start
            }
        } else {
            // Overnight window: free is [0, end) ∪ [start, 1440)
            if nowMinuteOfDay < end {
                freeMinutesElapsed = nowMinuteOfDay
            } else if nowMinuteOfDay < start {
                freeMinutesElapsed = end
            } else {
                freeMinutesElapsed = end + (nowMinuteOfDay - start)
            }
        }

        return nowMinuteOfDay - freeMinutesElapsed
    }

    /// Minutes of blocking remaining on the calendar day containing `date`, after `date`.
    func remainingProtectedMinutes(at date: Date) -> Int {
        guard isEnabled else { return 0 }

        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let weekday = Weekday.from(calendarWeekday: calendar.component(.weekday, from: date))

        let totalBlockingMinutes: Int
        if activeDays.contains(weekday) {
            totalBlockingMinutes = (24 * 60) - totalFreeTimeMinutes
        } else {
            totalBlockingMinutes = 24 * 60
        }
        return max(0, totalBlockingMinutes - protectedMinutes(at: date))
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
        case isEnabled, activeHoursStart, activeHoursEnd
        case activeMinutesStart, activeMinutesEnd
        case activeDays, timeZone
        case lastDisabledAt, intentionQuote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        startHour = try container.decode(Int.self, forKey: .activeHoursStart)
        endHour = try container.decode(Int.self, forKey: .activeHoursEnd)
        startMinute = try container.decodeIfPresent(Int.self, forKey: .activeMinutesStart) ?? 0
        endMinute = try container.decodeIfPresent(Int.self, forKey: .activeMinutesEnd) ?? 0
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
        try container.encode(startMinute, forKey: .activeMinutesStart)
        try container.encode(endMinute, forKey: .activeMinutesEnd)
        try container.encode(activeDays, forKey: .activeDays)
        try container.encode(timeZone.identifier, forKey: .timeZone)
        try container.encodeIfPresent(lastDisabledAt, forKey: .lastDisabledAt)
        try container.encodeIfPresent(intentionQuote, forKey: .intentionQuote)
    }
}
