import Foundation

/// Returns the ShieldConfig that should be applied, given a log and a moment in time.
/// Pure; deterministic.
///
/// Priority:
///   1. Active session ⇒ `.allExcept(session.apps)`. Session always wins —
///      schedule transitions during a session do not unlock other apps.
///   2. Schedule snapshot present ⇒ schedule is the source of truth.
///      `isFreeTime(at:)` returns `true` when the schedule is disabled (matching
///      the UI model: "Blocking off ⇒ nothing blocked"), so a disabled schedule
///      yields `.none`. Enabled + free interval ⇒ `.none`. Enabled + outside
///      free ⇒ `.all`.
///   3. No snapshot (legacy pre-snapshot logs that haven't yet run a save) ⇒
///      fall back to `.all`. The app's intent is "all apps blocked by default",
///      so blocking when state is unknown is the safer fallback. The
///      schedule-aware path above takes over as soon as the user's schedule
///      snapshot is persisted into IntentLog.
func compute(_ log: IntentLog, at now: Date) -> ShieldConfig {
    if let session = log.activeSession, now < session.endsAt {
        return .allExcept(session.apps)
    }
    if let schedule = log.weeklySchedule {
        return schedule.isFreeTime(at: now) ? .none : .all
    }
    return .all
}
