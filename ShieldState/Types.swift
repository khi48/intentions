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
    static let minutesPerWeek = 10_080

    /// Start + duration in minutes from Monday 00:00 in the schedule's timezone.
    struct Interval: Codable, Sendable, Equatable {
        let startMinuteOfWeek: Int
        let durationMinutes: Int
    }

    var isEnabled: Bool
    var intervals: [Interval]
    /// TimeZone identifier (e.g. "Pacific/Auckland"). Stored as String for Sendable.
    var timeZoneIdentifier: String

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    /// Disabled snapshot ⇒ blocking is off everywhere. Used as a no-op default.
    static let disabled = ScheduleSnapshot(isEnabled: false, intervals: [], timeZoneIdentifier: TimeZone.current.identifier)

    func isFreeTime(at date: Date) -> Bool {
        guard isEnabled else { return true }
        let mow = minuteOfWeek(for: date)
        return intervals.contains { Self.contains(interval: $0, minuteOfWeek: mow) }
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
        for _ in 0..<Self.minutesPerWeek {
            probe = calendar.date(byAdding: .minute, value: 1, to: probe)!
            if isBlocking(at: probe) != reference {
                return probe
            }
        }
        return nil
    }

    private func minuteOfWeek(for date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let calendarWeekday = calendar.component(.weekday, from: date)
        // Foundation: Sun=1..Sat=7. Normalise to Monday=0..Sunday=6.
        let mondayZeroIndex: Int
        switch calendarWeekday {
        case 1: mondayZeroIndex = 6
        case 2: mondayZeroIndex = 0
        case 3: mondayZeroIndex = 1
        case 4: mondayZeroIndex = 2
        case 5: mondayZeroIndex = 3
        case 6: mondayZeroIndex = 4
        case 7: mondayZeroIndex = 5
        default: mondayZeroIndex = 0
        }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return mondayZeroIndex * Self.minutesPerDay + hour * 60 + minute
    }

    private static func contains(interval: Interval, minuteOfWeek: Int) -> Bool {
        let end = interval.startMinuteOfWeek + interval.durationMinutes
        if end <= Self.minutesPerWeek {
            return minuteOfWeek >= interval.startMinuteOfWeek && minuteOfWeek < end
        } else {
            // Wraps Sunday→Monday boundary.
            let wrappedEnd = end - Self.minutesPerWeek
            return minuteOfWeek >= interval.startMinuteOfWeek || minuteOfWeek < wrappedEnd
        }
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
        self.weeklySchedule = try c.decodeIfPresent(ScheduleSnapshot.self, forKey: .weeklySchedule)
    }
}

/// What the shield store should be configured to, at a moment in time.
enum ShieldConfig: Equatable, Sendable {
    case none                               // nothing shielded
    case allExcept(FamilyActivitySelection) // everything except these
    case all                                // everything shielded
}
