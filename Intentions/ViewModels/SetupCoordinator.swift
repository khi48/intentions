//
//  SetupCoordinator.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import Foundation
@preconcurrency import FamilyControls

/// Coordinates setup validation and determines when setup flow should be shown
@MainActor
@Observable
final class SetupCoordinator: Sendable {

    // MARK: - Published Properties

    private(set) var setupState: SetupState?
    private(set) var shouldShowSetup: Bool = false
    var isValidating: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let stateManager: SetupStateManager
    private let screenTimeService: ScreenTimeManaging

    // MARK: - Initialization

    init(
        stateManager: SetupStateManager? = nil,
        screenTimeService: ScreenTimeManaging
    ) {
        self.stateManager = stateManager ?? SetupStateManager()
        self.screenTimeService = screenTimeService
    }

    // MARK: - Public API

    func validateSetupRequirements(cachedAuthStatus: AuthorizationStatus? = nil) async {
        isValidating = true
        errorMessage = nil
        defer { isValidating = false }

        let savedState = await stateManager.loadSetupState()

        let authStatus: AuthorizationStatus
        if let cached = cachedAuthStatus {
            authStatus = cached
        } else {
            var freshStatus = await screenTimeService.authorizationStatus()
            if freshStatus == .notDetermined {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let recheckStatus = await screenTimeService.authorizationStatus()
                if recheckStatus != .notDetermined {
                    freshStatus = recheckStatus
                }
            }
            authStatus = freshStatus
        }

        let screenTimeAuth = authStatus == .approved

        let actualState: SetupState
        if let savedState = savedState {
            // Update saved state to reflect current system reality
            if savedState.screenTimeAuthorized != screenTimeAuth {
                actualState = savedState.withScreenTimeAuthorized(screenTimeAuth)
                await stateManager.saveSetupState(actualState)
            } else {
                actualState = savedState
            }
        } else {
            actualState = SetupState(screenTimeAuthorized: screenTimeAuth)
            await stateManager.saveSetupState(actualState)
        }

        setupState = actualState
        shouldShowSetup = !actualState.isSetupSufficient || !actualState.isSetupCurrent
    }

    func forceSetupFlow() {
        shouldShowSetup = true
    }

    func resetSetupStateForRerun() {
        if setupState != nil {
            setupState = SetupState(screenTimeAuthorized: false, intentionQuoteCompleted: false)
            shouldShowSetup = true
        }
    }

    func completeSetupStep(_ step: SetupStep) async {
        guard let currentState = setupState else { return }

        let updatedState: SetupState
        switch step {
        case .landing:
            updatedState = currentState
        case .screenTimeAuthorization:
            let authorized = await screenTimeService.authorizationStatus() == .approved
            updatedState = currentState.withScreenTimeAuthorized(authorized)
        case .intentionQuote:
            updatedState = currentState.withIntentionQuoteCompleted(true)
        }

        setupState = updatedState
        await stateManager.saveSetupState(updatedState)

        if updatedState.isSetupSufficient {
            shouldShowSetup = false
        }
    }

    func resetSetup() async {
        await stateManager.clearSetupState()
        setupState = nil
        shouldShowSetup = true
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Setup Steps

    var pendingSetupSteps: [SetupStep] {
        guard let state = setupState else {
            return SetupStep.allCases
        }

        var pending: [SetupStep] = []
        if !state.isSetupSufficient {
            pending.append(.landing)
        }
        if !state.screenTimeAuthorized {
            pending.append(.screenTimeAuthorization)
        }
        if !state.intentionQuoteCompleted {
            pending.append(.intentionQuote)
        }
        return pending
    }

    var completedSetupSteps: [SetupStep] {
        guard let state = setupState else { return [] }
        var completed: [SetupStep] = []
        if state.screenTimeAuthorized {
            completed.append(.screenTimeAuthorization)
        }
        if state.intentionQuoteCompleted {
            completed.append(.intentionQuote)
        }
        return completed
    }
}
