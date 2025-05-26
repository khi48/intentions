//
//  HomeViewModel.swift
//  Intentions
//
//  Created by Claude on 13/07/2025.
//

import Foundation
import SwiftUI
@preconcurrency import FamilyControls
import ManagedSettings

/// ViewModel for the main home view
/// Manages current session status, quick actions, and session controls
@MainActor
@Observable
final class HomeViewModel: Sendable {
    
    // MARK: - Published Properties
    
    /// Whether the view is currently loading
    var isLoading: Bool = false
    
    /// Current error message to display
    var errorMessage: String? = nil
    
    /// Current active session if any
    private(set) var activeSession: IntentionSession? = nil
    
    /// Whether user can start a new session
    var canStartSession: Bool {
        !isLoading && activeSession == nil && authorizationStatus == .approved
    }
    
    /// Whether user can end current session
    var canEndSession: Bool {
        !isLoading && activeSession != nil
    }
    
    /// Current Screen Time authorization status
    private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    
    /// Quick action app groups for easy session creation
    private(set) var quickActionGroups: [AppGroup] = []
    
    /// Recent sessions for history display
    private(set) var recentSessions: [IntentionSession] = []
    
    /// Today's session statistics
    private(set) var todayStats: SessionStatistics = SessionStatistics()
    
    /// Remaining time in current session (in seconds)
    var remainingTime: TimeInterval {
        guard let session = activeSession, session.isActive else { return 0 }
        return session.remainingTime
    }
    
    /// Progress percentage of current session (0.0 to 1.0)
    var sessionProgress: Double {
        guard let session = activeSession, session.isActive else { return 0.0 }
        return session.progressPercentage
    }
    
    /// Formatted remaining time string
    var formattedRemainingTime: String {
        let time = remainingTime
        if time >= 3600 {
            let hours = Int(time) / 3600
            let minutes = (Int(time) % 3600) / 60
            return "\(hours)h \(minutes)m"
        } else {
            let minutes = Int(time) / 60
            return "\(minutes)m"
        }
    }
    
    // MARK: - Dependencies
    
    private let dataService: DataPersisting
    private let screenTimeService: ScreenTimeManaging
    
    // MARK: - Callbacks
    
    var onSessionStart: ((IntentionSession) async -> Void)?
    var onSessionEnd: (() async -> Void)?
    var onShowIntentionPrompt: (() -> Void)?
    
    // MARK: - Initialization
    
    init(
        dataService: DataPersisting = MockDataPersistenceService(),
        screenTimeService: ScreenTimeManaging = MockScreenTimeService()
    ) {
        self.dataService = dataService
        self.screenTimeService = screenTimeService
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        await withLoading {
            do {
                // Load authorization status
                authorizationStatus = await screenTimeService.authorizationStatus()
                
                // Load active session
                await loadActiveSession()
                
                // Load quick action groups (first 3 most used)
                let allGroups = try await dataService.loadAppGroups()
                quickActionGroups = Array(allGroups.prefix(3))
                
                // Load recent sessions
                let sessions = try await dataService.loadIntentionSessions()
                recentSessions = Array(sessions
                    .filter { !$0.isActive }
                    .sorted(by: { $0.createdAt > $1.createdAt })
                    .prefix(5))
                
                // Calculate today's statistics
                await calculateTodayStats()
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    private func loadActiveSession() async {
        do {
            let sessions = try await dataService.loadIntentionSessions()
            activeSession = sessions.first { $0.isActive }
        } catch {
            // Non-critical error - just log it
            print("Failed to load active session: \(error)")
        }
    }
    
    private func calculateTodayStats() async {
        do {
            let sessions = try await dataService.loadIntentionSessions()
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
            
            let todaySessions = sessions.filter { session in
                session.createdAt >= today && session.createdAt < tomorrow
            }
            
            todayStats = SessionStatistics(
                totalSessions: todaySessions.count,
                totalTime: todaySessions.reduce(0) { $0 + $1.duration },
                completedSessions: todaySessions.filter { !$0.isActive }.count,
                averageSessionLength: todaySessions.isEmpty ? 0 : 
                    todaySessions.reduce(0) { $0 + $1.duration } / Double(todaySessions.count)
            )
            
        } catch {
            // Non-critical error
            print("Failed to calculate today's stats: \(error)")
        }
    }
    
    // MARK: - Session Management
    
    /// Start a quick session with a predefined app group
    func startQuickSession(with group: AppGroup, duration: TimeInterval = AppConstants.Session.defaultDuration) async {
        guard canStartSession else { return }
        
        await withLoading {
            do {
                let session = try IntentionSession(
                    appGroups: [group.id],
                    applications: group.applications,
                    duration: duration
                )
                
                await onSessionStart?(session)
                activeSession = session
                
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// End the current active session
    func endCurrentSession() async {
        guard canEndSession else { return }
        
        await withLoading {
            do {
                if let session = activeSession {
                    session.complete()
                    try await dataService.saveIntentionSession(session)
                    activeSession = nil
                    
                    await onSessionEnd?()
                    
                    // Refresh data
                    await loadData()
                }
            } catch {
                await handleError(error)
            }
        }
    }
    
    /// Show the full intention prompt
    func showIntentionPrompt() {
        guard authorizationStatus == .approved else {
            Task {
                await handleError(AppError.screenTimeAuthorizationRequired("Screen Time access is required to set intentions"))
            }
            return
        }
        
        onShowIntentionPrompt?()
    }
    
    // MARK: - Authorization Management
    
    /// Request Screen Time authorization
    func requestAuthorization() async {
        await withLoading {
            let granted = await screenTimeService.requestAuthorization()
            authorizationStatus = granted ? .approved : .denied
            
            if !granted {
                await handleError(AppError.screenTimeAuthorizationFailed)
            }
        }
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
    
    // MARK: - Helper Methods
    
    private func withLoading<T: Sendable>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
}

// MARK: - SessionStatistics

struct SessionStatistics: Sendable {
    let totalSessions: Int
    let totalTime: TimeInterval
    let completedSessions: Int
    let averageSessionLength: TimeInterval
    
    init(
        totalSessions: Int = 0,
        totalTime: TimeInterval = 0,
        completedSessions: Int = 0,
        averageSessionLength: TimeInterval = 0
    ) {
        self.totalSessions = totalSessions
        self.totalTime = totalTime
        self.completedSessions = completedSessions
        self.averageSessionLength = averageSessionLength
    }
    
    var formattedTotalTime: String {
        if totalTime >= 3600 {
            let hours = Int(totalTime) / 3600
            let minutes = (Int(totalTime) % 3600) / 60
            return "\(hours)h \(minutes)m"
        } else {
            let minutes = Int(totalTime) / 60
            return "\(minutes)m"
        }
    }
    
    var formattedAverageLength: String {
        if averageSessionLength >= 3600 {
            let hours = Int(averageSessionLength) / 3600
            let minutes = (Int(averageSessionLength) % 3600) / 60
            return "\(hours)h \(minutes)m"
        } else {
            let minutes = Int(averageSessionLength) / 60
            return "\(minutes)m"
        }
    }
}

// MARK: - Extensions

extension HomeViewModel {
    
    /// Get status message for current state
    var statusMessage: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Screen Time access required"
        case .denied:
            return "Screen Time access denied"
        case .approved:
            if let session = activeSession, session.isActive {
                return "Session active • \(formattedRemainingTime) remaining"
            } else {
                return "Ready to set intention"
            }
        @unknown default:
            return "Unknown authorization status"
        }
    }
    
    /// Get appropriate status color
    var statusColor: Color {
        switch authorizationStatus {
        case .notDetermined:
            return .orange
        case .denied:
            return .red
        case .approved:
            return activeSession?.isActive == true ? .green : .blue
        @unknown default:
            return .gray
        }
    }
}