import Foundation
import OSLog
@preconcurrency import FamilyControls

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

        var log = store.load()
        log.activeSession = Session(apps: apps, startedAt: now, endsAt: endsAt)
        store.save(log)

        do {
            try scheduler?.schedule(endsAt: endsAt)
            logger.notice("startSession: DAM scheduled successfully")
        } catch {
            logger.error("startSession: DAM schedule FAILED — \(error.localizedDescription, privacy: .public)")
        }

        let config = compute(log, at: now)
        logger.notice("startSession: applying \(String(describing: config), privacy: .public)")
        applier.apply(config)
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

        let config = compute(log, at: now)
        logger.notice("endSession: applying \(String(describing: config), privacy: .public)")
        applier.apply(config)
    }

    func flipDefault(to newDefault: DefaultState, now: Date = Date()) {
        logger.notice("flipDefault to \(newDefault.rawValue, privacy: .public)")
        scheduler?.cancel()

        var log = store.load()
        log.defaultState = newDefault
        log.activeSession = nil
        store.save(log)

        let config = compute(log, at: now)
        logger.notice("flipDefault: applying \(String(describing: config), privacy: .public)")
        applier.apply(config)
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
        let config = compute(log, at: now)
        logger.notice("handleExpiry: applying \(String(describing: config), privacy: .public)")
        applier.apply(config)
    }

    /// Called by the main app on scenePhase → .active.
    /// Repairs state if DAM silently failed to fire.
    func catchUpOnForeground(now: Date = Date()) {
        DebugBreadcrumbs.record(.engineCatchUp)
        logger.notice("catchUpOnForeground called at \(now, privacy: .public)")
        var log = store.load()
        guard let session = log.activeSession else {
            logger.notice("catchUpOnForeground: no active session in log, no-op")
            return
        }
        guard session.endsAt <= now else {
            logger.notice("catchUpOnForeground: session not yet expired (endsAt=\(session.endsAt, privacy: .public)), no-op")
            return
        }
        logger.notice("catchUpOnForeground: clearing stale session")
        log.activeSession = nil
        store.save(log)
        let config = compute(log, at: now)
        logger.notice("catchUpOnForeground: applying \(String(describing: config), privacy: .public)")
        applier.apply(config)
    }

    /// Re-apply the currently-computed shield config without mutating the log.
    /// Intended for the main app's BGAppRefreshTask handler: DAM extension
    /// writes from its own process don't re-render the springboard shield
    /// layer on iOS 26 (Apple DTS 807934). The extension submits a BGTask;
    /// this method runs inside the main-app process so the store write
    /// propagates correctly.
    func reapplyCurrentState(now: Date = Date()) {
        DebugBreadcrumbs.record(.engineReapply)
        logger.notice("reapplyCurrentState called at \(now, privacy: .public)")
        let log = store.load()
        let config = compute(log, at: now)
        logger.notice("reapplyCurrentState: applying \(String(describing: config), privacy: .public)")
        applier.apply(config)
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

    /// Production engine used by the DAM extension (no scheduling — only handles expiry).
    static func damExtension() -> ShieldEngine {
        ShieldEngine(
            store: IntentLogStore(),
            applier: ManagedSettingsShieldApplier(),
            scheduler: nil
        )
    }
}
