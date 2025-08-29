//
//  AppGroupEditorSheet.swift
//  Intentions
//
//  Created by Claude on 27/08/2025.
//

import SwiftUI
import FamilyControls
import ManagedSettings

/// Sheet view for creating and editing app groups
/// Provides a comprehensive interface for group management with app selection
struct AppGroupEditorSheet: View {
    @Bindable var viewModel: AppGroupsViewModel
    let editingGroup: AppGroup?
    
    @Environment(\.dismiss) private var dismiss
    
    // Local state for the editor
    @State private var groupName: String = ""
    @State private var selectedApps: Set<ApplicationToken> = []
    @State private var selectedCategories: Set<ActivityCategoryToken> = []
    @State private var familyActivitySelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var showingFamilyActivityPicker = false
    @State private var searchText = ""
    
    private var isEditing: Bool { editingGroup != nil }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Group name input
                        groupNameSection
                        
                        // App selection section
                        appSelectionSection
                        
                        // Selected apps preview
                        if !selectedApps.isEmpty || !selectedCategories.isEmpty {
                            selectedItemsPreview
                        }
                    }
                    .padding()
                    .padding(.bottom, 20) // Extra bottom padding for keyboard
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Edit Group" : "Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Update" : "Create") {
                        Task {
                            await saveGroup()
                        }
                    }
                    .disabled(!isValidGroup)
                    .fontWeight(.semibold)
                }
            }
            .familyActivityPicker(
                isPresented: $showingFamilyActivityPicker,
                selection: $familyActivitySelection
            )
            .onChange(of: familyActivitySelection) { _, newSelection in
                updateSelectedItems(from: newSelection)
            }
            .onAppear {
                setupInitialValues()
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: isEditing ? "pencil.circle.fill" : "plus.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text(isEditing ? "Edit App Group" : "Create New App Group")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Organize apps into collections for quick session setup")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Group Name Section
    
    private var groupNameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group Name")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                TextField("Enter group name...", text: $groupName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .submitLabel(.done)
                
                // Always show validation area with fixed height
                HStack {
                    if !groupName.isEmpty && groupName.count > AppConstants.AppGroup.maxNameLength {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        
                        Text("Name exceeds maximum length of \(AppConstants.AppGroup.maxNameLength) characters")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if !groupName.isEmpty && AppConstants.AppGroup.reservedNames.contains(groupName) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        
                        Text("This name is reserved. Please choose a different name.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                }
                .frame(height: 16) // Fixed height prevents layout changes
            }
        }
    }
    
    // MARK: - App Selection Section
    
    private var appSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Apps & Categories")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Choose the apps and categories that will be included in this group")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {
                showingFamilyActivityPicker = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Apps & Categories")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        Text("Tap to open app selector")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(.blue.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Selected Items Preview
    
    private var selectedItemsPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Items")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                if !selectedApps.isEmpty {
                    selectedAppsView
                }
                
                if !selectedCategories.isEmpty {
                    selectedCategoriesView
                }
            }
            .padding()
            .background(.green.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private var selectedAppsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "app.badge")
                    .foregroundColor(.green)
                Text("Individual Apps")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(selectedApps.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Selected individual apps will be included in this group")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var selectedCategoriesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder.badge")
                    .foregroundColor(.green)
                Text("App Categories")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(selectedCategories.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("All apps in the selected categories will be included in this group")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Computed Properties
    
    private var isValidGroup: Bool {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty &&
               trimmedName.count <= AppConstants.AppGroup.maxNameLength &&
               !AppConstants.AppGroup.reservedNames.contains(trimmedName) &&
               (!selectedApps.isEmpty || !selectedCategories.isEmpty)
    }
    
    private var hasUnsavedChanges: Bool {
        if let editingGroup = editingGroup {
            return groupName != editingGroup.name ||
                   selectedApps != editingGroup.applications ||
                   selectedCategories != editingGroup.categories
        } else {
            return !groupName.isEmpty || !selectedApps.isEmpty || !selectedCategories.isEmpty
        }
    }
    
    // MARK: - Methods
    
    private func setupInitialValues() {
        if let editingGroup = editingGroup {
            groupName = editingGroup.name
            selectedApps = editingGroup.applications
            selectedCategories = editingGroup.categories
            
            // Set up FamilyActivitySelection from existing data
            familyActivitySelection = FamilyActivitySelection(includeEntireCategory: true)
            // Note: FamilyActivitySelection will be updated through the UI picker
        }
    }
    
    private func updateSelectedItems(from selection: FamilyActivitySelection) {
        selectedApps = Set(selection.applications.compactMap { $0.token })
        selectedCategories = Set(selection.categories.compactMap { $0.token })
    }
    
    private func saveGroup() async {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let editingGroup = editingGroup {
            await viewModel.updateAppGroup(
                id: editingGroup.id,
                name: trimmedName,
                applicationTokens: selectedApps,
                categoryTokens: selectedCategories
            )
        } else {
            await viewModel.createAppGroup(
                name: trimmedName,
                applicationTokens: selectedApps,
                categoryTokens: selectedCategories
            )
        }
        
        // Close the sheet after successful save
        if viewModel.errorMessage == nil {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview("Create Group") {
    AppGroupEditorSheet(
        viewModel: AppGroupsViewModel(
            dataService: MockDataPersistenceService()
        ),
        editingGroup: nil
    )
}

#Preview("Edit Group") {
    let mockGroup = try! AppGroup(
        name: "Work Apps",
        applications: Set()
    )
    
    AppGroupEditorSheet(
        viewModel: AppGroupsViewModel(
            dataService: MockDataPersistenceService()
        ),
        editingGroup: mockGroup
    )
}