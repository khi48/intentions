//
//  ScreenTimeAuthorizationStepView.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import SwiftUI
@preconcurrency import FamilyControls

/// Setup step for requesting Screen Time authorization
struct ScreenTimeAuthorizationStepView: View {
    
    @State private var setupCoordinator: SetupCoordinator
    @State private var isRequesting: Bool = false
    @State private var authorizationStatus: AuthorizationStatus = .notDetermined
    @State private var showingManualInstructions: Bool = false
    
    let onComplete: () async -> Void
    
    init(setupCoordinator: SetupCoordinator, onComplete: @escaping () async -> Void) {
        self._setupCoordinator = State(initialValue: setupCoordinator)
        self.onComplete = onComplete
    }
    
    var body: some View {
        VStack(spacing: 24) {
            
            // Step Header
            stepHeader
            
            // Authorization Status
            authorizationStatusSection
            
            // Action Button
            actionButton
            
            // Manual Instructions (if needed)
            if showingManualInstructions {
                manualInstructionsSection
            }
            
        }
        .padding()
        .task {
            await checkAuthorizationStatus()
        }
    }
    
    // MARK: - Step Header
    
    private var stepHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppConstants.Colors.surface)
                    .frame(width: 60, height: 60)
                
                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(AppConstants.Colors.text)
            }
            
            Text("Screen Time Permission")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap 'Grant Permission' below to allow Intent to manage app access during focused sessions.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Authorization Status
    
    private var authorizationStatusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Permission Status:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                statusBadge
            }
            
            if authorizationStatus == .approved {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppConstants.Colors.text)
                    Text("Screen Time permission granted successfully!")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.text)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusBadge: some View {
        Group {
            switch authorizationStatus {
            case .notDetermined:
                Label("Not Requested", systemImage: "questionmark.circle")
                    .foregroundColor(AppConstants.Colors.textSecondary)
            case .denied:
                Label("Denied", systemImage: "xmark.circle")
                    .foregroundColor(AppConstants.Colors.textSecondary)
            case .approved:
                Label("Approved", systemImage: "checkmark.circle")
                    .foregroundColor(AppConstants.Colors.text)
            @unknown default:
                Label("Unknown", systemImage: "exclamationmark.circle")
                    .foregroundColor(.gray)
            }
        }
        .font(.subheadline)
    }
    
    // MARK: - Action Button
    
    private var actionButton: some View {
        Group {
            switch authorizationStatus {
            case .approved:
                SettingsPrimaryButton("Continue", systemImage: "arrow.right") {
                    Task { await completeStep() }
                }
                
            case .denied:
                VStack(spacing: 12) {
                    SettingsPrimaryButton("Open iOS Settings", systemImage: "gear") {
                        openSettings()
                    }
                    SettingsPrimaryButton("I've Updated Settings", systemImage: "arrow.clockwise") {
                        Task { await recheckPermission() }
                    }
                }

            case .notDetermined:
                SettingsPrimaryButton(
                    isRequesting ? "Requesting..." : "Grant Screen Time Permission",
                    systemImage: "lock.shield",
                    isEnabled: !isRequesting
                ) {
                    Task { await requestPermission() }
                }

            @unknown default:
                SettingsPrimaryButton("Check Permission Status", systemImage: "arrow.clockwise") {
                    Task { await checkAuthorizationStatus() }
                }
            }
        }
    }
    
    // MARK: - Manual Instructions
    
    private var manualInstructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Setup Instructions")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                instructionStep(number: 1, text: "Open the Settings app on your device")
                instructionStep(number: 2, text: "Scroll down and tap 'Screen Time'")
                instructionStep(number: 3, text: "Look for 'Intent' in the app list")
                instructionStep(number: 4, text: "Grant the requested permissions")
                instructionStep(number: 5, text: "Return to this app and tap 'I've Updated Settings'")
            }
        }
        .padding()
        .background(AppConstants.Colors.surface)
        .cornerRadius(12)
    }
    
    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
    
    
    // MARK: - Actions
    
    private func checkAuthorizationStatus() async {
        let status = await AuthorizationCenter.shared.authorizationStatus
        await MainActor.run {
            authorizationStatus = status
        }
    }
    
    private func requestPermission() async {
        await MainActor.run {
            isRequesting = true
        }
        
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            
            // Wait a moment for the system to update the authorization status
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await checkAuthorizationStatus()
            
            // If authorization was granted, automatically complete the step
            if authorizationStatus == .approved {
                await completeStep()
            } else {
            }
        } catch {
            await MainActor.run {
                showingManualInstructions = true
            }
        }
        
        await MainActor.run {
            isRequesting = false
        }
    }
    
    private func recheckPermission() async {
        await checkAuthorizationStatus()
        
        if authorizationStatus == .approved {
            await completeStep()
        }
    }
    
    private func completeStep() async {
        await setupCoordinator.completeSetupStep(.screenTimeAuthorization)
        await onComplete()
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
        showingManualInstructions = true
    }
}

// MARK: - Preview

#Preview {
    ScreenTimeAuthorizationStepView(
        setupCoordinator: SetupCoordinator(
            screenTimeService: MockScreenTimeService()
        )
    ) {
    }
}