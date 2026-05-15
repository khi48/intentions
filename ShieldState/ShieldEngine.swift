import Foundation
import OSLog
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Orchestrator that owns all transitions in the shield state machine.
/// Reads/writes the intent log, calls the applier, optionally schedules DAM.
///
/// The scheduler parameter is optional: the DAM extension doesn't need to
/// schedule anything — only the main app schedules, and both sides handle expiry.
struct ShieldEngine: Sendable {
    private let store: IntentLogStoring
    private let applier: ShieldApplying
    private let scheduler: DAMScheduler?
    private let logger = Logger(subsystem: "oh.Intent", category: "ShieldEngine")

    init(store: IntentLogStoring, applier: ShieldApplying, scheduler: DAMScheduler?) {
        self.store = store
        self.applier = applier
        self.scheduler = scheduler
    }

    // MARK: - User-driven transitions

    func startSession(apps: FamilyActivitySelection, endsAt: Date, now: Date = Date()) {
        DebugBreadcrumbs.reset()
        DebugBreadcrumbs.record(.engineStartSession, note: "endsAt=\(endsAt.timeIntervalSince(now))s")
        logger.notice("startSession: endsAt=\(endsAt, privacy: .public), apps.count=\(apps.applicationTokens.count, privacy: .public)")

        scheduler?.cancel()

        let session = Session(apps: apps, startedAt: now, endsAt: endsAt)
        var log = store.load()
        log.activeSession = session
        log.knownApplicationTokens.formUnion(apps.applicationTokens)
        log.knownWebDomainTokens.formUnion(apps.webDomainTokens)
        store.save(log)

        do {
            try scheduler?.schedule(endsAt: endsAt, sessionId: session.id, apps: apps)
            logger.notice("startSession: DAM scheduled successfully")
        } catch {
            logger.error("startSession: DAM schedule FAILED — \(error.localizedDescription, privacy: .public)")
        }

        // Schedule-boundary monitor stays active during a session — session
        // takes precedence in compute() but we want the boundary chain ready
        // to fire post-session if the session ends mid-window.
        rescheduleBoundary(log: log, from: now)

        let config = compute(log, at: now)
        logger.notice("startSession: applying \(String(describing: config), privacy: .public)")
        applier.apply(config, knownApps: log.knownApplicationTokens, knownDomains: log.knownWebDomainTokens)
    }

    func endSession(now: Date = Date()) {
        logger.notice("endSession called")
        scheduler?.cancel()

        var log = store.load()
        guard log.activeSession != nil else {
            logger.notice("endSession: no active session, no-op")
            return
        }
        log.activeSession = nil
        store.save(log)

        rescheduleBoundary(log: log, from: now)

        let config = compute(log, at: now)
        logger.notice("endSession: applying \(String(describing: config), privacy: .public)")
        applier.apply(config, knownApps: log.knownApplicationTokens, knownDomains: log.knownWebDomainTokens)
    }

    /// Persist the latest schedule snapshot and (re-)register the next-boundary
    /// DAM monitor. Called by the main app on schedule edits and on
    /// scenePhase → .active to recover from missed boundaries / OS resets.
    /// Idempotent.
    func refreshScheduleMonitoring(_ snapshot: ScheduleSnapshot, now: Date = Date()) {
        DebugBreadcrumbs.record(.engineRefreshSchedule, note: "isEnabled=\(snapshot.isEnabled) intervals=\(snapshot.intervals.count)")
        logger.notice("refreshScheduleMonitoring: isEnabled=\(snapshot.isEnabled, privacy: .public) intervals=\(snapshot.intervals.count, privacy: .public)")

        var log = store.load()
        log.weeklySchedule = snapshot
        store.save(log)

        rescheduleBoundary(log: log, from: now)

        let config = compute(log, at: now)
        logger.notice("refreshScheduleMonitoring: applying \(String(describing: config), privacy: .public)")
        applier.apply(config, knownApps: log.knownApplicationTokens, knownDomains: log.knownWebDomainTokens)
    }

    // MARK: - System-driven transitions

    /// Called by the DAM extension at interval end.
    func handleExpiry(now: Date = Date()) {
        DebugBreadcrumbs.record(.engineHandleExpiry)
        logger.notice("handleExpiry called at \(now, privacy: .public)")
        var log = store.load()
        guard let session = log.activeSession else {
            logger.notice("handleExpiry: no active session in log, no-op")
            return
        }
        guard session.endsAt <= now else {
            logger.notice("handleExpiry: session not yet expired (endsAt=\(session.endsAt, privacy: .public)), no-op")
            return
        }
        logger.notice("handleExpiry: clearing expired session")
        log.activeSession = nil
        store.save(log)

        // Post-session, the schedule may put us into either free time or blocking.
        // Either way, register the next schedule boundary so we wake on its flip.
        rescheduleBoundary(log: log, from: now)

        let config = compute(log, at: now)
        logger.notice("handleExpiry: applying \(String(describing: config), privacy: .public)")
        applier.apply(config, knownApps: log.knownApplicationTokens, knownDomains: log.knownWebDomainTokens)
    }

    /// Called by the DAM extension when a schedule-boundary `intervalDidStart`
    /// fires. Idempotent reapply + chain to the next boundary.
    func handleScheduleTransition(now: Date = Date()) {
        DebugBreadcrumbs.record(.engineScheduleTransition)
        logger.notice("handleScheduleTransition called at \(now, privacy: .public)")
        let log = store.load()

        rescheduleBoundary(log: log, from: now)

        let config = compute(log, at: now)
        logger.notice("handleScheduleTransition: applying \(String(describing: config), privacy: .public)")
        applier.apply(config, knownApps: log.knownApplicationTokens, knownDomains: log.knownWebDomainTokens)
    }

    /// Called by the main app on scenePhase → .active.
    /// Repairs state if DAM silently failed to fire (session expiry OR schedule
    /// boundary). Compute is schedule-aware so a single reapply covers both.
    func catchUpOnForeground(now: Date = Date()) {
        DebugBreadcrumbs.record(.engineCatchUp)
        logger.notice("catchUpOnForeground called at \(now, privacy: .public)")
        var log = store.load()
        if let session = log.activeSession, session.endsAt <= now {
            logger.notice("catchUpOnForeground: clearing stale session")
            log.activeSession = nil
            store.save(log)
        }
        rescheduleBoundary(log: log, from: now)
        let config = compute(log, at: now)
        logger.notice("catchUpOnForeground: applying \(String(describing: config), privacy: .public)")
        applier.apply(config, knownApps: log.knownApplicationTokens, knownDomains: log.knownWebDomainTokens)
    }

    /// Union additional tokens into the IntentLog's `knownApplicationTokens` /
    /// `knownWebDomainTokens` and re-apply the current config so the gap-plug
    /// (`shield.applications = knownApps`) covers them on the next write.
    /// Called by the main app on launch with QuickActions tokens, so users who
    /// haven't started a session yet still get every app they've selected
    /// shielded by token, not just by category.
    func registerKnownTokens(apps: Set<ApplicationToken>, domains: Set<WebDomainToken> = [], now: Date = Date()) {
        var log = store.load()
        let appsBefore = log.knownApplicationTokens
        let domainsBefore = log.knownWebDomainTokens
        log.knownApplicationTokens.formUnion(apps)
        log.knownWebDomainTokens.formUnion(domains)
        guard log.knownApplicationTokens != appsBefore || log.knownWebDomainTokens != domainsBefore else { return }
        store.save(log)
        let config = compute(log, at: now)
        logger.notice("registerKnownTokens: +\(apps.count, privacy: .public)a/\(domains.count, privacy: .public)d → applying \(String(describing: config), privacy: .public)")
        applier.apply(config, knownApps: log.knownApplicationTokens, knownDomains: log.knownWebDomainTokens)
    }

    /// Re-apply the currently-computed shield config without mutating the log.
    /// Intended for the main app's BGAppRefreshTask handler: in this
    /// codebase's iOS 26 testing, the extension-process flush (`.none`) has
    /// not been observed re-rendering the springboard shield layer, so the
    /// extension submits a BGTask and this method runs inside the main-app
    /// process to do the flush there. Additive shield-on writes from the
    /// extension are unaffected.
    func reapplyCurrentState(now: Date = Date()) {
        DebugBreadcrumbs.record(.engineReapply)
        logger.notice("reapplyCurrentState called at \(now, privacy: .public)")
        let log = store.load()
        let config = compute(log, at: now)
        logger.notice("reapplyCurrentState: applying \(String(describing: config), privacy: .public)")
        applier.apply(config, knownApps: log.knownApplicationTokens, knownDomains: log.knownWebDomainTokens)
    }

    // MARK: - Helpers

    /// (Re-)register the next schedule-boundary DAM monitor based on the snapshot
    /// in `log`. No-op if no scheduler is wired (DAM extension) or no schedule
    /// snapshot is present. Errors are logged and swallowed: schedule boundaries
    /// are belt-and-braces over the foreground catch-up, so a failure here does
    /// not warrant a hard error.
    private func rescheduleBoundary(log: IntentLog, from now: Date) {
        guard let scheduler else { return }
        guard let snapshot = log.weeklySchedule else {
            scheduler.cancelScheduleBoundary()
            return
        }
        do {
            try scheduler.scheduleNextBoundary(schedule: snapshot, from: now)
        } catch {
            logger.error("rescheduleBoundary: failed — \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Production factories

extension ShieldEngine {
    /// Production engine used by the main app (schedules DAM).
    static func mainApp() -> ShieldEngine {
        ShieldEngine(
            store: IntentLogStore(),
            applier: ManagedSettingsShieldApplier(),
            scheduler: DAMScheduler()
        )
    }

    /// Production engine used by the DAM extension. Self-perpetuates the
    /// schedule-boundary chain: each `intervalDidStart` registers the NEXT
    /// boundary monitor via `DAMScheduler` from within the extension process.
    /// Uses `AdditiveShieldApplier` (no clearAllSettings). In our iOS 26
    /// testing, additive `.all()` writes from the extension render reliably
    /// but the obvious extension-process flush has not been observed
    /// re-rendering the springboard cache — so today the main app does the
    /// flush via `ManagedSettingsShieldApplier`. See `AdditiveShieldApplier`
    /// for the longer note (and an open question about the pattern other
    /// Family Controls apps use to unshield from the extension).
    static func damExtension() -> ShieldEngine {
        ShieldEngine(
            store: IntentLogStore(),
            applier: AdditiveShieldApplier(),
            scheduler: DAMScheduler()
        )
    }
}
