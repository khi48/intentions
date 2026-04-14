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
    /// Minimum free-time interval length emitted by migration. Matches the
    /// faithful migration's existing duration guard.
    private static let migrationMinIntervalMinutes = 10

    /// One-shot conversion of the legacy `ScheduleSettings` model to `WeeklySchedule`.
    ///
    /// Two semantics are supported:
    /// - **Faithful** (default): `activeHours` are FREE TIME windows. Each `activeDays`
    ///   day gets one `FreeTimeInterval` covering the start..end window. Overnight
    ///   windows wrap naturally.
    /// - **Inverted** (`old.wasLegacyV1Format == true`): `activeHours` were BLOCKING hours
    ///   on a day-by-day basis (v1.0 build 1 model). Each `activeDays` day emits the
    ///   COMPLEMENT of its blocking range as up to two free intervals. Days NOT in
    ///   `activeDays` were unblocked entirely and emit a full 24-hour free interval.
    static func migrate(from old: ScheduleSettings) -> WeeklySchedule {
        let schedule = WeeklySchedule()
        schedule.intervals = [] // overwrite the defaultIntervals seed
        schedule.isEnabled = old.isEnabled
        schedule.timeZone = old.timeZone
        schedule.lastDisabledAt = old.lastDisabledAt
        schedule.intentionQuote = old.intentionQuote

        if old.wasLegacyV1Format {
            schedule.intervals = invertedIntervals(from: old)
        } else {
            schedule.intervals = faithfulIntervals(from: old)
        }
        return schedule
    }

    private static func faithfulIntervals(from old: ScheduleSettings) -> [FreeTimeInterval] {
        let timeStart = old.startHour * 60 + old.startMinute
        let timeEnd = old.endHour * 60 + old.endMinute
        // Modulo-1440 so overnight windows keep their natural duration.
        let duration = ((timeEnd - timeStart) + FreeTimeInterval.minutesPerDay) % FreeTimeInterval.minutesPerDay
        guard duration >= migrationMinIntervalMinutes else { return [] }

        let sortedDays = old.activeDays.sorted { FreeTimeInterval.mondayDayIndex(for: $0) < FreeTimeInterval.mondayDayIndex(for: $1) }
        return sortedDays.map { day in
            let dayOrigin = FreeTimeInterval.mondayDayIndex(for: day) * FreeTimeInterval.minutesPerDay
            return FreeTimeInterval(
                id: UUID(),
                startMinuteOfWeek: dayOrigin + timeStart,
                durationMinutes: duration
            )
        }
    }

    /// Inverted migration for v1.0 build 1 records. v1 stored `activeHours` as a
    /// `ClosedRange<Int>` of BLOCKING hours, where `9...17` meant "blocked during
    /// hours 9, 10, ..., 17 inclusive" — i.e. blocked minute-of-day [9*60, 18*60).
    /// Free time is the complement on each `activeDays` day, plus full days for
    /// any non-active day.
    ///
    /// v1's ClosedRange precondition guaranteed `startHour <= endHour`, so no
    /// wraparound case is possible from a v1 record.
    private static func invertedIntervals(from old: ScheduleSettings) -> [FreeTimeInterval] {
        var intervals: [FreeTimeInterval] = []
        let allDays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

        for day in allDays {
            let dayOrigin = FreeTimeInterval.mondayDayIndex(for: day) * FreeTimeInterval.minutesPerDay

            if old.activeDays.contains(day) {
                // Day had a v1 blocking window. Free = complement.
                let blockStart = old.startHour * 60                  // inclusive
                let blockEnd = min((old.endHour + 1) * 60, FreeTimeInterval.minutesPerDay) // exclusive

                // Pre-blocking free segment: [0, blockStart)
                if blockStart >= migrationMinIntervalMinutes {
                    intervals.append(FreeTimeInterval(
                        id: UUID(),
                        startMinuteOfWeek: dayOrigin,
                        durationMinutes: blockStart
                    ))
                }
                // Post-blocking free segment: [blockEnd, 1440)
                let postFreeDuration = FreeTimeInterval.minutesPerDay - blockEnd
                if postFreeDuration >= migrationMinIntervalMinutes {
                    intervals.append(FreeTimeInterval(
                        id: UUID(),
                        startMinuteOfWeek: dayOrigin + blockEnd,
                        durationMinutes: postFreeDuration
                    ))
                }
            } else {
                // Non-active day in v1 = no blocking = free all day.
                intervals.append(FreeTimeInterval(
                    id: UUID(),
                    startMinuteOfWeek: dayOrigin,
                    durationMinutes: FreeTimeInterval.minutesPerDay
                ))
            }
        }
        return intervals
    }
}
