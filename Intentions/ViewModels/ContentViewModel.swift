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
    
    /// Current schedule settings
    private var scheduleSettings: ScheduleSettings = ScheduleSettings()
    
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
            authorizationStatus = await screenTimeService.authorizationStatus()

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

            await loadScheduleSettings()
            await loadActiveSession()
            await checkSetupRequired()
        }
        hasInitialized = true
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

            // CRITICAL: Also save to UserDefaults so DeviceActivityMonitor extension can access it
            saveScheduleSettingsToUserDefaults(scheduleSettings)
        } catch {
            logger.warning("Failed to load schedule settings, using defaults: \(error.localizedDescription)")
            scheduleSettings = ScheduleSettings()
            saveScheduleSettingsToUserDefaults(scheduleSettings)
        }
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
    
    /// Update schedule settings and apply blocking accordingly
    func updateScheduleSettings(_ newSettings: ScheduleSettings) async {
        scheduleSettings = newSettings

        // Save to persistence
        do {
            try await dataService.saveScheduleSettings(newSettings)
        } catch {
            logger.error("Failed to save schedule settings: \(error.localizedDescription)")
            handleError(error)
        }

        // Also save to UserDefaults for DeviceActivityMonitor extension
        saveScheduleSettingsToUserDefaults(newSettings)

        // Apply blocking based on new schedule
        if authorizationStatus == .approved {
            await applyDefaultBlocking()
        }
    }

    /// Save schedule settings to UserDefaults for DeviceActivityMonitor extension
    private func saveScheduleSettingsToUserDefaults(_ settings: ScheduleSettings) {
        guard let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) else { return }

        sharedDefaults.set(settings.isEnabled, forKey: AppConstants.Keys.scheduleIsEnabled)
        sharedDefaults.set(settings.startHour, forKey: AppConstants.Keys.scheduleStartHour)
        sharedDefaults.set(settings.startMinute, forKey: AppConstants.Keys.scheduleStartMinute)
        sharedDefaults.set(settings.endHour, forKey: AppConstants.Keys.scheduleEndHour)
        sharedDefaults.set(settings.endMinute, forKey: AppConstants.Keys.scheduleEndMinute)
        sharedDefaults.set(settings.activeDays.map { $0.calendarWeekday }, forKey: AppConstants.Keys.scheduleActiveDays)
        sharedDefaults.synchronize()
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
    
    /// Start a new intention session
    func startSession(_ session: IntentionSession) async {
        await withLoading {
            do {
                // If there's an existing active session, cancel its timers and complete it
                if let existingSession = activeSession, existingSession.isActive {
                    await screenTimeService.cancelSessionTimers()
                    existingSession.complete()
                    try await dataService.saveIntentionSession(existingSession)
                    activeSession = nil
                    currentlyAppliedSessionId = nil
                    try await screenTimeService.blockAllApps()
                }

                try await dataService.saveIntentionSession(session)
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
        guard let session = activeSession else { return }

        await withLoading {
            do {
                session.complete()
                try await dataService.saveIntentionSession(session)
                activeSession = nil
                currentlyAppliedSessionId = nil

                if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
                    sharedDefaults.removeObject(forKey: AppConstants.Keys.currentSessionId)
                    sharedDefaults.synchronize()
                }

                await NotificationService.shared.cancelSessionNotifications()
                clearWidgetSessionData()
                await applyDefaultBlocking()
            } catch {
                handleError(error)
            }
        }
    }

    /// Handle automatic session expiration (called by ScreenTimeService background task)
    private func handleSessionExpiration() async {
        guard let session = activeSession else { return }

        do {
            session.complete()
            try await dataService.saveIntentionSession(session)
            activeSession = nil
            currentlyAppliedSessionId = nil

            if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
                sharedDefaults.removeObject(forKey: AppConstants.Keys.currentSessionId)
                sharedDefaults.synchronize()
            }

            await NotificationService.shared.cancelSessionNotifications()
            clearWidgetSessionData()
            await applyDefaultBlocking()
            await NotificationService.shared.sendSessionExpiredNotification()
        } catch {
            logger.error("Error completing expired session: \(error.localizedDescription)")
            await applyDefaultBlocking()
        }
    }

    /// Extend the current session by additional time
    func extendCurrentSession(by extensionTime: TimeInterval) async {
        guard let session = activeSession, session.isActive else { return }

        await withLoading {
            do {
                // Extend the session duration
                session.duration += extensionTime
                try await dataService.saveIntentionSession(session)

                // Re-apply blocking with the new remaining time so the
                // ScreenTimeService timer and DeviceActivity schedule update
                currentlyAppliedSessionId = nil // Force re-application
                await applySessionBlocking(for: session)

                // Reschedule notifications for the new remaining time
                await NotificationService.shared.cancelSessionNotifications()
                await NotificationService.shared.scheduleSessionNotifications(for: session)

                updateWidgetSessionData(session)
            } catch {
                handleError(error)
            }
        }
    }
    
    /// Clean up stale sessions and ManagedSettingsStore before applying blocking
    private func cleanupOldSessionsBeforeBlocking() async {
        do {
            let allSessions = try await dataService.loadIntentionSessions()

            // Complete stale active sessions
            let staleSessions = allSessions.filter { $0.isActive && $0.id != activeSession?.id }
            for staleSession in staleSessions {
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
    
    /// Apply default blocking state based on schedule settings
    /// If a session is active, preserves session blocking
    private func applyDefaultBlocking() async {
        guard !isApplyingDefaultBlocking else { return }
        guard screenTimeService.isReady else { return }

        isApplyingDefaultBlocking = true
        defer { isApplyingDefaultBlocking = false }

        do {
            // Preserve active session blocking
            if let activeSession = activeSession, activeSession.isActive {
                await applySessionBlocking(for: activeSession)
                return
            }

            currentlyAppliedSessionId = nil

            // Block or allow based on schedule
            if scheduleSettings.isEnabled && scheduleSettings.isCurrentlyActive {
                try await screenTimeService.blockAllApps()
            } else {
                try await screenTimeService.allowAllAccess()
            }
        } catch {
            logger.error("Failed to apply default blocking: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Setup

    /// Check if setup flow is required
    private func checkSetupRequired() async {
        // Validate setup state using the coordinator (pass cached auth status to avoid redundant check)
        await setupCoordinator.validateSetupRequirements(cachedAuthStatus: authorizationStatus)

        // Only show setup flow when setup is genuinely incomplete (not just version-outdated),
        // and there's no active session
        let setupState = setupCoordinator.setupState
        let needsSetup = setupState?.isSetupSufficient != true && activeSession == nil

        if needsSetup {
            showingSetupFlow = true
        } else {
            // Setup is complete - initialize ScreenTimeService if needed
            await initializeScreenTimeServiceAfterSetup()
        }
    }
    
    /// Save the user's intention quote from the setup flow
    func setIntentionQuote(_ quote: String) {
        scheduleSettings.intentionQuote = quote
        Task {
            do {
                try await dataService.saveScheduleSettings(scheduleSettings)
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
        sharedDefaults.set(scheduleSettings.isEnabled && scheduleSettings.isCurrentlyActive, forKey: AppConstants.Keys.widgetBlockingStatus)
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
