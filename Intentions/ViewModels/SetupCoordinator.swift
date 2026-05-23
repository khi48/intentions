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

    /// - Parameter forceAuthUpdate: When `true`, skip the `.notDetermined` cold-launch guard
    ///   and trust the reported status. Use when the caller has already confirmed a real
    ///   revocation (e.g. status transitioned from `.approved` at runtime).
    func validateSetupRequirements(cachedAuthStatus: AuthorizationStatus? = nil, forceAuthUpdate: Bool = false) async {
        isValidating = true
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
            // Update saved state to reflect current system reality, but don't downgrade
            // auth status to false when the system reports .notDetermined on cold launch —
            // unless the caller confirmed this is a real revocation (forceAuthUpdate).
            let shouldUpdateAuth = savedState.screenTimeAuthorized != screenTimeAuth
                && (forceAuthUpdate || !(savedState.screenTimeAuthorized && authStatus == .notDetermined))
            if shouldUpdateAuth {
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
        shouldShowSetup = !actualState.canEnterApp || !actualState.isSetupCurrent
    }

    func forceSetupFlow() {
        shouldShowSetup = true
    }

    func resetSetupStateForRerun() {
        if setupState != nil {
            setupState = SetupState(
                screenTimeAuthorized: false,
                intentionQuoteCompleted: false,
                welcomeShown: false,
                setupFinished: false
            )
            shouldShowSetup = true
        }
    }

    /// Marks the user as having reached the end of the walkthrough. Called
    /// when the final (widget) step is dismissed, regardless of whether the
    /// user actually added the widget or skipped.
    func markSetupFinished() async {
        guard let currentState = setupState else { return }
        let updated = currentState.withSetupFinished(true)
        setupState = updated
        await stateManager.saveSetupState(updated)
        if updated.canEnterApp {
            shouldShowSetup = false
        }
    }

    func completeSetupStep(_ step: SetupStep) async {
        guard let currentState = setupState else { return }

        let updatedState: SetupState
        switch step {
        case .welcome:
            updatedState = currentState.withWelcomeShown(true)
        case .screenTimeAuthorization:
            let authorized = await screenTimeService.authorizationStatus() == .approved
            updatedState = currentState.withScreenTimeAuthorized(authorized)
        case .intentionQuote:
            updatedState = currentState.withIntentionQuoteCompleted(true)
        }

        setupState = updatedState
        await stateManager.saveSetupState(updatedState)

        if updatedState.canEnterApp {
            shouldShowSetup = false
        }
    }

    func resetSetup() async {
        await stateManager.clearSetupState()
        setupState = nil
        shouldShowSetup = true
    }

    // MARK: - Setup Steps

    var pendingSetupSteps: [SetupStep] {
        guard let state = setupState else {
            return SetupStep.allCases
        }

        var pending: [SetupStep] = []
        if !state.welcomeShown {
            pending.append(.welcome)
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
        if state.welcomeShown {
            completed.append(.welcome)
        }
        if state.screenTimeAuthorized {
            completed.append(.screenTimeAuthorization)
        }
        if state.intentionQuoteCompleted {
            completed.append(.intentionQuote)
        }
        return completed
    }
}
