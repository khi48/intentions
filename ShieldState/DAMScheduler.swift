import Foundation
@preconcurrency import DeviceActivity

/// Thin wrapper over DeviceActivityCenter that schedules session-expiry callbacks.
///
/// iOS imposes a minimum interval length (intervalTooShort, ~15 min). For
/// shorter sessions we pad the interval so startMonitoring accepts it.
/// `intervalDidEnd` still fires at the padded end, not the actual duration
/// — that's fine because the actual user-facing "session ended" signal is
/// the pre-scheduled local notification that NotificationService registers
/// at session start for the real endsAt; iOS delivers that reliably even
/// for fully-suspended apps. intervalDidEnd is cleanup: when it eventually
/// fires, the extension runs handleExpiry which is idempotent (no-op if the
/// main app already cleared the session on foreground).
///
/// We do NOT use a DeviceActivityEvent threshold. With an empty
/// applications/categories/webDomains set the threshold fires immediately
/// (~700 ms after startMonitoring on iOS 26) — the counter measures
/// something other than "seconds since interval start" and is effectively
/// useless for our purpose.
///
/// Each session gets a UNIQUE DeviceActivityName (`shieldstate.session-expiry.<uuid>`)
/// so replace semantics stop the prior schedule cleanly.
struct DAMScheduler: Sendable {
    static let sessionExpiryPrefix = "shieldstate.session-expiry"

    /// iOS requires monitored intervals to be at least this long. Shorter
    /// schedules throw intervalTooShort from startMonitoring.
    static let minimumIntervalSeconds: TimeInterval = 15 * 60

    private let center = DeviceActivityCenter()

    /// Per-session sub-schedule identifiers. We register multiple overlapping
    /// schedules per session so `intervalDidEnd` has multiple wake opportunities
    /// — iOS 26 DAM callback delivery is intermittent (thread 809410,
    /// 819242, 820956). Opal / Jomo / habitdoom all use this chaining pattern
    /// to raise the hit rate. Each slot has a unique DeviceActivityName so
    /// iOS schedules them independently; all share the same session prefix
    /// for cancel().
    static let chainSlots: [(suffix: String, offsetMinutes: Int)] = [
        (suffix: "primary", offsetMinutes: 0),     // padded session end
        (suffix: "retry1",  offsetMinutes: 15),    // +15 min
        (suffix: "retry2",  offsetMinutes: 30)     // +30 min
    ]

    static func activityName(for sessionId: UUID, slot: String = "primary") -> DeviceActivityName {
        DeviceActivityName("\(sessionExpiryPrefix).\(sessionId.uuidString).\(slot)")
    }

    static func isSessionExpiryActivity(_ activity: DeviceActivityName) -> Bool {
        activity.rawValue.hasPrefix(sessionExpiryPrefix)
    }

    func schedule(endsAt: Date, sessionId: UUID) throws {
        DebugBreadcrumbs.record(.damScheduleAttempted)
        let now = Date()
        let requestedDuration = endsAt.timeIntervalSince(now)
        let basePaddedEnd = now.addingTimeInterval(max(requestedDuration, Self.minimumIntervalSeconds) + 60)

        var succeeded: [String] = []
        var lastError: Error?

        for slot in Self.chainSlots {
            let slotEnd = basePaddedEnd.addingTimeInterval(Double(slot.offsetMinutes) * 60)
            let schedule = DeviceActivitySchedule(
                intervalStart: Self.components(from: now),
                intervalEnd: Self.components(from: slotEnd),
                repeats: false
            )
            let name = Self.activityName(for: sessionId, slot: slot.suffix)
            do {
                try center.startMonitoring(name, during: schedule)
                succeeded.append(slot.suffix)
            } catch {
                lastError = error
                DebugBreadcrumbs.record(.damScheduleFailed, note: "slot=\(slot.suffix) \(error.localizedDescription)")
            }
        }

        if succeeded.isEmpty, let err = lastError {
            throw err
        }
        DebugBreadcrumbs.record(
            .damScheduleSucceeded,
            note: "duration=\(Int(requestedDuration))s slots=\(succeeded.joined(separator: ",")) base-pad=\(Int(basePaddedEnd.timeIntervalSince(now)))s"
        )
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
