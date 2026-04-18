import Foundation

/// Returns the ShieldConfig that should be applied, given a log and a moment in time.
/// Pure; deterministic.
func compute(_ log: IntentLog, at now: Date) -> ShieldConfig {
    if let session = log.activeSession, now < session.endsAt {
        return .allExcept(session.apps)
    }
    switch log.defaultState {
    case .blocked: return .all
    case .open:    return .none
    }
}
