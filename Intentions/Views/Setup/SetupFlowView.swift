//
//  SetupFlowView.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import SwiftUI

/// Main setup flow view that guides users through app configuration
/// Presents a progressive, step-by-step setup experience
struct SetupFlowView: View {
    
    @State private var setupCoordinator: SetupCoordinator
    @State private var currentStepIndex: Int = 0
    @State private var isSetupComplete: Bool = false
    
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
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // Header
                        headerSection
                        
                        // Progress Indicator
                        progressSection
                        
                        // Current Step Content
                        currentStepContent
                        
                        
                        Spacer(minLength: 50)
                    }
                    .padding()
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task {
            await validateInitialState()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "gear.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Setup Intentions")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Let's configure your app for mindful phone usage. This only takes a few minutes.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            // Step indicators
            HStack(spacing: 8) {
                ForEach(Array(pendingSteps.enumerated()), id: \.offset) { index, step in
                    Circle()
                        .fill(index <= currentStepIndex ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.blue, lineWidth: index == currentStepIndex ? 2 : 0)
                        )
                    
                    if index < pendingSteps.count - 1 {
                        Rectangle()
                            .fill(index < currentStepIndex ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 2)
                            .frame(maxWidth: 40)
                    }
                }
            }
            .padding(.horizontal)
            
            // Progress text
            Text("Step \(currentStepIndex + 1) of \(pendingSteps.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Current Step Content
    
    @ViewBuilder
    private var currentStepContent: some View {
        if isSetupComplete {
            SetupCompletionView {
                onComplete()
            }
        } else if currentStepIndex < pendingSteps.count {
            let currentStep = pendingSteps[currentStepIndex]
            
            switch currentStep {
            case .screenTimeAuthorization:
                ScreenTimeAuthorizationStepView(
                    setupCoordinator: setupCoordinator,
                    onComplete: { await moveToNextStep() }
                )
            case .systemHealth:
                SystemHealthStepView(
                    setupCoordinator: setupCoordinator,
                    onComplete: { await moveToNextStep() }
                )
            case .categoryMapping:
                CategoryMappingStepView(
                    setupCoordinator: setupCoordinator,
                    onComplete: { await moveToNextStep() }
                )
            }
        } else {
            // Fallback - shouldn't happen
            Text("Setup configuration error")
                .foregroundColor(.red)
        }
    }
    
    // MARK: - Computed Properties
    
    private var pendingSteps: [SetupStep] {
        setupCoordinator.pendingSetupSteps
    }
    
    
    // MARK: - Actions
    
    private func validateInitialState() async {
        await setupCoordinator.validateSetupRequirements()
        
        // If setup is already complete, show completion
        if let state = setupCoordinator.setupState, state.isSetupSufficient {
            isSetupComplete = true
        }
    }
    
    private func moveToNextStep() async {
        if currentStepIndex < pendingSteps.count - 1 {
            currentStepIndex += 1
        } else {
            // All steps completed
            isSetupComplete = true
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