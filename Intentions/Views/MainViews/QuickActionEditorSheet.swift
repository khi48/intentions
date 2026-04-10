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
    let onSave: (QuickAction) async -> Void
    let onCancel: () -> Void
    let onDelete: ((QuickAction) async -> Void)?

    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var name: String = ""
    @State private var duration: TimeInterval = 300 // 5 minutes default
    @State private var selectedIcon: String = "bolt.fill"
    @State private var selectedApps: Set<ApplicationToken> = []
    @State private var allowAllWebsites: Bool = false
    @State private var familyActivitySelection = FamilyActivitySelection(includeEntireCategory: false)
    @State private var showingFamilyActivityPicker = false

    // UI state
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var lastSaveTapTime: Date = .distantPast
    @State private var lastPickerTapTime: Date = .distantPast
    @State private var showingIconPicker: Bool = false

    var isEditing: Bool {
        editingQuickAction != nil
    }

    private let availableIcons = [
        "bolt.fill", "star.fill", "flame.fill", "heart.fill", "crown.fill",
        "laptopcomputer", "book.fill", "gamecontroller.fill", "cup.and.saucer.fill",
        "music.note", "camera.fill", "message.fill", "phone.fill", "envelope.fill",
        "location.fill", "car.fill", "airplane", "bicycle", "figure.walk"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Live mini preview card
                        miniPreviewCard
                            .padding(.top, 14)
                            .padding(.bottom, 10)

                        // Name + tappable icon row
                        nameIconRow

                        // Duration pill selector
                        durationPillsSection

                        // Apps row
                        appsRow

                        // Selected apps preview (if any)
                        if !selectedApps.isEmpty {
                            selectedAppsPreview
                        }

                        // Website toggle row
                        websiteRow

                        // Delete (editing only)
                        if isEditing {
                            deleteRow
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)

                // Bottom action button
                Button(action: {
                    Task { await saveQuickAction() }
                }) {
                    Text(isEditing ? "Update" : "Create")
                        .font(.headline)
                        .foregroundColor(AppConstants.Colors.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            isValidQuickAction && !isLoading
                                ? AppConstants.Colors.text
                                : AppConstants.Colors.textSecondary.opacity(0.3)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!isValidQuickAction || isLoading)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle(isEditing ? "Edit Quick Action" : "New Quick Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
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
            .sheet(isPresented: $showingIconPicker) {
                iconPickerSheet
            }
        }
        .onAppear {
            setupForEditing()
        }
    }

    // MARK: - Mini Preview Card

    private var miniPreviewCard: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: selectedIcon)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.text)
                    .frame(width: 22, height: 22)
                    .background(AppConstants.Colors.text.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                Text(name.isEmpty ? "Untitled" : name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(name.isEmpty ? AppConstants.Colors.textSecondary : AppConstants.Colors.text)
                    .lineLimit(1)

                Text("\(formatDuration(duration)) · \(selectedApps.count) apps")
                    .font(.caption2)
                    .foregroundColor(AppConstants.Colors.textSecondary)
                    .padding(.top, 2)
            }
            .frame(width: 100, height: 100)
            .padding(10)
            .background(AppConstants.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppConstants.Colors.textSecondary.opacity(0.2), lineWidth: 1)
            )
            Spacer()
        }
    }

    // MARK: - Name + Icon Row

    private var nameIconRow: some View {
        HStack(spacing: 10) {
            // Tappable icon chip
            Button(action: { showingIconPicker = true }) {
                Image(systemName: selectedIcon)
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.text)
                    .frame(width: 34, height: 34)
                    .background(AppConstants.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppConstants.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Inline name field
            TextField("Quick action name", text: $name)
                .font(.body)
                .submitLabel(.done)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppConstants.Colors.textSecondary.opacity(0.15)).frame(height: 0.5)
        }
    }

    // MARK: - Duration Pills

    private var durationPillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DURATION")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppConstants.Colors.textSecondary)
                .padding(.top, 14)

            HStack(spacing: 5) {
                durationPill("5m", 5 * 60)
                durationPill("15m", 15 * 60)
                durationPill("30m", 30 * 60)
                durationPill("1h", 60 * 60)
                durationPill("1.5h", 90 * 60)
                durationPill("2h", 2 * 60 * 60)
            }
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppConstants.Colors.textSecondary.opacity(0.15)).frame(height: 0.5)
            }
        }
    }

    private func durationPill(_ label: String, _ value: TimeInterval) -> some View {
        let isActive = abs(duration - value) < 60
        return Button(action: { duration = value }) {
            Text(label)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(isActive ? AppConstants.Colors.text.opacity(0.1) : AppConstants.Colors.surface)
                .foregroundColor(isActive ? AppConstants.Colors.text : AppConstants.Colors.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? AppConstants.Colors.textSecondary : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Apps Row

    private var appsRow: some View {
        Button(action: {
            let now = Date()
            guard now.timeIntervalSince(lastPickerTapTime) > 1.0 else { return }
            lastPickerTapTime = now
            showingFamilyActivityPicker = true
        }) {
            HStack {
                Text("Apps")
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.text)
                Spacer()
                Text(selectedApps.isEmpty ? "None" : "\(selectedApps.count) selected")
                    .font(.subheadline)
                    .foregroundColor(AppConstants.Colors.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(AppConstants.Colors.textSecondary)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppConstants.Colors.textSecondary.opacity(0.15)).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected Apps Preview

    private var selectedAppsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            FullAppIconsGrid(
                applicationTokens: Array(selectedApps),
                onRemove: { token in removeApp(token) }
            )
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppConstants.Colors.textSecondary.opacity(0.15)).frame(height: 0.5)
        }
    }

    // MARK: - Website Row

    private var websiteRow: some View {
        HStack {
            Text("Allow all websites")
                .font(.body)
                .foregroundColor(AppConstants.Colors.text)
            Spacer()
            Toggle("", isOn: $allowAllWebsites)
                .labelsHidden()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppConstants.Colors.textSecondary.opacity(0.15)).frame(height: 0.5)
        }
    }

    // MARK: - Delete Row

    private var deleteRow: some View {
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
            Text("Delete Quick Action")
                .font(.body)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }

    // MARK: - Icon Picker Sheet

    private var iconPickerSheet: some View {
        NavigationStack {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(availableIcons, id: \.self) { icon in
                    let isSelected = selectedIcon == icon
                    Button(action: {
                        selectedIcon = icon
                        showingIconPicker = false
                    }) {
                        Image(systemName: icon)
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(isSelected ? AppConstants.Colors.text : AppConstants.Colors.surface)
                            .foregroundColor(isSelected ? AppConstants.Colors.background : AppConstants.Colors.text)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingIconPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Computed Properties

    private var isValidQuickAction: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty &&
               trimmedName.count <= 50 &&
               !selectedApps.isEmpty
    }

    // MARK: - Actions

    private func updateSelectedItems(from selection: FamilyActivitySelection) {
        // Convert new selections to tokens
        let newApps = Set(selection.applications.compactMap { $0.token })

        // Only add items that aren't already selected (additive behavior)
        let appsToAdd = newApps.subtracting(selectedApps)

        // Add new items to existing selections
        selectedApps.formUnion(appsToAdd)
    }

    private func removeApp(_ token: ApplicationToken) {
        selectedApps.remove(token)
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

        guard !selectedApps.isEmpty else {
            errorMessage = "At least one app must be selected"
            return
        }

        isLoading = true

        let quickAction: QuickAction

        if var existing = editingQuickAction {
            // Update existing
            existing.update(
                name: name,
                subtitle: nil,
                iconName: selectedIcon,
                color: .blue,
                duration: duration,
                individualApplications: selectedApps,
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
                individualApplications: selectedApps,
                allowAllWebsites: allowAllWebsites
            )
        }

        await onSave(quickAction)

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
        onSave: { _ in },
        onCancel: {},
        onDelete: nil
    )
}
