//
//  CategoryMappingSetupView.swift
//  Intentions
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI
@preconcurrency import FamilyControls
import ManagedSettings

/// Extended setup view that maps apps to categories through individual category selection
/// Users select each category one by one to build comprehensive app-to-category mappings
struct CategoryMappingSetupView: View {
    
    @State private var mappingService = CategoryMappingService()
    @State private var currentCategory: CategoryMappingService.AppCategory?
    @State private var showingFamilyActivityPicker = false
    @State private var currentSelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var isProcessingSelection = false
    @State private var hasLaunchServicesError = false
    @State private var errorDetectionTimer: Timer?
    @State private var pickerDidAppear = false
    
    let onComplete: (CategoryMappingService) -> Void
    
    var body: some View {
        ScrollView {
                VStack(spacing: 24) {
                    
                    // Authorization and Simulator Warning Section
                    if AuthorizationCenter.shared.authorizationStatus != .approved {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)

                            Text("Screen Time Authorization Required")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("Category mapping requires Screen Time permissions. Please grant access in Settings.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)

                            Text("Status: \(String(describing: AuthorizationCenter.shared.authorizationStatus))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(16)
                    }

                    // System compatibility notice
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Note")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        Text("If the app picker doesn't appear or shows errors, this is typically due to iOS system limitations. Try restarting the app or testing on a physical device for best results.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)

                    
                    // Header Section
                    headerSection
                    
                    // Progress Section
                    progressSection
                    
                    // Categories Section
                    categoriesSection
                    
                    // Completion Section
                    if mappingService.isSetupCompleted {
                        completionSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
        .navigationTitle("App Category Mapping")
        .navigationBarTitleDisplayMode(.large)
        .familyActivityPicker(isPresented: $showingFamilyActivityPicker, selection: $currentSelection)
        .onChange(of: showingFamilyActivityPicker) { oldValue, newValue in
            print("🎯 FamilyActivityPicker showing state changed: \(oldValue) → \(newValue)")

            // Track when picker actually appears
            if !oldValue && newValue {
                print("✅ FamilyActivityPicker appeared - ready to accept selections")
                pickerDidAppear = true
            }

            // If picker was dismissed, handle cleanup
            if oldValue && !newValue {
                print("🔄 FamilyActivityPicker dismissed")

                // Clear the error detection timer when picker is dismissed
                errorDetectionTimer?.invalidate()

                // Reset picker appearance tracking
                pickerDidAppear = false

                // Only check for abandoned selections if we have an active category
                if currentCategory != nil {
                    // Give a short delay to let selection processing complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if !isProcessingSelection {
                            print("❌ No selection processed, resetting state")
                            currentCategory = nil
                        }
                    }
                }
            }
        }
        .onChange(of: currentSelection) { oldSelection, newSelection in
            print("🎯 FamilyActivityPicker selection changed: \(newSelection.applications.count) apps, \(newSelection.categories.count) categories")

            // Only process selections when:
            // 1. We have an active category selection in progress
            // 2. The picker has actually appeared (not just spurious selection events)
            // 3. The selection has actually changed from the previous one
            guard currentCategory != nil else {
                print("⚠️ Ignoring selection change - no active category selection")
                return
            }

            guard pickerDidAppear else {
                print("⚠️ Ignoring selection change - picker hasn't properly appeared yet")
                return
            }

            guard oldSelection != newSelection else {
                print("⚠️ Ignoring selection change - no actual change detected")
                return
            }

            handleCategorySelection(newSelection)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.badge.checkmark.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("App Category Mapping")
                .font(.title)
                .fontWeight(.bold)
            
            Text("To provide intelligent app blocking, we need to understand which apps belong to which categories. You must complete mapping for all categories to proceed. Please select each category individually when prompted.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Setup Progress")
                    .font(.headline)
                
                Spacer()
                
                Text("\(mappingService.completedCategories.count)/\(CategoryMappingService.AppCategory.allCases.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }
            
            ProgressView(value: mappingService.setupCompletionPercentage)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            
            Text(String(format: "%.0f%% complete", mappingService.setupCompletionPercentage * 100))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Categories Section
    
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Categories")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(CategoryMappingService.AppCategory.allCases, id: \.self) { category in
                    CategorySetupCard(
                        category: category,
                        isCompleted: mappingService.setupProgress[category, default: false],
                        appCount: mappingService.getApps(for: category).count,
                        categoryToken: mappingService.getCategoryToken(for: category),
                        onTap: {
                            startCategorySelection(category)
                        }
                    )
                }
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            errorDetectionTimer?.invalidate()
        }
    }
    
    // MARK: - Completion Section
    
    private var completionSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("Setup Complete!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.green)
            
            Text("All categories have been mapped. Your app blocking will now be intelligently prioritized by category.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            // Summary of mappings
            VStack(alignment: .leading, spacing: 8) {
                ForEach(mappingService.completedCategories.prefix(5), id: \.self) { category in
                    HStack {
                        Image(systemName: category.iconName)
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        
                        Text(category.displayName)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text("\(mappingService.getApps(for: category).count) apps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if mappingService.completedCategories.count > 5 {
                    Text("... and \(mappingService.completedCategories.count - 5) more categories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 28)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Button("Complete Setup") {
                onComplete(mappingService)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(16)
    }


    // MARK: - Actions
    
    private func startCategorySelection(_ category: CategoryMappingService.AppCategory) {
        print("🎯 Starting category selection for: \(category.displayName)")

        // Check authorization status before opening picker
        let authStatus = AuthorizationCenter.shared.authorizationStatus
        print("📋 Current authorization status: \(authStatus)")

        if authStatus != .approved {
            print("❌ Authorization not approved, cannot open picker")
            return
        }

        // Reset state for new selection
        currentCategory = category
        isProcessingSelection = false
        pickerDidAppear = false

        // Clear the old selection and open picker
        currentSelection = FamilyActivitySelection(includeEntireCategory: true)

        // Reset error state before showing picker
        hasLaunchServicesError = false

        // Start error detection timer - if LaunchServices errors occur, they happen immediately
        errorDetectionTimer?.invalidate()
        errorDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            Task { @MainActor in
                // If picker dismissed quickly without user interaction, likely a system error
                if !showingFamilyActivityPicker && !isProcessingSelection {
                    hasLaunchServicesError = true
                    print("🚨 SYSTEM ERROR: Detected likely LaunchServices failure - picker dismissed immediately")
                }
            }
        }

        // Add a small delay to ensure proper state reset before showing picker
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showingFamilyActivityPicker = true
        }
    }
    
    private func handleCategorySelection(_ selection: FamilyActivitySelection) {
        // Prevent multiple processing of the same selection
        guard !isProcessingSelection else {
            print("⚠️ Already processing selection, ignoring")
            return
        }

        guard let category = currentCategory else {
            print("ERROR: No current category set for selection")
            return
        }

        // Only process if we have meaningful selection
        let hasApps = !selection.applications.isEmpty
        let hasCategories = !selection.categories.isEmpty

        if hasApps || hasCategories {
            isProcessingSelection = true

            print("✅ Processing selection for \(category.displayName): \(selection.applications.count) apps, \(selection.categories.count) categories")

            // Record the mapping
            mappingService.recordCategoryMapping(category, selection: selection)

            // Clear the current category after a short delay to allow picker to fully close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                currentCategory = nil
                isProcessingSelection = false
                pickerDidAppear = false
                errorDetectionTimer?.invalidate()
                print("🔄 Reset state after successful mapping")
            }
        } else if !isProcessingSelection && !showingFamilyActivityPicker {
            // Empty selection - check if it's due to system error or user cancellation
            if hasLaunchServicesError {
                print("🚨 Empty selection for \(category.displayName) due to LaunchServices system error - not retrying")
                currentCategory = nil
                // Clear error state
                hasLaunchServicesError = false
            } else {
                print("❌ Empty selection for \(category.displayName) - user cancelled")
                currentCategory = nil
            }
            errorDetectionTimer?.invalidate()
        }
    }

}

// MARK: - Category Setup Card

struct CategorySetupCard: View {
    let category: CategoryMappingService.AppCategory
    let isCompleted: Bool
    let appCount: Int
    let categoryToken: ActivityCategoryToken?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Icon and status
                ZStack {
                    Circle()
                        .fill(isCompleted ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                        .frame(width: 44, height: 44)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    } else {
                        // Use Apple's system category icon if available, otherwise show blank for debugging
                        if let categoryToken = categoryToken {
                            Label(categoryToken)
                                .labelStyle(.iconOnly)
                                .font(.title3)
                        } else {
                            // Show blank circle for debugging when no ActivityCategoryToken
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                
                // Category info
                VStack(spacing: 6) {
                    Text(category.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(category.description)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // Debug info for ActivityCategoryToken availability
                    if categoryToken != nil {
                        Text("🟢 Has Apple Token")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Text("🔴 No Apple Token (Normal)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    
                    if isCompleted && appCount > 0 {
                        Text("\(appCount) apps mapped")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                
                Spacer()
                
                // Action indicator
                HStack {
                    if isCompleted {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Redo")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "hand.tap.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Tap to map")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180, maxHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCompleted ? Color.green : Color.blue, lineWidth: isCompleted ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    CategoryMappingSetupView { _ in
        // Preview completion handler
    }
}