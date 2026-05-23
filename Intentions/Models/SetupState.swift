//
//  SetupState.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import Foundation

/// Represents the current setup completion state of the app
struct SetupState: Codable, Sendable {

    // MARK: - Setup Requirements

    /// Whether Screen Time authorization has been granted
    let screenTimeAuthorized: Bool

    /// Whether the user has completed the intention quote step
    let intentionQuoteCompleted: Bool

    /// Whether the welcome walkthrough card has been shown to the user
    let welcomeShown: Bool

    /// Whether the user reached the end of the setup walkthrough. Only flips
    /// true when the final (widget) step is dismissed via its CTA. Required
    /// for `canEnterApp` — getting partway through and force-killing the app
    /// is NOT a completed setup.
    let setupFinished: Bool

    // MARK: - Metadata

    /// Version of setup requirements (for future migrations)
    let setupVersion: Int

    /// When setup was initially completed
    let completedDate: Date

    /// Last time setup state was validated
    let lastValidatedDate: Date

    // MARK: - Current Setup Version

    static let currentSetupVersion = 3

    // MARK: - Initialization

    init(
        screenTimeAuthorized: Bool = false,
        intentionQuoteCompleted: Bool = false,
        welcomeShown: Bool = false,
        setupFinished: Bool = false,
        setupVersion: Int = currentSetupVersion,
        completedDate: Date = Date(),
        lastValidatedDate: Date = Date()
    ) {
        self.screenTimeAuthorized = screenTimeAuthorized
        self.intentionQuoteCompleted = intentionQuoteCompleted
        self.welcomeShown = welcomeShown
        self.setupFinished = setupFinished
        self.setupVersion = setupVersion
        self.completedDate = completedDate
        self.lastValidatedDate = lastValidatedDate
    }

    // MARK: - Codable (backwards compatibility)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        screenTimeAuthorized = try container.decode(Bool.self, forKey: .screenTimeAuthorized)
        intentionQuoteCompleted = try container.decodeIfPresent(Bool.self, forKey: .intentionQuoteCompleted) ?? false
        welcomeShown = try container.decodeIfPresent(Bool.self, forKey: .welcomeShown) ?? false
        setupFinished = try container.decodeIfPresent(Bool.self, forKey: .setupFinished) ?? false
        setupVersion = try container.decode(Int.self, forKey: .setupVersion)
        completedDate = try container.decode(Date.self, forKey: .completedDate)
        lastValidatedDate = try container.decode(Date.self, forKey: .lastValidatedDate)
    }

    // MARK: - Validation

    /// Whether the app has every permission/data it needs to function. Used
    /// for runtime checks (banner re-prompts on auth revocation, etc.).
    var isSetupSufficient: Bool {
        screenTimeAuthorized && intentionQuoteCompleted
    }

    /// Whether the user can be dropped into the home screen on launch. This
    /// requires both "the app can function" AND "the walkthrough was finished
    /// end-to-end". Use this — not `isSetupSufficient` — as the launch gate.
    var canEnterApp: Bool {
        isSetupSufficient && setupFinished
    }

    /// Whether setup state is current (not outdated)
    var isSetupCurrent: Bool {
        setupVersion >= Self.currentSetupVersion
    }

    /// Whether we should show the setup flow
    var requiresSetupFlow: Bool {
        !canEnterApp || !isSetupCurrent
    }

    // MARK: - Update Methods

    func withScreenTimeAuthorized(_ authorized: Bool) -> SetupState {
        SetupState(
            screenTimeAuthorized: authorized,
            intentionQuoteCompleted: intentionQuoteCompleted,
            welcomeShown: welcomeShown,
            setupFinished: setupFinished,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date()
        )
    }

    func withIntentionQuoteCompleted(_ completed: Bool) -> SetupState {
        SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            intentionQuoteCompleted: completed,
            welcomeShown: welcomeShown,
            setupFinished: setupFinished,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date()
        )
    }

    func withWelcomeShown(_ shown: Bool) -> SetupState {
        SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            intentionQuoteCompleted: intentionQuoteCompleted,
            welcomeShown: shown,
            setupFinished: setupFinished,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date()
        )
    }

    func withSetupFinished(_ finished: Bool) -> SetupState {
        SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            intentionQuoteCompleted: intentionQuoteCompleted,
            welcomeShown: welcomeShown,
            setupFinished: finished,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date()
        )
    }

    func withUpdatedValidation() -> SetupState {
        SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            intentionQuoteCompleted: intentionQuoteCompleted,
            welcomeShown: welcomeShown,
            setupFinished: setupFinished,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date()
        )
    }
}

// MARK: - Setup Step Enumeration

enum SetupStep: String, CaseIterable, Sendable {
    case welcome = "welcome"
    case screenTimeAuthorization = "screen_time_auth"
    case intentionQuote = "intention_quote"

    var displayName: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .screenTimeAuthorization:
            return "Screen Time Permission"
        case .intentionQuote:
            return "Set Your Intention"
        }
    }

    var isRequired: Bool {
        switch self {
        case .welcome:
            return false
        case .screenTimeAuthorization, .intentionQuote:
            return true
        }
    }
}
