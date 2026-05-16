import Foundation

/// Returns the ShieldConfig that should be applied, given a log and a moment in time.
/// Pure; deterministic.
///
/// Priority (R3, #27 — free-time and session are mutually exclusive):
///   1. Free-time wins. If a schedule snapshot is present and `isFreeTime(at:)`
///      returns true, the result is `.none` — even when an active session is
///      in the log. Free-time means *all apps free*. An in-log session inside
///      a free-time window is a transient state that ShieldEngine clears on
///      the actual transition (`handleScheduleTransition` /
///      `refreshScheduleMonitoring`); compute() reflects the rule purely.
///      `isFreeTime(at:)` returns `true` when the schedule is disabled
///      (matching the UI model: "Blocking off ⇒ nothing blocked"), so a
///      disabled schedule yields `.none` regardless of session state.
///   2. Active session inside a blocking window ⇒ `.allExcept(session.apps)`.
///   3. Schedule snapshot present, no session, outside free ⇒ `.all`.
///   4. No snapshot (legacy pre-snapshot logs that haven't yet run a save) ⇒
///      fall back to `.all`. The app's intent is "all apps blocked by default",
///      so blocking when state is unknown is the safer fallback. The
///      schedule-aware path above takes over as soon as the user's schedule
///      snapshot is persisted into IntentLog.
func compute(_ log: IntentLog, at now: Date) -> ShieldConfig {
    if let schedule = log.weeklySchedule, schedule.isFreeTime(at: now) {
        return .none
    }
    if let session = log.activeSession, now < session.endsAt {
        return .allExcept(session.apps)
    }
    if log.weeklySchedule != nil {
        // Schedule present, not free-time (free-time branch above already
        // returned) ⇒ blocking window.
        return .all
    }
    return .all
}
