//
//  SetupState.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import Foundation

/// Represents the current setup completion state of the app
/// This model tracks what setup steps have been completed and validates system requirements
struct SetupState: Codable, Sendable {
    
    // MARK: - Setup Requirements
    
    /// Whether Screen Time authorization has been granted
    let screenTimeAuthorized: Bool
    
    /// Whether category mapping setup has been completed
    let categoryMappingCompleted: Bool
    
    /// Whether basic app functionality is working
    let systemHealthValidated: Bool
    
    // MARK: - Metadata
    
    /// Version of setup requirements (for future migrations)
    let setupVersion: Int
    
    /// When setup was initially completed
    let completedDate: Date
    
    /// Last time setup state was validated
    let lastValidatedDate: Date
    
    /// Whether user has explicitly skipped non-critical setup steps
    let userSkippedOptionalSteps: Bool
    
    // MARK: - Current Setup Version
    
    static let currentSetupVersion = 1
    
    // MARK: - Initialization
    
    init(
        screenTimeAuthorized: Bool = false,
        categoryMappingCompleted: Bool = false, 
        systemHealthValidated: Bool = false,
        setupVersion: Int = currentSetupVersion,
        completedDate: Date = Date(),
        lastValidatedDate: Date = Date(),
        userSkippedOptionalSteps: Bool = false
    ) {
        self.screenTimeAuthorized = screenTimeAuthorized
        self.categoryMappingCompleted = categoryMappingCompleted
        self.systemHealthValidated = systemHealthValidated
        self.setupVersion = setupVersion
        self.completedDate = completedDate
        self.lastValidatedDate = lastValidatedDate
        self.userSkippedOptionalSteps = userSkippedOptionalSteps
    }
    
    // MARK: - Validation
    
    /// Whether all critical setup requirements are met
    var isCriticalSetupComplete: Bool {
        return screenTimeAuthorized && systemHealthValidated
    }
    
    /// Whether all recommended setup is complete
    var isFullSetupComplete: Bool {
        return isCriticalSetupComplete && categoryMappingCompleted
    }
    
    /// Whether setup is sufficient to run the app (only critical setup required)
    var isSetupSufficient: Bool {
        // Category mapping is optional - only critical setup is required for app to function
        return isCriticalSetupComplete
    }
    
    /// Whether category mapping has been addressed (completed or explicitly skipped)
    private var categoryMappingAddressed: Bool {
        return categoryMappingCompleted || userSkippedOptionalSteps
    }
    
    /// Whether setup state is current (not outdated)
    var isSetupCurrent: Bool {
        return setupVersion >= Self.currentSetupVersion
    }
    
    /// Whether we should show the setup flow
    var requiresSetupFlow: Bool {
        return !isSetupSufficient || !isSetupCurrent
    }
    
    // MARK: - Update Methods
    
    /// Update with new authorization status
    func withScreenTimeAuthorized(_ authorized: Bool) -> SetupState {
        return SetupState(
            screenTimeAuthorized: authorized,
            categoryMappingCompleted: categoryMappingCompleted,
            systemHealthValidated: systemHealthValidated,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date(),
            userSkippedOptionalSteps: userSkippedOptionalSteps
        )
    }
    
    /// Update with category mapping completion
    func withCategoryMappingCompleted(_ completed: Bool) -> SetupState {
        return SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            categoryMappingCompleted: completed,
            systemHealthValidated: systemHealthValidated,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date(),
            userSkippedOptionalSteps: userSkippedOptionalSteps
        )
    }
    
    /// Update with system health validation
    func withSystemHealthValidated(_ validated: Bool) -> SetupState {
        return SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            categoryMappingCompleted: categoryMappingCompleted,
            systemHealthValidated: validated,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date(),
            userSkippedOptionalSteps: userSkippedOptionalSteps
        )
    }
    
    /// Mark optional steps as skipped by user
    func withOptionalStepsSkipped(_ skipped: Bool) -> SetupState {
        return SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            categoryMappingCompleted: categoryMappingCompleted,
            systemHealthValidated: systemHealthValidated,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date(),
            userSkippedOptionalSteps: skipped
        )
    }
    
    /// Update validation timestamp
    func withUpdatedValidation() -> SetupState {
        return SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            categoryMappingCompleted: categoryMappingCompleted,
            systemHealthValidated: systemHealthValidated,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date(),
            userSkippedOptionalSteps: userSkippedOptionalSteps
        )
    }
}

// MARK: - Setup Step Enumeration

/// Individual setup steps that can be validated
enum SetupStep: String, CaseIterable, Sendable {
    case screenTimeAuthorization = "screen_time_auth"
    case categoryMapping = "category_mapping"
    case systemHealth = "system_health"
    
    var displayName: String {
        switch self {
        case .screenTimeAuthorization:
            return "Screen Time Permission"
        case .categoryMapping:
            return "App Category Mapping"
        case .systemHealth:
            return "System Health Check"
        }
    }
    
    var description: String {
        switch self {
        case .screenTimeAuthorization:
            return "Grant permission to manage Screen Time for app blocking"
        case .categoryMapping:
            return "Configure app categories for intelligent blocking"
        case .systemHealth:
            return "Verify core app functionality is working"
        }
    }
    
    var isRequired: Bool {
        switch self {
        case .screenTimeAuthorization, .systemHealth:
            return true
        case .categoryMapping:
            return false // Recommended but not required
        }
    }
    
    var iconName: String {
        switch self {
        case .screenTimeAuthorization:
            return "hourglass.circle"
        case .categoryMapping:
            return "square.grid.3x3.topleft.filled"
        case .systemHealth:
            return "checkmark.shield"
        }
    }
}