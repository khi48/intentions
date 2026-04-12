//
//  SetupCoordinatorTests.swift
//  IntentionsTests
//
//  Created by Claude on 12/04/2026.
//

import XCTest
@preconcurrency import FamilyControls
@testable import Intentions

@MainActor
final class SetupCoordinatorTests: XCTestCase {

    private var coordinator: SetupCoordinator!
    private var stateManager: SetupStateManager!
    private var mockScreenTimeService: MockScreenTimeService!
    private var testDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        mockScreenTimeService = MockScreenTimeService()
        testDefaults = UserDefaults(suiteName: "SetupCoordinatorTests")!
        testDefaults.removePersistentDomain(forName: "SetupCoordinatorTests")
        stateManager = SetupStateManager(userDefaults: testDefaults)
        coordinator = SetupCoordinator(
            stateManager: stateManager,
            screenTimeService: mockScreenTimeService
        )
    }

    override func tearDown() async throws {
        coordinator = nil
        stateManager = nil
        mockScreenTimeService = nil
        testDefaults.removePersistentDomain(forName: "SetupCoordinatorTests")
        testDefaults = nil
        try await super.tearDown()
    }

    // MARK: - validateSetupRequirements Tests

    func testValidateWithApprovedAuthSetsStateCorrectly() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)

        // When
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)

        // Then
        XCTAssertNotNil(coordinator.setupState)
        XCTAssertTrue(coordinator.setupState!.screenTimeAuthorized)
        XCTAssertFalse(coordinator.isValidating)
        XCTAssertNil(coordinator.errorMessage)
    }

    func testValidateWithNoPriorStateCreatesNewState() async {
        // Given - No saved state (fresh defaults)
        await mockScreenTimeService.setMockAuthorizationStatus(.notDetermined)

        // When
        await coordinator.validateSetupRequirements(cachedAuthStatus: .notDetermined)

        // Then
        XCTAssertNotNil(coordinator.setupState)
        XCTAssertFalse(coordinator.setupState!.screenTimeAuthorized)
        // Should show setup since not sufficient
        XCTAssertTrue(coordinator.shouldShowSetup)
    }

    func testValidateWithDeniedAuthShowsSetup() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.denied)

        // When
        await coordinator.validateSetupRequirements(cachedAuthStatus: .denied)

        // Then
        XCTAssertNotNil(coordinator.setupState)
        XCTAssertFalse(coordinator.setupState!.screenTimeAuthorized)
        XCTAssertTrue(coordinator.shouldShowSetup)
    }

    func testValidateWithApprovedAndQuoteCompletedHidesSetup() async {
        // Given - Save a fully completed state
        let completedState = SetupState(
            screenTimeAuthorized: true,
            intentionQuoteCompleted: true,
            setupVersion: SetupState.currentSetupVersion
        )
        await stateManager.saveSetupState(completedState)
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)

        // When
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)

        // Then
        XCTAssertNotNil(coordinator.setupState)
        XCTAssertTrue(coordinator.setupState!.isSetupSufficient)
        XCTAssertFalse(coordinator.shouldShowSetup)
    }

    func testValidateWithOutdatedVersionShowsSetup() async {
        // Given - Save a state with old version
        let oldState = SetupState(
            screenTimeAuthorized: true,
            intentionQuoteCompleted: true,
            setupVersion: 1 // Older than currentSetupVersion
        )
        await stateManager.saveSetupState(oldState)
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)

        // When
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)

        // Then
        XCTAssertTrue(coordinator.shouldShowSetup) // Not current version
    }

    // MARK: - completeSetupStep Tests

    func testCompleteScreenTimeAuthorizationStep() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)

        // When
        await coordinator.completeSetupStep(.screenTimeAuthorization)

        // Then
        XCTAssertTrue(coordinator.setupState!.screenTimeAuthorized)
    }

    func testCompleteIntentionQuoteStep() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)

        // When
        await coordinator.completeSetupStep(.intentionQuote)

        // Then
        XCTAssertTrue(coordinator.setupState!.intentionQuoteCompleted)
    }

    func testCompleteAllStepsHidesSetup() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)

        // When
        await coordinator.completeSetupStep(.screenTimeAuthorization)
        await coordinator.completeSetupStep(.intentionQuote)

        // Then
        XCTAssertTrue(coordinator.setupState!.isSetupSufficient)
        XCTAssertFalse(coordinator.shouldShowSetup)
    }

    func testCompleteStepWithNoStateDoesNothing() async {
        // Given - No setup state (coordinator not validated yet)
        XCTAssertNil(coordinator.setupState)

        // When
        await coordinator.completeSetupStep(.screenTimeAuthorization)

        // Then
        XCTAssertNil(coordinator.setupState)
    }

    func testCompleteLandingStepDoesNotChangeState() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.notDetermined)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .notDetermined)
        let stateBefore = coordinator.setupState

        // When
        await coordinator.completeSetupStep(.landing)

        // Then
        XCTAssertEqual(coordinator.setupState?.screenTimeAuthorized, stateBefore?.screenTimeAuthorized)
        XCTAssertEqual(coordinator.setupState?.intentionQuoteCompleted, stateBefore?.intentionQuoteCompleted)
    }

    // MARK: - pendingSetupSteps Tests

    func testPendingSetupStepsWithNoState() {
        // Given - No setup state
        XCTAssertNil(coordinator.setupState)

        // When
        let pending = coordinator.pendingSetupSteps

        // Then - All steps should be pending
        XCTAssertEqual(pending, SetupStep.allCases)
    }

    func testPendingSetupStepsWithPartialCompletion() async {
        // Given - Auth completed but not quote
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)
        await coordinator.completeSetupStep(.screenTimeAuthorization)

        // When
        let pending = coordinator.pendingSetupSteps

        // Then
        XCTAssertFalse(pending.contains(.screenTimeAuthorization))
        XCTAssertTrue(pending.contains(.intentionQuote))
    }

    func testPendingSetupStepsWithFullCompletion() async {
        // Given
        let completedState = SetupState(
            screenTimeAuthorized: true,
            intentionQuoteCompleted: true,
            setupVersion: SetupState.currentSetupVersion
        )
        await stateManager.saveSetupState(completedState)
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)

        // When
        let pending = coordinator.pendingSetupSteps

        // Then
        XCTAssertFalse(pending.contains(.screenTimeAuthorization))
        XCTAssertFalse(pending.contains(.intentionQuote))
        // Landing is only added when !isSetupSufficient, which is false here
        XCTAssertFalse(pending.contains(.landing))
    }

    // MARK: - completedSetupSteps Tests

    func testCompletedSetupStepsWithNoState() {
        // Given
        XCTAssertNil(coordinator.setupState)

        // When
        let completed = coordinator.completedSetupSteps

        // Then
        XCTAssertTrue(completed.isEmpty)
    }

    func testCompletedSetupStepsWithAuthOnly() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)
        await coordinator.completeSetupStep(.screenTimeAuthorization)

        // When
        let completed = coordinator.completedSetupSteps

        // Then
        XCTAssertTrue(completed.contains(.screenTimeAuthorization))
        XCTAssertFalse(completed.contains(.intentionQuote))
    }

    func testCompletedSetupStepsWithBothDone() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)
        await coordinator.completeSetupStep(.screenTimeAuthorization)
        await coordinator.completeSetupStep(.intentionQuote)

        // When
        let completed = coordinator.completedSetupSteps

        // Then
        XCTAssertTrue(completed.contains(.screenTimeAuthorization))
        XCTAssertTrue(completed.contains(.intentionQuote))
    }

    // MARK: - resetSetup Tests

    func testResetSetup() async {
        // Given - Fully set up
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)
        await coordinator.completeSetupStep(.screenTimeAuthorization)
        await coordinator.completeSetupStep(.intentionQuote)
        XCTAssertFalse(coordinator.shouldShowSetup)

        // When
        await coordinator.resetSetup()

        // Then
        XCTAssertNil(coordinator.setupState)
        XCTAssertTrue(coordinator.shouldShowSetup)
    }

    // MARK: - forceSetupFlow Tests

    func testForceSetupFlow() async {
        // Given - Fully set up, setup not showing
        let completedState = SetupState(
            screenTimeAuthorized: true,
            intentionQuoteCompleted: true,
            setupVersion: SetupState.currentSetupVersion
        )
        await stateManager.saveSetupState(completedState)
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)
        XCTAssertFalse(coordinator.shouldShowSetup)

        // When
        coordinator.forceSetupFlow()

        // Then
        XCTAssertTrue(coordinator.shouldShowSetup)
    }

    // MARK: - resetSetupStateForRerun Tests

    func testResetSetupStateForRerun() async {
        // Given
        await mockScreenTimeService.setMockAuthorizationStatus(.approved)
        await coordinator.validateSetupRequirements(cachedAuthStatus: .approved)
        XCTAssertNotNil(coordinator.setupState)

        // When
        coordinator.resetSetupStateForRerun()

        // Then
        XCTAssertNotNil(coordinator.setupState)
        XCTAssertFalse(coordinator.setupState!.screenTimeAuthorized)
        XCTAssertFalse(coordinator.setupState!.intentionQuoteCompleted)
        XCTAssertTrue(coordinator.shouldShowSetup)
    }

    func testResetSetupStateForRerunWithNoState() {
        // Given - No state
        XCTAssertNil(coordinator.setupState)

        // When
        coordinator.resetSetupStateForRerun()

        // Then - Should not create state if none existed
        XCTAssertNil(coordinator.setupState)
    }

    // MARK: - clearError Tests

    func testClearError() {
        // Given
        coordinator.errorMessage = "Some error"

        // When
        coordinator.clearError()

        // Then
        XCTAssertNil(coordinator.errorMessage)
    }

    // MARK: - SetupStateManager Tests

    func testSetupStateManagerSaveAndLoad() async {
        // Given
        let state = SetupState(
            screenTimeAuthorized: true,
            intentionQuoteCompleted: false
        )

        // When
        await stateManager.saveSetupState(state)
        let loaded = await stateManager.loadSetupState()

        // Then
        XCTAssertNotNil(loaded)
        XCTAssertTrue(loaded!.screenTimeAuthorized)
        XCTAssertFalse(loaded!.intentionQuoteCompleted)
    }

    func testSetupStateManagerClearState() async {
        // Given
        let state = SetupState(screenTimeAuthorized: true)
        await stateManager.saveSetupState(state)
        let loaded = await stateManager.loadSetupState()
        XCTAssertNotNil(loaded)

        // When
        await stateManager.clearSetupState()

        // Then
        let afterClear = await stateManager.loadSetupState()
        XCTAssertNil(afterClear)
    }

    func testSetupStateManagerHasSetupBeenCompleted() async {
        // Given - No state
        var completed = await stateManager.hasSetupBeenCompleted()
        XCTAssertFalse(completed)

        // When - Incomplete state
        let incompleteState = SetupState(screenTimeAuthorized: true, intentionQuoteCompleted: false)
        await stateManager.saveSetupState(incompleteState)
        completed = await stateManager.hasSetupBeenCompleted()
        XCTAssertFalse(completed)

        // When - Complete state
        let completeState = SetupState(screenTimeAuthorized: true, intentionQuoteCompleted: true)
        await stateManager.saveSetupState(completeState)
        completed = await stateManager.hasSetupBeenCompleted()
        XCTAssertTrue(completed)
    }

    func testSetupStateManagerFactory() async {
        // Given/When
        let currentState = stateManager.createCurrentSetupState(screenTimeAuthorized: true)

        // Then
        XCTAssertTrue(currentState.screenTimeAuthorized)
        XCTAssertFalse(currentState.intentionQuoteCompleted)

        // Given/When
        let incompleteState = stateManager.createIncompleteSetupState()

        // Then
        XCTAssertFalse(incompleteState.screenTimeAuthorized)
        XCTAssertFalse(incompleteState.intentionQuoteCompleted)
    }

    // MARK: - SetupState Model Tests

    func testSetupStateIsSetupSufficient() {
        let sufficient = SetupState(screenTimeAuthorized: true, intentionQuoteCompleted: true)
        XCTAssertTrue(sufficient.isSetupSufficient)

        let noAuth = SetupState(screenTimeAuthorized: false, intentionQuoteCompleted: true)
        XCTAssertFalse(noAuth.isSetupSufficient)

        let noQuote = SetupState(screenTimeAuthorized: true, intentionQuoteCompleted: false)
        XCTAssertFalse(noQuote.isSetupSufficient)

        let neither = SetupState(screenTimeAuthorized: false, intentionQuoteCompleted: false)
        XCTAssertFalse(neither.isSetupSufficient)
    }

    func testSetupStateIsSetupCurrent() {
        let current = SetupState(setupVersion: SetupState.currentSetupVersion)
        XCTAssertTrue(current.isSetupCurrent)

        let old = SetupState(setupVersion: 1)
        XCTAssertFalse(old.isSetupCurrent)
    }

    func testSetupStateWithScreenTimeAuthorized() {
        let original = SetupState(screenTimeAuthorized: false, intentionQuoteCompleted: true)
        let updated = original.withScreenTimeAuthorized(true)

        XCTAssertTrue(updated.screenTimeAuthorized)
        XCTAssertTrue(updated.intentionQuoteCompleted) // preserved
        XCTAssertEqual(updated.setupVersion, original.setupVersion) // preserved
    }

    func testSetupStateWithIntentionQuoteCompleted() {
        let original = SetupState(screenTimeAuthorized: true, intentionQuoteCompleted: false)
        let updated = original.withIntentionQuoteCompleted(true)

        XCTAssertTrue(updated.screenTimeAuthorized) // preserved
        XCTAssertTrue(updated.intentionQuoteCompleted)
    }

    func testSetupStateRequiresSetupFlow() {
        let complete = SetupState(
            screenTimeAuthorized: true,
            intentionQuoteCompleted: true,
            setupVersion: SetupState.currentSetupVersion
        )
        XCTAssertFalse(complete.requiresSetupFlow)

        let incomplete = SetupState(screenTimeAuthorized: false)
        XCTAssertTrue(incomplete.requiresSetupFlow)

        let oldVersion = SetupState(
            screenTimeAuthorized: true,
            intentionQuoteCompleted: true,
            setupVersion: 1
        )
        XCTAssertTrue(oldVersion.requiresSetupFlow)
    }

    // MARK: - SetupStep Tests

    func testSetupStepCases() {
        let allCases = SetupStep.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.landing))
        XCTAssertTrue(allCases.contains(.screenTimeAuthorization))
        XCTAssertTrue(allCases.contains(.intentionQuote))
    }

    func testSetupStepIsRequired() {
        XCTAssertFalse(SetupStep.landing.isRequired)
        XCTAssertTrue(SetupStep.screenTimeAuthorization.isRequired)
        XCTAssertTrue(SetupStep.intentionQuote.isRequired)
    }

    func testSetupStepDisplayNames() {
        XCTAssertEqual(SetupStep.landing.displayName, "Getting Started")
        XCTAssertEqual(SetupStep.screenTimeAuthorization.displayName, "Screen Time Permission")
        XCTAssertEqual(SetupStep.intentionQuote.displayName, "Set Your Intention")
    }
}
