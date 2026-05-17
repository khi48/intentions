import Foundation

@MainActor
@Observable
final class WeeklySchedule: @preconcurrency Codable {

    var isEnabled: Bool
    var routines: [FreeTimeRoutine]
    var timeZone: TimeZone
    var lastDisabledAt: Date?
    var intentionQuote: String?

    init() {
        self.isEnabled = true
        self.routines = []
        self.timeZone = TimeZone.current
        self.lastDisabledAt = nil
        self.intentionQuote = nil
    }

    // MARK: - Public API

    /// Returns true when the given date is inside any free-time routine.
    /// If the schedule is disabled, returns true unconditionally (blocking is off).
    func isFreeTime(at date: Date) -> Bool {
        guard isEnabled else { return true }
        let (weekday, minuteOfDay) = weekdayAndMinuteOfDay(for: date)
        return routines.contains { $0.isActive(weekday: weekday, minuteOfDay: minuteOfDay) }
    }

    func isBlocking(at date: Date) -> Bool {
        guard isEnabled else { return false }
        return !isFreeTime(at: date)
    }

    /// Total minutes of blocking that have elapsed in the local calendar day of `date`, up to `date`.
    func protectedMinutes(at date: Date) -> Int {
        guard isEnabled else { return 0 }
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let startOfDay = calendar.startOfDay(for: date)
        let minuteOfDayNow = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        var blocked = 0
        for offset in 0..<minuteOfDayNow {
            let probe = calendar.date(byAdding: .minute, value: offset, to: startOfDay)!
            if isBlocking(at: probe) {
                blocked += 1
            }
        }
        return blocked
    }

    /// Remaining minutes of blocking in the local calendar day of `date`, after `date`.
    func remainingProtectedMinutes(at date: Date) -> Int {
        guard isEnabled else { return 0 }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: date)
        let minuteOfDayNow = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        var blocked = 0
        for offset in minuteOfDayNow..<FreeTimeRoutine.minutesPerDay {
            let probe = calendar.date(byAdding: .minute, value: offset, to: startOfDay)!
            if isBlocking(at: probe) {
                blocked += 1
            }
        }
        return blocked
    }

    /// The next wall-clock moment when `isBlocking(at:)` changes value, or `nil` if the schedule is disabled.
    func nextBoundary(after date: Date) -> Date? {
        guard isEnabled else { return nil }

        let calendar = calendarInScheduleTimezone()
        // Probe minute-by-minute over the next 7 days. 10_080 iterations is trivial.
        // Align start to minute boundary so returned date has second=0 — DAM scheduling
        // extracts hour/minute/second from this value.
        let alignedComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var probe = calendar.date(from: alignedComps) ?? date
        let reference = isBlocking(at: date)
        for _ in 0..<(FreeTimeRoutine.minutesPerDay * 7) {
            probe = calendar.date(byAdding: .minute, value: 1, to: probe)!
            if isBlocking(at: probe) != reference {
                return probe
            }
        }
        return nil
    }

    /// Days since the user last disabled blocking. Nil if never disabled.
    var streakDays: Int? {
        guard let lastDisabledAt else { return nil }
        let calendar = calendarInScheduleTimezone()
        let startOfLastDisable = calendar.startOfDay(for: lastDisabledAt)
        let startOfToday = calendar.startOfDay(for: Date())
        return calendar.dateComponents([.day], from: startOfLastDisable, to: startOfToday).day
    }

    // MARK: - Internal helpers

    /// Convert a wall-clock date to `(weekday, minute-of-day)` in `timeZone`.
    func weekdayAndMinuteOfDay(for date: Date) -> (Weekday, Int) {
        let calendar = calendarInScheduleTimezone()
        let calendarWeekday = calendar.component(.weekday, from: date)
        let weekday = Weekday.from(calendarWeekday: calendarWeekday)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return (weekday, hour * 60 + minute)
    }

    private func calendarInScheduleTimezone() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = 2 // Monday; does not affect .weekday component but keeps intent explicit
        return c
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case isEnabled, routines, timeZone, lastDisabledAt, intentionQuote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        routines = try c.decodeIfPresent([FreeTimeRoutine].self, forKey: .routines) ?? []
        let tzID = try c.decode(String.self, forKey: .timeZone)
        timeZone = TimeZone(identifier: tzID) ?? TimeZone.current
        lastDisabledAt = try c.decodeIfPresent(Date.self, forKey: .lastDisabledAt)
        intentionQuote = try c.decodeIfPresent(String.self, forKey: .intentionQuote)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(routines, forKey: .routines)
        try c.encode(timeZone.identifier, forKey: .timeZone)
        try c.encodeIfPresent(lastDisabledAt, forKey: .lastDisabledAt)
        try c.encodeIfPresent(intentionQuote, forKey: .intentionQuote)
    }
}

// MARK: - ShieldState bridge

extension WeeklySchedule {
    /// Convert this Observable schedule to a Sendable, value-type snapshot
    /// suitable for embedding in `IntentLog` and reading from the DAM extension.
    func snapshot() -> ScheduleSnapshot {
        ScheduleSnapshot(
            isEnabled: isEnabled,
            routines: routines.map {
                ScheduleSnapshot.Routine(
                    startMinute: $0.startMinute,
                    durationMinutes: $0.durationMinutes,
                    days: $0.days
                )
            },
            timeZoneIdentifier: timeZone.identifier
        )
    }
}
