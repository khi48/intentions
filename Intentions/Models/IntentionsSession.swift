//
//  IntentionsSession.swift
//  Intentions
//
//  Created by Kieran Hitchcock on 08/06/2025.
//
// =============================================================================
// Models/IntentionSession.swift - Active Session Data Model
// =============================================================================

import Foundation
import FamilyControls
import ManagedSettings

// MARK: - Session State
enum SessionState: Codable, Sendable {
    case active(startedAt: Date)
    case paused(totalElapsed: TimeInterval, pausedAt: Date)
    case completed(totalElapsed: TimeInterval, completedAt: Date)
    case cancelled(totalElapsed: TimeInterval, cancelledAt: Date)
    
    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
    
    var wasCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
    
    var totalElapsedTime: TimeInterval {
        switch self {
        case .active(let startedAt):
            return Date().timeIntervalSince(startedAt)
        case .paused(let totalElapsed, _):
            return totalElapsed
        case .completed(let totalElapsed, _):
            return totalElapsed
        case .cancelled(let totalElapsed, _):
            return totalElapsed
        }
    }
}

/// Session source tracking
enum SessionSource: Codable, Sendable {
    case quickAction(QuickAction)  // Store full quick action snapshot
    case manual
}

@Observable
final class IntentionSession: Identifiable, Codable, @unchecked Sendable {
    let id: UUID
    var requestedAppGroups: [UUID] // References to AppGroup IDs
    var requestedApplications: Set<ApplicationToken>
    var selectedCategories: Set<ActivityCategoryToken> = [] // Categories from FamilyActivityPicker
    var allowAllWebsites: Bool = false // Whether to allow access to all websites during this session
    var duration: TimeInterval
    var createdAt: Date
    var state: SessionState
    var source: SessionSource
    
    // Computed properties for backward compatibility
    var startTime: Date {
        switch state {
        case .active(let startedAt):
            return startedAt
        case .paused(_, let pausedAt):
            return pausedAt.addingTimeInterval(-state.totalElapsedTime)
        case .completed(_, let completedAt):
            return completedAt.addingTimeInterval(-state.totalElapsedTime)
        case .cancelled(_, let cancelledAt):
            return cancelledAt.addingTimeInterval(-state.totalElapsedTime)
        }
    }
    
    var endTime: Date {
        startTime.addingTimeInterval(duration)
    }
    
    var isActive: Bool {
        state.isActive
    }
    
    var wasCompleted: Bool {
        state.wasCompleted
    }
    
    // Computed properties
    var remainingTime: TimeInterval {
        guard isActive else { return 0 }
        let elapsed = state.totalElapsedTime
        return max(0, duration - elapsed)
    }
    
    var isExpired: Bool {
        state.totalElapsedTime >= duration
    }
    
    var progressPercentage: Double {
        guard duration > 0 else { return 0 }
        let elapsed = state.totalElapsedTime
        return min(1.0, elapsed / duration)
    }
    
    init(appGroups: [UUID] = [], applications: Set<ApplicationToken> = [], categories: Set<ActivityCategoryToken> = [], allowAllWebsites: Bool = false, duration: TimeInterval, source: SessionSource = .manual) throws {
        // Validate duration
        guard duration >= AppConstants.Session.minimumDuration else {
            throw AppError.validationFailed("duration", reason: "Session duration must be at least \(AppConstants.Session.minimumDuration.formattedDuration)")
        }
        guard duration <= AppConstants.Session.maximumDuration else {
            throw AppError.validationFailed("duration", reason: "Session duration cannot exceed \(AppConstants.Session.maximumDuration.formattedDuration)")
        }

        self.id = UUID()
        self.requestedAppGroups = appGroups
        self.requestedApplications = applications
        self.selectedCategories = categories
        self.allowAllWebsites = allowAllWebsites
        self.duration = duration
        self.createdAt = Date()
        self.state = .active(startedAt: Date())
        self.source = source
    }
    
    // Private initializer for persistence reconstruction with existing ID
    private init(id: UUID, appGroups: [UUID], applications: Set<ApplicationToken>, allowAllWebsites: Bool, duration: TimeInterval, createdAt: Date, source: SessionSource = .manual) throws {
        // Validate duration for reconstructed sessions too
        guard duration >= AppConstants.Session.minimumDuration else {
            throw AppError.validationFailed("duration", reason: "Session duration must be at least \(AppConstants.Session.minimumDuration.formattedDuration)")
        }
        guard duration <= AppConstants.Session.maximumDuration else {
            throw AppError.validationFailed("duration", reason: "Session duration cannot exceed \(AppConstants.Session.maximumDuration.formattedDuration)")
        }

        self.id = id
        self.requestedAppGroups = appGroups
        self.requestedApplications = applications
        self.allowAllWebsites = allowAllWebsites
        self.duration = duration
        self.createdAt = createdAt
        self.state = .active(startedAt: Date()) // Will be overridden by caller
        self.source = source
    }
    
    // Static factory method for persistence reconstruction
    static func fromPersistence(
        id: UUID,
        appGroups: [UUID],
        applications: Set<ApplicationToken>,
        allowAllWebsites: Bool = false,
        duration: TimeInterval,
        createdAt: Date,
        state: SessionState,
        source: SessionSource = .manual
    ) throws -> IntentionSession {
        let session = try IntentionSession(
            id: id,
            appGroups: appGroups,
            applications: applications,
            allowAllWebsites: allowAllWebsites,
            duration: duration,
            createdAt: createdAt,
            source: source
        )
        session.state = state
        return session
    }
    
    // MARK: - Session Control Methods
    
    func pause() {
        guard case .active(let startedAt) = state else { return }
        let totalElapsed = Date().timeIntervalSince(startedAt)
        state = .paused(totalElapsed: totalElapsed, pausedAt: Date())
    }
    
    func resume() {
        guard case .paused(let totalElapsed, _) = state else { return }
        // Adjust startedAt backwards by the already-elapsed time so that
        // Date().timeIntervalSince(startedAt) correctly returns totalElapsed + new time
        state = .active(startedAt: Date().addingTimeInterval(-totalElapsed))
    }
    
    func complete() {
        let totalElapsed = state.totalElapsedTime
        state = .completed(totalElapsed: totalElapsed, completedAt: Date())
    }
    
    func cancel() {
        let totalElapsed = state.totalElapsedTime
        state = .cancelled(totalElapsed: totalElapsed, cancelledAt: Date())
    }
    
    // Codable implementation
    enum CodingKeys: String, CodingKey {
        case id, requestedAppGroups, requestedApplications, duration, createdAt, state, source
        // Legacy keys for backward compatibility
        case startTime, endTime, isActive, wasCompleted
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        requestedAppGroups = try container.decode([UUID].self, forKey: .requestedAppGroups)
        requestedApplications = try container.decodeIfPresent(Set<ApplicationToken>.self, forKey: .requestedApplications) ?? []
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        
        // Try to decode new state format first, fall back to legacy format
        if let newState = try? container.decode(SessionState.self, forKey: .state) {
            state = newState
        } else {
            // Legacy format compatibility
            let startTime = try container.decode(Date.self, forKey: .startTime)
            let isActive = try container.decode(Bool.self, forKey: .isActive)
            let wasCompleted = try container.decode(Bool.self, forKey: .wasCompleted)

            if isActive {
                state = .active(startedAt: startTime)
            } else if wasCompleted {
                let elapsed = Date().timeIntervalSince(startTime)
                state = .completed(totalElapsed: elapsed, completedAt: Date())
            } else {
                let elapsed = Date().timeIntervalSince(startTime)
                state = .cancelled(totalElapsed: elapsed, cancelledAt: Date())
            }
        }

        // Decode source with backward compatibility
        source = try container.decodeIfPresent(SessionSource.self, forKey: .source) ?? .manual
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(requestedAppGroups, forKey: .requestedAppGroups)
        try container.encode(requestedApplications, forKey: .requestedApplications)
        try container.encode(duration, forKey: .duration)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(state, forKey: .state)
        try container.encode(source, forKey: .source)

        // Encode legacy format for backward compatibility
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(wasCompleted, forKey: .wasCompleted)
    }
}
