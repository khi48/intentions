import Foundation

/// Returns the ShieldConfig that should be applied, given a log and a moment in time.
/// Pure; deterministic.
///
/// Priority (#59 — session is a deliberate user commitment that overrides the
/// schedule-default state for its duration):
///   1. Active session inside its window ⇒ `.allExcept(session.apps)`. Beats
///      both free-time and disabled-schedule. A user who started a session
///      while blocking was off has explicitly opted into a temporary shield;
///      the session establishes its own blocking floor until `endsAt`.
///   2. Free-time wins over default blocking. If a schedule snapshot is present
///      and `isFreeTime(at:)` returns true, the result is `.none`.
///      `isFreeTime(at:)` returns `true` when the schedule is disabled
///      (matching the UI model: "Blocking off ⇒ nothing blocked"), so a
///      disabled schedule yields `.none` once the session check above falls
///      through.
///   3. Schedule snapshot present, no session, outside free ⇒ `.all`.
///   4. No snapshot (legacy pre-snapshot logs that haven't yet run a save) ⇒
///      fall back to `.all`. The app's intent is "all apps blocked by default",
///      so blocking when state is unknown is the safer fallback. The
///      schedule-aware path above takes over as soon as the user's schedule
///      snapshot is persisted into IntentLog.
func compute(_ log: IntentLog, at now: Date) -> ShieldConfig {
    if let session = log.activeSession, now < session.endsAt {
        return .allExcept(session.apps)
    }
    if let schedule = log.weeklySchedule, schedule.isFreeTime(at: now) {
        return .none
    }
    if log.weeklySchedule != nil {
        // Schedule present, not free-time (free-time branch above already
        // returned) ⇒ blocking window.
        return .all
    }
    return .all
}
