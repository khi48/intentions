import Foundation
@preconcurrency import DeviceActivity

/// Thin wrapper over DeviceActivityCenter that schedules session-expiry callbacks.
///
/// iOS imposes a minimum interval length (intervalTooShort) on
/// DeviceActivitySchedule (~15 min). For shorter sessions we still need
/// exact-time firing, so we schedule **both**:
///  - a padded interval so startMonitoring accepts it (intervalDidEnd fires at pad end)
///  - a threshold event at the actual duration (eventDidReachThreshold fires at real expiry)
///
/// **Critical:** each session gets a UNIQUE DeviceActivityName
/// (`shieldstate.session-expiry.<uuid>`). Reusing a single name across
/// sessions causes iOS to carry over the threshold-counter state — a new
/// schedule under the same name fires its threshold event *at session
/// start*, not at the actual duration. Unique names reset the counter.
struct DAMScheduler: Sendable {
    static let sessionExpiryPrefix = "shieldstate.session-expiry"
    static let thresholdEventName = DeviceActivityEvent.Name("threshold")

    /// iOS requires monitored intervals to be at least this long. Shorter
    /// schedules throw intervalTooShort from startMonitoring.
    static let minimumIntervalSeconds: TimeInterval = 15 * 60

    private let center = DeviceActivityCenter()

    static func activityName(for sessionId: UUID) -> DeviceActivityName {
        DeviceActivityName("\(sessionExpiryPrefix).\(sessionId.uuidString)")
    }

    /// Returns true iff the given activity name is one of ours.
    static func isSessionExpiryActivity(_ activity: DeviceActivityName) -> Bool {
        activity.rawValue.hasPrefix(sessionExpiryPrefix)
    }

    /// Schedule a single-fire session-expiry callback for `endsAt`.
    /// Throws if authorization is missing or the schedule is otherwise rejected.
    func schedule(endsAt: Date, sessionId: UUID) throws {
        DebugBreadcrumbs.record(.damScheduleAttempted)
        let now = Date()
        let requestedDuration = endsAt.timeIntervalSince(now)

        // Pad the interval end if the requested duration is below the iOS minimum.
        let paddedEnd = now.addingTimeInterval(max(requestedDuration, Self.minimumIntervalSeconds) + 60)

        let schedule = DeviceActivitySchedule(
            intervalStart: Self.components(from: now),
            intervalEnd: Self.components(from: paddedEnd),
            repeats: false
        )

        // Threshold event fires at the ACTUAL requested duration.
        let threshold = DeviceActivityEvent(
            applications: [],
            categories: [],
            webDomains: [],
            threshold: DateComponents(second: max(Int(requestedDuration), 1))
        )

        let name = Self.activityName(for: sessionId)
        do {
            try center.startMonitoring(
                name,
                during: schedule,
                events: [Self.thresholdEventName: threshold]
            )
            DebugBreadcrumbs.record(.damScheduleSucceeded, note: "duration=\(Int(requestedDuration))s padded=\(Int(paddedEnd.timeIntervalSince(now)))s name=\(name.rawValue)")
        } catch {
            DebugBreadcrumbs.record(.damScheduleFailed, note: "\(error.localizedDescription)")
            throw error
        }
    }

    /// Cancel every session-expiry schedule currently registered. Iterates
    /// DeviceActivityCenter.activities because we do not persist the exact
    /// set of active names — anything that looks like one of ours is ours.
    func cancel() {
        let ours = center.activities.filter { Self.isSessionExpiryActivity($0) }
        guard !ours.isEmpty else { return }
        center.stopMonitoring(ours)
    }

    private static func components(from date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }
}
