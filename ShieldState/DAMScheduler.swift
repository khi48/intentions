import Foundation
@preconcurrency import FamilyControls
@preconcurrency import DeviceActivity

/// Wall-clock-future-start scheduler for session expiry. Validated in
/// block-mvp on iOS 26.5 beta 3 across 5 scenarios (force-killed app
/// included). The breakthrough: `DeviceActivitySchedule`'s 15-min minimum
/// applies to `intervalEnd - intervalStart` (duration), NOT to
/// `intervalStart - now` (offset). So we set `intervalStart` at the
/// session's wall-clock end time and `intervalEnd` 15min30s later. iOS
/// fires `intervalDidStart` in the extension at the session-end moment
/// (within +2s to +9s slop), regardless of main-app state.
///
/// Secondary: a `DeviceActivityEvent` with the session's REAL tokens and
/// a 1-second threshold catches the case where the user opens the picked
/// app post-expiry before iOS gets around to firing `intervalDidStart`.
/// Empty-token thresholds fire at ~700ms on iOS 26 — populating tokens
/// fixes that.
///
/// `intervalDidEnd` remains as a third belt-and-braces; the extension's
/// `handleExpiry` is idempotent so late fires are no-ops.
struct DAMScheduler: Sendable {
    static let sessionExpiryPrefix = "shieldstate.session-expiry"
    static let firstTouchEventName = DeviceActivityEvent.Name("shieldstate.first-touch")

    private let center = DeviceActivityCenter()

    static func activityName(for sessionId: UUID) -> DeviceActivityName {
        DeviceActivityName("\(sessionExpiryPrefix).\(sessionId.uuidString)")
    }

    static func isSessionExpiryActivity(_ activity: DeviceActivityName) -> Bool {
        activity.rawValue.hasPrefix(sessionExpiryPrefix)
    }

    /// Schedule one DAM monitoring window whose interval BEGINS at the
    /// session end time. iOS fires `intervalDidStart` at that wall-clock
    /// moment in the extension process — that's the canonical reshield
    /// trigger.
    func schedule(endsAt: Date, sessionId: UUID, apps: FamilyActivitySelection) throws {
        DebugBreadcrumbs.record(.damScheduleAttempted)
        let now = Date()
        let requestedDuration = endsAt.timeIntervalSince(now)

        // intervalStart at wall-clock session end → intervalDidStart fires there.
        // intervalEnd 15min30s later → satisfies iOS 15-min duration minimum;
        // intervalDidEnd fires there as a third fallback.
        let start = endsAt
        let end = start.addingTimeInterval(15 * 60 + 30)

        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute, .second], from: start),
            intervalEnd: calendar.dateComponents([.hour, .minute, .second], from: end),
            repeats: false
        )

        // Secondary: usage-counter event with REAL session tokens. Fires ~1s
        // into the user's foreground use of any picked app post-expiry.
        // Catches "user opens picked app before intervalDidStart was honored".
        let firstTouch = DeviceActivityEvent(
            applications: apps.applicationTokens,
            categories: apps.categoryTokens,
            webDomains: apps.webDomainTokens,
            threshold: DateComponents(second: 1)
        )
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [
            Self.firstTouchEventName: firstTouch
        ]

        let name = Self.activityName(for: sessionId)
        do {
            try center.startMonitoring(name, during: schedule, events: events)
            DebugBreadcrumbs.record(
                .damScheduleSucceeded,
                note: "duration=\(Int(requestedDuration))s intervalStart=+\(Int(start.timeIntervalSince(now)))s intervalEnd=+\(Int(end.timeIntervalSince(now)))s name=\(name.rawValue)"
            )
        } catch {
            DebugBreadcrumbs.record(.damScheduleFailed, note: error.localizedDescription)
            throw error
        }
    }

    /// Cancel every session-expiry schedule currently registered. Iterates
    /// `DeviceActivityCenter.activities` because we do not persist the exact
    /// set of active names — anything matching the session-expiry prefix is ours.
    func cancel() {
        let ours = center.activities.filter { Self.isSessionExpiryActivity($0) }
        guard !ours.isEmpty else { return }
        center.stopMonitoring(ours)
    }
}
