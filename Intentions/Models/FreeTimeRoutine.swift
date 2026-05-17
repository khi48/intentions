import Foundation

/// A recurring free-time window. Time-of-day + a set of weekdays it repeats on.
/// Single-day only: `startMinute + durationMinutes` must not exceed 1440. Late-night
/// routines that cross midnight are expressed as two separate routines.
struct FreeTimeRoutine: Identifiable, Codable, Hashable, Sendable {
    static let minutesPerDay = 24 * 60          // 1440

    let id: UUID
    var name: String?
    /// 0..<1440. Minute-of-day in the schedule's timezone.
    var startMinute: Int
    /// 1...(1440 - startMinute). Strictly positive, single-day.
    var durationMinutes: Int
    /// Days of the week on which this routine recurs.
    var days: Set<Weekday>
    /// Manual order index — list view sorts ascending.
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        name: String? = nil,
        startMinute: Int,
        durationMinutes: Int,
        days: Set<Weekday>,
        sortIndex: Int
    ) {
        self.id = id
        self.name = name
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.days = days
        self.sortIndex = sortIndex
    }

    /// Exclusive end-minute-of-day. Always `<= 1440`.
    var endMinute: Int { startMinute + durationMinutes }

    /// True if `weekday ∈ days && minuteOfDay ∈ [startMinute, endMinute)`.
    func isActive(weekday: Weekday, minuteOfDay: Int) -> Bool {
        guard days.contains(weekday) else { return false }
        return minuteOfDay >= startMinute && minuteOfDay < endMinute
    }

    /// Display string, e.g. `"08:30"`.
    var startTimeOfDayString: String {
        Self.timeOfDayString(forMinute: startMinute)
    }

    /// Display string, e.g. `"12:00"`.
    var endTimeOfDayString: String {
        Self.timeOfDayString(forMinute: endMinute)
    }

    static func timeOfDayString(forMinute minute: Int) -> String {
        let h = minute / 60
        let m = minute % 60
        return String(format: "%02d:%02d", h, m)
    }

    /// Card title resolution: trimmed non-empty name wins; otherwise the time-range string.
    static func title(for routine: FreeTimeRoutine) -> String {
        if let raw = routine.name {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "\(routine.startTimeOfDayString)–\(routine.endTimeOfDayString)"
    }
}
