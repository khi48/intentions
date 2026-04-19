import Foundation
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

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
    /// Every ApplicationToken the user has picked in any session so far.
    /// Used as a belt-and-suspenders against a known iOS 26 Family Controls
    /// gap: `shield.applicationCategories = .all()` does NOT reliably shield
    /// every app — some apps (common: browsers, picks previously unlocked in
    /// a session) slip through. Setting `shield.applications` with an
    /// explicit token set plugs the gap. Old codebase called this
    /// `knownAppTokens`; name kept here for continuity in the plist.
    var knownApplicationTokens: Set<ApplicationToken>
    var knownWebDomainTokens: Set<WebDomainToken>

    init(
        defaultState: DefaultState,
        activeSession: Session?,
        knownApplicationTokens: Set<ApplicationToken> = [],
        knownWebDomainTokens: Set<WebDomainToken> = []
    ) {
        self.defaultState = defaultState
        self.activeSession = activeSession
        self.knownApplicationTokens = knownApplicationTokens
        self.knownWebDomainTokens = knownWebDomainTokens
    }

    static let empty = IntentLog(defaultState: .blocked, activeSession: nil)
}

extension IntentLog {
    private enum CodingKeys: String, CodingKey {
        case defaultState, activeSession, knownApplicationTokens, knownWebDomainTokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultState = try c.decode(DefaultState.self, forKey: .defaultState)
        self.activeSession = try c.decodeIfPresent(Session.self, forKey: .activeSession)
        // Tolerate logs saved before these fields existed.
        self.knownApplicationTokens = try c.decodeIfPresent(Set<ApplicationToken>.self, forKey: .knownApplicationTokens) ?? []
        self.knownWebDomainTokens = try c.decodeIfPresent(Set<WebDomainToken>.self, forKey: .knownWebDomainTokens) ?? []
    }
}

/// What the shield store should be configured to, at a moment in time.
enum ShieldConfig: Equatable, Sendable {
    case none                               // nothing shielded
    case allExcept(FamilyActivitySelection) // everything except these
    case all                                // everything shielded
}
