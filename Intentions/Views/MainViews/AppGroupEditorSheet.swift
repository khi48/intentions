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
    @State private var allowAllWebsites: Bool = false
    @State private var familyActivitySelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var showingFamilyActivityPicker = false
    @State private var searchText = ""
    
    // Local error handling to prevent conflicts with parent view
    @State private var localErrorMessage: String? = nil
    @State private var showingLocalError = false
    
    // Tap debouncing to prevent rapid double-taps causing presentation conflicts
    @State private var isProcessingSave = false
    @State private var lastPickerTapTime: Date = .distantPast
    
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

                        // Website access section
                        websiteAccessSection

                        // App selection section
                        appSelectionSection
                        
                        // Selected apps preview
                        if !selectedApps.isEmpty || !selectedCategories.isEmpty {
                            selectedItemsPreview
                        }
                        
                        // Delete group option (only when editing existing group)
                        if isEditing {
                            deleteGroupSection
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
                        // Prevent rapid double-taps that could cause presentation conflicts
                        guard !isProcessingSave else { 
                            print("🚫 DEBOUNCE: Ignoring rapid tap - save already in progress")
                            return 
                        }
                        
                        Task {
                            await saveGroup()
                        }
                    }
                    .disabled(!isValidGroup || isProcessingSave)
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
        // COMPLETELY DISABLED: Even the sheet's own alert to test if this is the source
        .alert("Error", isPresented: .constant(false)) {
            Button("OK") {
                localErrorMessage = nil
                showingLocalError = false
            }
        } message: {
            Text(localErrorMessage ?? "")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: isEditing ? "pencil.circle.fill" : "plus.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(AppConstants.Colors.text)
            
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Group Name")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Enter group name...", text: Binding(
                    get: { groupName },
                    set: { newValue in
                        groupName = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .submitLabel(.done)
                
                // Always show validation area with fixed height
                HStack {
                    if !groupName.isEmpty && groupName.count > AppConstants.AppGroup.maxNameLength {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppConstants.Colors.textSecondary)
                            .font(.caption)
                        
                        Text("Name exceeds maximum length of \(AppConstants.AppGroup.maxNameLength) characters")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    } else if !groupName.isEmpty && AppConstants.AppGroup.reservedNames.contains(groupName) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppConstants.Colors.textSecondary)
                            .font(.caption)
                        
                        Text("This name is reserved. Please choose a different name.")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    }
                    
                    Spacer()
                }
                .frame(height: 16) // Fixed height prevents layout changes
            }
        }
    }

    // MARK: - Website Access Section

    private var websiteAccessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Website Access")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Allow All Websites", isOn: $allowAllWebsites)
                    .toggleStyle(SwitchToggleStyle())

                Text("When enabled, this group will include access to all websites during sessions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(AppConstants.UI.cornerRadius)
    }

    // MARK: - App Selection Section
    
    private var appSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Apps & Categories")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(isEditing ? "Add more apps and categories to this group" : "Choose the apps and categories that will be included in this group")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {
                // Debounce rapid taps to prevent multiple picker presentations
                let now = Date()
                let timeSinceLastTap = now.timeIntervalSince(lastPickerTapTime)
                
                guard timeSinceLastTap > 1.0 else {
                    print("🚫 PICKER DEBOUNCE: Ignoring rapid tap (\(timeSinceLastTap)s ago)")
                    return
                }
                
                lastPickerTapTime = now
                print("📱 PICKER TAP: Opening family activity picker")
                showingFamilyActivityPicker = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(AppConstants.Colors.text)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isEditing ? "Add More Apps & Categories" : "Add Apps & Categories")
                            .font(.headline)
                            .foregroundColor(AppConstants.Colors.text)
                        
                        Text(isEditing ? "New selections will be added to existing ones" : "Tap to open app selector")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(AppConstants.Colors.surface)
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

                // Show optimization note when both apps and categories are selected
                if willOptimizeSelection {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(AppConstants.Colors.text)
                            .font(.caption)
                        Text("Categories will include their apps automatically, so individual app selections will be optimized out.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
            .background(AppConstants.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private var selectedAppsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "app.badge")
                    .foregroundColor(AppConstants.Colors.text)
                Text("Individual Apps")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppConstants.Colors.textSecondary)
                Spacer()
                Text("\(selectedApps.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Full expandable app icons grid with remove functionality
            if !selectedApps.isEmpty {
                FullAppIconsGrid(
                    applicationTokens: Array(selectedApps),
                    onRemove: { token in
                        removeApp(token)
                    }
                )
            } else {
                Text("Selected individual apps will be included in this group")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var selectedCategoriesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(AppConstants.Colors.text)
                Text("App Categories")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(selectedCategories.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show individual category items with remove buttons
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(Array(selectedCategories), id: \.self) { categoryToken in
                    CategoryItemView(
                        token: categoryToken,
                        onRemove: { token in
                            removeCategory(token)
                        }
                    )
                }
            }
            
            Text("All apps in the selected categories will be included in this group")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Delete Group Section
    
    private var deleteGroupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Divider to separate from other content
            Divider()
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Delete Group")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("This action cannot be undone. The group will be permanently removed from your collection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button(action: {
                    guard let editingGroup = editingGroup else { return }
                    print("🗑️ DELETE BUTTON: Confirming delete for \(editingGroup.name)")
                    
                    // Call the viewModel's delete confirmation
                    viewModel.confirmDeleteGroup(editingGroup)
                    
                    // Close the sheet after initiating delete
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .font(.headline)
                        Text("Delete \"\(editingGroup?.name ?? "Group")\"")
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppConstants.Colors.textSecondary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
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

    /// Returns true if the current selection will be optimized during save
    private var willOptimizeSelection: Bool {
        return !selectedCategories.isEmpty && !selectedApps.isEmpty
    }
    
    private var hasUnsavedChanges: Bool {
        if let editingGroup = editingGroup {
            return groupName != editingGroup.name ||
                   selectedApps != editingGroup.applications ||
                   selectedCategories != editingGroup.categories ||
                   allowAllWebsites != editingGroup.allowAllWebsites
        } else {
            return !groupName.isEmpty || !selectedApps.isEmpty || !selectedCategories.isEmpty || allowAllWebsites
        }
    }
    
    // MARK: - Methods
    
    private func setupInitialValues() {
        if let editingGroup = editingGroup {
            groupName = editingGroup.name
            selectedApps = editingGroup.applications
            selectedCategories = editingGroup.categories
            allowAllWebsites = editingGroup.allowAllWebsites

            // Set up FamilyActivitySelection from existing data
            familyActivitySelection = FamilyActivitySelection(includeEntireCategory: true)
            // Note: FamilyActivitySelection will be updated through the UI picker
        }
    }
    
    private func updateSelectedItems(from selection: FamilyActivitySelection) {
        // Convert new selections to tokens
        let newApps = Set(selection.applications.compactMap { $0.token })
        let newCategories = Set(selection.categories.compactMap { $0.token })

        // Only add items that aren't already selected (additive behavior)
        let appsToAdd = newApps.subtracting(selectedApps)
        let categoriesToAdd = newCategories.subtracting(selectedCategories)

        // Add new items to existing selections
        selectedApps.formUnion(appsToAdd)
        selectedCategories.formUnion(categoriesToAdd)
    }
    
    private func removeApp(_ token: ApplicationToken) {
        selectedApps.remove(token)
    }
    
    private func removeCategory(_ token: ActivityCategoryToken) {
        selectedCategories.remove(token)
    }

    /// Optimizes the selection by prioritizing categories over individual apps
    /// When categories are selected, individual apps become redundant since categories include all their apps
    private func getOptimizedSelection() -> (apps: Set<ApplicationToken>, categories: Set<ActivityCategoryToken>) {
        // If no categories are selected, return all individual apps
        guard !selectedCategories.isEmpty else {
            return (apps: selectedApps, categories: Set())
        }

        // If categories are selected, prioritize them for efficiency
        // Categories automatically include all their apps, so individual app selections become redundant
        // This follows the principle: "When entire categories are being saved, there is no need
        // to save all the individual apps from those categories too"

        if !selectedCategories.isEmpty {
            // Categories are selected - they handle app inclusion automatically
            // Only keep individual apps if no categories are selected, otherwise categories take precedence
            return (apps: Set(), categories: selectedCategories)
        } else {
            // Only individual apps are selected
            return (apps: selectedApps, categories: Set())
        }
    }
    
    private func saveGroup() async {
        // Set processing flag to prevent rapid double-taps
        guard !isProcessingSave else {
            print("🚫 SAVE GUARD: Save already in progress, skipping duplicate call")
            return
        }
        
        print("💾 SAVE START: Beginning save operation...")
        isProcessingSave = true
        defer { 
            print("💾 SAVE END: Resetting processing flag")
            isProcessingSave = false 
        }
        
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // COMPLETELY ISOLATE error handling - don't touch viewModel errors at all
        localErrorMessage = nil
        showingLocalError = false
        
        do {
            // COMPLETELY DISABLED: All error handling to test if validation triggers are the issue
            // Just print errors to console instead of showing alerts
            guard !trimmedName.isEmpty else {
                print("❌ VALIDATION ERROR: Group name cannot be empty")
                return
            }
            guard trimmedName.count <= AppConstants.AppGroup.maxNameLength else {
                print("❌ VALIDATION ERROR: Group name exceeds maximum length")
                return
            }
            guard !AppConstants.AppGroup.reservedNames.contains(trimmedName) else {
                print("❌ VALIDATION ERROR: Group name is reserved")
                return
            }
            guard !selectedApps.isEmpty || !selectedCategories.isEmpty else {
                print("❌ VALIDATION ERROR: Please select at least one app or category")
                return
            }

            // Get optimized selection to avoid redundancy
            let optimizedSelection = getOptimizedSelection()

            if let editingGroup = editingGroup {
                // Create updated group locally - should not throw now
                let updatedGroup = try AppGroup(
                    id: editingGroup.id,
                    name: trimmedName,
                    applications: optimizedSelection.apps,
                    categories: optimizedSelection.categories,
                    allowAllWebsites: allowAllWebsites,
                    createdAt: editingGroup.createdAt,
                    lastModified: Date()
                )
                
                // Save directly to data service on main actor
                try await viewModel.dataServiceAccess.saveAppGroup(updatedGroup)
                
                // Update viewModel manually to avoid error propagation
                viewModel.updateAppGroupDirectly(updatedGroup)
                viewModel.closeGroupEditor()
                
            } else {
                // Create new group locally - should not throw now due to pre-validation
                let newGroup = try AppGroup(
                    id: UUID(),
                    name: trimmedName,
                    applications: optimizedSelection.apps,
                    categories: optimizedSelection.categories,
                    allowAllWebsites: allowAllWebsites,
                    createdAt: Date(),
                    lastModified: Date()
                )
                
                // Save directly to data service on main actor
                try await viewModel.dataServiceAccess.saveAppGroup(newGroup)
                
                // Update viewModel manually to avoid error propagation
                viewModel.addAppGroupDirectly(newGroup)
                viewModel.notifyAppGroupsChanged()
                viewModel.closeGroupEditor()
            }
            
            // Close the sheet after successful save
            dismiss()
            
        } catch {
            // COMPLETELY DISABLED: Even catch block error handling
            print("❌ CATCH ERROR: \(error.localizedDescription)")
            // Don't try to show any alerts, just log
        }
    }
}

// MARK: - Stable App Icons Grid

private struct FullAppIconsGrid: View {
    let applicationTokens: [ApplicationToken]
    let onRemove: ((ApplicationToken) -> Void)?
    
    init(applicationTokens: [ApplicationToken], onRemove: ((ApplicationToken) -> Void)? = nil) {
        self.applicationTokens = applicationTokens
        self.onRemove = onRemove
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Create all Labels once with stable identity - no dynamic showing/hiding
            StableIconGrid(tokens: applicationTokens, onRemove: onRemove)
        }
    }
}

// MARK: - Stable Icon Grid Implementation

private struct StableIconGrid: View {
    let tokens: [ApplicationToken]
    let onRemove: ((ApplicationToken) -> Void)?
    
    var body: some View {
        // Simple, static grid with fixed-width columns to allow larger icons
        let columns = Array(repeating: GridItem(.fixed(100), spacing: 16), count: 3)

        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(tokens.indices, id: \.self) { index in
                StableAppIconCell(
                    token: tokens[index],
                    tokenID: tokens[index].hashValue, // Use token hash as stable ID
                    onRemove: onRemove
                )
            }
        }
    }
}

// MARK: - Stable App Icon Cell

private struct StableAppIconCell: View {
    let token: ApplicationToken
    let tokenID: Int // Stable identifier
    let onRemove: ((ApplicationToken) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // App icon with overlay remove button
            StableFamilyControlsLabel(token: token, id: tokenID, size: 55)
                .overlay(alignment: .topTrailing) {
                    // Remove button (only show if onRemove callback provided)
                    if let onRemove = onRemove {
                        Button(action: {
                            onRemove(token)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AppConstants.Colors.textSecondary)
                                .background(Color.white, in: Circle())
                        }
                        .buttonStyle(.plain)
//                        .padding(6) // Padding within overlay instead of offset
                    }
                }

            // App name with stable token reference - smaller text
            StableFamilyControlsName(token: token, id: tokenID)
                .font(.caption2)
                .foregroundColor(.primary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Category Item View

private struct CategoryItemView: View {
    let token: ActivityCategoryToken
    let onRemove: (ActivityCategoryToken) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16))
                .foregroundColor(AppConstants.Colors.text)
                .frame(width: 20, height: 20)
            
            Text("Category") // Note: ActivityCategoryToken doesn't have a display name
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: {
                onRemove(token)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppConstants.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - FamilyControls Components

private struct StableFamilyControlsLabel: View {
    let token: ApplicationToken
    let id: Int
    let size: CGFloat

    init(token: ApplicationToken, id: Int, size: CGFloat = 50) {
        self.token = token
        self.id = id
        self.size = size
    }

    var body: some View {
        Label(token)
            .labelStyle(.iconOnly)
            .scaleEffect(size / 25) // Scale from native 25px to desired size
            .grayscale(1.0) // Convert to greyscale
            .frame(width: size, height: size)
            .id("app_icon_\(id)")
    }
}

private struct StableFamilyControlsName: View {
    let token: ApplicationToken 
    let id: Int
    
    var body: some View {
        Label(token)
            .labelStyle(.titleOnly)
            .id("app_name_\(id)")
    }
}

// MARK: - Legacy Code Removed
// Simplified to stable, non-dynamic view creation only

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
