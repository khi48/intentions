import Foundation
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

    init(store: IntentLogStoring, applier: ShieldApplying, scheduler: DAMScheduler?) {
        self.store = store
        self.applier = applier
        self.scheduler = scheduler
    }

    // MARK: - User-driven transitions

    func startSession(apps: FamilyActivitySelection, endsAt: Date, now: Date = Date()) {
        scheduler?.cancel()

        var log = store.load()
        log.activeSession = Session(apps: apps, startedAt: now, endsAt: endsAt)
        store.save(log)

        do {
            try scheduler?.schedule(endsAt: endsAt)
        } catch {
            // Scheduling failed — still apply the shield. Foreground catch-up
            // will repair if the DAM never fires.
        }

        applier.apply(compute(log, at: now))
    }

    func endSession(now: Date = Date()) {
        scheduler?.cancel()

        var log = store.load()
        guard log.activeSession != nil else { return }
        log.activeSession = nil
        store.save(log)

        applier.apply(compute(log, at: now))
    }

    func flipDefault(to newDefault: DefaultState, now: Date = Date()) {
        scheduler?.cancel()

        var log = store.load()
        log.defaultState = newDefault
        log.activeSession = nil
        store.save(log)

        applier.apply(compute(log, at: now))
    }

    // MARK: - System-driven transitions

    /// Called by the DAM extension at interval end.
    func handleExpiry(now: Date = Date()) {
        var log = store.load()
        guard let session = log.activeSession, session.endsAt <= now else { return }
        log.activeSession = nil
        store.save(log)
        applier.apply(compute(log, at: now))
    }

    /// Called by the main app on scenePhase → .active.
    /// Repairs state if DAM silently failed to fire.
    func catchUpOnForeground(now: Date = Date()) {
        var log = store.load()
        guard let session = log.activeSession, session.endsAt <= now else { return }
        log.activeSession = nil
        store.save(log)
        applier.apply(compute(log, at: now))
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
