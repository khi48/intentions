import Foundation
@preconcurrency import FamilyControls

/// Base mode the app returns to when no session is active.
enum DefaultState: String, Codable, Sendable, Equatable {
    case blocked
    case open
}

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

/// Persisted source of truth for shield decisions. Read/written by main app and DAM extension.
struct IntentLog: Codable, Sendable, Equatable {
    var defaultState: DefaultState
    var activeSession: Session?

    static let empty = IntentLog(defaultState: .blocked, activeSession: nil)
}

/// What the shield store should be configured to, at a moment in time.
enum ShieldConfig: Equatable, Sendable {
    case none                               // nothing shielded
    case allExcept(FamilyActivitySelection) // everything except these
    case all                                // everything shielded
}
