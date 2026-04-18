// Services/ScreenTimeService.swift
// Core Screen Time Service Implementation

import Foundation
import Synchronization
import OSLog
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@preconcurrency import DeviceActivity
import WidgetKit

/// Implementation of Screen Time management using Apple's Family Controls framework
/// Uses actor isolation for thread safety without blocking the main thread
actor ScreenTimeService: ScreenTimeManaging {

    // MARK: - Properties

    /// Logger for Console.app debugging
    private nonisolated let logger = Logger(subsystem: "oh.Intent", category: "ScreenTimeService")

    /// The managed settings store for applying restrictions
    private let managedSettingsStore = ManagedSettingsStore()
    
    /// Currently allowed applications - protected by actor isolation
    private var currentlyAllowedApps: Set<ApplicationToken> = []
    
    /// Timer for tracking session expiration - protected by actor isolation
    private var sessionExpirationTask: Task<Void, Never>?

    /// Flag to prevent callbacks from executing when session is being replaced
    private var isSessionBeingReplaced: Bool = false

    /// DeviceActivity center for scheduling background expiration
    private let deviceActivityCenter = DeviceActivityCenter()

    /// Currently active DeviceActivity name (for cancellation)
    private var activeDeviceActivityName: DeviceActivityName?

    /// Essential system apps that should never be blocked
    private var essentialSystemApps: Set<ApplicationToken> = []

    /// All app tokens the user has ever selected across QuickActions.
    /// Used as a belt-and-suspenders layer: `shield.applications` catches apps that
    /// slip through category-based blocking (`.all()` has known gaps).
    private var knownAppTokens: Set<ApplicationToken> = []
    
    /// Track initialization state. Uses Atomic for safe nonisolated reads.
    private let _isInitialized = Atomic<Bool>(false)

    /// Single-flight task for initialize(). Prevents reentrancy races when multiple
    /// concurrent callers enter initialize() and both suspend on await authorizationStatus().
    /// Once set, subsequent callers await the same task instead of starting a new one.
    private var initializationTask: Task<Void, Error>?

    /// Callback to restore proper default state when session ends
    private var restoreDefaultStateCallback: (@Sendable () async -> Void)?

    // MARK: - Initialization

    init() {
        // Clean initialization - no async work
        // Call initialize() after creating the service
    }

    // Note: No deinit needed. sessionExpirationTask uses [weak self] and will
    // clean up naturally. ManagedSettingsStore settings should persist across
    // service lifecycle since the app keeps blocking active by default.

    /// Initialize the service without applying any blocking
    /// Must be called after creating the service before any other operations
    /// Blocking should be applied separately based on schedule settings
    ///
    /// Uses a single-flight Task pattern to prevent reentrancy: if called
    /// concurrently, all callers await the same underlying initialization task.
    func initialize() async throws {
        if _isInitialized.load(ordering: .acquiring) { return }

        // If initialization is already in progress, await the existing task
        if let existingTask = initializationTask {
            try await existingTask.value
            return
        }

        // Start a new initialization task and store it before awaiting so that
        // subsequent concurrent callers reuse it instead of starting their own.
        let task = Task { [self] in
            try await self.performInitialize()
        }
        initializationTask = task

        do {
            try await task.value
        } catch {
            // Clear the failed task so initialization can be retried
            initializationTask = nil
            throw error
        }
    }

    /// Performs the actual initialization work. Callers must go through initialize()
    /// to ensure single-flight semantics.
    private func performInitialize() async throws {
        // Check current authorization status first
        let currentStatus = await authorizationStatus()

        let authorized: Bool
        if currentStatus == .approved {
            // Already authorized - no need to request again
            authorized = true
        } else {
            // Need to request authorization
            authorized = await requestAuthorization()
        }

        guard authorized else {
            throw AppError.screenTimeAuthorizationFailed
        }

        // Mark as initialized - blocking will be applied separately by ContentViewModel
        _isInitialized.store(true, ordering: .releasing)
        logger.info("ScreenTimeService initialized successfully")
    }
    
    /// Check if the service has been properly initialized
    nonisolated var isReady: Bool {
        _isInitialized.load(ordering: .acquiring)
    }

    /// Ensure service is initialized before performing operations
    private func ensureInitialized() throws {
        guard _isInitialized.load(ordering: .acquiring) else {
            throw AppError.serviceUnavailable("ScreenTimeService not initialized. Call initialize() first.")
        }
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        do {
            // Access AuthorizationCenter directly in async context
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            let status = await authorizationStatus()
            return status == .approved
        } catch {
            logger.error("Authorization failed: \(error.localizedDescription)")
            return false
        }
    }
    
    func authorizationStatus() async -> AuthorizationStatus {
        // Access authorization status safely
        return AuthorizationCenter.shared.authorizationStatus
    }
    
    // MARK: - App Management
    
    /// Block all apps by default - core concept of Intentions app
    /// Uses comprehensive blocking: category-based blocking + web content blocking
    /// This is the DEFAULT STATE when no session is active during protected hours
    func blockAllApps() async throws {
        try ensureInitialized()

        let status = await authorizationStatus()
        guard status == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }

        logger.notice("🚫 BLOCK ALL: Starting comprehensive default blocking")

        // CRITICAL: Update widget FIRST, before clearing shields
        // This prevents the widget from reading "no blocking" state during the clear/reblock window
        logger.info("🚫 BLOCK ALL: Step 0 - Updating widget to 'Blocked' BEFORE clearing shields")
        updateWidgetBlockingStatus(isBlocking: true)

        // Clear allowed apps tracking - nothing is allowed initially
        currentlyAllowedApps.removeAll()

        // Cancel any existing session expiration
        sessionExpirationTask?.cancel()
        sessionExpirationTask = nil

        // Cancel any DeviceActivity schedule
        cancelDeviceActivitySchedule()

        // Per project_stale_shield_state.md: a previous session's
        // `.all(except: tokens)` can persist in the system cache, causing a fresh
        // `.all()` to silently fail to re-block the previously-allowed apps. Nil
        // each shield key first and then flush with clearAllSettings() before
        // re-applying blocking. The brief "no shields" window is a smaller
        // regression than the cache-staleness failure this protects against.
        logger.info("🚫 BLOCK ALL: Flushing stale shield state before re-applying")
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.shield.webDomainCategories = nil
        managedSettingsStore.webContent.blockedByFilter = nil
        managedSettingsStore.clearAllSettings()

        logger.info("🚫 BLOCK ALL: Applying blocking (categories + known tokens + web)")
        managedSettingsStore.shield.applications = knownAppTokens.isEmpty ? nil : knownAppTokens
        managedSettingsStore.shield.applicationCategories = .all()
        managedSettingsStore.webContent.blockedByFilter = .all()

        logger.notice("✅ BLOCK ALL: Blocking applied (categories + \(self.knownAppTokens.count) known tokens + web)")
    }
    
    /// Get all discoverable applications for comprehensive blocking
    /// In production, this would use stored FamilyActivityPicker selections
    private func getAllDiscoverableApplications() -> Set<ApplicationToken> {
        // For default-block-all approach, we'll use category-based blocking instead
        // Individual app tokens are device-specific and can't be pre-determined
        return Set<ApplicationToken>()
    }
    
    func allowApps(_ tokens: sending Set<ApplicationToken>, webDomains: Set<WebDomainToken> = [], allowWebsites: Bool = false, duration: TimeInterval, sessionId: UUID) async throws {
        try ensureInitialized()

        let status = await authorizationStatus()
        guard status == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }

        guard duration >= AppConstants.Session.minimumDuration else {
            throw AppError.validationFailed("duration", reason: "Must be at least \(AppConstants.Session.minimumDuration.formattedDuration)")
        }

        guard duration <= AppConstants.Session.maximumDuration else {
            throw AppError.validationFailed("duration", reason: "Cannot exceed \(AppConstants.Session.maximumDuration.formattedDuration)")
        }

        guard !tokens.isEmpty else {
            throw AppError.validationFailed("applications", reason: "At least one application must be specified")
        }

        // Accumulate newly seen tokens for blockAllApps() to use later
        knownAppTokens.formUnion(tokens)

        // Overwrite shield properties directly — no clearAllSettings().
        // Direct overwrites replace the previous value atomically and preserve
        // the ShieldConfiguration extension binding. clearAllSettings() creates
        // a brief "no shields" window that detaches the extension, causing the
        // default iOS shield to appear instead of our custom one.
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = .all(except: tokens)
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.shield.webDomainCategories = nil

        // Web content blocking
        if allowWebsites {
            managedSettingsStore.webContent.blockedByFilter = nil
        } else if !webDomains.isEmpty {
            managedSettingsStore.shield.webDomainCategories = .all(except: webDomains)
            managedSettingsStore.webContent.blockedByFilter = .all()
        } else {
            managedSettingsStore.webContent.blockedByFilter = .all()
        }

        // Update tracking
        currentlyAllowedApps = tokens

        // Cancel any existing expiration task
        if sessionExpirationTask != nil {
            sessionExpirationTask?.cancel()
            sessionExpirationTask = nil
        }

        do {
            try await scheduleDeviceActivityExpiration(duration: duration, sessionId: sessionId)
        } catch {
            logger.error("DeviceActivity scheduling failed: \(error.localizedDescription)")
            throw AppError.appBlockingFailed("Failed to schedule expiration: \(error.localizedDescription)")
        }

        // Keep in-app timer for immediate handling
        sessionExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: duration.nanoseconds)

                guard !Task.isCancelled else { return }
                guard let self = self else { return }

                let isReplacing = await self.isSessionBeingReplaced
                guard !isReplacing else { return }

                // Restore the original state
                if let callback = await self.restoreDefaultStateCallback {
                    await callback()
                } else {
                    try? await self.blockAllApps()
                }
            } catch {
                return
            }
        }

        // Clear the session replacement flag
        isSessionBeingReplaced = false

    }

    func getCurrentlyAllowedApps() async -> Set<ApplicationToken> {
        return currentlyAllowedApps
    }
    
    func allowAllAccess() async throws {
        try ensureInitialized()

        let status = await authorizationStatus()
        guard status == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }

        logger.notice("🧹 ALLOW ALL ACCESS: Clearing all shields and restrictions")

        // Cancel session expiration task
        sessionExpirationTask?.cancel()
        sessionExpirationTask = nil

        // Cancel any DeviceActivity schedule
        cancelDeviceActivitySchedule()

        // Clear tracking
        currentlyAllowedApps.removeAll()

        // clearAllSettings() alone doesn't reliably clear shield.applicationCategories
        // when it was set to .all(except:). Explicitly nil out all shield properties.
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.shield.webDomainCategories = nil
        managedSettingsStore.webContent.blockedByFilter = nil
        managedSettingsStore.clearAllSettings()
        updateWidgetBlockingStatus(isBlocking: false)

        logger.notice("✅ ALLOW ALL ACCESS: All shields cleared, widget updated to unblocked")
    }
    
    /// Clean up all resources and reset service state
    func cleanup() async {
        logger.notice("🧹 CLEANUP: Clearing all settings during cleanup")

        // Cancel any running tasks
        sessionExpirationTask?.cancel()
        sessionExpirationTask = nil

        // Cancel any DeviceActivity schedule
        cancelDeviceActivitySchedule()

        // Clear current state tracking
        currentlyAllowedApps.removeAll()

        // Standard clear all settings
        managedSettingsStore.clearAllSettings()

        // Explicitly clear specific shield types
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.shield.webDomainCategories = nil
        managedSettingsStore.webContent.blockedByFilter = nil
        managedSettingsStore.application.denyAppInstallation = nil
        managedSettingsStore.application.denyAppRemoval = nil
        managedSettingsStore.gameCenter.denyMultiplayerGaming = nil
        managedSettingsStore.gameCenter.denyAddingFriends = nil
    }
    
    func isAppAllowed(_ token: sending ApplicationToken) async -> Bool {
        return currentlyAllowedApps.contains(token) || essentialSystemApps.contains(token)
    }
    
    func getEssentialSystemApps() async -> Set<ApplicationToken> {
        return essentialSystemApps
    }
    
    // MARK: - Helper Methods
    
    /// Add essential system apps to the allowlist
    /// This should be called during app discovery to populate system apps
    func addEssentialSystemApp(_ token: sending ApplicationToken) async {
        essentialSystemApps.insert(token)
    }
    
    
    /// Set callback to restore default state when sessions end
    func setRestoreDefaultStateCallback(_ callback: @escaping @Sendable () async -> Void) async {
        restoreDefaultStateCallback = callback
    }

    /// Cancel session timers without triggering re-blocking
    /// Used when starting a new session to prevent the old session's timer from firing
    func cancelSessionTimers() async {
        // Set flag to prevent any in-flight callbacks from executing
        isSessionBeingReplaced = true

        // Cancel in-app timer
        if sessionExpirationTask != nil {
            sessionExpirationTask?.cancel()
            sessionExpirationTask = nil
        }

        // Cancel DeviceActivity schedule
        cancelDeviceActivitySchedule()

        // CRITICAL: Clear the current session ID from UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
            sharedDefaults.removeObject(forKey: AppConstants.Keys.currentSessionId)
            sharedDefaults.synchronize()
        }
    }

    func updateKnownAppTokens(_ tokens: Set<ApplicationToken>) async {
        knownAppTokens.formUnion(tokens)
    }

    /// Remove all system apps (for testing/reset purposes)
    func clearEssentialSystemApps() async {
        essentialSystemApps.removeAll()
    }

    /// Clear all shield-related ManagedSettings entries from the main app
    /// process so the springboard re-renders. Per the note in
    /// `project_stale_shield_state.md`, always call `clearAllSettings()`
    /// before setting individual keys to nil — the cache can otherwise stay
    /// stale. Does not touch DeviceActivity schedules; caller owns the
    /// session lifecycle.
    func clearAllShields() async {
        logger.notice("🧹 CLEAR ALL SHIELDS: flushing store from main app process")
        managedSettingsStore.clearAllSettings()
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.shield.webDomainCategories = nil
        managedSettingsStore.webContent.blockedByFilter = nil
        currentlyAllowedApps.removeAll()
        updateWidgetBlockingStatus(isBlocking: false)
    }
    
    /// Get detailed status information for debugging
    func getStatusInfo() async -> ScreenTimeStatusInfo {
        let status = await authorizationStatus()
        return ScreenTimeStatusInfo(
            authorizationStatus: status,
            currentlyAllowedAppsCount: currentlyAllowedApps.count,
            essentialSystemAppsCount: essentialSystemApps.count,
            hasActiveSession: sessionExpirationTask != nil,
            isInitialized: isReady
        )
    }
    
    
    // MARK: - DeviceActivity Scheduling

    /// Schedule a DeviceActivity interval that will trigger the monitor extension when the session expires
    /// This ensures blocking is restored even if the app isn't running
    ///
    /// **Strategy**: Uses a combination of intervalDidEnd AND a threshold event to work around iOS limitations:
    /// - For long sessions (≥15 min): intervalDidEnd works reliably
    /// - For short sessions (<15 min): threshold event triggers at exact expiration time
    /// - This dual approach ensures the extension fires regardless of session duration
    ///
    /// - Parameter duration: Session duration in seconds
    /// - Parameter sessionId: UUID of the session being scheduled
    private func scheduleDeviceActivityExpiration(duration: TimeInterval, sessionId: UUID) async throws {
        // Cancel any existing DeviceActivity FIRST
        if let oldActivityName = activeDeviceActivityName {
            deviceActivityCenter.stopMonitoring([oldActivityName])
            activeDeviceActivityName = nil
        }

        // Create a unique activity name for this session
        let activityName = DeviceActivityName("intentions.session.\(sessionId.uuidString)")
        activeDeviceActivityName = activityName

        // Calculate start and end times
        let now = Date()
        let endDate = now.addingTimeInterval(duration)

        // Create date components for the schedule
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let startComponents = calendar.dateComponents(components, from: now)

        // Use extended end to avoid intervalTooShort
        let scheduledEndDate = now.addingTimeInterval(max(duration, 15 * 60) + 60)
        let endComponents = calendar.dateComponents(components, from: scheduledEndDate)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        // Create threshold event for exact expiration
        let thresholdComponents = DateComponents(second: Int(duration))
        let thresholdEventName = DeviceActivityEvent.Name("intentions.session.threshold")

        let event = DeviceActivityEvent(
            applications: Set<ApplicationToken>(),
            categories: Set<ActivityCategoryToken>(),
            webDomains: Set<WebDomainToken>(),
            threshold: thresholdComponents
        )

        let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [thresholdEventName: event]

        do {
            try deviceActivityCenter.startMonitoring(activityName, during: schedule, events: events)

            // Write to shared UserDefaults for extension
            if let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId) {
                sharedDefaults.set(activityName.rawValue, forKey: AppConstants.Keys.lastScheduledActivity)
                sharedDefaults.set(endDate, forKey: AppConstants.Keys.lastScheduledEndTime)
                sharedDefaults.set(Date(), forKey: AppConstants.Keys.lastScheduleTime)
                sharedDefaults.set(duration, forKey: AppConstants.Keys.lastScheduledDuration)
                sharedDefaults.set(sessionId.uuidString, forKey: AppConstants.Keys.currentSessionId)
                sharedDefaults.synchronize()
            }
        } catch {
            logger.error("DeviceActivity scheduling failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Cancel the active DeviceActivity schedule
    private func cancelDeviceActivitySchedule() {
        if let activityName = activeDeviceActivityName {
            deviceActivityCenter.stopMonitoring([activityName])
            activeDeviceActivityName = nil
        }
    }

    // MARK: - Widget Data Sharing

    /// Update widget with current blocking status
    private func updateWidgetBlockingStatus(isBlocking: Bool) {
        let appGroupId = AppConstants.appGroupId

        guard let sharedDefaults = UserDefaults(suiteName: appGroupId) else {
            // Fallback to standard UserDefaults only
            UserDefaults.standard.set(isBlocking, forKey: AppConstants.Keys.widgetBlockingStatus)
            UserDefaults.standard.set(Date(), forKey: AppConstants.Keys.widgetLastUpdate)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        // Set the data
        sharedDefaults.set(isBlocking, forKey: AppConstants.Keys.widgetBlockingStatus)
        sharedDefaults.set(Date(), forKey: AppConstants.Keys.widgetLastUpdate)
        sharedDefaults.synchronize()

        // Also set in standard UserDefaults as fallback
        UserDefaults.standard.set(isBlocking, forKey: AppConstants.Keys.widgetBlockingStatus)
        UserDefaults.standard.set(Date(), forKey: AppConstants.Keys.widgetLastUpdate)

        // Force widget timeline refresh
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: "IntentionsWidget")
    }

}
