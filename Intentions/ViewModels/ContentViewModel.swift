//
//  ContentViewModel.swift
//  Intentions
//
//  Created by Claude on 12/07/2025.
//

import Foundation
import SwiftUI
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
import UserNotifications
import WidgetKit
import OSLog

/// Tracks the lifecycle state of the ScreenTimeService within ContentViewModel
enum ScreenTimeServiceState: Sendable {
    case uninitialized
    case initializing
    case ready
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Main app state coordinator and navigation controller
/// Manages global app state, authorization status, and navigation flow
@MainActor
@Observable
final class ContentViewModel: Sendable {

    // Logger for persistent diagnostics
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Intentions", category: "ContentViewModel")
    private let logger = ContentViewModel.logger
    
    // MARK: - Published Properties
    
    /// Current authorization status for Screen Time
    private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    
    /// Whether the app is currently loading or performing operations
    var isLoading: Bool = false
    
    /// Current error message to display to user
    var errorMessage: String? = nil
    
    /// Current active session if any
    private(set) var activeSession: IntentionSession? = nil
    
    /// Current weekly schedule
    private var weeklySchedule: WeeklySchedule = WeeklySchedule()
    
    /// Whether initial app loading has completed
    var hasInitialized: Bool = false

    /// Whether we're showing the unified setup flow
    var showingSetupFlow: Bool = false

    /// Setup coordinator for managing app configuration
    let setupCoordinator: SetupCoordinator

    /// Shared quick actions view model for consistency across Home and QuickActions tabs
    let sharedQuickActionsViewModel: QuickActionsViewModel

    /// Current selected tab for navigation
    var selectedTab: AppTab = .home
    
    /// Trigger to notify when app groups have changed
    var appGroupsDidChange: UUID = UUID()

    /// Flag to prevent infinite loops in applyDefaultBlocking
    private var isApplyingDefaultBlocking: Bool = false

    /// Track the currently applied session to prevent duplicate session blocking
    private var currentlyAppliedSessionId: UUID? = nil

    /// Lifecycle state of the ScreenTimeService
    private(set) var screenTimeState: ScreenTimeServiceState = .uninitialized

    /// Observable flag for UI to track when ScreenTimeService is ready
    var isScreenTimeServiceReady: Bool {
        screenTimeState.isReady
    }

    // MARK: - Dependencies
    
    let screenTimeService: ScreenTimeManaging
    private let dataService: DataPersisting
    
    /// Public access to data service for child views
    var dataServiceProvider: DataPersisting {
        dataService
    }
    
    // MARK: - Initialization
    
    init(
        screenTimeService: ScreenTimeManaging? = nil,
        dataService: DataPersisting? = nil
    ) throws {
        self.screenTimeService = screenTimeService ?? ScreenTimeService()
        
        if let providedService = dataService {
            self.dataService = providedService
        } else {
            self.dataService = try DataPersistenceService()
        }
        
        // Initialize shared view models
        self.sharedQuickActionsViewModel = QuickActionsViewModel(dataService: self.dataService)

        // Initialize setup coordinator
        self.setupCoordinator = SetupCoordinator(
            screenTimeService: self.screenTimeService
        )
    }
    
    // MARK: - App Lifecycle

    /// Set up observers for notification tap actions
    func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .showSessionStatus,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.selectedTab = .home
            }
        }

        NotificationCenter.default.addObserver(
            forName: .sessionCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.selectedTab = .home
            }
        }
    }

    /// Initialize the app when it launches
    func initializeApp() async {
        setupNotificationObservers()

        await withLoading {
            // On cold launch the system may transiently report .notDetermined before
            // settling to the real status. Retry once so we don't mis-classify a
            // revoked-auth launch as "transient".
            var status = await screenTimeService.authorizationStatus()
            if status == .notDetermined {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let retried = await screenTimeService.authorizationStatus()
                if retried != .notDetermined { status = retried }
            }
            authorizationStatus = status

            // Request notification permissions in background
            Task {
                await NotificationService.shared.checkAuthorizationStatus()
                let notificationStatus = NotificationService.shared.authorizationStatus
                if notificationStatus == .notDetermined {
                    let granted = await NotificationService.shared.requestPermissions()
                    if !granted {
                        self.logger.info("User declined notification permissions")
                    }
                }
            }

            // Pre-load quick actions so the home view doesn't flash the empty state
            await sharedQuickActionsViewModel.loadData()
            await feedKnownAppTokens()

            await loadScheduleSettings()
            await loadActiveSession()
            await checkSetupRequired()
        }
        hasInitialized = true
    }
    
    /// Load weekly schedule from persistence
    private func loadScheduleSettings() async {
        do {
            weeklySchedule = try await dataService.loadWeeklySchedule() ?? WeeklySchedule()
        } catch {
            logger.warning("Failed to load weekly schedule, using defaults: \(error.localizedDescription)")
            weeklySchedule = WeeklySchedule()
        }
        // Push fresh snapshot to ShieldEngine so DAM extension reads it from
        // the IntentLog plist and the next schedule boundary is registered.
        await screenTimeService.refreshSchedule(weeklySchedule.snapshot())
    }
    
    /// Load any existing active session from persistence
    /// Blocking is applied later by initializeScreenTimeServiceAfterSetup()
    private func loadActiveSession() async {
        do {
            let sessions = try await dataService.loadIntentionSessions()
            let activeSessions = sessions.filter { $0.isActive }

            // Check if DeviceActivityMonitor extension expired a session while app was closed
            if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId),
               sharedDefaults.bool(forKey: AppConstants.Keys.sessionExpired) {
                let currentSessionId = sharedDefaults.string(forKey: AppConstants.Keys.currentSessionId) ?? ""

                let shouldExpireSessions: Bool
                if let activeSession = activeSessions.first {
                    shouldExpireSessions = activeSession.id.uuidString == currentSessionId || activeSession.isExpired
                } else {
                    shouldExpireSessions = false
                }

                sharedDefaults.set(false, forKey: AppConstants.Keys.sessionExpired)
                sharedDefaults.synchronize()

                if shouldExpireSessions {
                    for session in activeSessions {
                        session.complete()
                        try await dataService.saveIntentionSession(session)
                    }
                    activeSession = nil
                    return
                }
            }

            if let loadedSession = activeSessions.first {
                if loadedSession.isExpired {
                    loadedSession.complete()
                    try await dataService.saveIntentionSession(loadedSession)
                    activeSession = nil
                } else {
                    activeSession = loadedSession
                }
            } else {
                activeSession = nil

                // Clear stale session ID from UserDefaults
                if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
                    sharedDefaults.removeObject(forKey: AppConstants.Keys.currentSessionId)
                }
            }
        } catch {
            logger.error("Failed to load active session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Schedule Management

    /// Update weekly schedule and apply blocking accordingly
    func updateWeeklySchedule(_ schedule: WeeklySchedule) async {
        weeklySchedule = schedule

        // Save to persistence (canonical store: App Group UserDefaults)
        do {
            try await dataService.saveWeeklySchedule(schedule)
        } catch {
            logger.error("Failed to save weekly schedule: \(error.localizedDescription)")
            handleError(error)
        }

        // Gate the IntentLog push on service readiness. If we push to an
        // uninitialised engine the snapshot may not actually persist — the
        // user sees a successful Save but IntentLog retains the previous
        // snapshot, and `compute()` runs against stale state. Surface this
        // loudly instead of silently no-op'ing.
        guard screenTimeService.isReady else {
            handleError(AppError.serviceUnavailable(
                "Screen Time service is not ready. Schedule saved locally but blocking has not been activated — please complete setup."
            ))
            return
        }

        // Push fresh snapshot to ShieldEngine — persists in IntentLog,
        // re-registers next schedule-boundary DAM monitor, re-applies shield.
        let snapshot = schedule.snapshot()
        await screenTimeService.refreshSchedule(snapshot)

        // Verify the engine actually persisted the snapshot. If not, the
        // edit-flow has silently lost the user's change; surface it.
        let persisted = IntentLogStore().load().weeklySchedule
        if persisted != snapshot {
            DebugBreadcrumbs.record(
                .weeklyScheduleVerified,
                note: "MISMATCH saved enabled=\(snapshot.isEnabled)/intervals=\(snapshot.intervals.count) log enabled=\(persisted?.isEnabled.description ?? "nil")/intervals=\(persisted?.intervals.count.description ?? "nil")"
            )
            handleError(AppError.persistenceError(
                "Schedule was saved but the shield engine did not persist it. Please retry."
            ))
            return
        }
        DebugBreadcrumbs.record(
            .weeklyScheduleVerified,
            note: "ok enabled=\(snapshot.isEnabled) intervals=\(snapshot.intervals.count)"
        )

        // If blocking was disabled and there's an active session, cancel it —
        // session exists to manage blocking, so no blocking means no session.
        if !schedule.isEnabled, let session = activeSession, session.isActive {
            await cancelActiveSessionForDisable()
        }

        // Apply blocking based on new schedule
        if authorizationStatus == .approved {
            await applyDefaultBlocking()
        }
    }

    // MARK: - Authorization Management
    
    /// Request Screen Time authorization from user
    func requestAuthorization() async {
        await withLoading {
            let success = await screenTimeService.requestAuthorization()
            if success {
                authorizationStatus = await screenTimeService.authorizationStatus()
            } else {
                handleError(AppError.screenTimeAuthorizationFailed)
            }
        }
    }
    
    /// Check if app is ready to use (authorized and initialized)
    var isAppReady: Bool {
        return authorizationStatus == .approved
    }

    /// Re-request Screen Time authorization (e.g. after revocation) and re-initialise if granted.
    func requestReauthorization() async {
        let success = await screenTimeService.requestAuthorization()
        if success {
            authorizationStatus = .approved
            await setupCoordinator.validateSetupRequirements(
                cachedAuthStatus: .approved,
                forceAuthUpdate: true
            )
            screenTimeState = .uninitialized
            await initializeScreenTimeServiceAfterSetup()
        } else {
            authorizationStatus = await screenTimeService.authorizationStatus()
        }
    }
    
    // MARK: - Navigation Actions
    
    /// Navigate to Settings tab
    func showSettings() {
        // Navigate to Settings tab and reset navigation to home page
        selectedTab = .settings
        // The navigation reset will be handled by the TabView's selection binding
        // which already has logic to reset navigation when navigating TO Settings
    }
    
    /// Navigate to specific tab
    func navigateToTab(_ tab: AppTab) {
        selectedTab = tab
    }
    
    // MARK: - Session Management

    // MARK: Session Start Guard (#28)
    //
    // Preventive guard that blocks session start when blocking is off entirely.
    // The reactive cancel-on-disable path (`cancelActiveSessionForDisable`) is
    // the safety net for "user disables blocking while a session is running" —
    // this guard prevents the inverse "user starts a session while blocking is
    // already disabled," which would create a session that has nothing to
    // manage. #27 will extend this to also refuse during free-time intervals.

    /// Whether the user is currently allowed to start a new intention session.
    /// Returns false when the weekly schedule is disabled (all apps unlocked).
    var canStartSession: Bool {
        // For #28 only the `isEnabled` branch is enforced.
        // After #27 lands, this also checks `!weeklySchedule.isFreeTime(at: Date())`.
        weeklySchedule.isEnabled
    }

    /// Human-readable reason why a session cannot be started, or nil when it can.
    /// Surfaced as a caption on disabled session-start affordances in the UI.
    var cannotStartReason: String? {
        if !weeklySchedule.isEnabled {
            return "All apps are unlocked — turn blocking on to start a session."
        }
        // #27 adds the free-time branch here:
        // if weeklySchedule.isFreeTime(at: Date()) {
        //     return "All apps are unlocked during free time."
        // }
        return nil
    }

    /// Start a new intention session
    func startSession(_ session: IntentionSession) async {
        guard canStartSession else {
            logger.notice("startSession refused: \(self.cannotStartReason ?? "unknown")")
            return
        }
        await withLoading {
            do {
                // If there's an existing active session, this is a replace flow.
                // Cancel all pending notifications for the OLD session BEFORE any
                // state change so the old pre-scheduled completion cannot leak.
                // Don't call blockAllApps() here — allowApps() already clears all
                // shields before applying. Extra mutations can leave stale exceptions.
                if let existingSession = activeSession, existingSession.isActive {
                    let oldSessionId = existingSession.id
                    await NotificationService.shared.cancelAllSessionNotifications(sessionId: oldSessionId)
                    await screenTimeService.cancelSessionTimers()
                    existingSession.complete()
                    try await dataService.saveIntentionSession(existingSession)
                    activeSession = nil
                    currentlyAppliedSessionId = nil
                }

                try await dataService.saveIntentionSession(session)

                // Reset the extension's cross-call dedupe flag so intervalDidEnd
                // for THIS session isn't suppressed by a previous session's
                // "already handled" marker.
                if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
                    sharedDefaults.set(false, forKey: AppConstants.Keys.sessionExpired)
                    sharedDefaults.removeObject(forKey: AppConstants.Keys.sessionExpiredBy)
                    sharedDefaults.synchronize()
                }

                await applySessionBlocking(for: session)
                activeSession = session
                updateWidgetSessionData(session)
                await NotificationService.shared.scheduleSessionNotifications(for: session)
            } catch {
                handleError(error)
            }
        }
    }

    /// End the current session
    func endCurrentSession() async {
        guard activeSession != nil else { return }
        await withLoading {
            await finalizeSession(cause: .endedManually)
        }
    }

    /// Handle automatic session expiration (called by ScreenTimeService in-app timer
    /// when the app is foregrounded at expiration time). The authoritative end-time
    /// notification is the pre-scheduled `session_completion_<id>` trigger — this
    /// path only posts a fallback if that pre-scheduled notification did not deliver.
    private func handleSessionExpiration() async {
        guard activeSession != nil else { return }
        await finalizeSession(cause: .naturalCompletion)
    }

    /// Extend the current session by additional time
    func extendCurrentSession(by extensionTime: TimeInterval) async {
        guard let session = activeSession, session.isActive else { return }

        await withLoading {
            do {
                let sessionId = session.id
                // Extend the session duration
                session.duration += extensionTime
                try await dataService.saveIntentionSession(session)

                // Re-apply blocking with the new remaining time so the
                // ScreenTimeService timer and DeviceActivity schedule update
                currentlyAppliedSessionId = nil // Force re-application
                await applySessionBlocking(for: session)

                // Reschedule notifications for the new remaining time. Cancel ONLY
                // this session's pending warnings + completion before rescheduling,
                // so unrelated notifications (there shouldn't be any) stay untouched.
                await NotificationService.shared.cancelAllSessionNotifications(sessionId: sessionId)
                await NotificationService.shared.scheduleSessionNotifications(for: session)

                updateWidgetSessionData(session)
            } catch {
                handleError(error)
            }
        }
    }
    
    /// Cancel the active session because the user disabled blocking entirely.
    /// Treated as a manual end — cancels all pending session notifications.
    private func cancelActiveSessionForDisable() async {
        guard let session = activeSession, session.isActive else { return }
        let sessionId = session.id
        // Cancel pending notifications BEFORE mutating session state so the
        // pre-scheduled completion trigger cannot fire in the racing window.
        await NotificationService.shared.cancelAllSessionNotifications(sessionId: sessionId)
        await screenTimeService.cancelSessionTimers()
        session.cancel()
        try? await dataService.saveIntentionSession(session)
        await teardownSessionState()
    }

    // MARK: - Session Teardown Helpers

    /// Single path for ending a session: complete it, tear down state, apply schedule-based blocking.
    ///
    /// Notification behavior by cause:
    /// - `.naturalCompletion`: the pre-scheduled `session_completion_<id>` trigger is
    ///   authoritative and fires at the real end time. We cancel only the warning
    ///   notifications; the completion one is left to fire (or already fired). If the
    ///   pre-scheduled notification was never delivered (e.g. permissions changed after
    ///   scheduling), a fallback `sendSessionExpiredNotification` is posted.
    /// - `.endedManually` / `.replaced`: all pending session notifications are cancelled
    ///   before any state change so the pre-scheduled completion cannot leak. No
    ///   notification is posted.
    private func finalizeSession(cause: SessionEndCause) async {
        guard let session = activeSession else { return }
        let sessionId = session.id

        logger.notice("🏁 finalizeSession: ending session \(sessionId), cause=\(String(describing: cause))")

        // Cancel pending notifications FIRST so manual/replaced paths cannot
        // accidentally deliver the pre-scheduled completion between now and
        // the session-state mutation.
        switch cause {
        case .endedManually, .replaced:
            await NotificationService.shared.cancelAllSessionNotifications(sessionId: sessionId)
        case .naturalCompletion:
            // Leave the completion trigger alone — it is the authoritative end-time
            // notification. Warnings are stale now that the session is over.
            await NotificationService.shared.cancelSessionWarnings(sessionId: sessionId)
        }

        do {
            session.complete()
            try await dataService.saveIntentionSession(session)
        } catch {
            logger.error("Failed to save completed session: \(error.localizedDescription)")
        }

        await teardownSessionState()
        await applyDefaultBlocking()

        // Clear currentSessionId AFTER blocking is applied. The extension needs this
        // ID to validate — clearing it too early causes the extension to skip
        // restoreDefaultBlocking when it races with the in-app timer.
        if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
            sharedDefaults.removeObject(forKey: AppConstants.Keys.currentSessionId)
            sharedDefaults.synchronize()
        }

        // Fallback notification for natural completion: only post if the
        // pre-scheduled completion did not deliver (e.g. permissions changed,
        // or the trigger was cleared by some other path). Dedupe guard prevents
        // a second banner when the pre-scheduled already fired.
        if cause == .naturalCompletion {
            let alreadyDelivered = await NotificationService.shared
                .hasDeliveredCompletionNotification(sessionId: sessionId)
            if !alreadyDelivered {
                logger.notice("🏁 finalizeSession: pre-scheduled completion not delivered, posting fallback")
                await NotificationService.shared.sendSessionExpiredNotification()
            } else {
                logger.info("🏁 finalizeSession: completion already delivered, skipping fallback")
            }
        }
    }

    /// Clear session-related transient state (widget, tracking vars, expired flag).
    /// Notifications are handled by the caller per-cause — this helper does NOT touch
    /// pending notifications.
    /// Does NOT complete/cancel the session model, apply blocking, or clear currentSessionId.
    private func teardownSessionState() async {
        activeSession = nil
        currentlyAppliedSessionId = nil

        clearWidgetSessionData()

        if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
            sharedDefaults.set(false, forKey: AppConstants.Keys.sessionExpired)
            sharedDefaults.synchronize()
        }
    }

    /// Aggregate all app tokens from QuickActions and feed them to ScreenTimeService
    /// so it can use `shield.applications` as a second blocking layer.
    private func feedKnownAppTokens() async {
        let allTokens = sharedQuickActionsViewModel.quickActions
            .reduce(into: Set<ApplicationToken>()) { $0.formUnion($1.individualApplications) }
        if !allTokens.isEmpty {
            await screenTimeService.updateKnownAppTokens(allTokens)
        }
    }

    /// Clean up stale sessions and ManagedSettingsStore before applying blocking
    private func cleanupOldSessionsBeforeBlocking() async {
        do {
            let allSessions = try await dataService.loadIntentionSessions()

            // Complete stale active sessions and drop any pending notifications they
            // may have left scheduled (could fire as a ghost banner otherwise).
            let staleSessions = allSessions.filter { $0.isActive && $0.id != activeSession?.id }
            for staleSession in staleSessions {
                await NotificationService.shared.cancelAllSessionNotifications(sessionId: staleSession.id)
                staleSession.complete()
                try await dataService.saveIntentionSession(staleSession)
            }

            // Delete completed sessions older than retention period
            let cutoff = Calendar.current.date(byAdding: .day, value: -AppConstants.DataCleanup.sessionRetentionDays, to: Date()) ?? Date()
            for oldSession in allSessions.filter({ !$0.isActive && $0.endTime < cutoff }) {
                try await dataService.deleteIntentionSession(oldSession.id)
            }

            // Clear ManagedSettingsStore if no active sessions remain
            if !allSessions.contains(where: { $0.isActive }) {
                await screenTimeService.cleanup()
            }
        } catch {
            logger.error("Session cleanup error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Unified Blocking Pipeline
    
    /// Apply session-based blocking - allows only the session's apps/categories
    private func applySessionBlocking(for session: IntentionSession) async {
        guard screenTimeService.isReady else {
            handleError(AppError.serviceUnavailable("Screen Time service is not ready. Please complete setup first."))
            return
        }

        guard currentlyAppliedSessionId != session.id else { return }
        currentlyAppliedSessionId = session.id

        do {
            if !session.requestedApplications.isEmpty {
                try await screenTimeService.allowApps(
                    session.requestedApplications,
                    webDomains: session.requestedWebDomains,
                    allowWebsites: session.allowAllWebsites,
                    duration: session.duration,
                    sessionId: session.id
                )
            } else {
                await applyDefaultBlocking()
            }
        } catch {
            logger.error("Failed to apply session blocking: \(error.localizedDescription)")
            await applyDefaultBlocking()
        }
    }
    
    /// Called when the app becomes active. Re-checks authorization (the user may have
    /// revoked Family Controls in iOS Settings while backgrounded) and re-applies blocking.
    func reconcileBlockingOnForeground() async {
        logger.info("👁️ reconcileBlockingOnForeground: app became active, session=\(self.activeSession?.id.uuidString ?? "none")")
        let freshStatus = await screenTimeService.authorizationStatus()
        let previousStatus = authorizationStatus
        authorizationStatus = freshStatus

        if previousStatus == .approved && freshStatus != .approved {
            // Authorization was confirmed revoked at runtime — not a cold-launch transient.
            // Cancel active session (can't manage blocking without auth) and reset service state.
            if let session = activeSession, session.isActive {
                await cancelActiveSessionForDisable()
            }
            screenTimeState = .uninitialized

            // Re-request authorization immediately — shows the system dialog
            let reauthorized = await screenTimeService.requestAuthorization()
            if reauthorized {
                authorizationStatus = .approved
                await setupCoordinator.validateSetupRequirements(
                    cachedAuthStatus: .approved,
                    forceAuthUpdate: true
                )
                await initializeScreenTimeServiceAfterSetup()
            } else {
                // User denied re-auth — update state but stay on home screen.
                // The ScreenTimeAccessBanner handles the UI from here.
                authorizationStatus = await screenTimeService.authorizationStatus()
                await setupCoordinator.validateSetupRequirements(
                    cachedAuthStatus: authorizationStatus,
                    forceAuthUpdate: true
                )
            }
            return
        }

        await applyDefaultBlocking()
    }

    /// Reconcile in-app session state with shield state.
    ///
    /// Shield decisions (session vs schedule vs default) are owned by
    /// `ShieldEngine.compute(_:at:)`. This method only handles the SwiftData
    /// side of session lifecycle (mark expired sessions complete, tear down
    /// UI state) and then asks the engine to re-evaluate via
    /// `refreshSchedule(...)` — which pushes the latest snapshot, re-registers
    /// the schedule-boundary DAM monitor, and applies the computed config.
    private func applyDefaultBlocking() async {
        guard !isApplyingDefaultBlocking else {
            logger.info("⏭️ applyDefaultBlocking: skipped (already in progress)")
            return
        }
        guard screenTimeService.isReady else {
            logger.warning("⏭️ applyDefaultBlocking: skipped (service not ready)")
            return
        }

        isApplyingDefaultBlocking = true
        defer { isApplyingDefaultBlocking = false }

        // Session expired while app was backgrounded — DAM extension already
        // cleared shared ManagedSettings. We only need to update the app's
        // data model (mark session complete, clear UI state).
        // This is a .naturalCompletion — pre-scheduled notif already delivered
        // (or will deliver) at the true end time.
        if let activeSession = activeSession, activeSession.isActive, activeSession.isExpired {
            let expiredId = activeSession.id
            logger.notice("🔄 applyDefaultBlocking: found expired session \(expiredId), completing")
            await NotificationService.shared.cancelSessionWarnings(sessionId: expiredId)
            activeSession.complete()
            try? await dataService.saveIntentionSession(activeSession)
            await teardownSessionState()
            if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
                sharedDefaults.removeObject(forKey: AppConstants.Keys.currentSessionId)
                sharedDefaults.synchronize()
            }
            // Fall through to engine reapply below.
        } else if let activeSession = activeSession, activeSession.isActive {
            logger.info("🔄 applyDefaultBlocking: active session \(activeSession.id) still running, preserving")
            await applySessionBlocking(for: activeSession)
            return
        }

        currentlyAppliedSessionId = nil

        // Delegate to engine: pushes snapshot, registers next boundary,
        // applies compute(IntentLog, now) which handles session/schedule/default.
        await screenTimeService.refreshSchedule(weeklySchedule.snapshot())
    }
    
    // MARK: - Setup

    /// Check if setup flow is required
    private func checkSetupRequired() async {
        // Validate setup state using the coordinator (pass cached auth status to avoid redundant check)
        await setupCoordinator.validateSetupRequirements(cachedAuthStatus: authorizationStatus)

        let setupState = setupCoordinator.setupState

        // Only show setup flow for genuine first-time setup. If the user already
        // completed the intention quote step, setup was finished at least once —
        // a later auth revocation is handled by the home-screen banner, not by
        // re-running the entire setup flow.
        let neverCompletedSetup = setupState?.intentionQuoteCompleted != true
        let needsSetup = setupState?.isSetupSufficient != true && neverCompletedSetup && activeSession == nil

        if needsSetup {
            showingSetupFlow = true
        } else {
            // Setup was completed before — initialize ScreenTimeService if possible
            await initializeScreenTimeServiceAfterSetup()
        }
    }
    
    /// Save the user's intention quote from the setup flow
    func setIntentionQuote(_ quote: String) {
        weeklySchedule.intentionQuote = quote
        Task {
            do {
                try await dataService.saveWeeklySchedule(weeklySchedule)
            } catch {
                logger.error("Failed to save intention quote: \(error.localizedDescription)")
                handleError(error)
            }
        }
    }

    /// Handle completion of the unified setup flow
    func completeSetupFlow() async {
        await initializeScreenTimeServiceAfterSetup()

        if screenTimeState.isReady {
            showingSetupFlow = false
        } else {
            handleError(AppError.serviceUnavailable(
                "Screen Time initialization failed. Please try again."
            ))
        }
    }

    /// Initialize ScreenTimeService after setup completion
    private func initializeScreenTimeServiceAfterSetup() async {
        guard case .uninitialized = screenTimeState else { return }
        screenTimeState = .initializing

        await withLoading {
            do {
                authorizationStatus = await screenTimeService.authorizationStatus()

                guard authorizationStatus == .approved,
                      setupCoordinator.setupState?.isSetupSufficient == true else {
                    screenTimeState = .uninitialized
                    return
                }

                if !screenTimeService.isReady {
                    try await screenTimeService.initialize()
                }

                await screenTimeService.setRestoreDefaultStateCallback { [weak self] in
                    await self?.handleSessionExpiration()
                }

                await cleanupOldSessionsBeforeBlocking()
                await applyDefaultBlocking()

                screenTimeState = .ready
            } catch {
                screenTimeState = .failed(error.localizedDescription)
                logger.error("ScreenTimeService initialization error: \(error.localizedDescription)")
                handleError(error)
            }
        }
    }
    
    // MARK: - Error Handling
    
    func handleError(_ error: Error) {
        if let appError = error as? AppError {
            errorMessage = appError.errorDescription
        } else {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Helper Methods

    /// Execute an operation with loading state management
    private func withLoading<T: Sendable>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
    
    // MARK: - App Group Notifications
    
    /// Notify that app groups have been modified
    func notifyAppGroupsChanged() {
        appGroupsDidChange = UUID()
    }
    
    /// Update widget with session information
    private func updateWidgetSessionData(_ session: IntentionSession) {
        guard let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) else { return }

        let sessionTitle: String
        switch session.source {
        case .quickAction(let quickAction): sessionTitle = quickAction.name
        case .manual: sessionTitle = "Session"
        }

        sharedDefaults.set(sessionTitle, forKey: AppConstants.Keys.widgetSessionTitle)
        sharedDefaults.set(session.endTime, forKey: AppConstants.Keys.widgetSessionEndTime)
        sharedDefaults.set(false, forKey: AppConstants.Keys.widgetBlockingStatus)
        sharedDefaults.set(Date(), forKey: AppConstants.Keys.widgetLastUpdate)
        sharedDefaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Clear widget session data when session ends
    private func clearWidgetSessionData() {
        guard let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) else { return }

        sharedDefaults.removeObject(forKey: AppConstants.Keys.widgetSessionTitle)
        sharedDefaults.removeObject(forKey: AppConstants.Keys.widgetSessionEndTime)
        sharedDefaults.set(weeklySchedule.isBlocking(at: Date()), forKey: AppConstants.Keys.widgetBlockingStatus)
        sharedDefaults.set(Date(), forKey: AppConstants.Keys.widgetLastUpdate)
        sharedDefaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - App Navigation

/// Represents the main navigation tabs in the app
enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .settings: return "gear"
        }
    }
}
