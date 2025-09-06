//
//  QuickActionEditorSheet.swift
//  Intentions
//
//  Created by Claude on 03/09/2025.
//

import SwiftUI
import FamilyControls

/// Sheet for creating and editing quick actions
struct QuickActionEditorSheet: View {
    let dataService: DataPersisting
    let editingQuickAction: QuickAction?
    let availableAppGroups: [AppGroup]
    let onSave: (QuickAction) async -> Void
    let onCancel: () -> Void
    
    // Form state
    @State private var name: String = ""
    @State private var subtitle: String = ""
    @State private var selectedIcon: String = "star.fill"
    @State private var selectedColor: Color = .blue
    @State private var duration: TimeInterval = AppConstants.Session.defaultDuration
    @State private var selectedAppGroupIds: Set<UUID> = []
    // Temporarily disabled for FamilyControls integration until device testing  
    // @State private var selectedApplications: Set<ApplicationToken> = []
    // @State private var selectedCategories: Set<ActivityCategoryToken> = []
    
    // UI state
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showingFamilyActivityPicker = false
    @State private var lastSaveTapTime: Date = .distantPast
    
    // Available icons
    private let availableIcons = [
        "star.fill", "bolt.fill", "flame.fill", "heart.fill", "crown.fill",
        "laptopcomputer", "book.fill", "gamecontroller.fill", "cup.and.saucer.fill",
        "music.note", "camera.fill", "message.fill", "phone.fill", "envelope.fill",
        "location.fill", "car.fill", "airplane", "bicycle", "figure.walk"
    ]
    
    // Available colors
    private let availableColors: [Color] = [
        .blue, .green, .orange, .red, .purple, .pink, .yellow, .indigo, .teal, .brown
    ]
    
    var isEditing: Bool {
        editingQuickAction != nil
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Basic info section
                    basicInfoSection
                    
                    // Appearance section
                    appearanceSection
                    
                    // Duration section
                    durationSection
                    
                    // App groups section
                    appGroupsSection
                    
                    // Individual apps section
                    individualAppsSection
                    
                    // Delete section (if editing)
                    if isEditing {
                        deleteSection
                    }
                }
                .padding()
            }
            .navigationTitle(isEditing ? "Edit Quick Action" : "New Quick Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await saveQuickAction()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty || isLoading)
                }
            }
            // Temporarily disabled FamilyActivityPicker until device testing
            /*.sheet(isPresented: $showingFamilyActivityPicker) {
                FamilyActivityPicker(selection: Binding(
                    get: {
                        FamilyActivitySelection(
                            applicationTokens: selectedApplications,
                            categoryTokens: selectedCategories
                        )
                    },
                    set: { selection in
                        selectedApplications = selection.applicationTokens
                        selectedCategories = selection.categoryTokens
                    }
                ))
            }*/
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
    
    // MARK: - Basic Info Section
    
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Basic Information")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 16) {
                // Name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // Container to isolate UITextField from SwiftUI layout system
                    GeometryReader { geometry in
                        let safeWidth = geometry.size.width.isFinite && geometry.size.width > 0 ? geometry.size.width : 200
                        let safeHeight: CGFloat = 36
                        
                        SafeUITextField(
                            placeholder: "Enter action name",
                            text: $name,
                            onTextChange: { _ in }
                        )
                        .frame(width: safeWidth, height: safeHeight)
                    }
                    .frame(height: 36) // Force container height
                }
                
                // Subtitle field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Subtitle (Optional)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // Container to isolate UITextField from SwiftUI layout system
                    GeometryReader { geometry in
                        let safeWidth = geometry.size.width.isFinite && geometry.size.width > 0 ? geometry.size.width : 200
                        let safeHeight: CGFloat = 36
                        
                        SafeUITextField(
                            placeholder: "Brief description",
                            text: $subtitle,
                            onTextChange: { _ in }
                        )
                        .frame(width: safeWidth, height: safeHeight)
                    }
                    .frame(height: 36) // Force container height
                }
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Appearance Section
    
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 20) {
                // Icon selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Icon")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(availableIcons, id: \.self) { icon in
                            iconButton(icon)
                        }
                    }
                }
                
                // Color selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(availableColors, id: \.self) { color in
                            colorButton(color)
                        }
                    }
                }
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Duration Section
    
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Duration")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 16) {
                durationSliderSection
                durationButtonsSection
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - App Groups Section
    
    private var appGroupsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Groups")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 16) {
                if availableAppGroups.isEmpty {
                    Text("No app groups available. Create app groups first to use them in quick actions.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ForEach(availableAppGroups) { group in
                        AppGroupSelectionRow(
                            group: group,
                            isSelected: selectedAppGroupIds.contains(group.id)
                        ) {
                            if selectedAppGroupIds.contains(group.id) {
                                selectedAppGroupIds.remove(group.id)
                            } else {
                                selectedAppGroupIds.insert(group.id)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Individual Apps Section (Temporarily Disabled)
    
    private var individualAppsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Individual Apps & Categories")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 16) {
                Text("Individual app selection will be available when testing on a physical device. For now, use app groups to organize your apps.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                
                /*
                Button(action: {
                    showingFamilyActivityPicker = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Select Apps & Categories")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                */
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    
    // MARK: - Delete Section
    
    private var deleteSection: some View {
        VStack(spacing: 16) {
            Button(action: {
                // TODO: Handle delete
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Quick Action")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.red)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // MARK: - Helper Views
    
    private var durationSliderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            durationHeader
            durationSlider
        }
    }
    
    private var durationHeader: some View {
        HStack {
            Text("Duration")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            Text(safeFormatDuration(duration))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var durationBinding: Binding<TimeInterval> {
        Binding(
            get: { 
                let currentDuration = duration
                if currentDuration.isNaN || currentDuration.isInfinite || !currentDuration.isFinite || currentDuration < 0 {
                    return AppConstants.Session.defaultDuration
                }
                return currentDuration
            },
            set: { newValue in
                if newValue.isNaN || newValue.isInfinite || !newValue.isFinite {
                    return
                }
                let safeValue = max(5*60, min(4*60*60, newValue))
                duration = safeValue
            }
        )
    }
    
    private var durationSlider: some View {
        Slider(
            value: durationBinding,
            in: 5*60...4*60*60, // 5 minutes to 4 hours
            step: 5*60 // 5 minute steps
        ) {
            Text("Duration")
        } minimumValueLabel: {
            Text("5m")
                .font(.caption)
        } maximumValueLabel: {
            Text("4h")
                .font(.caption)
        }
    }
    
    private var durationButtonsSection: some View {
        HStack(spacing: 12) {
            durationButton("15m", 15*60)
            durationButton("30m", 30*60)
            durationButton("1h", 60*60)
            durationButton("2h", 2*60*60)
        }
    }
    
    private func durationButton(_ title: String, _ value: TimeInterval) -> some View {
        // Safe comparison to prevent NaN issues
        let isSelected = duration.isFinite && value.isFinite && abs(duration - value) < 60
        
        return Button(title) {
            duration = value
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? selectedColor : Color.gray.opacity(0.2))
        .foregroundColor(isSelected ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Actions
    
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
        
        isLoading = true
        
        do {
            let quickAction: QuickAction
            
            if var existing = editingQuickAction {
                // Update existing
                existing.update(
                    name: name,
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    iconName: selectedIcon,
                    color: selectedColor,
                    duration: duration,
                    appGroupIds: selectedAppGroupIds
                )
                quickAction = existing
            } else {
                // Create new
                quickAction = QuickAction(
                    name: name,
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    iconName: selectedIcon,
                    color: selectedColor,
                    duration: duration,
                    appGroupIds: selectedAppGroupIds
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
        subtitle = quickAction.subtitle ?? ""
        selectedIcon = quickAction.iconName
        selectedColor = quickAction.color
        
        // Validate duration from quick action
        let qaDuration = quickAction.duration
        if qaDuration.isNaN || qaDuration.isInfinite || !qaDuration.isFinite || qaDuration <= 0 {
            duration = AppConstants.Session.defaultDuration
        } else {
            duration = qaDuration
        }
        
        selectedAppGroupIds = quickAction.appGroupIds
    }
    
    private func safeFormatDuration(_ duration: TimeInterval) -> String {
        // Extra aggressive validation with detailed logging
        print("🔍 SAFE FORMAT: Input duration = \(duration)")
        
        if duration.isNaN {
            print("❌ SAFE FORMAT: Duration is NaN, using fallback")
            return "0m"
        }
        
        if duration.isInfinite {
            print("❌ SAFE FORMAT: Duration is infinite, using fallback")
            return "0m"
        }
        
        if !duration.isFinite {
            print("❌ SAFE FORMAT: Duration is not finite, using fallback")
            return "0m"
        }
        
        if duration < 0 {
            print("❌ SAFE FORMAT: Duration is negative (\(duration)), using fallback")
            return "0m"
        }
        
        return formatDuration(duration)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        // Comprehensive safety check for NaN or invalid values
        guard !duration.isNaN && !duration.isInfinite && duration.isFinite && duration >= 0 else {
            print("⚠️ DURATION FORMAT: Invalid duration value: \(duration)")
            return "0m"
        }
        
        // Additional safety for conversion to Int
        let safeDuration = max(0, duration)
        guard safeDuration.isFinite else {
            print("⚠️ DURATION FORMAT: Duration not finite after safety conversion: \(safeDuration)")
            return "0m"
        }
        
        if safeDuration >= 3600 {
            let totalSeconds = Int(safeDuration)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        } else {
            let minutes = max(0, Int(safeDuration) / 60)
            return "\(minutes)m"
        }
    }
    
    private func clearError() {
        errorMessage = nil
    }
    
    
    private func iconButton(_ icon: String) -> some View {
        let isSelected = selectedIcon == icon
        
        return Button(action: {
            selectedIcon = icon
        }) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(isSelected ? selectedColor : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func colorButton(_ color: Color) -> some View {
        let isSelected = selectedColor == color
        
        return Button(action: {
            selectedColor = color
        }) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 3)
                )
        }
    }
}

// MARK: - App Group Selection Row

private struct AppGroupSelectionRow: View {
    let group: AppGroup
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Selection indicator
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                    
                    // Group info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("\(group.applications.count) apps, \(group.categories.count) categories")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    QuickActionEditorSheet(
        dataService: MockDataPersistenceService(),
        editingQuickAction: nil,
        availableAppGroups: [],
        onSave: { _ in },
        onCancel: {}
    )
}

// MARK: - Safe UITextField Wrapper

/// Custom UITextField that disables problematic features that can cause CoreGraphics NaN errors
class SafeTextField: UITextField {
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Disable all context menu actions that might trigger complex layout calculations
        return false
    }
    
    override var selectedTextRange: UITextRange? {
        get { return nil } // Always return nil to disable selection
        set { /* Ignore all selection changes */ }
    }
}

struct SafeUITextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onTextChange: (String) -> Void
    
    func makeUIView(context: Context) -> SafeTextField {
        let textField = SafeTextField()
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.delegate = context.coordinator
        textField.text = text
        
        // Force constraints to prevent NaN frame calculations
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // CRITICAL: Disable long press and problematic gestures that can cause NaN
        textField.isUserInteractionEnabled = true
        
        // Disable context menu (long press) which triggers complex layout calculations
        // Simplified approach to prevent gesture-related NaN issues
        textField.isSecureTextEntry = false
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        
        // Disable magnifier and selection UI that can cause layout issues
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidBeginEditing(_:)), for: .editingDidBegin)
        
        
        return textField
    }
    
    func updateUIView(_ uiView: SafeTextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: SafeUITextField
        
        init(_ parent: SafeUITextField) {
            self.parent = parent
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let newText = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? string
            
            // Update binding safely
            DispatchQueue.main.async {
                self.parent.text = newText
                self.parent.onTextChange(newText)
            }
            
            return true
        }
        
        @objc func textFieldDidBeginEditing(_ textField: UITextField) {
            // Disable text selection which can cause layout calculations
            DispatchQueue.main.async {
                textField.selectedTextRange = nil
            }
        }
        
        // Simplified approach - just handle basic text changes
    }
}