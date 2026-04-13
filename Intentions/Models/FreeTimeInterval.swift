import Foundation

/// A contiguous block of free time on the weekly schedule.
/// Stored as a (start, duration) pair measured in minutes from Monday 00:00.
struct FreeTimeInterval: Identifiable, Codable, Hashable, Sendable {
    static let minutesPerDay = 24 * 60          // 1440
    static let minutesPerWeek = 7 * 24 * 60     // 10080

    let id: UUID
    /// 0..<10080. Monday 00:00 is 0.
    let startMinuteOfWeek: Int
    /// Strictly positive, max 10080 − 10.
    let durationMinutes: Int

    // MARK: - Containment

    /// Returns true if `minuteOfWeek` (0..<10080) falls inside this interval.
    /// End is exclusive. Wrap-around across the week boundary is supported.
    func contains(minuteOfWeek: Int) -> Bool {
        let end = startMinuteOfWeek + durationMinutes
        if end <= FreeTimeInterval.minutesPerWeek {
            return minuteOfWeek >= startMinuteOfWeek && minuteOfWeek < end
        } else {
            let wrappedEnd = end - FreeTimeInterval.minutesPerWeek
            return minuteOfWeek >= startMinuteOfWeek || minuteOfWeek < wrappedEnd
        }
    }

    /// Returns true if this interval shares any minute with `other`.
    func overlaps(_ other: FreeTimeInterval) -> Bool {
        // Two positive-length intervals overlap iff one contains at least one endpoint of the other.
        // Checking all four endpoints (start + last-inclusive minute of each) is both necessary and
        // sufficient. The % minutesPerWeek on each last-minute handles the wrap-around case.
        return contains(minuteOfWeek: other.startMinuteOfWeek)
            || contains(minuteOfWeek: (other.startMinuteOfWeek + other.durationMinutes - 1) % FreeTimeInterval.minutesPerWeek)
            || other.contains(minuteOfWeek: startMinuteOfWeek)
            || other.contains(minuteOfWeek: (startMinuteOfWeek + durationMinutes - 1) % FreeTimeInterval.minutesPerWeek)
    }

    // MARK: - Derived day/time

    var startDayOfWeek: Weekday {
        Self.weekday(fromMondayDayIndex: startMinuteOfWeek / FreeTimeInterval.minutesPerDay)
    }

    var startHour: Int {
        (startMinuteOfWeek % FreeTimeInterval.minutesPerDay) / 60
    }

    var startMinute: Int {
        startMinuteOfWeek % 60
    }

    /// The minute-of-week of the final minute contained by this interval (inclusive).
    var lastMinuteOfWeek: Int {
        (startMinuteOfWeek + durationMinutes - 1) % FreeTimeInterval.minutesPerWeek
    }

    /// The exclusive end minute of this interval, modulo week length.
    private var endMinuteExclusiveOfWeek: Int {
        (startMinuteOfWeek + durationMinutes) % FreeTimeInterval.minutesPerWeek
    }

    var endDayOfWeek: Weekday {
        Self.weekday(fromMondayDayIndex: lastMinuteOfWeek / FreeTimeInterval.minutesPerDay)
    }

    var endHour: Int {
        (endMinuteExclusiveOfWeek % FreeTimeInterval.minutesPerDay) / 60
    }

    var endMinute: Int {
        endMinuteExclusiveOfWeek % 60
    }

    /// True if the interval's extent crosses from Sunday back to Monday.
    var wrapsWeekBoundary: Bool {
        startMinuteOfWeek + durationMinutes > FreeTimeInterval.minutesPerWeek
    }

    // MARK: - Internal helpers

    /// Inverse of `mondayDayIndex(for:)`. Private because only the `startDayOfWeek` /
    /// `endDayOfWeek` computed properties on this type call it.
    private static func weekday(fromMondayDayIndex index: Int) -> Weekday {
        switch index {
        case 0: return .monday
        case 1: return .tuesday
        case 2: return .wednesday
        case 3: return .thursday
        case 4: return .friday
        case 5: return .saturday
        case 6: return .sunday
        default: return .monday
        }
    }

    /// Convert a `Weekday` case to a 0..6 Monday-origin day index.
    static func mondayDayIndex(for weekday: Weekday) -> Int {
        switch weekday {
        case .monday: return 0
        case .tuesday: return 1
        case .wednesday: return 2
        case .thursday: return 3
        case .friday: return 4
        case .saturday: return 5
        case .sunday: return 6
        }
    }
}
