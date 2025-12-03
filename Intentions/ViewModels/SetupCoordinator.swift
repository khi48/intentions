//
//  SetupCoordinator.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import Foundation
@preconcurrency import FamilyControls

/// Coordinates setup validation and determines when setup flow should be shown
/// This is the main controller for the setup process
@MainActor
@Observable
final class SetupCoordinator: Sendable {
    
    // MARK: - Published Properties
    
    /// Current setup state
    private(set) var setupState: SetupState?
    
    /// Whether setup flow should be shown
    private(set) var shouldShowSetup: Bool = false
    
    /// Whether setup is currently being validated
    var isValidating: Bool = false
    
    /// Current error message if validation fails
    var errorMessage: String?
    
    // MARK: - Dependencies

    private let stateManager: SetupStateManager
    private let screenTimeService: ScreenTimeManaging
    let categoryMappingService: CategoryMappingService  // Public for access by setup views
    
    // MARK: - Initialization
    
    init(
        stateManager: SetupStateManager? = nil,
        screenTimeService: ScreenTimeManaging,
        categoryMappingService: CategoryMappingService
    ) {
        self.stateManager = stateManager ?? SetupStateManager()
        self.screenTimeService = screenTimeService
        self.categoryMappingService = categoryMappingService
    }
    
    // MARK: - Public API
    
    /// Validate current setup state and determine if setup flow is needed
    /// This is called on app launch and when returning from background
    /// - Parameter cachedAuthStatus: Optional cached authorization status to avoid redundant checks
    func validateSetupRequirements(cachedAuthStatus: AuthorizationStatus? = nil) async {
        await withValidation {
            // Load existing setup state
            let savedState = await stateManager.loadSetupState()

            // Get current system status (use cached auth status if provided)
            let currentStatus = await getCurrentSystemStatus(cachedAuthStatus: cachedAuthStatus)

            // If no saved state exists, create one based on current system status
            let actualState: SetupState
            if let savedState = savedState {
                actualState = savedState
            } else {
                // Create initial state based on current system status
                actualState = stateManager.createCurrentSetupState(
                    screenTimeAuthorized: currentStatus.screenTimeAuthorized,
                    categoryMappingCompleted: currentStatus.categoryMappingCompleted,
                    systemHealthValidated: true // Always true since we removed system health validation
                )
                // Save the initial state immediately
                await stateManager.saveSetupState(actualState)
            }

            // Determine if setup is required
            let setupRequired = await determineSetupRequired(
                savedState: actualState,
                currentStatus: currentStatus
            )

            // Update state
            setupState = actualState
            shouldShowSetup = setupRequired
        }
    }
    
    /// Force setup to be shown (for manual triggers from Settings)
    func forceSetupFlow() {
        shouldShowSetup = true
    }

    /// Reset setup state to force a complete re-run (for Settings navigation)
    func resetSetupStateForRerun() {
        // Temporarily set the state to indicate setup is not sufficient
        if let currentState = setupState {
            let resetState = SetupState(
                screenTimeAuthorized: false,  // Force re-authorization
                categoryMappingCompleted: false,  // Force re-mapping
                setupVersion: currentState.setupVersion
            )
            setupState = resetState
            shouldShowSetup = true
        }
    }
    
    /// Complete a setup step and update state
    func completeSetupStep(_ step: SetupStep) async {
        guard let currentState = setupState else {
            return
        }

        let updatedState = await updateStateForCompletedStep(step, currentState: currentState)
        setupState = updatedState
        await stateManager.saveSetupState(updatedState)

        // Check if setup is now complete
        if updatedState.isSetupSufficient {
            shouldShowSetup = false
        }
    }
    
    
    /// Reset setup state (for testing or user-requested reset)
    func resetSetup() async {
        await stateManager.clearSetupState()
        setupState = nil
        shouldShowSetup = true
    }
    
    // MARK: - Private Methods
    
    private func withValidation<T: Sendable>(_ operation: () async throws -> T) async rethrows -> T {
        isValidating = true
        errorMessage = nil
        defer { isValidating = false }
        
        do {
            return try await operation()
        } catch {
            errorMessage = error.localizedDescription
            print("SETUP VALIDATION ERROR: \(error)")
            throw error
        }
    }
    
    /// Get current system status by checking all requirements
    /// - Parameter cachedAuthStatus: Optional cached authorization status to avoid redundant checks
    private func getCurrentSystemStatus(cachedAuthStatus: AuthorizationStatus? = nil) async -> SystemStatus {
        let authStatus: AuthorizationStatus

        // Use cached status if provided, otherwise check fresh
        if let cached = cachedAuthStatus {
            authStatus = cached
        } else {
            var freshStatus = await screenTimeService.authorizationStatus()

            // If authorization status is "Not Determined", double-check after a brief delay
            // This handles cases where the system needs time to return the correct status
            if freshStatus == .notDetermined {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                let recheckStatus = await screenTimeService.authorizationStatus()
                if recheckStatus != .notDetermined {
                    freshStatus = recheckStatus
                }
            }

            authStatus = freshStatus
        }

        let screenTimeAuth = authStatus == .approved
        let categoryMappingComplete = categoryMappingService.isTrulySetupCompleted

        return SystemStatus(
            screenTimeAuthorized: screenTimeAuth,
            categoryMappingCompleted: categoryMappingComplete,
            systemHealthValidated: true // Always true since we removed system health validation
        )
    }
    
    /// Determine if setup flow should be shown
    private func determineSetupRequired(savedState: SetupState, currentStatus: SystemStatus) async -> Bool {
        
        // If setup version is outdated
        if !savedState.isSetupCurrent {
            return true
        }

        // If critical requirements have changed
        if savedState.screenTimeAuthorized != currentStatus.screenTimeAuthorized {
            return true
        }


        // If setup was never completed properly
        if !savedState.isSetupSufficient {
            return true
        }
        
        // Setup is not required
        return false
    }
    
    /// Update setup state when a step is completed
    private func updateStateForCompletedStep(_ step: SetupStep, currentState: SetupState) async -> SetupState {
        switch step {
        case .landing:
            // Landing step doesn't change state, just allows progression
            return currentState
            
        case .screenTimeAuthorization:
            let authorized = await screenTimeService.authorizationStatus() == .approved
            return currentState.withScreenTimeAuthorized(authorized)
            
        case .categoryMapping:
            let completed = categoryMappingService.isTrulySetupCompleted
            return currentState.withCategoryMappingCompleted(completed)
        }
    }
    
    /// Clear any errors
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Supporting Types

/// Current system status for comparison with saved state
private struct SystemStatus {
    let screenTimeAuthorized: Bool
    let categoryMappingCompleted: Bool
    let systemHealthValidated: Bool
}

// MARK: - Setup Requirements

extension SetupCoordinator {
    
    /// Get list of setup steps that still need to be completed
    var pendingSetupSteps: [SetupStep] {
        guard let state = setupState else {
            return SetupStep.allCases
        }
        
        var pending: [SetupStep] = []
        
        // Always start with landing page if setup is needed
        if !state.isSetupSufficient {
            pending.append(.landing)
        }
        
        if !state.screenTimeAuthorized {
            pending.append(.screenTimeAuthorization)
        }
        
        // Always include category mapping if not completed (can be skipped during the step)
        if !state.categoryMappingCompleted {
            pending.append(.categoryMapping)
        }
        
        return pending
    }
    
    /// Get list of completed setup steps
    var completedSetupSteps: [SetupStep] {
        guard let state = setupState else {
            return []
        }
        
        var completed: [SetupStep] = []
        
        if state.screenTimeAuthorized {
            completed.append(.screenTimeAuthorization)
        }
        
        if state.categoryMappingCompleted {
            completed.append(.categoryMapping)
        }
        
        return completed
    }
}