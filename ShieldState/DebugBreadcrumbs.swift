import Foundation

/// Diagnostic harness for on-device testing. Each touchpoint in the wake
/// chain writes a timestamped breadcrumb to shared UserDefaults so we can
/// reconstruct the sequence after the fact. Not for production — this is
/// scaffolding for Case A diagnosis.
enum DebugBreadcrumbs {
    private static let suiteName = "group.oh.Intent"

    enum Event: String {
        case engineStartSession          = "shieldstate.debug.engine.startSession"
        case engineHandleExpiry          = "shieldstate.debug.engine.handleExpiry"
        case engineCatchUp               = "shieldstate.debug.engine.catchUp"
        case engineReapply               = "shieldstate.debug.engine.reapply"
        case damIntervalDidEnd           = "shieldstate.debug.dam.intervalDidEnd"
        case damEventThreshold           = "shieldstate.debug.dam.eventThreshold"
        case damScheduleAttempted        = "shieldstate.debug.dam.scheduleAttempted"
        case damScheduleSucceeded        = "shieldstate.debug.dam.scheduleSucceeded"
        case damScheduleFailed           = "shieldstate.debug.dam.scheduleFailed"
        case darwinPosted                = "shieldstate.debug.darwin.posted"
        case darwinObserverInstalled     = "shieldstate.debug.darwin.observerInstalled"
        case darwinReceived              = "shieldstate.debug.darwin.received"
        case bgtaskSubmitted             = "shieldstate.debug.bgtask.submitted"
        case bgtaskSubmitFailed          = "shieldstate.debug.bgtask.submitFailed"
        case bgtaskHandlerRan            = "shieldstate.debug.bgtask.handlerRan"
        case scenePhaseActive            = "shieldstate.debug.scenePhase.active"
        case applierApply                = "shieldstate.debug.applier.apply"
    }

    /// Record a breadcrumb with the current timestamp and an optional note.
    static func record(_ event: Event, note: String = "") {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let stamp = DateFormatter.iso.string(from: Date())
        let value = note.isEmpty ? stamp : "\(stamp) | \(note)"
        defaults.set(value, forKey: event.rawValue)
    }

    /// Read all breadcrumbs, sorted by timestamp, as a multi-line string.
    /// Safe to call from anywhere.
    static func dump() -> String {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return "(no app group)" }
        var entries: [(String, String)] = []
        for event in allEvents {
            if let value = defaults.string(forKey: event.rawValue) {
                entries.append((value, event.rawValue.replacingOccurrences(of: "shieldstate.debug.", with: "")))
            }
        }
        entries.sort { $0.0 < $1.0 }
        if entries.isEmpty { return "(no breadcrumbs)" }
        return entries.map { "  \($0.0)  \($0.1)" }.joined(separator: "\n")
    }

    /// Clear every breadcrumb. Call when a new session starts so the log
    /// reflects one test run at a time.
    static func reset() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        for event in allEvents {
            defaults.removeObject(forKey: event.rawValue)
        }
    }

    private static let allEvents: [Event] = [
        .engineStartSession, .engineHandleExpiry, .engineCatchUp, .engineReapply,
        .damIntervalDidEnd, .damEventThreshold,
        .damScheduleAttempted, .damScheduleSucceeded, .damScheduleFailed,
        .darwinPosted, .darwinObserverInstalled, .darwinReceived,
        .bgtaskSubmitted, .bgtaskSubmitFailed, .bgtaskHandlerRan,
        .scenePhaseActive, .applierApply
    ]
}

private extension DateFormatter {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
}
