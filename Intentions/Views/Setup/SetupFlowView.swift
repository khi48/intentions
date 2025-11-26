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
    case categoryMapping
    case widgetSetup
}

/// Main setup flow view with simple state machine
struct SetupFlowView: View {
    
    @State private var currentPage: SetupPage = .landing
    @State private var setupCoordinator: SetupCoordinator

    let onComplete: () -> Void
    let embedInNavigationView: Bool
    let forceSetup: Bool

    // MARK: - Initialization

    init(
        setupCoordinator: SetupCoordinator,
        onComplete: @escaping () -> Void
    ) {
        self._setupCoordinator = State(initialValue: setupCoordinator)
        self.embedInNavigationView = true
        self.forceSetup = false
        self.onComplete = onComplete
    }

    init(
        setupCoordinator: SetupCoordinator,
        embedInNavigationView: Bool = true,
        forceSetup: Bool = false,
        onComplete: @escaping () -> Void
    ) {
        self._setupCoordinator = State(initialValue: setupCoordinator)
        self.embedInNavigationView = embedInNavigationView
        self.forceSetup = forceSetup
        self.onComplete = onComplete
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if embedInNavigationView {
                NavigationView {
                    setupContent
                }
            } else {
                setupContent
            }
        }
        .onAppear {
            print("📱 SETUP VIEW: onAppear - forceSetup=\(forceSetup), currentPage=\(currentPage)")
        }
        .onDisappear {
            print("📱 SETUP VIEW: onDisappear")
        }
    }

    private var setupContent: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [AppConstants.Colors.surface, AppConstants.Colors.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Page Content
            Group {
                switch currentPage {
                case .landing:
                    // No scroll view for landing
                    VStack(spacing: 24) {
                        landingPageContent
                        Spacer(minLength: 50)
                    }
                    .padding()

                case .screenTimePermission:
                    ScrollView {
                        VStack(spacing: 24) {
                            progressSection(step: 1)
                            screenTimePermissionContent
                            Spacer(minLength: 50)
                        }
                        .padding()
                    }

                case .categoryMapping:
                    ScrollView {
                        VStack(spacing: 24) {
                            progressSection(step: 2)
                            categoryMappingContent
                            Spacer(minLength: 50)
                        }
                        .padding()
                    }

                case .widgetSetup:
                    ScrollView {
                        VStack(spacing: 24) {
                            progressSection(step: 3)
                            widgetSetupContent
                            Spacer(minLength: 50)
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task {
            await initializeSetup()
        }
    }
    
    
    // MARK: - Progress Section
    
    private func progressSection(step: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                // Step 1: Screen Time
                Circle()
                    .fill(step >= 1 ? AppConstants.Colors.text : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(AppConstants.Colors.text, lineWidth: step == 1 ? 2 : 0)
                    )
                
                Rectangle()
                    .fill(step >= 2 ? AppConstants.Colors.text : Color.gray.opacity(0.3))
                    .frame(height: 2)
                    .frame(maxWidth: 30)
                
                // Step 2: Category Mapping
                Circle()
                    .fill(step >= 2 ? AppConstants.Colors.text : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(AppConstants.Colors.text, lineWidth: step == 2 ? 2 : 0)
                    )
                
                Rectangle()
                    .fill(step >= 3 ? AppConstants.Colors.text : Color.gray.opacity(0.3))
                    .frame(height: 2)
                    .frame(maxWidth: 30)
                
                // Step 3: Widget Setup
                Circle()
                    .fill(step >= 3 ? AppConstants.Colors.text : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(AppConstants.Colors.text, lineWidth: step == 3 ? 2 : 0)
                    )
            }
            .padding(.horizontal)
            
            Text("Step \(step) of 3")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Page Content
    
    private var landingPageContent: some View {
        SetupLandingView {
            print("📱 STATE: Moving from landing to screenTimePermission")
            currentPage = .screenTimePermission
        }
    }
    
    private var screenTimePermissionContent: some View {
        ScreenTimeAuthorizationStepView(
            setupCoordinator: setupCoordinator,
            onComplete: {
                print("📱 STATE: Screen Time completed, moving to categoryMapping")
                await setupCoordinator.completeSetupStep(.screenTimeAuthorization)
                currentPage = .categoryMapping
            }
        )
    }
    
    private var categoryMappingContent: some View {
        CategoryMappingStepView(
            setupCoordinator: setupCoordinator,
            onComplete: {
                print("📱 STATE: Category mapping completed, moving to widget setup")
                await setupCoordinator.completeSetupStep(.categoryMapping)
                currentPage = .widgetSetup
            }
        )
    }
    
    private var widgetSetupContent: some View {
        // Temporary inline widget setup view until WidgetSetupStepView is added to project
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppConstants.Colors.surface)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "widget.large.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(AppConstants.Colors.text)
                }
                
                Text("Add Intent Widget")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Add the Intent widget to your lock screen or home screen to quickly see if your apps are currently blocked or accessible.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 16) {
                Text("Widget shows:")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(AppConstants.Colors.textSecondary)
                            .font(.title2)
                        Text("Blocked")
                            .font(.caption)
                    }
                    
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(AppConstants.Colors.text)
                            .font(.title2)
                        Text("Open")
                            .font(.caption)
                    }
                    
                    VStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(AppConstants.Colors.textSecondary)
                            .font(.title2)
                        Text("Unknown")
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Button("Start Using Intent") {
                print("📱 STATE: Widget setup completed, finishing setup")
                onComplete()
            }
            .buttonStyle(.bordered)
            .foregroundColor(AppConstants.Colors.text)
            .controlSize(.large)
            
            Text("You can add the widget later from your device settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    
    // MARK: - Actions
    
    private func initializeSetup() async {
        print("📱 STATE: Initializing setup flow")
        print("📱 STATE: forceSetup = \(forceSetup)")
        await setupCoordinator.validateSetupRequirements()

        // Check if we should skip to a later page based on current state
        if let state = setupCoordinator.setupState {
            print("📱 STATE: Setup state - sufficient: \(state.isSetupSufficient), screenTime: \(state.screenTimeAuthorized)")
            if state.isSetupSufficient && !forceSetup {
                print("📱 STATE: Setup already complete, exiting setup")
                onComplete()
            } else if state.screenTimeAuthorized && !forceSetup {
                print("📱 STATE: Screen Time already authorized, starting at category mapping")
                currentPage = .categoryMapping
            } else {
                print("📱 STATE: Starting fresh setup (forced: \(forceSetup))")
                currentPage = .landing
            }
        } else {
            print("📱 STATE: No setup state available")
            currentPage = .landing
        }
    }
}


// MARK: - Preview

#Preview {
    SetupFlowView(
        setupCoordinator: SetupCoordinator(
            screenTimeService: MockScreenTimeService(),
            categoryMappingService: CategoryMappingService()
        )
    ) {
        print("Setup completed")
    }
}