import Foundation
import WidgetKit
import OSLog

/// Single source of truth for App Group writes that feed the widget extension.
/// Hardcodes literals so this file compiles cleanly in both the main app and
/// the DAM extension (same reason as IntentLogStore).
///
/// Key strings MUST match `SharedConstants.WidgetKeys.*` (widget reads via that
/// enum; main app + widget targets include SharedConstants, DAM does not).
enum WidgetBridge {
    static let suiteName = "group.oh.Intent"

    enum Keys {
        static let blockingStatus = "intentions.widget.blockingStatus"
        static let lastUpdate     = "intentions.widget.lastUpdate"
        static let sessionTitle   = "intentions.widget.sessionTitle"
        static let sessionEndTime = "intentions.widget.sessionEndTime"
    }

    private static let log = Logger(subsystem: "oh.Intent", category: "WidgetBridge")

    /// Active-session push: sets blocking=false (session means apps unblocked)
    /// and persists session metadata for the timer view.
    static func pushSession(title: String, endsAt: Date) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            log.error("pushSession: UserDefaults(suiteName:) returned nil")
            return
        }
        defaults.set(false, forKey: Keys.blockingStatus)
        defaults.set(title, forKey: Keys.sessionTitle)
        defaults.set(endsAt, forKey: Keys.sessionEndTime)
        defaults.set(Date(), forKey: Keys.lastUpdate)
        log.notice("pushSession: title=\(title, privacy: .public) endsAt=\(endsAt, privacy: .public)")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// No-session push: clears session metadata and writes the given blocking
    /// state. Use after session end, on schedule transitions, on app foreground.
    static func pushNoSession(isBlocking: Bool) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            log.error("pushNoSession: UserDefaults(suiteName:) returned nil")
            return
        }
        defaults.removeObject(forKey: Keys.sessionTitle)
        defaults.removeObject(forKey: Keys.sessionEndTime)
        defaults.set(isBlocking, forKey: Keys.blockingStatus)
        defaults.set(Date(), forKey: Keys.lastUpdate)
        log.notice("pushNoSession: isBlocking=\(isBlocking, privacy: .public)")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
