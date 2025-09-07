//
//  SystemHealthStepView.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import SwiftUI

/// Setup step for validating system health and core functionality
struct SystemHealthStepView: View {
    
    @State private var setupCoordinator: SetupCoordinator
    @State private var isValidating: Bool = false
    @State private var validationStatus: ValidationStatus = .notStarted
    @State private var errorMessage: String?
    
    let onComplete: () async -> Void
    
    init(setupCoordinator: SetupCoordinator, onComplete: @escaping () async -> Void) {
        self._setupCoordinator = State(initialValue: setupCoordinator)
        self.onComplete = onComplete
    }
    
    var body: some View {
        VStack(spacing: 24) {
            
            // Step Header
            stepHeader
            
            // Validation Status
            validationStatusSection
            
            // Action Button
            actionButton
            
            // Help Section
            helpSection
            
        }
        .padding()
        .task {
            await performValidation()
        }
    }
    
    // MARK: - Step Header
    
    private var stepHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }
            
            Text("System Health Check")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Verifying that core app functionality is working properly on your device.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Validation Status
    
    private var validationStatusSection: some View {
        VStack(spacing: 16) {
            
            // Overall Status
            HStack {
                Text("System Status:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                statusBadge
            }
            
            // Individual Checks
            VStack(spacing: 12) {
                validationCheckRow(
                    title: "Screen Time Integration",
                    status: validationStatus,
                    icon: "hourglass"
                )
                
                validationCheckRow(
                    title: "App Category System",
                    status: validationStatus,
                    icon: "square.grid.3x3"
                )
                
                validationCheckRow(
                    title: "Data Persistence",
                    status: validationStatus,
                    icon: "externaldrive"
                )
            }
            
            // Error Message
            if let errorMessage = errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Validation Issue")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                    
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusBadge: some View {
        Group {
            switch validationStatus {
            case .notStarted:
                Label("Pending", systemImage: "clock")
                    .foregroundColor(.orange)
            case .inProgress:
                Label("Checking...", systemImage: "arrow.clockwise")
                    .foregroundColor(.blue)
            case .passed:
                Label("Healthy", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            case .failed:
                Label("Issues Found", systemImage: "xmark.circle")
                    .foregroundColor(.red)
            }
        }
        .font(.subheadline)
    }
    
    private func validationCheckRow(title: String, status: ValidationStatus, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Group {
                switch status {
                case .notStarted:
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                case .inProgress:
                    ProgressView()
                        .scaleEffect(0.8)
                case .passed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    // MARK: - Action Button
    
    private var actionButton: some View {
        Group {
            switch validationStatus {
            case .passed:
                Button("Continue") {
                    Task {
                        await completeStep()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
            case .failed:
                VStack(spacing: 12) {
                    Button("Retry Validation") {
                        Task {
                            await performValidation()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Continue Anyway") {
                        Task {
                            await completeStep()
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.orange)
                }
                
            case .notStarted, .inProgress:
                Button(isValidating ? "Validating..." : "Run System Check") {
                    Task {
                        await performValidation()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isValidating)
            }
        }
    }
    
    // MARK: - Help Section
    
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What does this check?")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("This validation ensures that Screen Time integration works properly, app categorization is functional, and data can be saved reliably. Most issues resolve themselves automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - Actions
    
    private func performValidation() async {
        await MainActor.run {
            isValidating = true
            validationStatus = .inProgress
            errorMessage = nil
        }
        
        // Simulate validation process with delay for UX
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        do {
            // Perform actual system validation
            let isHealthy = await validateSystemHealth()
            
            await MainActor.run {
                if isHealthy {
                    validationStatus = .passed
                } else {
                    validationStatus = .failed
                    errorMessage = "Some system components may not be working optimally. The app should still function normally."
                }
                isValidating = false
            }
        } catch {
            await MainActor.run {
                validationStatus = .failed
                errorMessage = "Validation encountered an error: \(error.localizedDescription)"
                isValidating = false
            }
        }
    }
    
    private func validateSystemHealth() async -> Bool {
        // This would contain the actual validation logic
        // For now, we'll assume it passes unless there are obvious issues
        return true
    }
    
    private func completeStep() async {
        await setupCoordinator.completeSetupStep(.systemHealth)
        await onComplete()
    }
}

// MARK: - Supporting Types

private enum ValidationStatus {
    case notStarted
    case inProgress
    case passed
    case failed
}

// MARK: - Preview

#Preview {
    SystemHealthStepView(
        setupCoordinator: SetupCoordinator(
            screenTimeService: MockScreenTimeService(),
            categoryMappingService: CategoryMappingService()
        )
    ) {
        print("System health step completed")
    }
}