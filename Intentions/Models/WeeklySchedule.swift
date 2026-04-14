import Foundation

@MainActor
@Observable
final class WeeklySchedule: @preconcurrency Codable {

    var isEnabled: Bool
    var intervals: [FreeTimeInterval]
    var timeZone: TimeZone
    var lastDisabledAt: Date?
    var intentionQuote: String?

    init() {
        self.isEnabled = true
        self.intervals = AppConstants.Schedule.defaultIntervals
        self.timeZone = TimeZone.current
        self.lastDisabledAt = nil
        self.intentionQuote = nil
    }

    // MARK: - Public API

    /// Returns true when the given date is inside any free-time interval.
    /// If the schedule is disabled, returns true unconditionally (blocking is off).
    func isFreeTime(at date: Date) -> Bool {
        guard isEnabled else { return true }
        let mow = minuteOfWeek(for: date)
        return intervals.contains { $0.contains(minuteOfWeek: mow) }
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
        for offset in minuteOfDayNow..<FreeTimeInterval.minutesPerDay {
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
        var probe = date
        let reference = isBlocking(at: date)
        for _ in 0..<FreeTimeInterval.minutesPerWeek {
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

    /// Convert a wall-clock date to its minute-of-week (0..<10080) in `timeZone`.
    /// Monday is day 0.
    func minuteOfWeek(for date: Date) -> Int {
        let calendar = calendarInScheduleTimezone()
        // Normalise weekday so Monday=0. Foundation's calendar.weekday is Sun=1..Sat=7.
        let calendarWeekday = calendar.component(.weekday, from: date)
        let mondayZeroIndex: Int
        switch calendarWeekday {
        case 1: mondayZeroIndex = 6 // Sunday
        case 2: mondayZeroIndex = 0 // Monday
        case 3: mondayZeroIndex = 1
        case 4: mondayZeroIndex = 2
        case 5: mondayZeroIndex = 3
        case 6: mondayZeroIndex = 4
        case 7: mondayZeroIndex = 5 // Saturday
        default: mondayZeroIndex = 0
        }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return mondayZeroIndex * FreeTimeInterval.minutesPerDay + hour * 60 + minute
    }

    private func calendarInScheduleTimezone() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = 2 // Monday; does not affect .weekday component but keeps intent explicit
        return c
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case isEnabled, intervals, timeZone, lastDisabledAt, intentionQuote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        intervals = try c.decode([FreeTimeInterval].self, forKey: .intervals)
        let tzID = try c.decode(String.self, forKey: .timeZone)
        timeZone = TimeZone(identifier: tzID) ?? TimeZone.current
        lastDisabledAt = try c.decodeIfPresent(Date.self, forKey: .lastDisabledAt)
        intentionQuote = try c.decodeIfPresent(String.self, forKey: .intentionQuote)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(intervals, forKey: .intervals)
        try c.encode(timeZone.identifier, forKey: .timeZone)
        try c.encodeIfPresent(lastDisabledAt, forKey: .lastDisabledAt)
        try c.encodeIfPresent(intentionQuote, forKey: .intentionQuote)
    }
}

// MARK: - Weekend backfill (one-shot, v97+)

extension WeeklySchedule {
    private static let weekendBackfillFlagKey = "intentions.weeklySchedule.backfill.weekends.v97"

    /// One-shot upgrade for users who persisted a Mon–Fri-only schedule before build 97,
    /// when the app defaults expanded to Mon–Sun. Uses the first existing interval as the
    /// time-of-day template and appends matching Saturday + Sunday intervals if either is
    /// missing. Runs at most once per install (guarded by a UserDefaults flag).
    ///
    /// Returns `true` if any intervals were appended.
    @discardableResult
    func backfillWeekendsIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.weekendBackfillFlagKey) else { return false }
        defaults.set(true, forKey: Self.weekendBackfillFlagKey)

        guard let template = intervals.first else { return false }

        let existingDays = Set(intervals.map { $0.startDayOfWeek })
        var changed = false
        for day: Weekday in [.saturday, .sunday] where !existingDays.contains(day) {
            let dayOrigin = FreeTimeInterval.mondayDayIndex(for: day) * FreeTimeInterval.minutesPerDay
            let timeOfDay = template.startMinuteOfWeek % FreeTimeInterval.minutesPerDay
            intervals.append(FreeTimeInterval(
                id: UUID(),
                startMinuteOfWeek: dayOrigin + timeOfDay,
                durationMinutes: template.durationMinutes
            ))
            changed = true
        }
        return changed
    }
}

// MARK: - Migration from legacy ScheduleSettings

extension WeeklySchedule {
    /// One-shot conversion of the legacy `ScheduleSettings` model to `WeeklySchedule`.
    /// Creates one `FreeTimeInterval` per day in `old.activeDays`, faithfully replaying
    /// overnight windows (start > end) as per-day cross-midnight intervals.
    static func migrate(from old: ScheduleSettings) -> WeeklySchedule {
        let schedule = WeeklySchedule()
        schedule.intervals = [] // overwrite the defaultIntervals seed
        schedule.isEnabled = old.isEnabled
        schedule.timeZone = old.timeZone
        schedule.lastDisabledAt = old.lastDisabledAt
        schedule.intentionQuote = old.intentionQuote

        let timeStart = old.startHour * 60 + old.startMinute
        let timeEnd = old.endHour * 60 + old.endMinute
        // Modulo-1440 so overnight windows keep their natural duration.
        let duration = ((timeEnd - timeStart) + FreeTimeInterval.minutesPerDay) % FreeTimeInterval.minutesPerDay
        guard duration >= 10 else { return schedule }

        // Sort for a stable order in tests.
        let sortedDays = old.activeDays.sorted { FreeTimeInterval.mondayDayIndex(for: $0) < FreeTimeInterval.mondayDayIndex(for: $1) }
        for day in sortedDays {
            let dayOrigin = FreeTimeInterval.mondayDayIndex(for: day) * FreeTimeInterval.minutesPerDay
            schedule.intervals.append(FreeTimeInterval(
                id: UUID(),
                startMinuteOfWeek: dayOrigin + timeStart,
                durationMinutes: duration
            ))
        }
        return schedule
    }
}
