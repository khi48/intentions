//
//  CategoryMappingSetupView.swift
//  Intentions
//
//  Created by Claude on 07/08/2025.
//

import SwiftUI
@preconcurrency import FamilyControls

/// Extended setup view that maps apps to categories through individual category selection
/// Users select each category one by one to build comprehensive app-to-category mappings
struct CategoryMappingSetupView: View {
    
    @State private var mappingService = CategoryMappingService()
    @State private var currentCategory: CategoryMappingService.AppCategory?
    @State private var showingFamilyActivityPicker = false
    @State private var currentSelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var errorCategories: Set<CategoryMappingService.AppCategory> = []
    @State private var showingErrorAlert = false
    @State private var isProcessingSelection = false
    
    let onComplete: (CategoryMappingService) -> Void
    
    var body: some View {
        ScrollView {
                VStack(spacing: 24) {
                    
                    // Authorization Debug Section
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
        .background(
            // Use background modifier for FamilyActivityPicker to avoid sheet conflicts
            Group {
                if showingFamilyActivityPicker {
                    Color.clear
                        .familyActivityPicker(isPresented: $showingFamilyActivityPicker, selection: $currentSelection)
                        .onAppear {
                            print("🎛️ PICKER APPEARED: FamilyActivityPicker is now visible")
                            print("   - Authorization Status: \(AuthorizationCenter.shared.authorizationStatus)")
                        }
                        .onDisappear {
                            print("🎛️ PICKER DISAPPEARED: FamilyActivityPicker was dismissed")
                            print("   - showingFamilyActivityPicker: \(showingFamilyActivityPicker)")
                            print("   - currentCategory: \(currentCategory?.displayName ?? "nil")")
                            print("   - isProcessingSelection: \(isProcessingSelection)")
                            
                            // If picker disappeared without processing selection, mark as failed
                            if let category = currentCategory, !isProcessingSelection {
                                print("🚫 PICKER DISMISSED: Category mapping failed for \(category.displayName)")
                                errorCategories.insert(category)
                                currentCategory = nil
                                
                                if category == .shoppingFood {
                                    showingErrorAlert = true
                                }
                            }
                        }
                }
            }
        )
        .onChange(of: currentSelection) { oldSelection, newSelection in
            handleCategorySelection(newSelection)
        }
        .alert("Category Mapping Issue", isPresented: $showingErrorAlert) {
            Button("Continue Without This Category") { }
            Button("Try Again") {
                if let category = errorCategories.first(where: { $0 == .shoppingFood }) {
                    startCategorySelection(category)
                }
            }
        } message: {
            Text("The Shopping & Food category experienced technical issues. You can continue without mapping this category or try again. The app will work fine either way.")
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
            
            Text("To provide intelligent app blocking, we need to understand which apps belong to which categories. Please select each category individually when prompted.")
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
                        hasError: errorCategories.contains(category),
                        appCount: mappingService.getApps(for: category).count,
                        onTap: {
                            startCategorySelection(category)
                        }
                    )
                }
            }
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
        print("\n🚀 STARTING CATEGORY SELECTION: \(category.displayName)")
        print("📋 Instructions: Please select ONLY the \(category.displayName) category")
        print("🔍 The picker will open with includeEntireCategory: true")
        print("✅ This should populate individual app tokens for this category")
        
        print("🔧 STATE BEFORE START:")
        print("   - currentCategory: \(currentCategory?.displayName ?? "nil")")
        print("   - isProcessingSelection: \(isProcessingSelection)")
        print("   - showingFamilyActivityPicker: \(showingFamilyActivityPicker)")
        print("   - currentSelection apps: \(currentSelection.applications.count)")
        print("   - currentSelection categories: \(currentSelection.categories.count)")
        
        // Reset state for new selection
        currentCategory = category
        isProcessingSelection = false
        errorCategories.remove(category) // Clear any previous error state
        
        // Clear the old selection and show picker
        currentSelection = FamilyActivitySelection(includeEntireCategory: true)
        showingFamilyActivityPicker = true
        
        print("🔧 STATE AFTER START:")
        print("   - currentCategory: \(currentCategory?.displayName ?? "nil")")
        print("   - isProcessingSelection: \(isProcessingSelection)")
        print("   - showingFamilyActivityPicker: \(showingFamilyActivityPicker)")
    }
    
    private func handleCategorySelection(_ selection: FamilyActivitySelection) {
        print("\n📱 HANDLE CATEGORY SELECTION CALLED")
        print("🔧 SELECTION STATE:")
        print("   - Selection apps: \(selection.applications.count)")
        print("   - Selection categories: \(selection.categories.count)")
        print("   - currentCategory: \(currentCategory?.displayName ?? "nil")")
        print("   - isProcessingSelection: \(isProcessingSelection)")
        print("   - showingFamilyActivityPicker: \(showingFamilyActivityPicker)")
        
        // Prevent multiple processing of the same selection
        guard !isProcessingSelection else {
            print("🔄 SELECTION: Already processing, ignoring duplicate")
            return
        }
        
        guard let category = currentCategory else {
            print("❌ ERROR: No current category set for selection")
            print("🔧 DEBUG: This suggests currentCategory was cleared unexpectedly")
            return
        }
        
        // Allow processing even if picker is closing, but prevent duplicate processing
        // The picker might set showingFamilyActivityPicker to false naturally when user completes
        
        // Only process if we have meaningful selection
        let hasApps = !selection.applications.isEmpty
        let hasCategories = !selection.categories.isEmpty
        
        print("🔧 PROCESSING DECISION:")
        print("   - hasApps: \(hasApps)")
        print("   - hasCategories: \(hasCategories)")
        print("   - Will process: \(hasApps || hasCategories)")
        print("   - showingFamilyActivityPicker: \(showingFamilyActivityPicker)")
        
        if hasApps || hasCategories {
            print("📥 PROCESSING SELECTION for \(category.displayName)")
            isProcessingSelection = true
            
            // Cancel any retry timers since we got a successful selection
            
            mappingService.recordCategoryMapping(category, selection: selection)
            
            // Clear the current category after a short delay to allow picker to fully close
            // This prevents the onChange from firing again with no current category
            print("⏰ SCHEDULING state clear in 0.5 seconds for \(category.displayName)")
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await MainActor.run {
                    print("🧹 CLEARING STATE after delay for \(category.displayName)")
                    print("   - About to clear currentCategory: \(currentCategory?.displayName ?? "nil")")
                    currentCategory = nil
                    isProcessingSelection = false
                    print("✅ COMPLETED: \(category.displayName) mapping finished and state cleared")
                }
            }
            
            print("✅ PROCESSING COMPLETE: \(category.displayName) mapping saved")
        } else if !isProcessingSelection && !showingFamilyActivityPicker {
            // Only handle empty selection if we haven't already processed a successful selection
            // and if the picker is not currently showing (user actually cancelled/failed)
            print("⚠️ EMPTY SELECTION for \(category.displayName) - user may have cancelled or encountered error")
            print("🔧 EMPTY SELECTION DEBUG:")
            print("   - isProcessingSelection: \(isProcessingSelection)")
            print("   - showingFamilyActivityPicker: \(showingFamilyActivityPicker)")
            print("   - currentCategory before clear: \(currentCategory?.displayName ?? "nil")")
            
            // Track categories that consistently fail
            errorCategories.insert(category)
            currentCategory = nil
            print("🔧 STATE: Cleared currentCategory due to empty selection")
            
            // Show helpful alert for known problematic categories
            if category == .shoppingFood {
                showingErrorAlert = true
            }
        } else {
            print("🔄 IGNORED: Empty selection - processing=\(isProcessingSelection), pickerShowing=\(showingFamilyActivityPicker)")
        }
    }
}

// MARK: - Category Setup Card

struct CategorySetupCard: View {
    let category: CategoryMappingService.AppCategory
    let isCompleted: Bool
    let hasError: Bool
    let appCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Icon and status
                ZStack {
                    Circle()
                        .fill(isCompleted ? Color.green.opacity(0.2) : 
                              hasError ? Color.red.opacity(0.2) : 
                              Color.blue.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    } else if hasError {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    } else {
                        Image(systemName: category.iconName)
                            .font(.title3)
                            .foregroundColor(.blue)
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
                    
                    if isCompleted && appCount > 0 {
                        Text("\(appCount) apps mapped")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                            .padding(.top, 2)
                    } else if hasError {
                        Text("Mapping failed")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
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
                    } else if hasError {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text("Retry")
                            .font(.caption2)
                            .foregroundColor(.red)
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
    CategoryMappingSetupView { mappingService in
        print("Setup completed with mapping service: \(mappingService)")
    }
}