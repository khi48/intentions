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
    case complete
}

/// Main setup flow view with simple state machine
struct SetupFlowView: View {
    
    @State private var currentPage: SetupPage = .landing
    @State private var setupCoordinator: SetupCoordinator
    
    let onComplete: () -> Void
    
    // MARK: - Initialization
    
    init(
        setupCoordinator: SetupCoordinator,
        onComplete: @escaping () -> Void
    ) {
        self._setupCoordinator = State(initialValue: setupCoordinator)
        self.onComplete = onComplete
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
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
                        
                    case .complete:
                        VStack(spacing: 24) {
                            completionContent
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
                    .fill(step >= 1 ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: step == 1 ? 2 : 0)
                    )
                
                Rectangle()
                    .fill(step >= 2 ? Color.blue : Color.gray.opacity(0.3))
                    .frame(height: 2)
                    .frame(maxWidth: 40)
                
                // Step 2: Category Mapping
                Circle()
                    .fill(step >= 2 ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: step == 2 ? 2 : 0)
                    )
            }
            .padding(.horizontal)
            
            Text("Step \(step) of 2")
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
                print("📱 STATE: Category mapping completed, finishing setup")
                await setupCoordinator.completeSetupStep(.categoryMapping)
                currentPage = .complete
            }
        )
    }
    
    private var completionContent: some View {
        SetupCompletionView {
            print("📱 STATE: Setup complete, exiting to main app")
            onComplete()
        }
    }
    
    // MARK: - Actions
    
    private func initializeSetup() async {
        print("📱 STATE: Initializing setup flow")
        await setupCoordinator.validateSetupRequirements()
        
        // Check if we should skip to a later page based on current state
        if let state = setupCoordinator.setupState {
            if state.isSetupSufficient {
                print("📱 STATE: Setup already complete")
                currentPage = .complete
            } else if state.screenTimeAuthorized {
                print("📱 STATE: Screen Time already authorized, starting at category mapping")
                currentPage = .categoryMapping
            } else {
                print("📱 STATE: Starting fresh setup")
                currentPage = .landing
            }
        }
    }
}

// MARK: - Setup Completion View

struct SetupCompletionView: View {
    
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Setup Complete!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.green)
            
            Text("Intentions is now configured for mindful app usage. You can access additional settings anytime from the Settings tab.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "hourglass.circle.fill")
                        .foregroundColor(.green)
                    Text("Screen Time permissions configured")
                        .font(.subheadline)
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.3x3.topleft.filled")
                        .foregroundColor(.green)
                    Text("App categories mapped")
                        .font(.subheadline)
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("System health validated")
                        .font(.subheadline)
                    Spacer()
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
            
            Button("Start Using Intentions") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
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