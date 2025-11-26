//
//  SessionStatusViewModel.swift
//  Intentions
//
//  Created by Claude on 13/07/2025.
//

import Foundation
import SwiftUI
import Combine
@preconcurrency import FamilyControls
import ManagedSettings
import UserNotifications

/// ViewModel for session status display and management
/// Handles real-time session monitoring, countdown timers, and session controls
@MainActor
@Observable
final class SessionStatusViewModel: Sendable {
    
    // MARK: - Published Properties
    
    /// Whether the view is currently loading
    var isLoading: Bool = false
    
    /// Current error message to display
    var errorMessage: String? = nil
    
    /// Current active session
    private(set) var session: IntentionSession?
    
    /// Whether the session is currently active
    var isSessionActive: Bool {
        session?.isActive == true
    }
    
    /// Remaining time in seconds
    private(set) var remainingTime: TimeInterval = 0
    
    /// Elapsed time in seconds
    var elapsedTime: TimeInterval {
        guard let session = session else { return 0 }
        return session.state.totalElapsedTime
    }
    
    /// Progress percentage (0.0 to 1.0)
    var progress: Double {
        guard let session = session, session.duration > 0 else { return 0.0 }
        return min(1.0, elapsedTime / session.duration)
    }
    
    /// Formatted remaining time
    var formattedRemainingTime: String {
        formatTime(remainingTime)
    }
    
    /// Formatted elapsed time
    var formattedElapsedTime: String {
        formatTime(elapsedTime)
    }
    
    /// Formatted total duration
    var formattedTotalDuration: String {
        guard let session = session else { return "0m" }
        return formatTime(session.duration)
    }
    
    /// Whether session is in warning state (< 5 minutes remaining)
    var isInWarningState: Bool {
        remainingTime <= AppConstants.Session.warningThreshold
    }
    
    /// Whether session is in critical state (< 1 minute remaining)
    var isInCriticalState: Bool {
        remainingTime <= AppConstants.Session.criticalThreshold
    }
    
    /// Current session phase
    var sessionPhase: SessionPhase {
        guard isSessionActive else { return .inactive }
        
        if isInCriticalState {
            return .critical
        } else if isInWarningState {
            return .warning
        } else if progress < 0.5 {
            return .early
        } else {
            return .active
        }
    }
    
    /// App groups associated with current session
    private(set) var sessionAppGroups: [AppGroup] = []
    
    /// Individual apps associated with current session
    private(set) var sessionApps: [DiscoveredApp] = []

    /// Application tokens from the session (for direct display)
    private(set) var sessionTokens: [ApplicationToken] = []

    /// Quick action associated with the session (if it's a quick action session)
    private(set) var associatedQuickAction: QuickAction?
    
    /// Whether showing session controls
    var showingControls: Bool = false
    
    /// Whether showing extend session dialog
    var showingExtendDialog: Bool = false
    
    /// Extension time options (in minutes)
    let extensionOptions: [Int] = [5, 10, 15, 30]
    
    /// Selected extension time
    var selectedExtensionTime: Int = 15
    
    // MARK: - Dependencies

    private let dataService: DataPersisting
    private let screenTimeService: ScreenTimeManaging
    private let contentViewModel: ContentViewModel
    private let notificationService: NotificationService
    
    // MARK: - Timer
    
    nonisolated(unsafe) private var timer: Timer?
    
    // MARK: - Callbacks (Legacy - will be removed)
    
    var onSessionExpired: (() async -> Void)?
    var onSessionExtended: ((TimeInterval) async -> Void)?
    var onSessionEnded: (() async -> Void)?
    
    // MARK: - Initialization
    
    init(
        session: IntentionSession? = nil,
        contentViewModel: ContentViewModel,
        dataService: DataPersisting? = nil,
        screenTimeService: ScreenTimeManaging? = nil,
        notificationService: NotificationService? = nil
    ) {
        self.session = session
        self.contentViewModel = contentViewModel
        self.dataService = dataService ?? contentViewModel.dataServiceProvider
        self.screenTimeService = screenTimeService ?? contentViewModel.screenTimeService
        self.notificationService = notificationService ?? NotificationService.shared

        if let session = session {
            updateRemainingTime()
            startTimer()

            // Load session data (app groups, tokens, quick action) on initialization
            Task {
                await self.loadSessionData()
                await self.loadAssociatedQuickAction()
                // TEMPORARILY DISABLED: Testing if notifications cause SpringBoard crash
                // await self.notificationService.scheduleSessionNotifications(for: session)
            }
        }
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Session Management
    
    /// Update the current session
    func updateSession(_ newSession: IntentionSession?) {
        let wasActive = isSessionActive
        session = newSession

        if let session = newSession, session.isActive {
            updateRemainingTime()
            if !wasActive {
                startTimer()

                // TEMPORARILY DISABLED: Testing if notifications cause SpringBoard crash
                // Schedule notifications for new session
                // Task {
                //     await notificationService.scheduleSessionNotifications(for: session)
                // }
            }

            Task {
                await loadSessionData()
                await loadAssociatedQuickAction()
            }
        } else {
            stopTimer()
            remainingTime = 0
            sessionAppGroups = []
            sessionApps = []

            // Cancel notifications when session ends
            Task {
                await notificationService.cancelSessionNotifications()
            }
        }
    }
    
    /// Extend the current session
    func extendSession(by minutes: Int) async {
        guard let currentSession = session, currentSession.isActive else {
            return
        }

        let extensionTime = TimeInterval(minutes * 60)
        
        await withLoading {
            do {
                // Create extended session by modifying current session
                let extendedSession = currentSession
                extendedSession.duration += extensionTime

                try await dataService.saveIntentionSession(extendedSession)
                session = extendedSession
                updateRemainingTime()

                // TEMPORARILY DISABLED: Testing if notifications cause SpringBoard crash
                // Reschedule notifications for extended session
                // await notificationService.scheduleSessionNotifications(for: extendedSession)

                await onSessionExtended?(extensionTime)

                // Close dialog
                showingExtendDialog = false
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// End the current session early
    func endSession() async {
        guard let currentSession = session, currentSession.isActive else { return }
        
        await withLoading {
            do {
                // End current session
                currentSession.complete()
                let endedSession = currentSession
                
                try await dataService.saveIntentionSession(endedSession)
                session = endedSession
                stopTimer()

                // Cancel any pending notifications
                await notificationService.cancelSessionNotifications()

                // Directly call ContentViewModel to handle blocking logic
                await contentViewModel.endCurrentSession()

                // Keep legacy callback for backward compatibility during transition
                await onSessionEnded?()
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    // MARK: - UI Actions
    
    /// Toggle session controls visibility
    func toggleControls() {
        showingControls.toggle()
    }
    
    /// Show extend session dialog
    func showExtendDialog() {
        showingExtendDialog = true
        showingControls = false
    }
    
    /// Cancel extend dialog
    func cancelExtendDialog() {
        showingExtendDialog = false
    }
    
    // MARK: - Data Loading
    
    private func loadSessionData() async {
        guard let session = session else {
            return
        }

        do {
            // Load app groups for this session
            let allGroups = try await dataService.loadAppGroups()
            sessionAppGroups = allGroups.filter { group in
                session.requestedAppGroups.contains(group.id)
            }

            // Store the ApplicationTokens directly - no need to convert
            sessionTokens = Array(session.requestedApplications)

            // For now, create simple placeholder DiscoveredApps for backward compatibility
            var allSessionApps: [DiscoveredApp] = []
            for (index, token) in session.requestedApplications.enumerated() {
                let discoveredApp = DiscoveredApp(
                    displayName: "App \(index + 1)", // Placeholder name - in real app this would come from the app metadata
                    bundleIdentifier: "com.app\(index + 1).bundle", // Placeholder - would be real bundle ID
                    token: token,
                    category: "Allowed"
                )
                allSessionApps.append(discoveredApp)
            }

            sessionApps = allSessionApps

        } catch {
            print("❌ Failed to load session data: \(error)")
        }
    }
    



    
    // MARK: - Timer Management
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRemainingTime()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateRemainingTime() {
        guard let session = session, session.isActive else {
            remainingTime = 0
            return
        }

        remainingTime = session.remainingTime

        // Check if session expired
        if remainingTime <= 0 {
            stopTimer()
            Task {
                // End the session via manual UI timer expiration
                // This will complete the session, clear state, and re-block apps
                print("⏰ UI TIMER: Session expired - ending session via UI timer")
                await contentViewModel.endCurrentSession()

                // Keep legacy callback for backward compatibility during transition
                await onSessionExpired?()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = Int(timeInterval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
    
    private func withLoading<T: Sendable>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
    
    // MARK: - Error Handling
    
    func handleError(_ error: Error) async {
        if let appError = error as? AppError {
            errorMessage = appError.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func clearError() {
        errorMessage = nil
    }

    private func loadAssociatedQuickAction() async {
        guard let session = session else {
            associatedQuickAction = nil
            return
        }

        guard case .quickAction(let quickAction) = session.source else {
            associatedQuickAction = nil
            return
        }

        // Quick action is now stored directly on the session - no lookup needed!
        associatedQuickAction = quickAction
    }
}

// MARK: - SessionPhase

enum SessionPhase: String, CaseIterable, Sendable {
    case inactive = "inactive"
    case early = "early"
    case active = "active"
    case warning = "warning"
    case critical = "critical"
    
    var color: Color {
        switch self {
        case .inactive:
            return .gray
        case .early:
            return .green
        case .active:
            return .blue
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
    
    var description: String {
        switch self {
        case .inactive:
            return "No active session"
        case .early:
            return "Session starting"
        case .active:
            return "Session active"
        case .warning:
            return "Session ending soon"
        case .critical:
            return "Session ending very soon"
        }
    }
}

// MARK: - Constants Extension

extension AppConstants.Session {
    static let warningThreshold: TimeInterval = 5 * 60 // 5 minutes
    static let criticalThreshold: TimeInterval = 1 * 60 // 1 minute
}
