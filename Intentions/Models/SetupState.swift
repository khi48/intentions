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

    // MARK: - Metadata

    /// Version of setup requirements (for future migrations)
    let setupVersion: Int

    /// When setup was initially completed
    let completedDate: Date

    /// Last time setup state was validated
    let lastValidatedDate: Date

    // MARK: - Current Setup Version

    static let currentSetupVersion = 2

    // MARK: - Initialization

    init(
        screenTimeAuthorized: Bool = false,
        intentionQuoteCompleted: Bool = false,
        setupVersion: Int = currentSetupVersion,
        completedDate: Date = Date(),
        lastValidatedDate: Date = Date()
    ) {
        self.screenTimeAuthorized = screenTimeAuthorized
        self.intentionQuoteCompleted = intentionQuoteCompleted
        self.setupVersion = setupVersion
        self.completedDate = completedDate
        self.lastValidatedDate = lastValidatedDate
    }

    // MARK: - Codable (backwards compatibility)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        screenTimeAuthorized = try container.decode(Bool.self, forKey: .screenTimeAuthorized)
        intentionQuoteCompleted = try container.decodeIfPresent(Bool.self, forKey: .intentionQuoteCompleted) ?? false
        setupVersion = try container.decode(Int.self, forKey: .setupVersion)
        completedDate = try container.decode(Date.self, forKey: .completedDate)
        lastValidatedDate = try container.decode(Date.self, forKey: .lastValidatedDate)
    }

    // MARK: - Validation

    /// Whether setup is sufficient to run the app
    var isSetupSufficient: Bool {
        screenTimeAuthorized && intentionQuoteCompleted
    }

    /// Whether setup state is current (not outdated)
    var isSetupCurrent: Bool {
        setupVersion >= Self.currentSetupVersion
    }

    /// Whether we should show the setup flow
    var requiresSetupFlow: Bool {
        !isSetupSufficient || !isSetupCurrent
    }

    // MARK: - Update Methods

    func withScreenTimeAuthorized(_ authorized: Bool) -> SetupState {
        SetupState(
            screenTimeAuthorized: authorized,
            intentionQuoteCompleted: intentionQuoteCompleted,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date()
        )
    }

    func withIntentionQuoteCompleted(_ completed: Bool) -> SetupState {
        SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            intentionQuoteCompleted: completed,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date()
        )
    }

    func withUpdatedValidation() -> SetupState {
        SetupState(
            screenTimeAuthorized: screenTimeAuthorized,
            intentionQuoteCompleted: intentionQuoteCompleted,
            setupVersion: setupVersion,
            completedDate: completedDate,
            lastValidatedDate: Date()
        )
    }
}

// MARK: - Setup Step Enumeration

enum SetupStep: String, CaseIterable, Sendable {
    case landing = "landing"
    case screenTimeAuthorization = "screen_time_auth"
    case intentionQuote = "intention_quote"

    var displayName: String {
        switch self {
        case .landing:
            return "Getting Started"
        case .screenTimeAuthorization:
            return "Screen Time Permission"
        case .intentionQuote:
            return "Set Your Intention"
        }
    }

    var isRequired: Bool {
        switch self {
        case .landing:
            return false
        case .screenTimeAuthorization, .intentionQuote:
            return true
        }
    }
}
