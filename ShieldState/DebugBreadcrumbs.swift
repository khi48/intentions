import Foundation

/// Diagnostic harness for on-device testing. Each touchpoint in the wake
/// chain appends a timestamped entry to a ring-buffer (cap 100) stored in
/// the App-Group `UserDefaults`. Not for production — this is scaffolding
/// for Case A diagnosis.
///
/// History semantics:
/// - **Live ring** (`shieldstate.debug.history`) — appended on every
///   `record()`; trimmed to `historyCap` lines.
/// - **Frozen ring** (`shieldstate.frozen.history`) — snapshot of the live
///   ring taken once per process at `IntentApp.init()` (via `freeze()`),
///   so the pre-foreground state can be inspected after the foreground
///   reapply has begun overwriting the live ring.
enum DebugBreadcrumbs {
    private static let suiteName = "group.oh.Intent"

    enum Event: String {
        case engineStartSession          = "shieldstate.debug.engine.startSession"
        case engineHandleExpiry          = "shieldstate.debug.engine.handleExpiry"
        case engineCatchUp               = "shieldstate.debug.engine.catchUp"
        case engineReapply               = "shieldstate.debug.engine.reapply"
        case engineScheduleTransition    = "shieldstate.debug.engine.scheduleTransition"
        case engineRefreshSchedule       = "shieldstate.debug.engine.refreshSchedule"
        case damIntervalDidStart         = "shieldstate.debug.dam.intervalDidStart"
        case damIntervalDidEnd           = "shieldstate.debug.dam.intervalDidEnd"
        case damEventThreshold           = "shieldstate.debug.dam.eventThreshold"
        case damScheduleAttempted        = "shieldstate.debug.dam.scheduleAttempted"
        case damScheduleSucceeded        = "shieldstate.debug.dam.scheduleSucceeded"
        case damScheduleFailed           = "shieldstate.debug.dam.scheduleFailed"
        case scheduleBoundaryScheduled   = "shieldstate.debug.scheduleBoundary.scheduled"
        case scheduleBoundarySkipped     = "shieldstate.debug.scheduleBoundary.skipped"
        case scheduleBoundaryFailed      = "shieldstate.debug.scheduleBoundary.failed"
        case scenePhaseActive            = "shieldstate.debug.scenePhase.active"
        // Split per-writer so the main-app applier doesn't clobber the
        // extension's last write under the single `applier.apply` key.
        case extensionApplied            = "shieldstate.debug.applier.extensionApplied"
        case mainAppApplied              = "shieldstate.debug.applier.mainAppApplied"
        case weeklyScheduleLoaded        = "shieldstate.debug.dataPersistence.weeklyScheduleLoaded"
        case weeklyScheduleVerified      = "shieldstate.debug.cvm.weeklyScheduleVerified"
    }

    /// Append a breadcrumb to the live ring-buffer history with the current
    /// timestamp and an optional note.
    static func record(_ event: Event, note: String = "") {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let stamp = DateFormatter.iso.string(from: Date())
        appendToHistory(stamp: stamp, event: event, note: note, defaults: defaults)
    }

    // MARK: - Ring-buffer history

    private static let historyKey = "shieldstate.debug.history"
    private static let frozenHistoryKey = "shieldstate.frozen.history"
    private static let frozenAtKey = "shieldstate.frozen.capturedAt"
    private static let historyCap = 100

    /// Append one entry to the live history and trim to `historyCap` lines.
    /// Read-modify-write — racy across processes (main app + DAM extension)
    /// but tolerable for diagnostics; occasional lost appends are fine.
    private static func appendToHistory(stamp: String, event: Event, note: String, defaults: UserDefaults) {
        let shortName = event.rawValue.replacingOccurrences(of: "shieldstate.debug.", with: "")
        let line = "\(stamp)  \(shortName)  \(note)"
        let existing = defaults.string(forKey: historyKey) ?? ""
        var lines = existing.isEmpty
            ? []
            : existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.append(line)
        if lines.count > historyCap {
            lines = Array(lines.suffix(historyCap))
        }
        defaults.set(lines.joined(separator: "\n"), forKey: historyKey)
    }

    /// Chronological dump of the live ring-buffer history (oldest first).
    static func dumpHistory() -> String {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return "(no app group)" }
        let raw = defaults.string(forKey: historyKey) ?? ""
        if raw.isEmpty { return "(no history)" }
        return raw
    }

    /// Chronological dump of the frozen ring-buffer history (oldest first).
    /// Includes the `frozen at:` header timestamp if `freeze()` has ever run.
    static func dumpFrozenHistory() -> String {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return "(no app group)" }
        let raw = defaults.string(forKey: frozenHistoryKey) ?? ""
        if raw.isEmpty {
            return "(no frozen history — freeze() not run or live ring was empty)"
        }
        let frozenAt = defaults.string(forKey: frozenAtKey)
        let header = frozenAt.map { "  (frozen at: \($0))" } ?? "  (frozen at: ?)"
        return ([header, raw]).joined(separator: "\n")
    }

    /// Snapshot the live ring-buffer history into the frozen-history key.
    /// **One-shot per process**: invoked exactly once at the end of
    /// `IntentApp.init()`, after the Darwin observer install and before any
    /// main-app reconcile or scenePhase work. The frozen snapshot therefore
    /// preserves whatever the extension wrote between the previous app exit
    /// and this process spawn. Do NOT call this anywhere else — a second
    /// freeze (e.g. on scenePhase.active) would clobber that pre-launch
    /// snapshot with foreground-reapply data and we'd lose the diagnostic.
    static func freeze() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let history = defaults.string(forKey: historyKey) {
            defaults.set(history, forKey: frozenHistoryKey)
        } else {
            defaults.removeObject(forKey: frozenHistoryKey)
        }
        defaults.set(DateFormatter.iso.string(from: Date()), forKey: frozenAtKey)
    }

    /// Clear the ring-buffer history. Call when a new session starts so the
    /// log reflects one test run at a time. Frozen ring is preserved so the
    /// pre-foreground snapshot from this process spawn stays available.
    static func reset() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removeObject(forKey: historyKey)
    }
}

private extension DateFormatter {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
}
