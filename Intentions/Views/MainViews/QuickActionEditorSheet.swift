//
//  QuickActionEditorSheet.swift
//  Intentions
//
//  Created by Claude on 03/09/2025.
//

import SwiftUI
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Sheet for creating and editing quick actions
struct QuickActionEditorSheet: View {
    let dataService: DataPersisting
    let editingQuickAction: QuickAction?
    let availableAppGroups: [AppGroup]
    let onSave: (QuickAction) async -> Void
    let onCancel: () -> Void
    let onDelete: ((QuickAction) async -> Void)?

    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var name: String = ""
    @State private var duration: TimeInterval = 300 // 5 minutes default
    @State private var selectedIcon: String = "bolt.fill"
    @State private var selectedApps: Set<ApplicationToken> = []
    @State private var selectedCategories: Set<ActivityCategoryToken> = []
    @State private var allowAllWebsites: Bool = false
    @State private var familyActivitySelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var showingFamilyActivityPicker = false

    // UI state
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var lastSaveTapTime: Date = .distantPast
    @State private var lastPickerTapTime: Date = .distantPast

    var isEditing: Bool {
        editingQuickAction != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection

                        // Quick action name input
                        nameSection

                        // Icon selection
                        iconSelectionSection

                        // Duration section
                        durationSection

                        // App selection section
                        appSelectionSection

                        // Website access toggle
                        websiteAccessSection

                        // Selected items preview
                        if !selectedApps.isEmpty || !selectedCategories.isEmpty {
                            selectedItemsPreview
                        }

                        // Delete quick action option (only when editing)
                        if isEditing {
                            deleteQuickActionSection
                        }
                    }
                    .padding()
                    .padding(.bottom, 20) // Extra bottom padding for keyboard
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Edit Quick Action" : "Create Quick Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Update" : "Create") {
                        Task {
                            await saveQuickAction()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValidQuickAction || isLoading)
                }
            }
            .familyActivityPicker(
                isPresented: $showingFamilyActivityPicker,
                selection: $familyActivitySelection
            )
            .onChange(of: familyActivitySelection) { _, newSelection in
                updateSelectedItems(from: newSelection)
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in clearError() }
            )) {
                Button("OK") { clearError() }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            setupForEditing()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: isEditing ? "pencil.circle.fill" : "plus.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(AppConstants.Colors.text)

            Text(isEditing ? "Edit Quick Action" : "Create New Quick Action")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create instant shortcuts to start sessions with your favorite apps and categories")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Action Name")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Enter name...", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .submitLabel(.done)
                    .onChange(of: name) { _, newValue in
                        name = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                // Validation area
                HStack {
                    if !name.isEmpty && name.count > 50 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppConstants.Colors.textSecondary)
                            .font(.caption)

                        Text("Name exceeds maximum length of 50 characters")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    }

                    Spacer()
                }
                .frame(height: 16) // Fixed height prevents layout changes
            }
        }
    }

    // MARK: - Icon Selection Section

    private var iconSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Icon")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Choose an icon to represent this quick action")
                .font(.subheadline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(availableIcons, id: \.self) { icon in
                    iconButton(icon)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(AppConstants.UI.cornerRadius)
        }
    }

    private func iconButton(_ icon: String) -> some View {
        let isSelected = selectedIcon == icon

        return Button(action: {
            selectedIcon = icon
        }) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(isSelected ? AppConstants.Colors.text : AppConstants.Colors.surface)
                .foregroundColor(isSelected ? AppConstants.Colors.background : AppConstants.Colors.text)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private let availableIcons = [
        "bolt.fill", "star.fill", "flame.fill", "heart.fill", "crown.fill",
        "laptopcomputer", "book.fill", "gamecontroller.fill", "cup.and.saucer.fill",
        "music.note", "camera.fill", "message.fill", "phone.fill", "envelope.fill",
        "location.fill", "car.fill", "airplane", "bicycle", "figure.walk"
    ]

    // MARK: - Duration Section

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Duration")
                .font(.headline)
                .foregroundColor(.primary)

            Text("How long should this session last when started?")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                // Duration slider with current value
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Duration")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Text(formatDuration(duration))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Slider(
                        value: $duration,
                        in: TimeInterval(AppConstants.Session.minimumDuration)...TimeInterval(AppConstants.Session.maximumDuration),
                        step: 5 * 60 // 5-minute intervals
                    ) {
                        Text("Duration")
                    } minimumValueLabel: {
                        Text("5m")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    } maximumValueLabel: {
                        Text("2h")
                            .font(.caption)
                            .foregroundColor(AppConstants.Colors.textSecondary)
                    }
                    .tint(AppConstants.Colors.text)
                }

                // Quick duration buttons
                HStack(spacing: 8) {
                    durationButton("5m", 5*60)
                    durationButton("15m", 15*60)
                    durationButton("30m", 30*60)
                    durationButton("1h", 60*60)
                    durationButton("2h", 2*60*60)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(AppConstants.UI.cornerRadius)
        }
    }

    // MARK: - Website Access Section

    private var websiteAccessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow All Websites")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Enable unrestricted access to all websites during this session")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $allowAllWebsites)
                    .labelsHidden()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(AppConstants.UI.cornerRadius)
        }
    }

    // MARK: - App Selection Section

    private var appSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Apps & Categories")
                .font(.headline)
                .foregroundColor(.primary)

            Text(isEditing ? "Add more apps and categories to this quick action" : "Choose the apps and categories that will be included in this quick action")
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

            // App icons grid with remove functionality
            if !selectedApps.isEmpty {
                FullAppIconsGrid(
                    applicationTokens: Array(selectedApps),
                    onRemove: { token in
                        removeApp(token)
                    }
                )
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

            Text("All apps in the selected categories will be included in this quick action")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Delete Section

    private var deleteQuickActionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Divider to separate from other content
            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 12) {
                Text("Delete Quick Action")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("This action cannot be undone. The quick action will be permanently removed.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: {
                    guard let quickAction = editingQuickAction, let onDelete = onDelete else {
                        dismiss()
                        return
                    }
                    Task {
                        await onDelete(quickAction)
                        dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .font(.headline)
                        Text("Delete \"\(name)\"")
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

    // MARK: - Helper Views

    private func durationButton(_ title: String, _ value: TimeInterval) -> some View {
        let isSelected = abs(duration - value) < 60
        let backgroundColor = isSelected ? AppConstants.Colors.text : AppConstants.Colors.surface
        let textColor = isSelected ? AppConstants.Colors.background : AppConstants.Colors.textSecondary

        return Button(action: {
            duration = value
        }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .medium : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .foregroundColor(textColor)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Properties

    private var isValidQuickAction: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty &&
               trimmedName.count <= 50 &&
               (!selectedApps.isEmpty || !selectedCategories.isEmpty)
    }

    // MARK: - Actions

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

    @MainActor
    private func saveQuickAction() async {
        // Debounce rapid taps
        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastSaveTapTime)

        guard timeSinceLastTap > 1.0 else {
            return
        }

        lastSaveTapTime = now

        guard !name.isEmpty else {
            errorMessage = "Name is required"
            return
        }

        guard !selectedApps.isEmpty || !selectedCategories.isEmpty else {
            errorMessage = "At least one app or category must be selected"
            return
        }

        isLoading = true

        do {
            let quickAction: QuickAction

            if var existing = editingQuickAction {
                // Update existing
                existing.update(
                    name: name,
                    subtitle: nil,
                    iconName: selectedIcon,
                    color: .blue,
                    duration: duration,
                    appGroupIds: [], // Clear app groups, use individual selections
                    individualApplications: selectedApps,
                    individualCategories: selectedCategories,
                    allowAllWebsites: allowAllWebsites
                )
                quickAction = existing
            } else {
                // Create new
                quickAction = QuickAction(
                    name: name,
                    subtitle: nil,
                    iconName: selectedIcon,
                    color: .blue,
                    duration: duration,
                    appGroupIds: [],
                    individualApplications: selectedApps,
                    individualCategories: selectedCategories,
                    allowAllWebsites: allowAllWebsites
                )
            }

            await onSave(quickAction)

        } catch {
            errorMessage = "Failed to save quick action: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func setupForEditing() {
        guard let quickAction = editingQuickAction else { return }

        name = quickAction.name
        selectedIcon = quickAction.iconName
        allowAllWebsites = quickAction.allowAllWebsites

        // Validate duration from quick action
        let qaDuration = quickAction.duration
        if qaDuration.isNaN || qaDuration.isInfinite || !qaDuration.isFinite || qaDuration <= 0 {
            duration = 300 // 5 minutes default
        } else {
            duration = qaDuration
        }

        selectedApps = quickAction.individualApplications
        selectedCategories = quickAction.individualCategories
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        guard !duration.isNaN && !duration.isInfinite && duration.isFinite && duration >= 0 else {
            return "0m"
        }

        if duration >= 3600 {
            let totalSeconds = Int(duration)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        } else {
            let minutes = max(0, Int(duration) / 60)
            return "\(minutes)m"
        }
    }

    private func clearError() {
        errorMessage = nil
    }
}

// MARK: - Stable App Icons Grid (copied from AppGroupEditorSheet)

private struct FullAppIconsGrid: View {
    let applicationTokens: [ApplicationToken]
    let onRemove: ((ApplicationToken) -> Void)?

    init(applicationTokens: [ApplicationToken], onRemove: ((ApplicationToken) -> Void)? = nil) {
        self.applicationTokens = applicationTokens
        self.onRemove = onRemove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StableIconGrid(tokens: applicationTokens, onRemove: onRemove)
        }
    }
}

private struct StableIconGrid: View {
    let tokens: [ApplicationToken]
    let onRemove: ((ApplicationToken) -> Void)?

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(100), spacing: 16), count: 3)

        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(tokens.indices, id: \.self) { index in
                StableAppIconCell(
                    token: tokens[index],
                    tokenID: tokens[index].hashValue,
                    onRemove: onRemove
                )
            }
        }
    }
}

private struct StableAppIconCell: View {
    let token: ApplicationToken
    let tokenID: Int
    let onRemove: ((ApplicationToken) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            StableFamilyControlsLabel(token: token, id: tokenID, size: 55)
                .overlay(alignment: .topTrailing) {
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
                    }
                }

            StableFamilyControlsName(token: token, id: tokenID)
                .font(.caption2)
                .foregroundColor(.primary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
    }
}

private struct CategoryItemView: View {
    let token: ActivityCategoryToken
    let onRemove: (ActivityCategoryToken) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16))
                .foregroundColor(AppConstants.Colors.text)
                .frame(width: 20, height: 20)

            Text("Category")
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
            .scaleEffect(size / 25)
            .grayscale(1.0)
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

#Preview {
    QuickActionEditorSheet(
        dataService: MockDataPersistenceService(),
        editingQuickAction: nil,
        availableAppGroups: [],
        onSave: { _ in },
        onCancel: {},
        onDelete: nil
    )
}
