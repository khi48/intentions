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
    private let categoryMappingService: CategoryMappingService
    
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
    func validateSetupRequirements() async {
        await withValidation {
            // Load existing setup state
            let savedState = await stateManager.loadSetupState()
            
            // Get current system status
            let currentStatus = await getCurrentSystemStatus()
            
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
                print("✅ SETUP: Created and saved initial setup state")
            }
            
            // Determine if setup is required
            let setupRequired = await determineSetupRequired(
                savedState: actualState,
                currentStatus: currentStatus
            )
            
            // Update state
            setupState = actualState
            shouldShowSetup = setupRequired
            
            print("🔍 SETUP VALIDATION: Setup required: \(setupRequired)")
            print("   📊 Current state: ScreenTime=\(actualState.screenTimeAuthorized), Mapping=\(actualState.categoryMappingCompleted)")
            print("   📊 Setup sufficient: \(actualState.isSetupSufficient)")
        }
    }
    
    /// Force setup to be shown (for manual triggers from Settings)
    func forceSetupFlow() {
        shouldShowSetup = true
        print("🔄 SETUP: Forced setup flow requested")
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
            print("🔄 SETUP: Reset state for forced re-run")
        }
    }
    
    /// Complete a setup step and update state
    func completeSetupStep(_ step: SetupStep) async {
        guard let currentState = setupState else {
            print("❌ SETUP: Cannot complete step - no current state")
            return
        }
        
        let updatedState = await updateStateForCompletedStep(step, currentState: currentState)
        setupState = updatedState
        await stateManager.saveSetupState(updatedState)
        
        print("✅ SETUP: Completed step \(step.displayName)")
        
        // Check if setup is now complete
        if updatedState.isSetupSufficient {
            shouldShowSetup = false
            print("🎉 SETUP: Setup is now complete!")
        }
    }
    
    
    /// Reset setup state (for testing or user-requested reset)
    func resetSetup() async {
        await stateManager.clearSetupState()
        setupState = nil
        shouldShowSetup = true
        print("🔄 SETUP: Setup state reset")
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
            print("❌ SETUP VALIDATION: Error: \(error)")
            throw error
        }
    }
    
    /// Get current system status by checking all requirements
    private func getCurrentSystemStatus() async -> SystemStatus {
        var authStatus = await screenTimeService.authorizationStatus()
        
        // If authorization status is "Not Determined", double-check after a brief delay
        // This handles cases where the system needs time to return the correct status
        if authStatus == .notDetermined {
            print("🔄 SETUP: Authorization status is 'Not Determined', rechecking...")
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            let recheckStatus = await screenTimeService.authorizationStatus()
            if recheckStatus != .notDetermined {
                authStatus = recheckStatus
                print("✅ SETUP: Updated authorization status to: \(authStatus)")
            }
        }
        
        let screenTimeAuth = authStatus == .approved
        let categoryMappingComplete = categoryMappingService.isTrulySetupCompleted
        
        print("🔍 SYSTEM STATUS DEBUG:")
        print("   - Screen Time authorized: \(screenTimeAuth)")
        print("   - Category mapping isTrulySetupCompleted: \(categoryMappingComplete)")
        print("   - Category mapping isSetupCompleted: \(categoryMappingService.isSetupCompleted)")
        
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
            print("🔄 SETUP: Setup version outdated - setup required")
            return true
        }
        
        // If critical requirements have changed
        if savedState.screenTimeAuthorized != currentStatus.screenTimeAuthorized {
            print("🔐 SETUP: Screen Time authorization changed - setup required")
            return true
        }
        
        
        // If setup was never completed properly
        if !savedState.isSetupSufficient {
            print("❌ SETUP: Setup never completed - setup required")
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
            print("🔍 UPDATING CATEGORY MAPPING STATE:")
            print("   - Service isTrulySetupCompleted: \(completed)")
            print("   - Service isSetupCompleted: \(categoryMappingService.isSetupCompleted)")
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
        
        print("🔍 SETUP DEBUG: Pending steps determined")
        print("   - Setup sufficient: \(state.isSetupSufficient)")
        print("   - Screen Time authorized: \(state.screenTimeAuthorized)")
        print("   - Category mapping completed: \(state.categoryMappingCompleted)")
        print("   - Pending steps: \(pending.map { $0.displayName })")
        
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