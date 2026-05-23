//
//  SetupFlowView.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import SwiftUI

// MARK: - Setup State Machine

enum SetupPage {
    case welcome
    case screenTimePermission
    case alwaysAllowedInfo
    case intentionQuote
    case widgetSetup
}

/// Main setup flow view with simple state machine
struct SetupFlowView: View {

    @State private var currentPage: SetupPage = .welcome
    @State private var setupCoordinator: SetupCoordinator
    @State private var intentionQuoteText: String = ""

    let onComplete: () -> Void
    let onIntentionQuoteSet: ((String) -> Void)?
    let embedInNavigationView: Bool
    let forceSetup: Bool

    // MARK: - Initialization

    init(
        setupCoordinator: SetupCoordinator,
        onIntentionQuoteSet: ((String) -> Void)? = nil,
        onComplete: @escaping () -> Void
    ) {
        self._setupCoordinator = State(initialValue: setupCoordinator)
        self.embedInNavigationView = true
        self.forceSetup = false
        self.onIntentionQuoteSet = onIntentionQuoteSet
        self.onComplete = onComplete
    }

    init(
        setupCoordinator: SetupCoordinator,
        embedInNavigationView: Bool = true,
        forceSetup: Bool = false,
        onIntentionQuoteSet: ((String) -> Void)? = nil,
        onComplete: @escaping () -> Void
    ) {
        self._setupCoordinator = State(initialValue: setupCoordinator)
        self.embedInNavigationView = embedInNavigationView
        self.forceSetup = forceSetup
        self.onIntentionQuoteSet = onIntentionQuoteSet
        self.onComplete = onComplete
    }

    // MARK: - Body

    var body: some View {
        Group {
            if embedInNavigationView {
                NavigationStack {
                    setupContent
                }
            } else {
                setupContent
            }
        }
    }

    private var setupContent: some View {
        ZStack {
            AppConstants.Colors.background
                .ignoresSafeArea()

            Group {
                switch currentPage {
                case .welcome:
                    WelcomeWalkthroughView {
                        Task {
                            await setupCoordinator.completeSetupStep(.welcome)
                        }
                        currentPage = .intentionQuote
                    }

                case .intentionQuote:
                    SetupStepScaffold(progressStep: 1) {
                        intentionQuoteContent
                    } footer: {
                        intentionQuoteFooter
                    }

                case .screenTimePermission:
                    ScreenTimeAuthorizationStepView(
                        setupCoordinator: setupCoordinator,
                        onComplete: {
                            await setupCoordinator.completeSetupStep(.screenTimeAuthorization)
                            currentPage = .alwaysAllowedInfo
                        }
                    )

                case .alwaysAllowedInfo:
                    AlwaysAllowedInfoStepView(
                        onContinue: {
                            currentPage = .widgetSetup
                        }
                    )

                case .widgetSetup:
                    WidgetSetupStepView(setupCoordinator: setupCoordinator, onComplete: onComplete)
                }
            }
        }
        .onTapGesture {
            isIntentionFieldFocused = false
        }
        .task {
            await initializeSetup()
        }
    }

    // MARK: - Intention quote step

    @FocusState private var isIntentionFieldFocused: Bool

    private var isIntentionQuoteValid: Bool {
        intentionQuoteText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
    }

    private var intentionQuoteContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppConstants.Colors.surface)
                        .frame(width: 80, height: 80)

                    Image(systemName: "quote.opening")
                        .font(.system(size: 40))
                        .foregroundColor(AppConstants.Colors.text)
                }

                Text("Set Your Intention")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Why are you setting up app blocking? Write a short reminder to yourself — it'll be shown if you ever try to disable protection.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            TextField("e.g. I want to be more present with my family", text: $intentionQuoteText, axis: .vertical)
                .lineLimit(2...4)
                .font(.body)
                .padding()
                .background(AppConstants.Colors.surface)
                .cornerRadius(12)
                .focused($isIntentionFieldFocused)
                .textInputAutocapitalization(.sentences)
                .onChange(of: intentionQuoteText) { _, newValue in
                    if newValue.contains("\n") {
                        intentionQuoteText = newValue.replacingOccurrences(of: "\n", with: "")
                        isIntentionFieldFocused = false
                    }
                }
        }
    }

    private var intentionQuoteFooter: some View {
        SettingsPrimaryButton("Continue",
                              systemImage: "arrow.right",
                              isEnabled: isIntentionQuoteValid) {
            let trimmed = intentionQuoteText.trimmingCharacters(in: .whitespacesAndNewlines)
            onIntentionQuoteSet?(trimmed)
            Task {
                await setupCoordinator.completeSetupStep(.intentionQuote)
            }
            currentPage = .screenTimePermission
        }
    }

    // MARK: - Actions

    private func initializeSetup() async {
        await setupCoordinator.validateSetupRequirements()

        guard let state = setupCoordinator.setupState else {
            currentPage = .welcome
            return
        }

        if state.canEnterApp && !forceSetup {
            onComplete()
            return
        }

        if !state.welcomeShown {
            currentPage = .welcome
        } else if !state.intentionQuoteCompleted {
            currentPage = .intentionQuote
        } else if !state.screenTimeAuthorized {
            currentPage = .screenTimePermission
        } else {
            currentPage = .widgetSetup
        }
    }
}


// MARK: - Preview

#Preview {
    SetupFlowView(
        setupCoordinator: SetupCoordinator(
            screenTimeService: MockScreenTimeService()
        )
    ) {
    }
}
