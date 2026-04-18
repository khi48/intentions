// Services/ScreenTimeService.swift
// Authorization + public API surface for Screen Time. All shield-state
// transitions are delegated to ShieldEngine (see ShieldState/).

import Foundation
import Synchronization
import OSLog
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
import WidgetKit

actor ScreenTimeService: ScreenTimeManaging {

    // MARK: - Properties

    private nonisolated let logger = Logger(subsystem: "oh.Intent", category: "ScreenTimeService")
    private nonisolated let engine: ShieldEngine

    private let _isInitialized = Atomic<Bool>(false)
    private var initializationTask: Task<Void, Error>?

    // MARK: - Initialization

    init(engine: ShieldEngine = .mainApp()) {
        self.engine = engine
    }

    func initialize() async throws {
        if _isInitialized.load(ordering: .acquiring) { return }

        if let existing = initializationTask {
            try await existing.value
            return
        }

        let task = Task { [self] in try await self.performInitialize() }
        initializationTask = task

        do {
            try await task.value
        } catch {
            initializationTask = nil
            throw error
        }
    }

    private func performInitialize() async throws {
        let currentStatus = await authorizationStatus()
        let authorized = currentStatus == .approved ? true : await requestAuthorization()
        guard authorized else { throw AppError.screenTimeAuthorizationFailed }

        _isInitialized.store(true, ordering: .releasing)
        logger.info("ScreenTimeService initialized")
    }

    nonisolated var isReady: Bool { _isInitialized.load(ordering: .acquiring) }

    private func ensureInitialized() throws {
        guard _isInitialized.load(ordering: .acquiring) else {
            throw AppError.serviceUnavailable("ScreenTimeService not initialized. Call initialize() first.")
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            return await authorizationStatus() == .approved
        } catch {
            logger.error("Authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    func authorizationStatus() async -> AuthorizationStatus {
        AuthorizationCenter.shared.authorizationStatus
    }

    // MARK: - Shield-state transitions (delegated to ShieldEngine)

    func blockAllApps() async throws {
        try ensureInitialized()
        guard await authorizationStatus() == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }

        logger.notice("blockAllApps → flipDefault(.blocked)")
        engine.flipDefault(to: .blocked)
        updateWidget(blocking: true)
    }

    func allowApps(
        _ tokens: sending Set<ApplicationToken>,
        webDomains: Set<WebDomainToken> = [],
        allowWebsites: Bool = false,
        duration: TimeInterval,
        sessionId: UUID
    ) async throws {
        try ensureInitialized()
        guard await authorizationStatus() == .approved else {
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

        var selection = FamilyActivitySelection()
        selection.applicationTokens = tokens
        selection.webDomainTokens = allowWebsites ? [] : webDomains

        let endsAt = Date().addingTimeInterval(duration)
        logger.notice("allowApps → startSession(endsAt: \(endsAt, privacy: .public), id: \(sessionId.uuidString, privacy: .public))")
        engine.startSession(apps: selection, endsAt: endsAt)
        updateWidget(blocking: true)
    }

    func allowAllAccess() async throws {
        try ensureInitialized()
        guard await authorizationStatus() == .approved else {
            throw AppError.screenTimeAuthorizationFailed
        }

        logger.notice("allowAllAccess → flipDefault(.open)")
        engine.flipDefault(to: .open)
        updateWidget(blocking: false)
    }

    // MARK: - Queries (read from IntentLog)

    func getCurrentlyAllowedApps() async -> Set<ApplicationToken> {
        IntentLogStore().load().activeSession?.apps.applicationTokens ?? []
    }

    func isAppAllowed(_ token: sending ApplicationToken) async -> Bool {
        await getCurrentlyAllowedApps().contains(token)
    }

    func getEssentialSystemApps() async -> Set<ApplicationToken> { [] }

    func getStatusInfo() async -> ScreenTimeStatusInfo {
        let log = IntentLogStore().load()
        return ScreenTimeStatusInfo(
            authorizationStatus: await authorizationStatus(),
            currentlyAllowedAppsCount: log.activeSession?.apps.applicationTokens.count ?? 0,
            essentialSystemAppsCount: 0,
            hasActiveSession: log.activeSession != nil,
            isInitialized: isReady
        )
    }

    // MARK: - Lifecycle

    /// Ends any active session. Kept under its original name to preserve the
    /// ScreenTimeManaging surface; callers that used to call this for
    /// "starting a new session" can call it directly or let startSession's
    /// replace semantics handle it transparently.
    func cancelSessionTimers() async {
        logger.notice("cancelSessionTimers → endSession")
        engine.endSession()
    }

    /// Full reset: end session + apply current default. Leaves authorization
    /// state untouched so a subsequent operation does not re-prompt.
    func cleanup() async {
        logger.notice("cleanup → endSession")
        engine.endSession()
    }

    /// Foreground repair path: drains any expired session and applies the
    /// matching default config.
    func clearAllShields() async {
        logger.notice("clearAllShields → catchUpOnForeground")
        engine.catchUpOnForeground()
    }

    // MARK: - Vestigial protocol methods (no-ops)

    /// Legacy: callback mechanism for session-end. ShieldEngine owns transitions
    /// directly now; callers that need to react to state changes should observe
    /// the IntentLog or use the widget/shared-state bus instead.
    func setRestoreDefaultStateCallback(_ callback: @escaping @Sendable () async -> Void) async {}

    /// Legacy: belt-and-suspenders app-token list for category-blocking gaps.
    /// New engine shields everything-except-picked via `.all(except:)`,
    /// categories included — no secondary token list needed.
    func updateKnownAppTokens(_ tokens: Set<ApplicationToken>) async {}

    // MARK: - Widget

    private nonisolated func updateWidget(blocking: Bool) {
        let appGroupId = AppConstants.appGroupId
        if let sharedDefaults = UserDefaults(suiteName: appGroupId) {
            sharedDefaults.set(blocking, forKey: AppConstants.Keys.widgetBlockingStatus)
            sharedDefaults.set(Date(), forKey: AppConstants.Keys.widgetLastUpdate)
        }
        UserDefaults.standard.set(blocking, forKey: AppConstants.Keys.widgetBlockingStatus)
        UserDefaults.standard.set(Date(), forKey: AppConstants.Keys.widgetLastUpdate)
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: "IntentionsWidget")
    }
}
