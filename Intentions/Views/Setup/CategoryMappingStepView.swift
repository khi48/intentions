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
    // Use the SHARED categoryMappingService from the coordinator, not a new instance
    private var categoryMappingService: CategoryMappingService {
        setupCoordinator.categoryMappingService
    }

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
            
        }
        .padding()
        .onAppear {
        }
        .fullScreenCover(isPresented: $showingCategoryMapping) {
            CategoryMappingSetupView(mappingService: categoryMappingService) {
                // Use the shared service directly - no copying needed!
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
                    .fill(AppConstants.Colors.surface)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "square.grid.3x3.topleft.filled")
                    .font(.system(size: 40))
                    .foregroundColor(AppConstants.Colors.text)
            }
            
            Text("App Category Mapping")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Configure which apps belong to which categories for intelligent blocking during focused sessions. You must map all categories to proceed.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            if categoryMappingService.isTrulySetupCompleted {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppConstants.Colors.text)
                    Text("Category mapping completed successfully!")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.text)
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
            if categoryMappingService.isTrulySetupCompleted {
                Label("Complete", systemImage: "checkmark.circle")
                    .foregroundColor(AppConstants.Colors.text)
            } else if categoryMappingService.completedCategories.isEmpty {
                Label("Not Started", systemImage: "clock")
                    .foregroundColor(AppConstants.Colors.textSecondary)
            } else {
                Label("In Progress", systemImage: "arrow.clockwise")
                    .foregroundColor(AppConstants.Colors.text)
            }
        }
        .font(.subheadline)
    }
    
    private var progressBar: some View {
        ProgressView(value: categoryMappingService.setupCompletionPercentage)
            .progressViewStyle(LinearProgressViewStyle(tint: AppConstants.Colors.textSecondary))
            .scaleEffect(x: 1, y: 2, anchor: .center)
    }
    
    // MARK: - Action Button
    
    private var actionButton: some View {
        Group {
            if categoryMappingService.isTrulySetupCompleted {
                VStack(spacing: 12) {
                    Button("Continue") {
                        Task {
                            await completeStep()
                        }
                    }
                    .buttonStyle(.bordered)
            .foregroundColor(AppConstants.Colors.text)
                    .controlSize(.large)
                    
                    Button("Review Mapping") {
                        showingCategoryMapping = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 16) {
                    Button(categoryMappingService.completedCategories.isEmpty ? "Start Category Mapping" : "Continue Mapping") {
                        showingCategoryMapping = true
                    }
                    .buttonStyle(.bordered)
            .foregroundColor(AppConstants.Colors.text)
                    .controlSize(.large)
                    
                    // Show completion requirement message
                    if !categoryMappingService.completedCategories.isEmpty {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(AppConstants.Colors.text)
                                Text("All categories must be mapped to continue")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Complete mapping for all \(CategoryMappingService.AppCategory.allCases.count) categories to proceed to the next step")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .background(AppConstants.Colors.surface)
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    
    // MARK: - Actions
    
    private func completeStep() async {
        
        await setupCoordinator.completeSetupStep(.categoryMapping)
        await onComplete()
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
    }
}