//
//  SetupFlowView.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import SwiftUI

// MARK: - Setup State Machine

enum SetupPage {
    case landing
    case screenTimePermission
    case alwaysAllowedInfo
    case intentionQuote
    case widgetSetup
}

/// Main setup flow view with simple state machine
struct SetupFlowView: View {

    @State private var currentPage: SetupPage = .landing
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
                case .landing:
                    VStack(spacing: 24) {
                        landingPageContent
                        Spacer(minLength: 50)
                    }
                    .padding()

                case .intentionQuote:
                    ScrollView {
                        VStack(spacing: 24) {
                            progressSection(step: 1)
                            intentionQuoteContent
                            Spacer(minLength: 50)
                        }
                        .padding()
                    }

                case .screenTimePermission:
                    ScrollView {
                        VStack(spacing: 24) {
                            progressSection(step: 2)
                            screenTimePermissionContent
                            Spacer(minLength: 50)
                        }
                        .padding()
                    }

                case .alwaysAllowedInfo:
                    ScrollView {
                        VStack(spacing: 24) {
                            progressSection(step: 3)
                            alwaysAllowedInfoContent
                            Spacer(minLength: 50)
                        }
                        .padding()
                    }

                case .widgetSetup:
                    ScrollView {
                        VStack(spacing: 24) {
                            progressSection(step: 4)
                            WidgetSetupStepView(onComplete: onComplete)
                            Spacer(minLength: 50)
                        }
                        .padding()
                    }
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


    // MARK: - Progress Section

    private func progressSection(step: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { i in
                    Circle()
                        .fill(step >= i ? AppConstants.Colors.text : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(AppConstants.Colors.text, lineWidth: step == i ? 2 : 0)
                        )
                    if i < 4 {
                        Rectangle()
                            .fill(step > i ? AppConstants.Colors.text : Color.gray.opacity(0.3))
                            .frame(height: 2)
                            .frame(maxWidth: 20)
                    }
                }
            }
            .padding(.horizontal)

            Text("Step \(step) of 4")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Page Content

    private var landingPageContent: some View {
        SetupLandingView {
            currentPage = .intentionQuote
        }
    }

    private var screenTimePermissionContent: some View {
        ScreenTimeAuthorizationStepView(
            setupCoordinator: setupCoordinator,
            onComplete: {
                await setupCoordinator.completeSetupStep(.screenTimeAuthorization)
                currentPage = .alwaysAllowedInfo
            }
        )
    }

    private var alwaysAllowedInfoContent: some View {
        AlwaysAllowedInfoStepView(
            onContinue: {
                currentPage = .widgetSetup
            }
        )
    }

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
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .focused($isIntentionFieldFocused)
                .textInputAutocapitalization(.sentences)
                .onChange(of: intentionQuoteText) { _, newValue in
                    if newValue.contains("\n") {
                        intentionQuoteText = newValue.replacingOccurrences(of: "\n", with: "")
                        isIntentionFieldFocused = false
                    }
                }

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
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer(minLength: 40)
        }
    }

    // MARK: - Actions

    private func initializeSetup() async {
        await setupCoordinator.validateSetupRequirements()

        if let state = setupCoordinator.setupState {
            if state.isSetupSufficient && !forceSetup {
                onComplete()
            } else {
                currentPage = .landing
            }
        } else {
            currentPage = .landing
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
