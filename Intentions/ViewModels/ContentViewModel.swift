//
//  ContentViewModel.swift
//  Intentions
//
//  Created by Claude on 12/07/2025.
//

import Foundation
import SwiftUI
@preconcurrency import FamilyControls
import WidgetKit
import OSLog

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
    
    /// Current schedule settings
    private var scheduleSettings: ScheduleSettings = ScheduleSettings()
    
    /// Whether we're showing the intention prompt
    var showingIntentionPrompt: Bool = false
    
    /// Whether we're showing the category mapping setup
    var showingCategoryMappingSetup: Bool = false
    
    /// Whether we're showing the unified setup flow
    var showingSetupFlow: Bool = false
    
    /// Category mapping service for smart app blocking
    let categoryMappingService = CategoryMappingService()
    
    /// Setup coordinator for managing app configuration
    let setupCoordinator: SetupCoordinator

    /// Shared quick actions view model for consistency across Home and QuickActions tabs
    let sharedQuickActionsViewModel = QuickActionsViewModel()

    /// Current selected tab for navigation
    var selectedTab: AppTab = .home
    
    /// Trigger to notify when app groups have changed
    var appGroupsDidChange: UUID = UUID()

    /// Flag to prevent infinite loops in applyDefaultBlocking
    private var isApplyingDefaultBlocking: Bool = false

    /// Track the currently applied session to prevent duplicate session blocking
    private var currentlyAppliedSessionId: UUID? = nil

    /// Flag to prevent duplicate ScreenTimeService initialization
    private var isScreenTimeServiceInitialized: Bool = false

    /// Observable flag for UI to track when ScreenTimeService is ready
    var isScreenTimeServiceReady: Bool = false

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
        
        // Initialize setup coordinator
        self.setupCoordinator = SetupCoordinator(
            screenTimeService: self.screenTimeService,
            categoryMappingService: categoryMappingService
        )
    }
    
    // MARK: - App Lifecycle
    
    /// Initialize the app when it launches
    func initializeApp() async {
        logger.info("🚀 APP INIT: initializeApp() started")
        await withLoading {
            do {
                // Check authorization status
                authorizationStatus = await screenTimeService.authorizationStatus()
                logger.info("🚀 APP INIT: Authorization status = \(String(describing: self.authorizationStatus))")

                // If status is "Not Determined", double-check after a brief delay
                // This handles cases where the system needs time to return the correct status
                if authorizationStatus == .notDetermined {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    let recheckStatus = await screenTimeService.authorizationStatus()

                    if recheckStatus != .notDetermined {
                        authorizationStatus = recheckStatus
                    }
                }

                // Initialize notification service in background (non-blocking)
                Task {
                    await NotificationService.shared.checkAuthorizationStatus()

                    // Request notification permissions on first launch if not determined
                    let notificationStatus = await NotificationService.shared.authorizationStatus
                    if notificationStatus == .notDetermined {
                        print("🔔 ContentViewModel: Requesting notification permissions on app startup")
                        let granted = await NotificationService.shared.requestPermissions()
                        if granted {
                            print("✅ ContentViewModel: Notification permissions granted")
                        } else {
                            print("❌ ContentViewModel: Notification permissions denied")
                        }
                    }
                }

                // Load schedule settings
                await loadScheduleSettings()

                // Load any existing active session (this may call applyDefaultBlocking if session expired)
                await loadActiveSession()

                // CRITICAL: Don't call cleanupOldSessions() here!
                // cleanupOldSessions() calls cleanup() which clears ManagedSettingsStore
                // If there's an active session in the database (even if activeSession is nil in memory),
                // we don't want to clear the blocking settings - the session will be reapplied later
                // The session cleanup happens inside cleanupOldSessions() itself with proper checks

                // Test widget communication in background (non-blocking for debugging)
                if authorizationStatus == .approved {
                    Task.detached(priority: .background) {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                        await self.testWidgetCommunication()
                    }
                }

                // Check if setup is needed - this will initialize ScreenTimeService if setup is complete
                // This is the single point where we check setup and initialize the service
                await checkSetupRequired()

                // Schedule a delayed retry for category mapping validation
                // This addresses the iOS ApplicationToken loading issue where tokens may not be available immediately
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
                    categoryMappingService.retrySetupValidation()

                    // Re-validate setup requirements after retry to update UI if needed
                    // This won't re-initialize the service, just update the setup state
                    await setupCoordinator.validateSetupRequirements()
                }

            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Load schedule settings from persistence
    private func loadScheduleSettings() async {
        do {
            if let savedSettings = try await dataService.loadScheduleSettings() {
                scheduleSettings = savedSettings
            } else {
                // Use default settings if none exist and save them
                scheduleSettings = ScheduleSettings()
                try await dataService.saveScheduleSettings(scheduleSettings)
            }
        } catch {
            print("Failed to load schedule settings, using defaults: \(error)")
            scheduleSettings = ScheduleSettings()
        }
    }
    
    /// Load any existing active session from persistence
    /// Note: This only loads and cleans up session state - it does NOT apply blocking
    /// Blocking is applied later in the initialization flow by initializeScreenTimeServiceAfterSetup()
    private func loadActiveSession() async {
        logger.info("===== LOAD SESSION START =====")

        // DIAGNOSTIC: Check the flag status IMMEDIATELY
        if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions") {
            let flagExists = sharedDefaults.bool(forKey: "intentions.session.expired")
            let flagTime = sharedDefaults.object(forKey: "intentions.session.expirationTime") as? Date
            let currentSessionId = sharedDefaults.string(forKey: "intentions.currentSessionId")
            logger.info("🔍 LOAD SESSION: Flag check at START - expired=\(flagExists), time=\(flagTime?.description ?? "nil", privacy: .public), sessionId=\(currentSessionId ?? "nil", privacy: .public)")
        }

        do {
            let sessions = try await dataService.loadIntentionSessions()
            let activeSessions = sessions.filter { $0.isActive }

            logger.info("📊 LOAD SESSION: Total sessions: \(sessions.count), Active sessions: \(activeSessions.count)")

            // Log all active sessions
            for (index, session) in activeSessions.enumerated() {
                logger.info("📊 LOAD SESSION: Active session #\(index + 1) - ID=\(session.id.uuidString, privacy: .public), endTime=\(session.endTime, privacy: .public), isExpired=\(session.isExpired)")
            }

            if activeSessions.count > 1 {
                logger.warning("⚠️ LOAD SESSION: Multiple active sessions detected - cleaning up duplicates")
            }

            // Check if DeviceActivityMonitor extension expired a session while app was closed
            if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions"),
               sharedDefaults.bool(forKey: "intentions.session.expired") {
                // Log detailed information about when the flag was set
                let expirationTime = sharedDefaults.object(forKey: "intentions.session.expirationTime") as? Date
                let expiredBy = sharedDefaults.string(forKey: "intentions.session.expiredBy") ?? "Unknown"
                let currentSessionId = sharedDefaults.string(forKey: "intentions.currentSessionId") ?? "None"

                logger.notice("🔔 LOAD SESSION: Extension expired a session FLAG FOUND")
                logger.notice("🔔   - Expiration time: \(expirationTime?.description ?? "Unknown", privacy: .public)")
                logger.notice("🔔   - Expired by: \(expiredBy, privacy: .public)")
                logger.notice("🔔   - Current session ID in UserDefaults: \(currentSessionId, privacy: .public)")
                logger.notice("🔔   - Active sessions found: \(activeSessions.count)")

                for session in activeSessions {
                    logger.notice("🔔   - Session ID: \(String(session.id.uuidString.prefix(8)), privacy: .public), expires: \(session.endTime, privacy: .public), is expired: \(session.isExpired)")
                }

                // CRITICAL FIX: Only expire the session if it actually matches the one that was expired
                // This prevents stale DeviceActivity events from expiring new sessions
                let shouldExpireSessions: Bool
                if let activeSession = activeSessions.first {
                    let sessionIdMatches = activeSession.id.uuidString == currentSessionId
                    let sessionIsActuallyExpired = activeSession.isExpired

                    print("   - Session ID matches: \(sessionIdMatches)")
                    print("   - Session actually expired: \(sessionIsActuallyExpired)")

                    // Only expire if EITHER the ID matches OR the session is genuinely expired
                    shouldExpireSessions = sessionIdMatches || sessionIsActuallyExpired
                } else {
                    // No active session - safe to clear the flag
                    shouldExpireSessions = false
                }

                // Clear the flag immediately to prevent it from affecting future app opens
                sharedDefaults.set(false, forKey: "intentions.session.expired")
                sharedDefaults.synchronize()
                print("   - Cleared expiration flag")

                if shouldExpireSessions {
                    logger.error("🔔 LOAD SESSION: EXPIRING SESSIONS (validation passed) - THIS COMPLETES THE SESSION!")
                    logger.notice("🔔 LOAD SESSION: Expiring sessions (validation passed)")
                    // Mark any active sessions as completed
                    for session in activeSessions {
                        logger.notice("🔔 COMPLETING SESSION: \(session.id.uuidString, privacy: .public)")
                        session.complete()
                        try await dataService.saveIntentionSession(session)
                    }

                    activeSession = nil
                    logger.info("✅ LOAD SESSION: Expired sessions cleaned up")
                    logger.info("✅ LOAD SESSION: Expired sessions cleaned up, blocking will be applied after setup check")
                    return
                } else {
                    print("⚠️ LOAD SESSION: Ignoring stale expiration flag - session IDs don't match and session not expired")
                    // Continue with normal session loading
                }
            }

            // Check if the active session has expired while app was in background/closed
            if let loadedSession = activeSessions.first {
                // Log detailed session information
                let now = Date()
                let sessionId = loadedSession.id.uuidString.prefix(8)
                let startTime = loadedSession.startTime
                let endTime = loadedSession.endTime
                let duration = loadedSession.duration
                let timeUntilExpiry = endTime.timeIntervalSince(now)
                let isExpired = loadedSession.isExpired

                print("📋 LOAD SESSION: Loaded session \(sessionId):")
                print("   - Current time: \(now)")
                print("   - Start time: \(startTime)")
                print("   - End time: \(endTime)")
                print("   - Duration: \(duration)s")
                print("   - Time until expiry: \(timeUntilExpiry)s")
                print("   - Total elapsed time: \(loadedSession.state.totalElapsedTime)s")
                print("   - Session state: \(loadedSession.state)")
                print("   - Is expired: \(isExpired)")

                if loadedSession.isExpired {
                    print("🕐 LOAD SESSION: Session IS EXPIRED - will be marked as complete")
                    // Session expired while app wasn't running - complete it now
                    loadedSession.complete()
                    try await dataService.saveIntentionSession(loadedSession)
                    activeSession = nil
                    print("✅ LOAD SESSION: Expired session cleaned up, blocking will be applied after setup check")
                } else {
                    // Session is still active - it will be reapplied after ScreenTimeService initialization
                    activeSession = loadedSession
                    print("✅ LOAD SESSION: Session is still active - will be reapplied")
                }
            } else {
                activeSession = nil
                logger.info("ℹ️ LOAD SESSION: No active sessions found")

                // CRITICAL: Clear stale session ID from UserDefaults if no active sessions exist
                // This prevents orphaned session IDs from causing issues
                if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions"),
                   let staleSessionId = sharedDefaults.string(forKey: "intentions.currentSessionId") {
                    logger.warning("⚠️ LOAD SESSION: Found stale session ID in UserDefaults: \(staleSessionId, privacy: .public)")
                    logger.warning("⚠️ LOAD SESSION: Clearing stale session ID since no active sessions exist")
                    sharedDefaults.removeObject(forKey: "intentions.currentSessionId")
                    sharedDefaults.synchronize()
                    logger.info("✅ LOAD SESSION: Cleared stale session ID from UserDefaults")
                }
            }
        } catch {
            // Non-critical error - just log it
            print("❌ LOAD SESSION: Failed to load active session: \(error)")
        }

        print("===== LOAD SESSION END =====\n")
    }
    
    // MARK: - Schedule Management
    
    /// Update schedule settings and apply blocking accordingly
    func updateScheduleSettings(_ newSettings: ScheduleSettings) async {
        scheduleSettings = newSettings

        // Save to persistence
        do {
            try await dataService.saveScheduleSettings(newSettings)
        } catch {
            print("Failed to save schedule settings: \(error)")
            await handleError(error)
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
            do {
                let success = await screenTimeService.requestAuthorization()
                if success {
                    authorizationStatus = await screenTimeService.authorizationStatus()
                    print("✅ ContentViewModel: Authorization successful - service will be initialized after setup completion")
                } else {
                    await handleError(AppError.screenTimeAuthorizationFailed)
                }
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Check if app is ready to use (authorized and initialized)
    var isAppReady: Bool {
        return authorizationStatus == .approved
    }
    
    // MARK: - Navigation Actions
    
    /// Show the intention prompt to create a new session
    func showIntentionPrompt() {
        guard isAppReady else {
            Task {
                await handleError(AppError.screenTimeAuthorizationRequired("Please authorize Screen Time access first"))
            }
            return
        }
        showingIntentionPrompt = true
    }
    
    /// Navigate to Settings tab and ensure we're at the home page
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
    
    // Callback to reset Settings state when navigating away
    var onSettingsTabExit: (() -> Void)?
    
    // MARK: - Session Management
    
    /// Start a new intention session using unified blocking pipeline
    func startSession(_ session: IntentionSession) async {
        await withLoading {
            do {
                // If there's an existing active session, cancel its timers FIRST
                // This prevents the old session's expiration callback from re-blocking apps
                if let existingSession = activeSession, existingSession.isActive {
                    print("🔄 START SESSION: Cancelling timers for existing session \(existingSession.id.uuidString.prefix(8))")

                    // Cancel the old session's timers WITHOUT triggering re-blocking
                    await screenTimeService.cancelSessionTimers()

                    // Now complete the session and save
                    print("🔄 START SESSION: Completing existing session")
                    existingSession.complete()
                    try await dataService.saveIntentionSession(existingSession)

                    // Clear the session state to force re-application
                    activeSession = nil
                    currentlyAppliedSessionId = nil

                    // Explicitly block all apps to ensure clean slate between sessions
                    // This prevents cumulative ManagedSettingsStore issues
                    print("🔄 START SESSION: Blocking all apps before applying new session")
                    try await screenTimeService.blockAllApps()

                    // Brief delay to ensure blocking takes effect
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    print("🔄 START SESSION: Ready to apply new session")
                }

                // Save new session to persistence
                try await dataService.saveIntentionSession(session)

                // Apply session-based blocking using unified pipeline
                await applySessionBlocking(for: session)

                // Update local state
                activeSession = session
                showingIntentionPrompt = false

                // Update widget data with session information
                updateWidgetSessionData(session)

            } catch {
                await handleError(error)
            }
        }
    }
    
    /// End the current session using unified blocking pipeline
    func endCurrentSession() async {
        guard let session = activeSession else { return }

        await withLoading {
            do {
                // Complete the session
                session.complete()
                try await dataService.saveIntentionSession(session)

                // Clear local state
                activeSession = nil
                currentlyAppliedSessionId = nil

                // CRITICAL: Clear session ID from UserDefaults to prevent stale session IDs
                // This ensures the DeviceActivityMonitor extension knows the session was manually stopped
                if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions") {
                    sharedDefaults.removeObject(forKey: "intentions.currentSessionId")
                    sharedDefaults.synchronize()
                    print("✅ END SESSION: Cleared session ID from UserDefaults")
                }

                // Clear widget session data
                clearWidgetSessionData()

                // Apply default blocking state (revert to block-all or allow-all based on schedule)
                await applyDefaultBlocking()

            } catch {
                await handleError(error)
            }
        }
    }

    /// Handle automatic session expiration (called by ScreenTimeService background task)
    /// This is triggered when the session timer expires automatically
    private func handleSessionExpiration() async {
        print("⏰ SESSION EXPIRED: Automatic expiration triggered by background task")

        guard let session = activeSession else {
            print("⚠️ SESSION EXPIRED: No active session found - already expired")
            return
        }

        print("⏰ SESSION EXPIRED: Completing session \(session.id.uuidString.prefix(8))")

        do {
            // Complete the session
            session.complete()
            try await dataService.saveIntentionSession(session)

            // Clear local state
            activeSession = nil
            currentlyAppliedSessionId = nil

            // CRITICAL: Clear session ID from UserDefaults to prevent stale session IDs
            // This ensures subsequent app launches know the session has expired
            if let sharedDefaults = UserDefaults(suiteName: "group.oh.Intentions") {
                sharedDefaults.removeObject(forKey: "intentions.currentSessionId")
                sharedDefaults.synchronize()
                print("✅ SESSION EXPIRED: Cleared session ID from UserDefaults")
            }

            // Clear widget session data
            clearWidgetSessionData()

            print("✅ SESSION EXPIRED: Session marked as complete and cleared from state")

            // Apply default blocking state (revert to block-all or allow-all based on schedule)
            await applyDefaultBlocking()

            // Send notification to user
            await NotificationService.shared.sendSessionExpiredNotification()

            print("✅ SESSION EXPIRED: Re-blocking applied and notification sent")

        } catch {
            print("❌ SESSION EXPIRED: Error completing session: \(error)")
            // Still apply default blocking even if save fails
            await applyDefaultBlocking()
        }
    }

    /// Extend the current session by additional time
    func extendCurrentSession(by extensionTime: TimeInterval) async {
        guard let session = activeSession else { return }
        
        await withLoading {
            do {
                // Extend the session duration
                session.duration += extensionTime
                try await dataService.saveIntentionSession(session)
                
                // Update local state
                activeSession = session
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Clean up stale sessions and ManagedSettingsStore BEFORE applying blocking
    /// This ensures we start with a clean slate
    private func cleanupOldSessionsBeforeBlocking() async {
        logger.info("🧹 CLEANUP BEFORE BLOCKING: Starting cleanup")
        do {
            let allSessions = try await dataService.loadIntentionSessions()

            // STEP 1: Find and complete any sessions that are marked as active but shouldn't be
            let staleSessions = allSessions.filter { session in
                session.isActive && session.id != activeSession?.id
            }

            logger.info("🧹 CLEANUP BEFORE BLOCKING: Found \(staleSessions.count) stale sessions")

            if !staleSessions.isEmpty {
                // Complete all stale sessions
                for staleSession in staleSessions {
                    staleSession.complete()
                    try await dataService.saveIntentionSession(staleSession)
                }
            }

            // STEP 2: Delete old completed sessions (keep last 30 days for statistics)
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let completedSessions = allSessions.filter { !$0.isActive }

            logger.info("🧹 CLEANUP BEFORE BLOCKING: Total completed sessions: \(completedSessions.count)")

            let oldCompletedSessions = completedSessions.filter { session in
                session.endTime < thirtyDaysAgo
            }

            logger.info("🧹 CLEANUP BEFORE BLOCKING: Found \(oldCompletedSessions.count) old completed sessions to delete")

            if !oldCompletedSessions.isEmpty {
                for oldSession in oldCompletedSessions {
                    logger.info("🗑️ CLEANUP: Deleting old session \(oldSession.id.uuidString, privacy: .public) from \(oldSession.startTime, privacy: .public)")
                    try await dataService.deleteIntentionSession(oldSession.id)
                }
                logger.info("✅ CLEANUP BEFORE BLOCKING: Deleted \(oldCompletedSessions.count) old sessions")
            }

            // STEP 3: CRITICAL - Clear ManagedSettingsStore if no active sessions
            // This removes any stale .all(except: tokens) settings from previous sessions
            let hasAnyActiveSessions = allSessions.contains { $0.isActive }

            if !hasAnyActiveSessions {
                logger.notice("🧹 CLEANUP BEFORE BLOCKING: No active sessions - clearing ManagedSettingsStore to remove stale exceptions")
                await screenTimeService.cleanup()
                logger.info("✅ CLEANUP BEFORE BLOCKING: ManagedSettingsStore cleared - ready for fresh blocking")
            } else {
                let activeCount = allSessions.filter { $0.isActive }.count
                logger.info("✅ CLEANUP BEFORE BLOCKING: Active sessions exist (\(activeCount)) - skipping cleanup() to preserve session blocking")
            }

        } catch {
            logger.error("❌ CLEANUP BEFORE BLOCKING: Error during session cleanup: \(error.localizedDescription)")
            // Don't throw - this is cleanup, shouldn't block the main flow
        }
    }
    
    // MARK: - Unified Blocking Pipeline
    
    /// Apply session-based blocking - allows only the apps/categories specified in the session
    /// This is the core method used by both IntentionPrompt and QuickActions
    private func applySessionBlocking(for session: IntentionSession) async {
        // Check if ScreenTimeService is initialized before using it
        guard screenTimeService.isReady else {
            print("❌ APPLY SESSION: ScreenTimeService not initialized - cannot start session")
            await handleError(AppError.serviceUnavailable("Screen Time service is not ready. Please complete setup first."))
            return
        }

        // Prevent re-applying the same session repeatedly
        if currentlyAppliedSessionId == session.id {
            print("🔄 SESSION ALREADY APPLIED: Session \(session.id.uuidString.prefix(8)) already applied - skipping duplicate")
            return
        }

        print("🎯 APPLYING SESSION BLOCKING: Starting session \(session.id.uuidString.prefix(8))")
        currentlyAppliedSessionId = session.id

        do {
            // Collect all applications, categories, and website preferences for this session
            var allApplications = session.requestedApplications
            var allCategories = session.selectedCategories
            var allowWebsites = session.allowAllWebsites

            // If session has appGroups but no individual apps/categories (like QuickActions),
            // extract tokens from the app groups
            if !session.requestedAppGroups.isEmpty && allApplications.isEmpty && allCategories.isEmpty {
                let appGroups = try await dataService.loadAppGroups()
                for groupId in session.requestedAppGroups {
                    if let group = appGroups.first(where: { $0.id == groupId }) {
                        allApplications.formUnion(group.applications)
                        allCategories.formUnion(group.categories)
                        // If any group allows websites, enable website access for the session
                        if group.allowAllWebsites {
                            allowWebsites = true
                        }
                    }
                }
            }

            // Apply Screen Time restrictions to allow only the specified apps/categories
            // NOTE: allowApps() handles cleanup internally - no need for explicit cleanup() call
            if !allApplications.isEmpty || !allCategories.isEmpty {
                // Allow only the session apps - this blocks everything else
                // Pass session ID for tracking and validation in DeviceActivity extension
                try await screenTimeService.allowApps(allApplications, categories: allCategories, allowWebsites: allowWebsites, duration: session.duration, sessionId: session.id)
            } else {
                // Fallback to default blocking
                await applyDefaultBlocking()
            }
            
        } catch {
            print("Failed to apply session blocking: \(error)")
            // Fallback to default blocking on error
            await applyDefaultBlocking()
        }
    }
    
    /// Apply default blocking state based on schedule settings
    /// Used when no session is active or when session ends
    /// IMPORTANT: If a session is active, preserves session blocking regardless of schedule settings
    private func applyDefaultBlocking() async {
        logger.notice("🔧 DEFAULT BLOCKING: ===== STARTING =====")

        // Prevent infinite loops from recursive calls
        guard !isApplyingDefaultBlocking else {
            logger.warning("⚠️ LOOP PREVENTION: applyDefaultBlocking already in progress - skipping recursive call")
            return
        }

        // Check if ScreenTimeService is initialized before using it
        guard screenTimeService.isReady else {
            logger.info("⏳ DEFAULT BLOCKING: ScreenTimeService not initialized yet - skipping")
            return
        }

        // Set flag to prevent recursive calls
        isApplyingDefaultBlocking = true
        defer { isApplyingDefaultBlocking = false }

        do {
            // CRITICAL: If there's an active session, preserve its blocking state
            // This prevents users from bypassing active sessions by disabling Intentions
            if let activeSession = activeSession, activeSession.isActive {
                logger.notice("🔒 DEFAULT BLOCKING: Active session detected - preserving session blocking")
                logger.info("   - Session ID: \(activeSession.id.uuidString, privacy: .public)")
                logger.info("   - Remaining time: \(activeSession.remainingTime)s")
                await applySessionBlocking(for: activeSession)
                return
            }

            // Clear any previously applied session since we're applying default blocking
            currentlyAppliedSessionId = nil
            logger.info("🔧 DEFAULT BLOCKING: Cleared session tracking (no active session)")

            // Clean up any stale sessions in the database
            do {
                let allSessions = try await dataService.loadIntentionSessions()
                let staleSessions = allSessions.filter { session in
                    session.isActive && session.id != activeSession?.id
                }

                if !staleSessions.isEmpty {
                    logger.warning("🧹 DEFAULT BLOCKING: Cleaning up \(staleSessions.count) stale sessions")
                    for staleSession in staleSessions {
                        staleSession.complete()
                        try await dataService.saveIntentionSession(staleSession)
                    }
                }
            } catch {
                logger.error("❌ DEFAULT BLOCKING: Error cleaning stale sessions: \(error.localizedDescription)")
            }

            // Apply blocking based on schedule only when no session is active
            // NOTE: blockAllApps() and allowAllAccess() handle cleanup internally - no need for explicit cleanup() call
            let currentlyActive = scheduleSettings.isCurrentlyActive

            logger.notice("🔧 DEFAULT BLOCKING: Schedule check:")
            logger.info("   - Schedule enabled: \(self.scheduleSettings.isEnabled)")
            logger.info("   - Currently active: \(currentlyActive)")
            logger.info("   - Active hours: \(self.scheduleSettings.activeHours)")
            logger.info("   - Active days: \(self.scheduleSettings.activeDays.map { $0.shortName }.joined(separator: ", "))")

            if scheduleSettings.isEnabled && currentlyActive {
                // Schedule is active - block all apps (default behavior during protected hours)
                logger.notice("🚫 DEFAULT BLOCKING: Schedule is ACTIVE - blocking ALL apps")
                try await screenTimeService.blockAllApps()
                logger.notice("✅ DEFAULT BLOCKING: Successfully blocked all apps")
            } else {
                // Schedule is inactive - allow all access
                logger.notice("✅ DEFAULT BLOCKING: Schedule is INACTIVE - allowing all access")
                try await screenTimeService.allowAllAccess()
                logger.notice("✅ DEFAULT BLOCKING: Successfully allowed all access")
            }

        } catch {
            logger.error("❌ DEFAULT BLOCKING: Failed to apply default blocking: \(error.localizedDescription)")
        }

        logger.notice("🔧 DEFAULT BLOCKING: ===== COMPLETE =====")
    }
    
    // MARK: - Category Mapping Setup
    
    /// Check if category mapping setup is required for smart blocking
    /// Check if comprehensive setup flow is required
    private func checkSetupRequired() async {
        // Validate setup state using the coordinator (pass cached auth status to avoid redundant check)
        await setupCoordinator.validateSetupRequirements(cachedAuthStatus: authorizationStatus)

        // Use the coordinator's shouldShowSetup property which handles all the logic
        let needsSetup = setupCoordinator.shouldShowSetup &&
                        !showingIntentionPrompt &&
                        activeSession == nil

        if needsSetup {
            showingSetupFlow = true
        } else {
            // Setup is complete - initialize ScreenTimeService if needed
            await initializeScreenTimeServiceAfterSetup()

            // Fallback to legacy category mapping setup if needed
            checkLegacyCategoryMappingSetupRequired()
        }
    }
    
    /// Legacy fallback for category mapping setup (to be removed later)
    private func checkLegacyCategoryMappingSetupRequired() {
        // Only show setup if:
        // 1. We have Screen Time authorization
        // 2. Category mapping setup is not completed
        // 3. We're not already showing other critical flows
        
        let needsSetup = authorizationStatus == .approved && 
                        !categoryMappingService.isTrulySetupCompleted &&
                        !showingIntentionPrompt &&
                        activeSession == nil
        
        if needsSetup {
            showingCategoryMappingSetup = true
        }
    }
    
    /// Handle completion of the unified setup flow
    func completeSetupFlow() {
        showingSetupFlow = false

        // Re-initialize the app with the new authorization status
        Task {
            await initializeScreenTimeServiceAfterSetup()
        }
    }
    
    /// Initialize and configure ScreenTimeService after setup completion
    /// This is THE ONLY place where ScreenTimeService should be initialized
    private func initializeScreenTimeServiceAfterSetup() async {
        // Prevent duplicate initialization
        guard !isScreenTimeServiceInitialized else {
            print("✅ INIT SKIPPED: ScreenTimeService already initialized")
            return
        }

        print("🔍 INIT CHECK: initializeScreenTimeServiceAfterSetup() called")
        print("   - authorizationStatus: \(authorizationStatus)")
        print("   - isSetupSufficient: \(setupCoordinator.setupState?.isSetupSufficient ?? false)")
        print("   - screenTimeService.isReady: \(screenTimeService.isReady)")

        await withLoading {
            do {
                // Refresh authorization status
                authorizationStatus = await screenTimeService.authorizationStatus()
                print("   - Refreshed authorizationStatus: \(authorizationStatus)")

                // Only initialize and configure if authorized and setup is complete
                if authorizationStatus == .approved && setupCoordinator.setupState?.isSetupSufficient == true {
                    // Initialize the service if not already done
                    if !screenTimeService.isReady {
                        print("🔧 Initializing ScreenTimeService after setup completion")
                        try await screenTimeService.initialize()
                        print("✅ ScreenTimeService initialized successfully")
                    } else {
                        print("✅ ScreenTimeService already ready")
                    }

                    // Configure category mapping service for intelligent blocking
                    await screenTimeService.setCategoryMappingService(categoryMappingService)

                    // Configure restore callback for session expiration
                    await screenTimeService.setRestoreDefaultStateCallback { [weak self] in
                        await self?.handleSessionExpiration()
                    }

                    // CRITICAL ORDER: Clean up stale sessions BEFORE applying default blocking
                    // This ensures any old session exceptions (like .all(except: tokens)) are removed
                    // before we apply fresh blocking settings
                    print("🔧 Cleaning up stale sessions before applying blocking")
                    await cleanupOldSessionsBeforeBlocking()

                    // Now apply default blocking with a clean slate
                    // This ensures apps are blocked immediately if we're within the "Intent" schedule period
                    print("🔧 Applying default blocking based on schedule")
                    await applyDefaultBlocking()

                    // Mark initialization as complete
                    isScreenTimeServiceInitialized = true
                    isScreenTimeServiceReady = true  // Update observable state for UI
                    print("✅ ScreenTimeService ready state updated for UI")
                } else if authorizationStatus != .approved {
                    print("⏳ Not authorized - skipping ScreenTimeService initialization")
                    isScreenTimeServiceReady = false
                } else {
                    print("⏳ Setup not complete - skipping ScreenTimeService initialization")
                    isScreenTimeServiceReady = false
                }

            } catch {
                print("❌ ContentViewModel: Error during initialization: \(error)")
                await handleError(error)
            }
        }
    }
    
    /// Handle completion of category mapping setup
    func completeCategoryMappingSetup(_ mappingService: CategoryMappingService) {
        showingCategoryMappingSetup = false

        // The mapping service is already shared, so smart blocking is now available
        // Future session starts will use the category-based prioritization
    }
    
    // MARK: - Error Handling
    
    func handleError(_ error: Error) async {
        await MainActor.run {
            if let appError = error as? AppError {
                errorMessage = appError.errorDescription
            } else {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
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
    
    /// Test widget communication by manually writing data
    private func testWidgetCommunication() async {
        let appGroupId = "group.oh.Intentions"

        // Force CFPreferences synchronization before creating UserDefaults
        CFPreferencesSynchronize(appGroupId as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            print("⚠️ ContentViewModel: Failed to access App Group \(appGroupId), using standard UserDefaults for test")
            // Fallback to standard UserDefaults only
            UserDefaults.standard.set(true, forKey: "intentions.widget.blockingStatus")
            UserDefaults.standard.set(Date(), forKey: "intentions.widget.lastUpdate")
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        // Write test data
        let testStatus = true
        let testDate = Date()

        // Try shared UserDefaults
        sharedDefaults.set(testStatus, forKey: "intentions.widget.blockingStatus")
        sharedDefaults.set(testDate, forKey: "intentions.widget.lastUpdate")
        sharedDefaults.synchronize()

        // Also try standard UserDefaults
        UserDefaults.standard.set(testStatus, forKey: "intentions.widget.blockingStatus")
        UserDefaults.standard.set(testDate, forKey: "intentions.widget.lastUpdate")
        UserDefaults.standard.synchronize()
    }

    /// Update widget with session information
    private func updateWidgetSessionData(_ session: IntentionSession) {
        let appGroupId = "group.oh.Intentions"

        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            print("⚠️ ContentViewModel: Failed to access App Group for widget update")
            return
        }

        // Derive session title from source
        let sessionTitle: String
        switch session.source {
        case .quickAction(let quickAction):
            sessionTitle = quickAction.name
        case .manual:
            sessionTitle = "Session"
        }

        // Write session information for widget
        sharedDefaults.set(sessionTitle, forKey: "intentions.widget.sessionTitle")
        sharedDefaults.set(session.endTime, forKey: "intentions.widget.sessionEndTime")
        sharedDefaults.set(false, forKey: "intentions.widget.blockingStatus") // Session active means not blocking all
        sharedDefaults.set(Date(), forKey: "intentions.widget.lastUpdate")
        sharedDefaults.synchronize()

        print("📱 WIDGET UPDATE: Updated widget with session '\(sessionTitle)', ends at \(session.endTime)")

        // Reload widget timelines to show updated information
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Clear widget session data when session ends
    private func clearWidgetSessionData() {
        let appGroupId = "group.oh.Intentions"

        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            print("⚠️ ContentViewModel: Failed to access App Group for widget update")
            return
        }

        // Clear session-specific data
        sharedDefaults.removeObject(forKey: "intentions.widget.sessionTitle")
        sharedDefaults.removeObject(forKey: "intentions.widget.sessionEndTime")
        // Update blocking status - will be set based on schedule by applyDefaultBlocking
        sharedDefaults.set(Date(), forKey: "intentions.widget.lastUpdate")
        sharedDefaults.synchronize()

        print("📱 WIDGET UPDATE: Cleared session data from widget")

        // Reload widget timelines
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
