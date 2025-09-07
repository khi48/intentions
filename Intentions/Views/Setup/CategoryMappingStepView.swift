//
//  CategoryMappingStepView.swift
//  Intentions
//
//  Created by Claude on 07/09/2025.
//

import SwiftUI

/// Setup step for category mapping configuration
/// This integrates with the existing CategoryMappingSetupView
struct CategoryMappingStepView: View {
    
    @State private var setupCoordinator: SetupCoordinator
    @State private var showingCategoryMapping: Bool = false
    @State private var categoryMappingService = CategoryMappingService()
    
    let onComplete: () async -> Void
    
    init(setupCoordinator: SetupCoordinator, onComplete: @escaping () async -> Void) {
        self._setupCoordinator = State(initialValue: setupCoordinator)
        self.onComplete = onComplete
    }
    
    var body: some View {
        VStack(spacing: 24) {
            
            // Step Header
            stepHeader
            
            // Current Status
            statusSection
            
            // Action Button
            actionButton
            
            // Help Section
            helpSection
            
        }
        .padding()
        .fullScreenCover(isPresented: $showingCategoryMapping) {
            CategoryMappingSetupView { completedMappingService in
                // Update our local service with the completed one
                categoryMappingService = completedMappingService
                showingCategoryMapping = false
                
                Task {
                    await completeStep()
                }
            }
        }
    }
    
    // MARK: - Step Header
    
    private var stepHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "square.grid.3x3.topleft.filled")
                    .font(.system(size: 40))
                    .foregroundColor(.purple)
            }
            
            Text("App Category Mapping")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Configure which apps belong to which categories for intelligent blocking during focused sessions.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(spacing: 16) {
            
            // Progress Overview
            HStack {
                Text("Mapping Progress:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                statusBadge
            }
            
            // Progress Details
            VStack(spacing: 8) {
                progressBar
                
                HStack {
                    Text("\(categoryMappingService.completedCategories.count) of \(CategoryMappingService.AppCategory.allCases.count) categories mapped")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(String(format: "%.0f%% complete", categoryMappingService.setupCompletionPercentage * 100))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            
            // Completion Status
            if categoryMappingService.isSetupCompleted {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Category mapping completed successfully!")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusBadge: some View {
        Group {
            if categoryMappingService.isSetupCompleted {
                Label("Complete", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            } else if categoryMappingService.completedCategories.isEmpty {
                Label("Not Started", systemImage: "clock")
                    .foregroundColor(.orange)
            } else {
                Label("In Progress", systemImage: "arrow.clockwise")
                    .foregroundColor(.blue)
            }
        }
        .font(.subheadline)
    }
    
    private var progressBar: some View {
        ProgressView(value: categoryMappingService.setupCompletionPercentage)
            .progressViewStyle(LinearProgressViewStyle(tint: .purple))
            .scaleEffect(x: 1, y: 2, anchor: .center)
    }
    
    // MARK: - Action Button
    
    private var actionButton: some View {
        Group {
            if categoryMappingService.isSetupCompleted {
                VStack(spacing: 12) {
                    Button("Continue") {
                        Task {
                            await completeStep()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Review Mapping") {
                        showingCategoryMapping = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 12) {
                    Button(categoryMappingService.completedCategories.isEmpty ? "Start Category Mapping" : "Continue Mapping") {
                        showingCategoryMapping = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    // Show "Finish Setup" option if user has made some progress
                    if !categoryMappingService.completedCategories.isEmpty {
                        Button("Finish Setup with Current Mapping") {
                            Task {
                                await finishSetupWithPartialMapping()
                            }
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.blue)
                    }
                }
            }
        }
    }
    
    // MARK: - Help Section
    
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why is this helpful?")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("Category mapping allows Intentions to intelligently prioritize which apps to block during focused sessions. Without it, all apps are treated equally, but with mapping, the app can focus on blocking the most distracting apps first.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - Actions
    
    private func completeStep() async {
        await setupCoordinator.completeSetupStep(.categoryMapping)
        await onComplete()
    }
    
    private func finishSetupWithPartialMapping() async {
        // Force the category mapping service to consider setup complete
        // even if not all categories have been mapped
        categoryMappingService.forceSetupCompleted()
        
        // Then complete the step normally
        await completeStep()
    }
    
}

// MARK: - Preview

#Preview {
    CategoryMappingStepView(
        setupCoordinator: SetupCoordinator(
            screenTimeService: MockScreenTimeService(),
            categoryMappingService: CategoryMappingService()
        )
    ) {
        print("Category mapping step completed")
    }
}