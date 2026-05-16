import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// A time-bounded user-granted access window.
struct Session: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let apps: FamilyActivitySelection
    let startedAt: Date
    let endsAt: Date

    init(id: UUID = UUID(), apps: FamilyActivitySelection, startedAt: Date, endsAt: Date) {
        self.id = id
        self.apps = apps
        self.startedAt = startedAt
        self.endsAt = endsAt
    }
}

/// Sendable, value-type snapshot of the user's weekly free-time schedule.
/// Mirrors the data + queries from `WeeklySchedule` (main-app-only, MainActor)
/// in a form the DAM extension can read out of the App Group plist.
struct ScheduleSnapshot: Codable, Sendable, Equatable {
    static let minutesPerDay = 1440

    /// One recurring free-time window: time-of-day range that fires on the named weekdays.
    struct Routine: Codable, Sendable, Equatable {
        let startMinute: Int
        let durationMinutes: Int
        let days: Set<Weekday>

        var endMinute: Int { startMinute + durationMinutes }

        func isActive(weekday: Weekday, minuteOfDay: Int) -> Bool {
            guard days.contains(weekday) else { return false }
            return minuteOfDay >= startMinute && minuteOfDay < endMinute
        }
    }

    var isEnabled: Bool
    var routines: [Routine]
    /// TimeZone identifier (e.g. "Pacific/Auckland"). Stored as String for Sendable.
    var timeZoneIdentifier: String

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    /// Disabled snapshot ⇒ blocking is off everywhere. Used as a no-op default.
    static let disabled = ScheduleSnapshot(isEnabled: false, routines: [], timeZoneIdentifier: TimeZone.current.identifier)

    func isFreeTime(at date: Date) -> Bool {
        guard isEnabled else { return true }
        let (weekday, minuteOfDay) = weekdayAndMinuteOfDay(for: date)
        return routines.contains { $0.isActive(weekday: weekday, minuteOfDay: minuteOfDay) }
    }

    func isBlocking(at date: Date) -> Bool {
        guard isEnabled else { return false }
        return !isFreeTime(at: date)
    }

    /// Next wall-clock moment when `isBlocking(at:)` flips, or `nil` if the schedule is
    /// disabled / never flips within the next week. Minute-by-minute probe over 7 days
    /// (10080 iterations — trivial).
    func nextBoundary(after date: Date) -> Date? {
        guard isEnabled else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Align probe to start of minute so returned boundary has second=0.
        // Free-time intervals are minute-grained; downstream DAM scheduling
        // extracts hour/minute/second, so a non-aligned probe would fire DAM
        // events at the input's seconds offset.
        let alignedComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var probe = calendar.date(from: alignedComps) ?? date
        let reference = isBlocking(at: date)
        for _ in 0..<(Self.minutesPerDay * 7) {
            probe = calendar.date(byAdding: .minute, value: 1, to: probe)!
            if isBlocking(at: probe) != reference {
                return probe
            }
        }
        return nil
    }

    private func weekdayAndMinuteOfDay(for date: Date) -> (Weekday, Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let calendarWeekday = calendar.component(.weekday, from: date)
        let weekday = Weekday.from(calendarWeekday: calendarWeekday)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return (weekday, hour * 60 + minute)
    }
}

/// Persisted source of truth for shield decisions. Read/written by main app and DAM extension.
struct IntentLog: Codable, Sendable, Equatable {
    var activeSession: Session?
    /// Every ApplicationToken the user has picked in any session so far.
    /// Used as a belt-and-suspenders against a known iOS 26 Family Controls
    /// gap: `shield.applicationCategories = .all()` does NOT reliably shield
    /// every app — some apps (common: browsers, picks previously unlocked in
    /// a session) slip through. Setting `shield.applications` with an
    /// explicit token set plugs the gap. Old codebase called this
    /// `knownAppTokens`; name kept here for continuity in the plist.
    var knownApplicationTokens: Set<ApplicationToken>
    var knownWebDomainTokens: Set<WebDomainToken>
    /// Cached snapshot of the user's weekly schedule. Written by the main app
    /// when the schedule changes and on foreground. The DAM extension reads it
    /// to evaluate `compute(_:at:)` correctly when handling schedule-boundary
    /// transitions (and when handling session expiry that lands in free time).
    /// Optional so logs persisted before this field exists decode cleanly.
    var weeklySchedule: ScheduleSnapshot?

    init(
        activeSession: Session?,
        knownApplicationTokens: Set<ApplicationToken> = [],
        knownWebDomainTokens: Set<WebDomainToken> = [],
        weeklySchedule: ScheduleSnapshot? = nil
    ) {
        self.activeSession = activeSession
        self.knownApplicationTokens = knownApplicationTokens
        self.knownWebDomainTokens = knownWebDomainTokens
        self.weeklySchedule = weeklySchedule
    }

    static let empty = IntentLog(activeSession: nil)
}

extension IntentLog {
    /// Codable contract: only the live fields are encoded/decoded. Legacy
    /// on-device blobs containing a `defaultState` key still decode cleanly —
    /// the unknown key is simply ignored by `KeyedDecodingContainer`.
    private enum CodingKeys: String, CodingKey {
        case activeSession, knownApplicationTokens, knownWebDomainTokens, weeklySchedule
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.activeSession = try c.decodeIfPresent(Session.self, forKey: .activeSession)
        // Tolerate logs saved before these fields existed.
        self.knownApplicationTokens = try c.decodeIfPresent(Set<ApplicationToken>.self, forKey: .knownApplicationTokens) ?? []
        self.knownWebDomainTokens = try c.decodeIfPresent(Set<WebDomainToken>.self, forKey: .knownWebDomainTokens) ?? []
        // Old IntentLog blobs stored an Interval-based snapshot under the same key.
        // Type-mismatch on decode falls back to nil; the main app will re-snapshot
        // on the next saveWeeklySchedule call and the DAM will pick it up.
        do {
            self.weeklySchedule = try c.decodeIfPresent(ScheduleSnapshot.self, forKey: .weeklySchedule)
        } catch {
            self.weeklySchedule = nil
        }
    }
}

/// What the shield store should be configured to, at a moment in time.
enum ShieldConfig: Equatable, Sendable {
    case none                               // nothing shielded
    case allExcept(FamilyActivitySelection) // everything except these
    case all                                // everything shielded
}
