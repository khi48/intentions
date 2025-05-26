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
    
    // MARK: - Timer
    
    nonisolated(unsafe) private var timer: Timer?
    
    // MARK: - Callbacks
    
    var onSessionExpired: (() async -> Void)?
    var onSessionExtended: ((TimeInterval) async -> Void)?
    var onSessionEnded: (() async -> Void)?
    
    // MARK: - Initialization
    
    init(
        session: IntentionSession? = nil,
        dataService: DataPersisting = MockDataPersistenceService(),
        screenTimeService: ScreenTimeManaging = MockScreenTimeService()
    ) {
        self.session = session
        self.dataService = dataService
        self.screenTimeService = screenTimeService
        
        if let session = session {
            updateRemainingTime()
            startTimer()
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
            }
            
            Task {
                await loadSessionData()
            }
        } else {
            stopTimer()
            remainingTime = 0
            sessionAppGroups = []
            sessionApps = []
        }
    }
    
    /// Extend the current session
    func extendSession(by minutes: Int) async {
        guard let currentSession = session, currentSession.isActive else { return }
        
        let extensionTime = TimeInterval(minutes * 60)
        
        await withLoading {
            do {
                // Create extended session by modifying current session
                let extendedSession = currentSession
                extendedSession.duration += extensionTime
                
                try await dataService.saveIntentionSession(extendedSession)
                session = extendedSession
                updateRemainingTime()
                
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
        guard let session = session else { return }
        
        do {
            // Load app groups for this session
            let allGroups = try await dataService.loadAppGroups()
            sessionAppGroups = allGroups.filter { group in
                session.requestedAppGroups.contains(group.id)
            }
            
            // Generate mock apps for individual selections
            sessionApps = generateMockAppsForTokens(session.requestedApplications)
            
        } catch {
            print("Failed to load session data: \(error)")
        }
    }
    
    private func generateMockAppsForTokens(_ tokens: Set<ApplicationToken>) -> [DiscoveredApp] {
        // For development, create mock discovered apps
        return tokens.enumerated().compactMap { (index, token) in
            DiscoveredApp(
                displayName: "App \(index + 1)",
                bundleIdentifier: "com.app\(index + 1).bundle",
                token: token,
                category: "Productivity"
            )
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
                await onSessionExpired?()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = Int(timeInterval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
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