import Foundation
@preconcurrency import DeviceActivity

/// Thin wrapper over DeviceActivityCenter that schedules session-expiry callbacks.
///
/// iOS imposes a minimum interval length (intervalTooShort) on
/// DeviceActivitySchedule. Exact minimum is ~15 min in practice. For short
/// sessions we still need exact-time firing, so we schedule **both**:
///  - a padded interval so startMonitoring accepts it (intervalDidEnd fires at pad end)
///  - a threshold event at the actual duration (eventDidReachThreshold fires at real expiry)
///
/// The DAM extension handles both callbacks and routes them to handleExpiry().
/// handleExpiry is idempotent — if both fire, the second is a no-op because
/// the session has already been cleared from the log.
struct DAMScheduler: Sendable {
    static let sessionExpiryName = DeviceActivityName("shieldstate.session-expiry")
    static let thresholdEventName = DeviceActivityEvent.Name("shieldstate.session-expiry.threshold")

    /// iOS requires monitored intervals to be at least this long. Shorter
    /// schedules throw intervalTooShort from startMonitoring.
    static let minimumIntervalSeconds: TimeInterval = 15 * 60

    private let center = DeviceActivityCenter()

    /// Schedule a single-fire session-expiry callback for `endsAt`.
    /// Throws if authorization is missing or the schedule is otherwise rejected.
    func schedule(endsAt: Date) throws {
        let now = Date()
        let requestedDuration = endsAt.timeIntervalSince(now)

        // Pad the interval end if the requested duration is below the iOS minimum.
        let paddedEnd = now.addingTimeInterval(max(requestedDuration, Self.minimumIntervalSeconds) + 60)

        let schedule = DeviceActivitySchedule(
            intervalStart: Self.components(from: now),
            intervalEnd: Self.components(from: paddedEnd),
            repeats: false
        )

        // Threshold event fires at the ACTUAL requested duration — this is
        // what gives short sessions their correct expiry time.
        let threshold = DeviceActivityEvent(
            applications: [],
            categories: [],
            webDomains: [],
            threshold: DateComponents(second: max(Int(requestedDuration), 1))
        )

        try center.startMonitoring(
            Self.sessionExpiryName,
            during: schedule,
            events: [Self.thresholdEventName: threshold]
        )
    }

    /// Cancel any in-flight schedule under our name. Safe to call when nothing is scheduled.
    func cancel() {
        center.stopMonitoring([Self.sessionExpiryName])
    }

    private static func components(from date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }
}
